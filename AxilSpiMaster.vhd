library ieee;
use     ieee.std_logic_1164.all;

use     work.StdRtlPkg.all;
use     work.AxiLitePkg.all;

entity AxilSpiMaster is
   generic (
      TPD_G              : time                 := 1 ns;
      NUM_SPI_SS_G       : natural range 0 to 4 := 1;
      AXIL_CLK_PERIOD_G  : real;
      SPI_SCLK_PERIOD_G  : real                 := 1.0E-6
   );
   port (
      axilClk            : in  std_logic;
      axilRst            : in  std_logic;
      axilReadMaster     : in  AxiLiteReadMasterType;
      axilReadSlave      : out AxiLiteReadSlaveType;
      axilWriteMaster    : in  AxiLiteWriteMasterType;
      axilWriteSlave     : out AxiLiteWriteSlaveType;

      spiSclk            : out std_logic;
      spiMosi            : out std_logic;
      spiMiso            : in  std_logic;
      spiSs              : out std_logic_vector(NUM_SPI_SS_G - 1 downto 0) := (others => '0');

      ctl_o              : out Slv32Array(3 downto 0);
      ctl_i              : in  Slv32Array(1 downto 0);

      irq                : out std_logic
   );
end entity AxilSpiMaster;

architecture rtl of AxilSpiMaster is

   constant SPI_D_W_C             : natural   := 8;
   constant NUM_CS_C              : natural   := 1;

   signal spiRdData               : std_logic_vector(SPI_D_W_C - 1 downto 0);
   signal spiWrData               : std_logic_vector(SPI_D_W_C - 1 downto 0);
   signal spiRst                  : std_logic;
   signal spiRstLoc               : std_logic;
   signal spiRdEn                 : std_logic;
   signal spiWrEn                 : std_logic;
   signal spiIrqEn                : std_logic;
   signal cs                      : std_logic_vector(NUM_CS_C  - 1 downto 0);

   signal statusReg               : std_logic_vector(15 downto 0) := (others => '0');

   type RegType is record
      cmdReg            : std_logic_vector(15 downto 0);
      axilReadSlave     : AxiLiteReadSlaveType;
      axilWriteSlave    : AxiLiteWriteSlaveType;
      ctl_o             : Slv32Array(3 downto 0);
   end record RegType;

   signal rin                     : RegType;

   function cmdRegInit(holdRst : std_logic) return std_logic_vector is
      variable v : std_logic_vector(15 downto 0);
   begin
      v     := (others => '0');
      v(13) := holdRst;
      v( 8 + NUM_SPI_SS_G - 1 downto 8 ) := (others => '1');
      return v;
   end function cmdRegInit;

   constant REG_INIT_C : RegType := (
      cmdReg            => cmdRegInit('0'),
      axilReadSlave     => AXI_LITE_READ_SLAVE_INIT_C,
      axilWriteSlave    => AXI_LITE_WRITE_SLAVE_INIT_C,
      ctl_o             => (others => (others => '1'))
   );

   signal r                       : RegType := REG_INIT_C;
begin

   statusReg(7 downto 0) <= spiRdData;
   statusReg(         8) <= cs(0);
   statusReg(        15) <= spiRdEn;

   spiWrEn               <= r.cmdReg(15);
   spiIrqEn              <= r.cmdReg(14);
   spiWrData             <= r.cmdReg( 7 downto 0);
   spiRstLoc             <= r.cmdReg(13);

   P_COMB : process(axilReadMaster, axilWriteMaster, axilRst, r, statusReg, cs, spiRstLoc, ctl_i) is
      variable v        : RegType;
      variable axilEp   : AxiLiteEndpointType;
   begin
      v := r;

      axiSlaveWaitTxn( axilEp, axilWriteMaster, axilReadMaster, v.axilWriteSlave, v.axilReadSlave );

      axiSlaveRegisterR( axilEp, x"000",  0, statusReg); -- lower 16-bit read-only
      if ( cs(0) = '1' ) then
         v.cmdReg(15) := '0';
      end if;
      axiSlaveRegister ( axilEp, x"000", 16, v.cmdReg ); -- upper 16-bit read-write

      axiSlaveRegister ( axilEp, x"010",  0, v.ctl_o(0));
      axiSlaveRegister ( axilEp, x"014",  0, v.ctl_o(1));
      axiSlaveRegister ( axilEp, x"018",  0, v.ctl_o(2));
      axiSlaveRegister ( axilEp, x"01C",  0, v.ctl_o(3));

      axiSlaveRegisterR( axilEp, x"020",  0, ctl_i(0));
      axiSlaveRegisterR( axilEp, x"024",  0, ctl_i(1));

      axiSlaveDefault(axilEp, v.axilWriteSlave, v.axilReadSlave, AXI_RESP_DECERR_C);

      if ( spiRstLoc = '1' ) then
         v.cmdReg := cmdRegInit( '1' );
      end if;

      rin <= v;
   end process P_COMB;

   P_SEQ : process (axilClk ) is
   begin
      if ( rising_edge( axilClk ) ) then
         if ( axilRst = '1' ) then
            r <= REG_INIT_C;
         else
            r <= rin;
         end if;
      end if;
   end process P_SEQ;

   spiRst <= spiRstLoc or axilRst;

   U_SPI : entity work.SpiMaster
      generic map (
         TPD_G             => TPD_G,
         NUM_CHIPS_G       => 1,
         DATA_SIZE_G       => 8,
         CLK_PERIOD_G      => AXIL_CLK_PERIOD_G,
         SPI_SCLK_PERIOD_G => SPI_SCLK_PERIOD_G
      )
      port map (
         --Global Signals
         clk        => axilClk,
         sRst       => spiRst,
         -- Parallel interface
         chipSel    => (others => '0'),
         wrEn       => spiWrEn,
         wrData     => spiWrData,
         rdEn       => spiRdEn,
         rdData     => spiRdData,
         shiftCount => open,
         --SPI interface
         spiSclk    => spiSclk,
         spiSdi     => spiMosi,
         spiSdo     => spiMiso,
         spiCsL     => cs
      );

   irq            <= spiRdEn and spiIrqEn;

   axilReadSlave  <= r.axiLReadSlave;
   axilWriteSlave <= r.axiLWriteSlave;

   spiSs          <= r.cmdReg( 8 + NUM_SPI_SS_G - 1 downto 8 );

   ctl_o          <= r.ctl_o;

end architecture rtl;
