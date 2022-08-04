library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.StdRtlPkg.all;
use     work.AxiLitePkg.all;
use     work.Lan9254Pkg.all;

entity AxilLan9254HbiMasterTb is
end entity AxilLan9254HbiMasterTb;

architecture sim of AxilLan9254HbiMasterTb is
   signal clk : sl := '0';
   signal run : boolean := true;

   signal axilReadMaster : AxiLiteReadMasterType  := AXI_LITE_READ_MASTER_INIT_C;
   signal axilReadSlave  : AxiLiteReadSlaveType   := AXI_LITE_READ_SLAVE_INIT_C;
   signal axilWriteMaster: AxiLiteWriteMasterType := AXI_LITE_WRITE_MASTER_INIT_C;
   signal axilWriteSlave : AxiLiteWriteSlaveType  := AXI_LITE_WRITE_SLAVE_INIT_C;

   signal hbiOut         : Lan9254HBIOutType      := LAN9254HBIOUT_INIT_C;
   signal hbiInp         : Lan9254HBIInpType      := LAN9254HBIINP_INIT_C;

begin

   hbiInp.ad      <= x"0210";

   process is
   begin
      wait for 5 ns;
      clk <= not clk;
      if not run then wait; end if;
   end process;

   process is 
      variable d : std_Logic_vector(31 downto 0);
   begin
      axiLiteBusSimRead( clk, axilReadMaster, axilReadSlave, x"0C008065", d );
      report integer'image(to_integer(unsigned(d(15 downto 8))));
      assert to_integer(unsigned(d(15 downto 8))) = 2 report "Test Failed" severity failure;

      axiLiteBusSimWrite( clk, axilWriteMaster, axilWriteSlave, x"00000000", x"deadbeef" );

      for i in 1 to 250 loop
         wait until rising_edge( clk );
      end loop;
      run <= false;
      wait;
   end process;

   U_DUT : entity work.AxilLan9254HbiMaster
      generic map (
         AXIL_CLK_PERIOD_G  => (10.0E-9)
      )
      port map (
         axilClk            => clk,
         axilRst            => '0',
         axilReadMaster     => axilReadMaster,
         axilReadSlave      => axilReadSlave,
         axilWriteMaster    => axilWriteMaster,
         axilWriteSlave     => axilWriteSlave,

         hbiOut             => hbiOut,
         hbiInp             => hbiInp
      );

end architecture sim;
