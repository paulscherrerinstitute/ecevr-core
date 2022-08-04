library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.ESCBasicTypesPkg.all;
use work.Lan9254Pkg.all;
use work.IlaWrappersPkg.all;

entity I2cWrapper is
   generic (
      CLOCK_FREQ_G       : real;               --Hz; at least 12*i2c freq
      I2C_FREQ_G         : real    := 100.0E3; --Hz
      I2C_BUSY_TIMEOUT_G : real    := 0.1;     -- sec
      I2C_CMD_TIMEOUT_G  : real    := 1.0E-3;  -- sec
      NUM_I2C_MST_G      : natural := 1;
      NUM_I2C_BUS_G      : natural := 1;
      GEN_I2CSTRM_ILA_G  : boolean := true
   );
   port (
      clk                : in  std_logic;
      rst                : in  std_logic;

      i2cStrmMstIb       : in  Lan9254StrmMstArray(NUM_I2C_MST_G - 1 downto 0);
      i2cStrmRdyIb       : out std_logic_vector   (NUM_I2C_MST_G - 1 downto 0);
      i2cStrmMstOb       : out Lan9254StrmMstArray(NUM_I2C_MST_G - 1 downto 0);
      i2cStrmRdyOb       : in  std_logic_vector   (NUM_I2C_MST_G - 1 downto 0);

      -- a stream master locks access to the i2c master once first granted access.
      -- it must de-assert its corresponding bit in i2cStrmLock to relinquish
      -- the master.
      i2cStrmLock        : in  std_logic_vector   (NUM_I2C_MST_G - 1 downto 0) := (others => '1');

      i2cSclInp          : in  std_logic_vector(NUM_I2C_BUS_G - 1 downto 0) := (others => '1');
      i2cSclOut          : out std_logic_vector(NUM_I2C_BUS_G - 1 downto 0);
      i2cSclHiZ          : out std_logic_vector(NUM_I2C_BUS_G - 1 downto 0);

      i2cSdaInp          : in  std_logic_vector(NUM_I2C_BUS_G - 1 downto 0) := (others => '1');
      i2cSdaOut          : out std_logic_vector(NUM_I2C_BUS_G - 1 downto 0);
      i2cSdaHiZ          : out std_logic_vector(NUM_I2C_BUS_G - 1 downto 0)

   );
end entity I2cWrapper;

architecture Impl of I2cWrapper is

   signal strmTxMst, strmRxMst : Lan9254StrmMstType;
   signal strmTxRdy, strmRxRdy : std_logic;
   signal debug                : std_logic_vector(63 downto 0);

   -- mux selection encoded in i2cStrmMstIb.usr
   signal i2cMuxSel            : natural;

   signal sclI, sclO, sclZ, sdaI, sdaO, sdaZ : std_logic;

begin

   U_MUX  : entity work.StrmMux
      generic map (
         NUM_MSTS_G      => NUM_I2C_MST_G
      )
      port map (
         clk             => clk,
         rst             => rst,

         busLock         => i2cStrmLock,

         reqMstIb        => i2cStrmMstIb,
         reqRdyIb        => i2cStrmRdyIb,
         repMstIb        => i2cStrmMstOb,
         repRdyIb        => i2cStrmRdyOb,


         reqMstOb(0)     => strmTxMst,
         reqRdyOb(0)     => strmTxRdy,
         repMstOb(0)     => strmRxMst,
         repRdyOb(0)     => strmRxRdy,

         debug           => debug
      );

   U_STRM : entity work.PsiI2cStreamIF
      generic map (
         CLOCK_FREQ_G   => CLOCK_FREQ_G,
         I2C_FREQ_G     => I2C_FREQ_G,
         BUSY_TIMEOUT_G => I2C_BUSY_TIMEOUT_G,
         CMD_TIMEOUT_G  => I2C_CMD_TIMEOUT_G,
         GEN_ILA_G      => GEN_I2CSTRM_ILA_G
      )
      port map (
         clk            => clk,
         rst            => rst,

         strmMstIb      => strmTxMst,
         strmRdyIb      => strmTxRdy,

         strmMstOb      => strmRxMst,
         strmRdyOb      => strmRxRdy,

         i2c_scl_i      => sclI,
         i2c_scl_o      => sclO,
         i2c_scl_t      => sclZ,

         i2c_sda_i      => sdaI,
         i2c_sda_o      => sdaO,
         i2c_sda_t      => sdaZ,

         debug          => debug
      );

   i2cMuxSel <= natural( to_integer( unsigned( strmTxMst.usr ) ) );

   P_I2C_MUX : process ( i2cSclInp, i2cSdaInp, i2cMuxSel, sclO, sclZ, sdaO, sdaZ ) is
   begin
      sclI                   <= i2cSclInp( i2cMuxSel );
      sdaI                   <= i2cSdaInp( i2cMuxSel );
      i2cSclOut              <= (others => '1');
      i2cSclHiZ              <= (others => '1');
      i2cSdaOut              <= (others => '1');
      i2cSdaHiZ              <= (others => '1');
      i2cSclOut( i2cMuxSel ) <= sclO;
      i2cSclHiZ( i2cMuxSel ) <= sclZ;
      i2cSdaOut( i2cMuxSel ) <= sdaO;
      i2cSdaHiZ( i2cMuxSel ) <= sdaZ;
   end process P_I2C_MUX;

end architecture Impl;
