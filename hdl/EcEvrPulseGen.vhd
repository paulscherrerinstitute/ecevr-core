library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.ESCBasicTypesPkg.all;
use work.Evr320ConfigPkg.all;

entity EcEvrPulseGen is
   generic (
      PULSE_INI_G : std_logic := '0';
      -- whether to try to load the pulse output into an IOB (xilinx)
      -- "TRUE" or "FALSE"
      USE_IOB_G   : string    := "TRUE"
   );
   port (
      clk         : in  std_logic;
      rst         : in  std_logic := '0';

      event_code  : in  std_logic_vector(7 downto 0);
      event_vld   : in  std_logic;

      pulse_out   : out std_logic;

      config      : in  Evr320PulseGenConfigType
   );
end entity EcEvrPulseGen;

architecture Impl of EcEvrPulseGen is

   attribute IOB          : string;

   type RegType is record
      cDly : signed(config.pulseDelay'left + 1 downto 0);
      cWid : signed(config.pulseWidth'left + 1 downto 0);
      pDly : signed(config.pulseDelay'left + 1 downto 0);
      pWid : signed(config.pulseWidth'left + 1 downto 0);
      code : std_logic_vector(7 downto 0);
   end record RegType;

   constant REG_INIT_C : RegType := (
      cDly => (others => '1'),
      cWid => (others => '1'),
      pDly => (others => '1'),
      pWid => (others => '1'),
      code => (others => '0')
   );

   signal r              : RegType := REG_INIT_C;
   signal rin            : RegType;

   signal pin            : std_logic;

   signal puls_r         : std_logic := PULSE_INI_G;
   attribute IOB         of puls_r   :  signal is USE_IOB_G;

begin

   P_COMB : process ( r, config, event_code, event_vld ) is
      variable v       : RegType;
      variable prevDly : unsigned(r.pDly'range);
      variable prevWid : unsigned(r.pWid'range);
   begin
      v := r;

      -- register config
      v.cDly := signed( '0' & config.pulseDelay ) - 1;
      v.cWid := signed( '0' & config.pulseWidth ) - 1;
      v.code := config.pulseEvent;
      if ( ( config.pulseEnbld = '0' ) or ( config.pulseEvent = x"00" ) ) then
         v.cWid := (others => '1');
      end if;

      -- counters
      if ( r.pDly( r.pDly'left ) = '0' ) then
         v.pDly := r.pDly - 1;
      end if;

      if ( r.pWid( r.pWid'left ) = '0' ) then
         v.pWid := r.pWid - 1;
      end if;

      if ( ( v.pDly( v.pDly'left ) = '1' ) and ( r.pDly( r.pDly'left ) = '0' ) ) then
         v.pWid := r.cWid;
      end if;

      -- event starts a new pulse (if enabled)
      if ( ( ( not r.cWid( r.cWid'left ) and event_vld ) = '1' ) and ( event_code = r.code ) ) then
         -- make sure current pulse is aborted
         v.pWid := (others => '1');
         -- load new delay
         v.pDly := r.cDly;
         if ( r.cDly( r.cDly'left ) = '1' ) then
            -- no delay; start width immediately
            v.pWid := r.cWid;
         end if;
      end if;

      -- gate output and register (
      pin <= (not v.pWid(v.pWid'left) and config.pulseEnbld) xor config.pulseInvrt;
      rin <= v;
   end process P_COMB;

   P_SEQ : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( rst = '1' ) then
            r      <= REG_INIT_C;
            puls_r <= config.pulseInvrt;
         else
            r      <= rin;
            puls_r <= pin;
         end if;
      end if;
   end process P_SEQ;

   pulse_out <= puls_r;

end architecture Impl;
