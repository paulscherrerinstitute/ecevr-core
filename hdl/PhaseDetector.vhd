library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library unisim;
use     unisim.vcomponents.all;

entity PhaseDetector is
   generic (
      FLEN_G       : natural  := 16;
      USE_MMCM_G   : boolean  := true;
      DECM_MULT_G  : positive := 1;
      CLK_PERIOD_G : real         -- in ns.
   );
   port (
      pclk       : in  std_logic_vector(1 downto 0);

      clk        : in  std_logic;
      rst        : in  std_logic;

      phas       : out signed(FLEN_G - 1 downto 0);
      locked     : out std_logic
   );
end entity PhaseDetector;

architecture rtl of PhaseDetector is
   constant     USE_IIR_C    : boolean := false;

   -- fdet = fin * (FBDIV_INT_C*8 + FBDIV_8TH_C)/(ODIV_INT_C*8 + ODIV_8TH_C);
   --
   -- fdel = fin - fdet = fdet ((8*ODIV_INT_C + ODIV_8TH_C) / (FBDIV_INT_C*8 + FBDIV_8TH_C) - 1)
   --      assuming ODIV_INT_C == FBDIV_INT_C
   -- fdel = fdet * (ODIV_8TH_C - FBDIV_8TH_C)/(FBDIV_INT_C*8 + FBDIV_8TH_C)
   --
   -- fdel smallest if | ODIV_8TH_C - FBDIV_8TH_C | = 1
   --                    ODIV_8TH_C = FBDIV_8TH_C +/- 1
   function check(constant l : string; constant x : real) return real is
   begin
      report l & " " & real'image(x);
      return x;
   end function check;

   function check(constant l : string; constant x : natural) return natural is
   begin
      report l & " " & integer'image(x);
      return x;
   end function check;


   constant     VCO_MAX_C    : real    := 1.4400; -- GHz
   constant     FBDIV_REA_C  : real    := check("FBDIV_REA_C", VCO_MAX_C * CLK_PERIOD_G);
   constant     FBDIV_INT_C  : natural := check("FBDIV_INT_C", natural( floor( FBDIV_REA_C ) ));
   constant     FBDIV_FRC_C  : real    := check("FBDIV_FRC_C", FBDIV_REA_C - real(FBDIV_INT_C));
   constant     FBDIV_8TH_C  : natural := check("FBDIV_8TH_C", natural( check("FBDIV_8TH_PRE", floor( 8.0 * FBDIV_FRC_C) ) ));
   constant     ODIV_INT_C   : natural := FBDIV_INT_C;
   constant     ODIV_8TH_C   : natural := FBDIV_8TH_C + 1;

   constant     MULT_F_C     : real    := real(FBDIV_INT_C) + 0.125*real(FBDIV_8TH_C);
   constant     DIV0_F_C     : real    := real(ODIV_INT_C ) + 0.125*real(ODIV_8TH_C );

   constant     PHAS_MAX_C   : natural := DECM_MULT_G * (8 * FBDIV_INT_C + FBDIV_8TH_C);

   function PHAS_BITS_F return natural is
      variable l : natural;
   begin
      -- full range is - PHAS_MAX_C .. + PHAS_MAX_C;
      l := natural( floor( log2( real( 2 * PHAS_MAX_C ) ) ) ) + 1;
      if ( l < FLEN_G ) then
         l := FLEN_G;
      end if;
      return l;
   end function PHAS_BITS_F;

   signal       pclk_i       : std_logic_vector(pclk'range);
   signal       detclk       : std_logic;
   signal       detclk_i     : std_logic;

   signal       clkfb        : std_logic;

   signal       phas_i       : signed(PHAS_BITS_F - 1 downto 0) := (others => '0');

   signal       det          : std_logic;

   signal       pclk10       : std_logic;
   signal       pclk10_i     : std_logic;

   signal       pclk_ii      : std_logic_vector(pclk'range);
begin

   assert false report "DIV_i "   & integer'image(ODIV_INT_C)
                     & " ODIV_f " & integer'image(ODIV_8TH_C)
                     & " FDIV_f " & integer'image(FBDIV_8TH_C)
                severity note;

   GEN_FF : for i in pclk'range generate
      signal ffp     : std_logic_vector(pclk'range) := (others => '0');
      signal ffn     : std_logic_vector(pclk'range) := (others => '0');
   begin
      P_FF : process ( pclk(i) ) is
      begin
         if ( rising_edge( pclk(i) ) ) then
            ffp(i) <= not ffp(i);
         end if;
         if ( falling_edge( pclk(i) ) ) then
            ffn(i) <= ffp(i);
         end if;
      end process P_FF;

      pclk_ii(i)  <= ffp(i) xor ffn(i);

      U_SYNC : entity work.Synchronizer
         generic map (
            STAGES_G => 3
         )
         port map (
            clk      => detclk,
            rst      => '0',
            dataIn   => pclk_ii(i),
            dataOut  => pclk_i(i)
         );
   end generate GEN_FF;

   GEN_MMCM : if ( USE_MMCM_G ) generate

      signal vld_wr : std_logic := '0';
      signal vld_rd : std_logic;
      signal ack_rd : std_logic := '0';
      signal ack_wr : std_logic;

      signal mbox_wr: signed(phas'range) := (others => '0');
      signal mbox_rd: signed(phas'range) := (others => '0');

   begin

   U_MMCM : MMCME2_BASE
   generic map (
      BANDWIDTH          => "OPTIMIZED",  -- Jitter programming (OPTIMIZED, HIGH, LOW)
      -- Artix-7 VCO fmax[MHz]: 1600 (speed -3), 1440 (speed -2), 1200 (speed -1)
      CLKFBOUT_MULT_F    => MULT_F_C,    -- Multiply value for all CLKOUT (2.000-64.000).
      CLKFBOUT_PHASE     => 0.0,     -- Phase offset in degrees of CLKFB (-360.000-360.000).
      CLKIN1_PERIOD      => CLK_PERIOD_G,      -- Input clock period in ns to ps resolution (i.e. 33.333 is 30 MHz).
      -- CLKOUT0_DIVIDE - CLKOUT6_DIVIDE: Divide amount for each CLKOUT (1-128)
      CLKOUT1_DIVIDE     => 7,
      CLKOUT2_DIVIDE     => 7,
      CLKOUT3_DIVIDE     => 7,
      CLKOUT4_DIVIDE     => 7,
      CLKOUT5_DIVIDE     => 7,
      CLKOUT6_DIVIDE     => 7,
      CLKOUT0_DIVIDE_F   => DIV0_F_C,   -- Divide amount for CLKOUT0 (1.000-128.000).
      -- CLKOUT0_DUTY_CYCLE - CLKOUT6_DUTY_CYCLE: Duty cycle for each CLKOUT (0.01-0.99).
      CLKOUT0_DUTY_CYCLE => 0.5,
      CLKOUT1_DUTY_CYCLE => 0.5,
      CLKOUT2_DUTY_CYCLE => 0.5,
      CLKOUT3_DUTY_CYCLE => 0.5,
      CLKOUT4_DUTY_CYCLE => 0.5,
      CLKOUT5_DUTY_CYCLE => 0.5,
      CLKOUT6_DUTY_CYCLE => 0.5,
      -- CLKOUT0_PHASE - CLKOUT6_PHASE: Phase offset for each CLKOUT (-360.000-360.000).
      CLKOUT0_PHASE      => 0.0,
      CLKOUT1_PHASE      => 0.0,
      CLKOUT2_PHASE      => 0.0,
      CLKOUT3_PHASE      => 0.0,
      CLKOUT4_PHASE      => 0.0,
      CLKOUT5_PHASE      => 0.0,
      CLKOUT6_PHASE      => 0.0,
      CLKOUT4_CASCADE    => FALSE,  -- Cascade CLKOUT4 counter with CLKOUT6 (FALSE, TRUE)
      DIVCLK_DIVIDE      => 1,        -- Master division value (1-106)
      REF_JITTER1        => 0.0,        -- Reference input jitter in UI (0.000-0.999).
      STARTUP_WAIT       => FALSE      -- Delays DONE until MMCM is locked (FALSE, TRUE)
   )
   port map (
      -- Clock Outputs: 1-bit (each) output: User configurable clock outputs
      CLKOUT0            => detclk_i,     -- 1-bit output: CLKOUT0
      CLKOUT0B           => open,   -- 1-bit output: Inverted CLKOUT0
      CLKOUT1            => open,     -- 1-bit output: CLKOUT1
      CLKOUT1B           => open,   -- 1-bit output: Inverted CLKOUT1
      CLKOUT2            => open,     -- 1-bit output: CLKOUT2
      CLKOUT2B           => open,   -- 1-bit output: Inverted CLKOUT2
      CLKOUT3            => open,     -- 1-bit output: CLKOUT3
      CLKOUT3B           => open,   -- 1-bit output: Inverted CLKOUT3
      CLKOUT4            => open,     -- 1-bit output: CLKOUT4
      CLKOUT5            => open,     -- 1-bit output: CLKOUT5
      CLKOUT6            => open,     -- 1-bit output: CLKOUT6
      -- Feedback Clocks: 1-bit (each) output: Clock feedback ports
      CLKFBOUT           => clkfb,   -- 1-bit output: Feedback clock
      CLKFBOUTB          => open, -- 1-bit output: Inverted CLKFBOUT
      -- Status Ports: 1-bit (each) output: MMCM status ports
      LOCKED             => locked,       -- 1-bit output: LOCK
      -- Clock Inputs: 1-bit (each) input: Clock input
      CLKIN1             => pclk(0),       -- 1-bit input: Clock
      -- Control Ports: 1-bit (each) input: MMCM control ports
      PWRDWN             => '0',       -- 1-bit input: Power-down
      RST                => rst,             -- 1-bit input: Reset
      -- Feedback Clocks: 1-bit (each) input: Clock feedback ports
      CLKFBIN            => clkfb      -- 1-bit input: Feedback clock
   );

   U_BUF : BUFG
      port map (
         I => detclk_i,
         O => detclk
      );


   U_SYNC_V : entity work.Synchronizer
      generic map (
         STAGES_G => 3
      )
      port map (
         clk      => clk,
         rst      => '0',
         dataIn   => vld_wr,
         dataOut  => vld_rd
      );

   U_SYNC_A : entity work.Synchronizer
      generic map (
         STAGES_G => 3
      )
      port map (
         clk      => detclk,
         rst      => '0',
         dataIn   => ack_rd,
         dataOut  => ack_wr
      );

   P_MBOX_WR : process ( detclk ) is
   begin
      if ( rising_edge( detclk ) ) then
         if ( ack_wr = vld_wr ) then
            vld_wr  <= not vld_wr;
            mbox_wr <= phas_i(phas_i'left downto phas_i'left - mbox_wr'length + 1);
         end if;
      end if;
   end process P_MBOX_WR;

   P_MBOX_RD : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( ack_rd /= vld_rd ) then
            ack_rd  <= not ack_rd;
            mbox_rd <= mbox_wr;
         end if;
      end if;
   end process P_MBOX_RD;

   phas <= mbox_rd;

   end generate GEN_MMCM;

   GEN_NO_MMCM : if ( not USE_MMCM_G ) generate
      locked <= '1';
      detclk <= clk;
      phas   <= phas_i(phas_i'left downto phas_i'left - phas'length + 1);
   end generate GEN_NO_MMCM;

   U_SYNC_10 : entity work.Synchronizer
      generic map (
         STAGES_G => 3
      )
      port map (
         clk      => pclk(0),
         rst      => '0',
         dataIn   => pclk_ii(1),
         dataOut  => pclk10_i
      );

   U_SYNC_P : entity work.Synchronizer
      generic map (
         STAGES_G => 3
      )
      port map (
         clk      => detclk,
         rst      => '0',
         dataIn   => pclk10_i,
         dataOut  => pclk10
      );

   det <= pclk_i(0) xor pclk_i(1);

   G_IIR : if ( USE_IIR_C ) generate

   P_FILT : process ( detclk ) is

      function PONE_F(constant x : in signed) return signed is
         variable v : signed(x'range);
      begin
         v := (others => '0');
         v( v'left     ) := '0';
         v( v'left - 1 ) := '1';
         return v;
      end function PONE_F;

      constant PONE : signed(phas_i'range) := PONE_F(phas_i);
      constant MONE : signed(phas_i'range) := - PONE;
      constant ZERO : signed(phas_i'range) := (others => '0');
      constant SHFT : natural              := phas_i'length - 13;
   begin
      if ( rising_edge ( detclk ) ) then
         if ( det = '1' ) then
            if ( pclk10 = '1' ) then
               phas_i <= phas_i + shift_right(PONE - phas_i, SHFT);
            else
               phas_i <= phas_i + shift_right(MONE - phas_i, SHFT);
            end if;
         else
               phas_i <= phas_i + shift_right(ZERO - phas_i, SHFT);
         end if;
      end if;
   end process P_FILT;

   end generate G_IIR;

   G_CIC : if ( not USE_IIR_C ) generate

      constant DECM_C : natural            := PHAS_MAX_C - 1;

      signal phas_l   : signed(phas_i'range) := (others => '0');
      signal phas_a   : signed(phas_i'range) := (others => '0');

      signal decm     : natural range 0 to DECM_C := 0;


   begin

   P_FILT : process ( detclk ) is
   begin
      if ( rising_edge ( detclk ) ) then
         if ( decm = 0 ) then
            phas_l <= phas_a;
            phas_i <= phas_a - phas_l;
            decm   <= DECM_C;
         else
            decm   <= decm - 1;
         end if;
         if ( det = '1' ) then
            if ( pclk10 = '1' ) then
               phas_a <= phas_a + 1;
            else
               phas_a <= phas_a - 1;
            end if;
         end if;
      end if;
   end process P_FILT;
   end generate G_CIC;

end architecture rtl;
