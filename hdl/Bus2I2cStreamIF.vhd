library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.ESCBasicTypesPkg.all;
use work.Lan9254Pkg.all;
use work.Udp2BusPkg.all;

-- byte address range [18:0] (dwaddr [18:2] <-> [16:0] )

-- read/write 8-bit i2c registers
--   i2c-addr   is encoded in byte-addr [18:12] -> dwaddr [16:10]
--   i2c-mux    is encoded in byte-addr [11: 8] -> dwaddr [ 9: 6]
--   i2c-offset is encoded in byte-addr [ 7: 0] -> dwaddr [ 5: 0] + byte-lanes
entity Bus2I2cStreamIF is
   port (
      clk       : in  std_logic;
      rst       : in  std_logic;

      busReq    : in  Udp2BusReqType := UDP2BUSREQ_INIT_C;
      busRep    : out Udp2BusRepType := UDP2BUSREP_INIT_C;

      strmLock  : out std_logic;

      strmMstOb : out Lan9254StrmMstType;
      strmRdyOb : in  std_logic := '1';

      strmMstIb : in  Lan9254StrmMstType := LAN9254STRM_MST_INIT_C;
      strmRdyIb : out std_logic := '1'
   );
end entity Bus2I2cStreamIF;

architecture Impl of Bus2I2cStreamIF is

   type StateType is (IDLE, ADDR, RESP, DONE);

   type RegType is record
      state     : StateType;
      mstOb     : Lan9254StrmMstType;
      busRep    : Udp2BusRepType;
      rdyIb     : std_logic;
      cnt       : natural range 0 to 3;
      off       : std_logic_vector(1 downto 0);
      read      : boolean;
      lock      : std_logic;
   end record RegType;

   constant REG_INIT_C : RegType := (
      state     => IDLE,
      mstOb     => LAN9254STRM_MST_INIT_C,
      busRep    => UDP2BUSREP_INIT_C,
      rdyIb     => '0',
      cnt       => 0,
      off       => "00",
      read      => false,
      lock      => '0'
   );

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

begin

   P_COMB : process( r, busReq, strmRdyOb, strmMstIb ) is
      variable v : RegType;
   begin
      v := r;

      if ( ( busReq.valid and r.busRep.valid ) = '1' ) then
         v.busRep.valid := '0';
         v.state        := IDLE;
      end if;

      case ( r.state ) is
         when IDLE =>
            if ( busReq.valid = '1' ) then
               v.mstOb.data  := busReq.rdnwr & "0000000" & busReq.dwAddr(16 downto 10) & '0';
               v.mstOb.valid := '1';
               v.mstOb.ben   := "11";
               v.mstOb.usr   := busReq.dwAddr(9 downto 6);
               v.mstOb.last  := '0';
               v.state       := ADDR;
               v.read        := (busReq.rdnwr = '1');
               v.lock        := '1';
               if    ( busReq.be = "0001" ) then
                  v.off := "00";
               elsif ( busReq.be = "0010" ) then
                  v.off := "01";
               elsif ( busReq.be = "0100" ) then
                  v.off := "10";
               elsif ( busReq.be = "1000" ) then
                  v.off := "11";
               else
                  v.busRep      := UDP2BUSREP_ERROR_C;
                  v.state       := DONE;
                  -- revoke valid
                  v.mstOb.valid := '0';
                  v.lock        := '0';
               end if;
            end if;

         when ADDR =>
           if ( (r.mstOb.valid and strmRdyOb) = '1' ) then
              -- I2c address was sent; write register address
              v.mstOb.data(7 downto 0) := busReq.dwaddr(5 downto 0) & r.off;
              v.mstOb.last             := '1';
              if ( busReq.rdnwr = '1' ) then
                 v.mstOb.ben(1) := '0';
              else
                 if    ( r.off = "00" ) then
                    v.mstOb.data(15 downto 8) := busReq.data( 7 downto  0);
                 elsif ( r.off = "01" ) then
                    v.mstOb.data(15 downto 8) := busReq.data(15 downto  8);
                 elsif ( r.off = "10" ) then
                    v.mstOb.data(15 downto 8) := busReq.data(23 downto 16);
                 else
                    v.mstOb.data(15 downto 8) := busReq.data(31 downto 24);
                 end if;
              end if;
              v.state := RESP;
           end if;

         when RESP =>
           if ( r.mstOb.valid = '1' ) then
              if ( strmRdyOb = '1' ) then
                 v.mstOb.valid := '0';
                 v.rdyIb       := '1';
              end if;
           elsif ( strmMstIb.valid = '1' ) then
              v.rdyIb := '0';

              -- reply to bus master
              v.busRep.rdata(31 downto 24) := strmMstIb.data(7 downto 0);
              v.busRep.rdata(23 downto 16) := strmMstIb.data(7 downto 0);
              v.busRep.rdata(15 downto  8) := strmMstIb.data(7 downto 0);
              v.busRep.rdata( 7 downto  0) := strmMstIb.data(7 downto 0);
              v.busRep.valid               := '1';
              v.state                      := DONE;
              v.lock                       := '0';
              if ( strmMstIb.ben = "00" ) then
                 v.busRep.berr := '1';
              else
                 v.busRep.berr := '0';
                 if ( r.read ) then
                    -- initiate read back
                    v.mstOb.data    := '0' & "0000000" & busReq.dwAddr(16 downto 10) & '1';
                    v.mstOb.valid   := '1';
                    v.mstOb.ben     := "01";
                    v.mstOb.last    := '1';
                    -- wait for reply
                    v.state         := RESP;
                    -- revoke changes made above since we are not DONE yet
                    v.busRep.valid  := '0';
                    v.read          := false;
                    v.lock          := '1';
                 end if;
              end if;
           end if;

         when DONE =>
            -- wait for busRep.valid to clear
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

   busRep    <= r.busRep;
   strmMstOb <= r.mstOb;
   strmRdyIb <= r.rdyIb;
   strmLock  <= r.lock;

end architecture Impl;

