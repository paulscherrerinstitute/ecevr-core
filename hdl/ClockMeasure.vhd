library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

-- clock frequency measurement with just a single CDC bit

entity ClockMeasure is
   generic (
      REF_FREQUENCY_G       : real;
      -- max. supported frequency is 2**MEAS_FREQ_WIDTH_G - 1
      MEAS_FREQ_WIDTH_G     : natural
   );
   port (
      measClk               : in  std_logic;
      refClk                : in  std_logic;
      hiRes                 : in  std_logic := '0';
      -- measured frequency (in refClk domain)
      freqOut               : out unsigned(MEAS_FREQ_WIDTH_G - 1 downto 0);
      -- valid asserted for 1 cycle when freqOut is updated
      freqVldOut            : out std_logic
   );
end entity ClockMeasure;

architecture rtl of ClockMeasure is

   constant MAX_FREQ_C      : real := 2.0**real(MEAS_FREQ_WIDTH_G) - 1.0;

   function BITS_F(constant x : real) return natural is
      variable n : natural;
      variable v : real;
   begin
      v := 1.0;
      n := 0;
      while ( x > v ) loop 
         v := v*2.0;
         n := n + 1;
      end loop;
      return n;
   end function BITS_F;


   -- prescale the measured clock to < FREQ_FREQUENCY_G / 2
   function PRESC_BITS_F return natural is
      variable v : real;
      variable n : natural;
   begin
      return BITS_F( MAX_FREQ_C / (REF_FREQUENCY_G / 2.0) );
   end function PRESC_BITS_F;

   constant PRESC_BITS_C    : natural := PRESC_BITS_F;

   subtype  TimerType       is unsigned(BITS_F(REF_FREQUENCY_G) + PRESC_BITS_C + 1 - 1 downto 0);

   constant TIME_HR_C       : TimerType := to_unsigned( natural(REF_FREQUENCY_G) * 2**PRESC_BITS_C, TimerType'length );
   constant TIME_LR_C       : TimerType := to_unsigned( natural(REF_FREQUENCY_G)                  , TimerType'length );

   -- extra bit holds toggle state
   signal prescaler         : unsigned(PRESC_BITS_C downto 0)          := (others => '0');
   signal measSynced        : std_logic;
   signal measLast          : std_logic;

   signal freqMeas          : unsigned(MEAS_FREQ_WIDTH_G - 1 downto 0) := (others => '0');
   signal freqVld           : std_logic                                := '0';
   signal timeBase          : TimerType                                := (others => '0');

begin

   P_PRESCALER : process ( measClk ) is
   begin
      if ( rising_edge( measClk ) ) then
         prescaler <= prescaler + 1;
      end if;
   end process P_PRESCALER;

   U_SYNC : entity work.SynchronizerBit
      port map (
         clk        => refClk,
         rst        => '0',
         datInp(0)  => prescaler(prescaler'left),
         datOut(0)  => measSynced
      );

   P_MEAS : process ( refClk ) is
   begin
      if ( rising_edge( refClk ) ) then
         measLast <= measSynced;
         if ( measSynced /= measLast ) then
            -- count transition
            freqMeas <= freqMeas + 1;
         end if;
         timeBase <= timeBase - 1;
         if ( freqVld = '1' ) then
            freqMeas <= (others => '0');
            if ( hiRes = '1' ) then
               timeBase <= TIME_HR_C - 2;
            else
               timeBase <= TIME_LR_C - 2;
            end if;
         end if;
      end if;
   end process P_MEAS;

   P_MUX : process ( hiRes, freqMeas ) is
   begin
      if ( hiRes = '1' ) then
         freqOut <= freqMeas;
      else
         freqOut <= shift_left(freqMeas, PRESC_BITS_C);
      end if;
   end process P_MUX;

   freqVld    <= timeBase(timeBase'left);
   freqVldOut <= freqVld;

end architecture rtl;
