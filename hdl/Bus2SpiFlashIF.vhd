-- read access to SPI flash via UDP

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.Udp2BusPkg.all;

entity Bus2SpiFlashIF is
   generic (
      -- since Udp2Bus only supports 22-bit addresses
      -- we break up access to the SPI flash into pages
      -- using an indirect addressing scheme.
      LD_PAGE_SIZE_G : natural range 2 to 20 := 16 -- byte address
   );
   port (
      clk     : in  std_logic;
      rst     : in  std_logic;

      busReq  : in  Udp2BusReqType;
      busRep  : out Udp2BusRepType;

      -- request/grant of SPI interface
      spiReq  : out std_logic;
      spiGnt  : in  std_logic := '1';

      -- spi controller request (output of this module)
      spiVldI : out std_logic;
      spiDatI : out std_logic_vector(7 downto 0);
      spiCsel : out std_logic;
      spiRdyI : in  std_logic;

      -- spi controller reply (input of this module)
      spiVldO : in  std_logic;
      spiDatO : in  std_logic_vector(7 downto 0);
      spiRdyO : out std_logic
   );
end entity Bus2SpiFlashIF;

architecture Impl of Bus2SpiFlashIF is

   type     SpiPhaseType    is ( ADDR, SWITCH, DATA, CSHI );
   type     StateType       is ( IDLE, ARB, WAIT_SPI, DONE );

   constant SPI_ABYTES_C    :  natural  := 3;

   constant CS_ACTIVE_C     :  std_logic := '0';
   constant CS_NOT_ACTIVE_C :  std_logic := not CS_ACTIVE_C;
   constant SPICMD_READ_C   :  std_logic_vector(7 downto 0) := x"9f";
   constant SPICMD_ONES_C   :  std_logic_vector(7 downto 0) := x"ff";

   subtype  CountType       is natural range 0 to 3;

   type RegType is record
      state     :  StateType;
      phas      :  SpiPhaseType;
      cnt       :  CountType;
      spiCsel   :  std_logic;
      addr      :  unsigned(8*SPI_ABYTES_C - 1 downto 0);
      busRep    :  Udp2BusRepType;
      skip      :  natural range 0 to 5;
      spiReq    :  std_logic;
      spiVldI   :  std_logic;
      spiDatI   :  std_logic_vector(7 downto 0);
      spiRdyO   :  std_logic;
   end record RegType;

   constant REG_INIT_C : RegType := (
      state     => IDLE,
      cnt       => 0,
      phas      => ADDR,
      spiCsel   => CS_NOT_ACTIVE_C,
      addr      => (others => '0'),
      busRep    => UDP2BUSREP_INIT_C,
      skip      =>  0,
      spiReq    => '0',
      spiVldI   => '0',
      spiDatI   => (others => '0'),
      spiRdyO   => '0'
   );

   function pageNo(constant byteAddr : in unsigned)
   return std_logic_vector is
      variable n : unsigned(31 downto 0);
   begin
      n := resize( byteAddr, n'length );
      n := shift_right( n, LD_PAGE_SIZE_G );
      return std_logic_vector( n );
   end function pageNo;

   procedure setPageNo(
      variable byteAddr : inout unsigned(23 downto 0);
      constant pgNo     : in    std_logic_vector(31 downto 0)
   ) is
      variable v : unsigned(byteAddr'length - LD_PAGE_SIZE_G - 1 downto 0);
   begin
      byteAddr := byteAddr;
      v        := unsigned( pgNo( v'range ) );
      byteAddr(byteAddr'left downto LD_PAGE_SIZE_G) := v;
   end procedure setPageNo;

   procedure setPageAddr(
      variable byteAddr : inout unsigned(23 downto 0);
      constant breq     : in    Udp2BusReqType
   ) is
   begin
      byteAddr := byteAddr;
      byteAddr(LD_PAGE_SIZE_G - 1 downto 2) := unsigned( breq.dwaddr( LD_PAGE_SIZE_G - 3 downto 0 ) );
      byteAddr(                 1 downto 0) := unsigned( byteAddrLsbs( breq ) );
   end procedure setPageAddr;

   signal r                : RegType := REG_INIT_C;
   signal rin              : RegType;

begin

   P_COMB : process ( r, busReq, spiGnt, spiRdyI, spiVldO, spiDatO ) is
      variable v : RegType;
   begin
      v   := r;

      case ( r.state ) is
         when IDLE =>
            if ( busReq.valid = '1' ) then
               if ( busReq.dwaddr( LD_PAGE_SIZE_G - 2 ) = '1' ) then
                  v.busRep.valid := '1';
                  v.busRep.berr  := '0';
                  if ( busReq.rdnwr = '1' ) then
                     v.busRep.rdata := (others => '0');
                     v.busRep.rdata := pageNo( r.addr );
                  else
                     setPageNo( v.addr, busReq.data );
                  end if;
                  v.state  := DONE;
               else
                  if ( busReq.rdnwr = '1' ) then
                     v.spiReq       := '1';
                     v.state        := ARB;
                     -- validity of byte-enable lanes is checked in ARB state
                     setPageAddr( v.addr, busReq );
                  else
                     -- write not supported
                     v.busRep.valid := '1';
                     v.busRep.berr  := '1';
                     v.state        := DONE;
                  end if;
               end if;
            end if;

         when ARB =>
            v.skip := 4 - accessWidth( busReq );
            if ( ( spiGnt = '0' ) or ( v.skip > 3 ) ) then
               -- access to SPI bus not granted, invalid byte-lanes
               -- or no data requested
               v.spiReq       := '0'; -- revoke bus request
               v.busRep.valid := '1';
               v.busRep.berr  := '1';
               if ( v.skip = 4 ) then
                  -- not an error after all; just a zero length request
                  v.busRep.berr := '0';
               end if;
               v.state := DONE;
            else
               v.busRep.berr := '0';
               v.spiDatI     := SPICMD_READ_C;
               v.spiVldI     := '1';
               v.spiCsel     := CS_ACTIVE_C;
               v.state       := WAIT_SPI;
               v.cnt         := SPI_ABYTES_C - 1;
               v.phas        := ADDR;
            end if;

         when WAIT_SPI =>
            if ( r.spiRdyO = '0' ) then
               -- wait for command to be accepted
               if ( spiRdyI = '1' ) then
                  -- sent it
                  v.spiVldI := '0';
                  -- now wait for the reply
                  v.spiRdyO := '1';
               end if;
            elsif ( spiVldO = '1' ) then
               -- got a reply
               v.spiRdyO := '0';
               -- initiate the next SPI transaction
               v.spiVldI := '1';

               if ( ADDR = r.phas ) then
                  v.spiDatI := std_logic_vector( r.addr(8 * r.cnt + 7 downto 8 * r.cnt) );
               end if;

               -- prepare next phase
               case ( r.phas ) is
                  when ADDR =>
                     if ( r.cnt = 0 ) then
                        -- delay one SPI transaction; in ADDR phase we *prepare* the next
                        -- SPI transaction, in DATA phase we examine the *result* of the
                        -- previous transaction; SWITCH is the 1st. SPI shift that results
                        -- in the first data byte.
                        v.phas := SWITCH;
                     else
                        v.cnt  := r.cnt - 1;
                     end if;
                  when SWITCH =>
                     v.cnt  := 3;
                     v.phas := DATA;

                  when DATA =>

                     if    ( r.cnt = 3 ) then
                        v.busRep.rdata := spiDatO & spiDatO & spiDatO & spiDatO;
                     elsif ( r.cnt = 2 ) then
                        v.busRep.rdata(15 downto  8) := spiDatO;
                        v.busRep.rdata(31 downto 24) := spiDatO;
                     elsif ( r.cnt = 1 ) then
                        v.busRep.rdata(23 downto 16) := spiDatO;
                     else
                        v.busRep.rdata(31 downto 24) := spiDatO;
                     end if;
                     if ( r.cnt = r.skip ) then
                        v.cnt     := 0;
                        v.phas    := CSHI;
                        v.spiCsel := CS_NOT_ACTIVE_C;
                     else
                        v.cnt     := r.cnt - 1;
                     end if;

                  when CSHI =>
                     -- done;
                     v.spiVldI      := '0'; -- revoke spiVldI
                     v.spiReq       := '0'; -- relinquish SPI interface
                     v.busRep.valid := '1'; -- signal that reply is ready
                     v.state        := DONE;
               end case;   
            end if;

         when DONE =>
            v.busRep.valid := '0';
            v.state        := IDLE;
      end case;
      rin <= v;
   end process P_COMB;

   P_SEQ : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( rst = '1' ) then
            r <= REG_INIT_C;
         else
            r <= rin;
         end if;
      end if;
   end process P_SEQ;

   busRep  <= r.busRep;

   -- spi controller arbitration
   spiReq  <= r.spiReq;

   -- spi controller request (output of this module)
   spiVldI <= r.spiVldI;
   spiDatI <= r.spiDatI;
   spiCsel <= r.spiCsel;

   -- spi controller reply (input of this module)
   spiRdyO <= r.spiRdyO;

end architecture Impl;
