library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use work.Udp2BusPkg.all;
use work.IlaWrappersPkg.all;

entity Bus2DRP is
   generic (
      GEN_ILA_G  : boolean := true;
      BUS_TIMO_G : natural := 20
   );
   port (
      clk     : in  std_logic;
      rst     : in  std_logic;

      req     : in  Udp2BusReqType := UDP2BUSREQ_INIT_C;
      rep     : out Udp2BusRepType;

      drpAddr : out std_logic_vector(15 downto 0);
      drpEn   : out std_logic;
      drpWe   : out std_logic;
      drpDin  : out std_logic_vector(15 downto 0);
      drpRdy  : in  std_logic := '0';
      drpDou  : in  std_logic_vector(15 downto 0) := (others => '0')
   );
end entity Bus2DRP;

architecture Impl of Bus2DRP is
   type StateType is (IDLE, WAI, DONE);

   type RegType is record
      state       : StateType;
      drpAddr     : std_logic_vector(15 downto 0);
      drpEn       : std_logic;
      drpWe       : std_logic;
      rep         : Udp2BusRepType;
      timo        : natural range 0 to BUS_TIMO_G - 1;
   end record RegType;

   constant REG_INIT_C : RegType := (
      state       => IDLE,
      drpAddr     => (others => '0'),
      drpEn       => '0',
      drpWe       => '0',
      rep         => UDP2BUSREP_INIT_C,
      timo        => 0
   );

   signal r         : RegType := REG_INIT_C;
   signal rin       : RegType;
 
   signal drpAddr_i : std_logic_vector(15 downto 0);
   signal drpWe_i   : std_logic;
   signal drpEn_i   : std_logic;
   signal drpDin_i  : std_logic_vector(15 downto 0);

begin

   P_COMB : process ( r, req, drpDou, drpRdy ) is
      variable v : RegType;
   begin
      v   := r;

      if ( (req.valid and r.rep.valid) = '1' ) then
         v.rep.valid := '0';
         v.state     := IDLE;
         v.timo      := 0;
      end if;

      if ( r.timo > 0 ) then
         v.timo := r.timo - 1;
      end if;

      -- asserted for just one cycle; reset
      v.drpEn := '0';
      v.drpWe := '0';

      case ( r.state ) is
         when IDLE =>
            if ( req.valid = '1' ) then
               if    ( (req.be = "0011") or (req.be = "1100") ) then 
                  v.drpEn  := '1';
                  v.drpWe  := not req.rdnwr;
                  v.state  := WAI;
                  v.timo   := BUS_TIMO_G - 1;
               else
                  v.rep   :=  UDP2BUSREP_ERROR_C;
                  v.state :=  DONE;
               end if;
            end if;

         when WAI  =>
            if ( drpRdy = '1' ) then
               -- replicate across both word lanes
               -- so the result is OK for either word address
               v.rep.rdata := drpDou & drpDou;
               v.rep.valid := '1';
               v.rep.berr  := '0';
               v.state     := DONE;
            elsif ( r.timo = 0 ) then
               v.rep   := UDP2BUSREP_ERROR_C;
               v.state := DONE;
            end if;

         when DONE =>
           -- just wait for rep.valid to clear
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

   GEN_DRP_ILA : if ( GEN_ILA_G ) generate
      U_ILA : component Ila_256
         port map (
            clk                  => clk,
            probe0(0)            => drpEn_i,
            probe0(1)            => drpWe_i,
            probe0(2)            => drpRdy,
            probe0(63 downto  3) => (others => '0'),

            probe1(15 downto  0) => drpAddr_i,
            probe1(31 downto 16) => drpDou,
            probe1(47 downto 32) => drpDin_i,
            probe1(63 downto 48) => (others => '0'),

            probe2(0)            => req.valid,
            probe2(3  downto  1) => "000",
            probe2(7  downto  4) => req.be,
            probe2(15 downto  8) => std_logic_vector(to_unsigned(StateType'pos(r.state), 8)),
            probe2(31 downto 16) => req.data(15 downto 0),
            probe2(33 downto 32) => "00",
            probe2(63 downto 34) => req.dwaddr,

            probe3(0)            => r.rep.valid,
            probe3(1)            => r.rep.berr,
            probe3(15 downto  2) => (others => '0'),
            probe3(31 downto 16) => r.rep.rdata(15 downto 0),
            probe3(63 downto 32) => (others => '0')
         );
   end generate GEN_DRP_ILA;


   drpAddr_i <= req.dwaddr(drpAddr'left - 1 downto 0) & req.be(2);
   drpEn_i   <= r.drpEn;
   drpWe_i   <= r.drpWe;
   drpDin_i  <= req.data(drpDin'range);

   drpAddr   <= drpAddr_i;
   drpEn     <= drpEn_i;
   drpWe     <= drpWe_i;
   drpDin    <= drpDin_i;

   rep       <= r.rep;
end architecture Impl;
