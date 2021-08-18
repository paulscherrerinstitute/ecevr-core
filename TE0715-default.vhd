-------------------------------------------------------------------------------
-- File       : TE0715.vhd
-- Company    : SLAC National Accelerator Laboratory
-- Created    : 2015-04-08
-- Last update: 2017-02-16
-------------------------------------------------------------------------------
-- Description: Top Level Entity
-------------------------------------------------------------------------------
-- This file is part of 'Example Project Firmware'.
-- It is subject to the license terms in the LICENSE.txt file found in the
-- top-level directory of this distribution and at:
--    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html.
-- No part of 'Example Project Firmware', including this file,
-- may be copied, modified, propagated, or distributed except according to
-- the terms contained in the LICENSE.txt file.
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- Structurally this project is a bit of a mess. This is due to the fact that
-- In SURF and Timing the MGTs are handled independently, i.e., ethernet and
-- timing 'embed' MGTs in their respective wrappers.
-- No problem because they can be clocked by individual 'channel PLLs'.
--
-- However, the Artix/GTP Transceiver lacks individual channel PLLs and therefore
-- must use/share the two available quad PLLs.
-- Unfortunately, both, the SURF/ethernet as well as the timing wrappers assume
-- they are the sole owners of a quad and instantiate the quad PLL which creates
-- a conflict.
--
-- When only a single quad is available then timing and ethernet have to share
-- the quad PLLs (each one can use one of the two available PLLs).
--
-- OTOH, we don't want to change the structure completely as it works fine for
-- other platforms (GTX). For this reason a modified version of the ethernet
-- wrapper was created (GigEthGtp7WrapperAdv) which adds ports and generics
-- that provide outside access to the quad pll.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.StdRtlPkg.all;
use work.AxiStreamPkg.all;
use work.AxiLitePkg.all;
use work.AxiPkg.all;
use work.EthMacPkg.all;
use work.TimingPkg.all;
use work.TimingConnectorPkg.all;
use work.ZynqBspPkg.all;
use work.Ila_256Pkg.all;

library unisim;
use unisim.vcomponents.all;

