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
      pDly : unsigned(config.pulseDelay'left + 1 downto 0);
      pWid : unsigned(config.pulseWidth'left + 1 downto 0);
   end record RegType;

   constant REG_INIT_C : RegType := (
      pDly => (others => '0'),
      pWid => (others => '0')
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
      -- event starts a new pulse (if enabled)
      if ( ( ( config.pulseEnbld and event_vld ) = '1' ) and ( event_code = config.pulseEvent ) ) then
         -- make sure current pulse is aborted
         v.pWid(v.pWid'left) := '0';
         -- load new delay
         prevDly             := unsigned( '1' & config.pulseDelay );
      else
         prevDly             := r.pDly;
      end if;
      -- compute next delay counter
      if ( prevDly(prevDly'left) = '1' ) then
         v.pDly := prevDly - 1;
      end if;
      -- if next delay is expired then load the pulse width counter
      if ( (v.pDly(v.pDly'left) = '0') and (prevDly(prevDly'left) = '1') ) then
         prevWid             := unsigned( '1' & config.pulseWidth );
      else
         prevWid             := r.pWid;
      end if;
      -- compute next pulse width
      if ( prevWid(prevWid'left) = '1' ) then
         v.pWid := prevWid - 1;
      end if;
      -- gate output and register (
      pin <= (v.pWid(v.pWid'left) and config.pulseEnbld) xor config.pulseInvrt;
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