entity TE0715 is
   generic (
      TPD_G             : time    := 1 ns;
      BUILD_INFO_G      : BuildInfoType;
      SIM_SPEEDUP_G     : boolean := false;
      SIMULATION_G      : boolean := false;
      NUM_TRIGS_G       : natural := 7;
      CLK_FEEDTHRU_G    : boolean := false;
      -- Did you set bit PMA_RSV2[5] of your GTX? See UG476 page 209.
      -- Otherwise the eye-scan is completely red
      PRJ_VARIANT_G     : string  := "deflt"; -- when 'ibert', load ip/_ibert_.xci
      NUM_SFPS_G        : natural := 2;
      PRJ_PART_G        : string;
      TIMING_ETH_MGT_G  : natural range 0 to 2 := 2 -- which MGT to use for the timing ethernet stream
   );
   port (
      DDR_addr          : inout STD_LOGIC_VECTOR ( 14 downto 0 );
      DDR_ba            : inout STD_LOGIC_VECTOR (  2 downto 0 );
      DDR_cas_n         : inout STD_LOGIC;
      DDR_ck_n          : inout STD_LOGIC;
      DDR_ck_p          : inout STD_LOGIC;
      DDR_cke           : inout STD_LOGIC;
      DDR_cs_n          : inout STD_LOGIC;
      DDR_dm            : inout STD_LOGIC_VECTOR ( 3 downto 0 );
      DDR_dq            : inout STD_LOGIC_VECTOR ( 31 downto 0 );
      DDR_dqs_n         : inout STD_LOGIC_VECTOR ( 3 downto 0 );
      DDR_dqs_p         : inout STD_LOGIC_VECTOR ( 3 downto 0 );
      DDR_odt           : inout STD_LOGIC;
      DDR_ras_n         : inout STD_LOGIC;
      DDR_reset_n       : inout STD_LOGIC;
      DDR_we_n          : inout STD_LOGIC;
      FIXED_IO_ddr_vrn  : inout STD_LOGIC;
      FIXED_IO_ddr_vrp  : inout STD_LOGIC;
      FIXED_IO_mio      : inout STD_LOGIC_VECTOR ( 53 downto 0 );
      FIXED_IO_ps_clk   : inout STD_LOGIC;
      FIXED_IO_ps_porb  : inout STD_LOGIC;
      FIXED_IO_ps_srstb : inout STD_LOGIC;

      mgtRefClkP        : in  slv(1 downto 0);
      mgtRefClkN        : in  slv(1 downto 0);
      mgtTxP            : out slv(3 downto 0);
      mgtTxN            : out slv(3 downto 0);
      mgtRxP            : in  slv(3 downto 0);
      mgtRxN            : in  slv(3 downto 0);

      B13_L0            : inout std_logic := 'Z';
      B13_L1_P          : inout std_logic := 'Z';
      B13_L1_N          : inout std_logic := 'Z';
      B13_L2_P          : inout std_logic := 'Z';
      B13_L2_N          : inout std_logic := 'Z';
      B13_L3_P          : inout std_logic := 'Z';
      B13_L3_N          : inout std_logic := 'Z';
      B13_L4_P          : inout std_logic := 'Z';
      B13_L4_N          : inout std_logic := 'Z';
      B13_L5_P          : inout std_logic := 'Z';
      B13_L5_N          : inout std_logic := 'Z';
      B13_L6_P          : inout std_logic := 'Z';
      B13_L6_N          : inout std_logic := 'Z';
      B13_L7_P          : inout std_logic := 'Z';
      B13_L7_N          : inout std_logic := 'Z';
      B13_L8_P          : inout std_logic := 'Z';
      B13_L8_N          : inout std_logic := 'Z';
      B13_L9_P          : inout std_logic := 'Z';
      B13_L9_N          : inout std_logic := 'Z';
      B13_L10_P         : inout std_logic := 'Z';
      B13_L10_N         : inout std_logic := 'Z';
      B13_L11_P         : inout std_logic := 'Z';
      B13_L11_N         : inout std_logic := 'Z';
      B13_L12_P         : inout std_logic := 'Z';
      B13_L12_N         : inout std_logic := 'Z';
      B13_L13_P         : inout std_logic := 'Z';
      B13_L13_N         : inout std_logic := 'Z';
      B13_L14_P         : inout std_logic := 'Z';
      B13_L14_N         : inout std_logic := 'Z';
      B13_L15_P         : inout std_logic := 'Z';
      B13_L15_N         : inout std_logic := 'Z';
      B13_L16_P         : inout std_logic := 'Z';
      B13_L16_N         : inout std_logic := 'Z';
      B13_L17_P         : inout std_logic := 'Z';
      B13_L17_N         : inout std_logic := 'Z';
      B13_L18_P         : inout std_logic := 'Z';
      B13_L18_N         : inout std_logic := 'Z';
      B13_L19_P         : inout std_logic := 'Z';
      B13_L19_N         : inout std_logic := 'Z';
      B13_L20_P         : inout std_logic := 'Z';
      B13_L20_N         : inout std_logic := 'Z';
      B13_L21_P         : inout std_logic := 'Z';
      B13_L21_N         : inout std_logic := 'Z';
      B13_L22_P         : inout std_logic := 'Z';
      B13_L22_N         : inout std_logic := 'Z';
      B13_L23_P         : inout std_logic := 'Z';
      B13_L23_N         : inout std_logic := 'Z';
      B13_L24_P         : inout std_logic := 'Z';
      B13_L24_N         : inout std_logic := 'Z';
      B13_L25           : inout std_logic := 'Z';
      B34_L0            : inout std_logic := 'Z';
      B34_L1_P          : inout std_logic := 'Z';
      B34_L1_N          : inout std_logic := 'Z';
      B34_L2_P          : inout std_logic := 'Z';
      B34_L2_N          : inout std_logic := 'Z';
      B34_L3_P          : inout std_logic := 'Z';
      B34_L3_N          : inout std_logic := 'Z';
      B34_L4_P          : inout std_logic := 'Z';
      B34_L4_N          : inout std_logic := 'Z';
      B34_L5_P          : inout std_logic := 'Z';
      B34_L5_N          : inout std_logic := 'Z';
      B34_L6_P          : inout std_logic := 'Z';
      B34_L6_N          : inout std_logic := 'Z';
      B34_L7_P          : inout std_logic := 'Z';
      B34_L7_N          : inout std_logic := 'Z';
      B34_L8_P          : inout std_logic := 'Z';
      B34_L8_N          : inout std_logic := 'Z';
      B34_L9_P          : inout std_logic := 'Z';
      B34_L9_N          : inout std_logic := 'Z';
      B34_L10_P         : inout std_logic := 'Z';
      B34_L10_N         : inout std_logic := 'Z';
      B34_L11_P         : inout std_logic := 'Z';
      B34_L11_N         : inout std_logic := 'Z';
      B34_L12_P         : inout std_logic := 'Z';
      B34_L12_N         : inout std_logic := 'Z';
      B34_L13_P         : inout std_logic := 'Z';
      B34_L13_N         : inout std_logic := 'Z';
      B34_L14_P         : inout std_logic := 'Z';
      B34_L14_N         : inout std_logic := 'Z';
      B34_L15_P         : inout std_logic := 'Z';
      B34_L15_N         : inout std_logic := 'Z';
      B34_L16_P         : inout std_logic := 'Z';
      B34_L16_N         : inout std_logic := 'Z';
      B34_L17_P         : inout std_logic := 'Z';
      B34_L17_N         : inout std_logic := 'Z';
      B34_L18_P         : inout std_logic := 'Z';
      B34_L18_N         : inout std_logic := 'Z';
      B34_L19_P         : inout std_logic := 'Z';
      B34_L19_N         : inout std_logic := 'Z';
      B34_L20_P         : inout std_logic := 'Z';
      B34_L20_N         : inout std_logic := 'Z';
      B34_L21_P         : inout std_logic := 'Z';
      B34_L21_N         : inout std_logic := 'Z';
      B34_L22_P         : inout std_logic := 'Z';
      B34_L22_N         : inout std_logic := 'Z';
      B34_L23_P         : inout std_logic := 'Z';
      B34_L23_N         : inout std_logic := 'Z';
      B34_L24_P         : inout std_logic := 'Z';
      B34_L24_N         : inout std_logic := 'Z';
      B34_L25           : inout std_logic := 'Z';
      B35_L0            : inout std_logic := 'Z';
      B35_L1_P          : inout std_logic := 'Z';
      B35_L1_N          : inout std_logic := 'Z';
      B35_L2_P          : inout std_logic := 'Z';
      B35_L2_N          : inout std_logic := 'Z';
      B35_L3_P          : inout std_logic := 'Z';
      B35_L3_N          : inout std_logic := 'Z';
      B35_L4_P          : inout std_logic := 'Z';
      B35_L4_N          : inout std_logic := 'Z';
      B35_L5_P          : inout std_logic := 'Z';
      B35_L5_N          : inout std_logic := 'Z';
      B35_L6_P          : inout std_logic := 'Z';
      B35_L6_N          : inout std_logic := 'Z';
      B35_L7_P          : inout std_logic := 'Z';
      B35_L7_N          : inout std_logic := 'Z';
      B35_L8_P          : inout std_logic := 'Z';
      B35_L8_N          : inout std_logic := 'Z';
      B35_L9_P          : inout std_logic := 'Z';
      B35_L9_N          : inout std_logic := 'Z';
      B35_L10_P         : inout std_logic := 'Z';
      B35_L10_N         : inout std_logic := 'Z';
      B35_L11_P         : inout std_logic := 'Z';
      B35_L11_N         : inout std_logic := 'Z';
      B35_L12_P         : inout std_logic := 'Z';
      B35_L12_N         : inout std_logic := 'Z';
      B35_L13_P         : inout std_logic := 'Z';
      B35_L13_N         : inout std_logic := 'Z';
      B35_L14_P         : inout std_logic := 'Z';
      B35_L14_N         : inout std_logic := 'Z';
      B35_L15_P         : inout std_logic := 'Z';
      B35_L15_N         : inout std_logic := 'Z';
      B35_L16_P         : inout std_logic := 'Z';
      B35_L16_N         : inout std_logic := 'Z';
      B35_L17_P         : inout std_logic := 'Z';
      B35_L17_N         : inout std_logic := 'Z';
      B35_L18_P         : inout std_logic := 'Z';
      B35_L18_N         : inout std_logic := 'Z';
      B35_L19_P         : inout std_logic := 'Z';
      B35_L19_N         : inout std_logic := 'Z';
      B35_L20_P         : inout std_logic := 'Z';
      B35_L20_N         : inout std_logic := 'Z';
      B35_L21_P         : inout std_logic := 'Z';
      B35_L21_N         : inout std_logic := 'Z';
      B35_L22_P         : inout std_logic := 'Z';
      B35_L22_N         : inout std_logic := 'Z';
      B35_L23_P         : inout std_logic := 'Z';
      B35_L23_N         : inout std_logic := 'Z';
      B35_L24_P         : inout std_logic := 'Z';
      B35_L24_N         : inout std_logic := 'Z';
      B35_L25           : inout std_logic := 'Z'
   );

end TE0715;
