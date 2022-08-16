library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.Udp2BusPkg.all;

entity Bus2SpiFlashTb is
end entity Bus2SpiFlashTb;

architecture sim of Bus2SpiFlashTb is
   signal clk : std_logic := '0';
   signal rst : std_logic := '1';
   signal don : boolean   := false;
   signal req : Udp2BusReqType := UDP2BUSREQ_INIT_C;
   signal rep : Udp2BusRepType := UDP2BUSREP_INIT_C;

   signal spiVldI : std_logic;
   signal spiDatI : std_logic_vector(7 downto 0);
   signal spiCsel : std_logic;
   signal spiRdyI : std_logic;

         -- spi controller reply (input of this module)
   signal spiVldO : std_logic;
   signal spiDatO : std_logic_vector(7 downto 0);
   signal spiRdyO : std_logic;


   signal cnt  : natural := 0;
   signal rcnt : natural := 10;

   procedure mkReq(
      signal   reqOut: out Udp2BusReqType;
      constant addr  : in  std_logic_vector;
      constant w     : in  natural;
      constant v     : in  std_logic_vector := ""
   ) is
      variable a : std_logic_vector(1 downto 0);
      variable l : natural;
      variable b : std_logic_vector(3 downto 0);
   begin
      reqOut.valid  <= '1';
      reqOut.dwaddr <= std_logic_vector( shift_right( resize( unsigned(addr), reqOut.dwaddr'length ), 2 ) );
      a := std_logic_vector( resize( unsigned( addr ), 2 ) );
      if ( w = 4 ) then
         b := "1111";
      elsif ( w = 2 ) then
         b := "0011";
      elsif ( w = 1 ) then
         b := "0001";
      elsif ( w = 0 ) then
         b := "0000";
      else
         assert false report "invalid width" severity failure;
      end if;
      if    ( a(1 downto 0) = "00" ) then
      elsif ( a(1 downto 0) = "01" ) then
         b := b(b'left - 1 downto 0) & b(b'left);
      elsif ( a(1 downto 0) = "10" ) then
         b := b(b'left - 2 downto 0) & b(b'left downto b'left - 1);
      else
         b := b(b'left - 3 downto 0) & b(b'left downto b'left - 2);
      end if;
      reqOut.be    <= b;
      if ( v'length /= 0 ) then
         reqOut.rdnwr <= '0';
         reqOut.data  <= v;
      else
         reqOut.data  <= (others => '0');
         reqOut.rdnwr <= '1';
      end if;
   end procedure mkReq;

   procedure xmit is
   begin
      wait until rising_edge( clk );
      while ( ( req.valid and rep.valid ) /= '1' ) loop
         wait until rising_edge( clk );
      end loop;
   end procedure xmit;

begin

   P_CLK : process is
   begin
      if don then
         wait;
      else
         wait for 10 ns;
         clk <= not clk;


      end if;
   end process P_CLK;

   P_DRV : process is
      variable lidx : natural;
   begin
      wait until rising_edge( clk );
      wait until rising_edge( clk );
      rst <= '0';
      wait until rising_edge( clk );

      mkReq( req, x"000010", 4, x"0000_0001" );
      xmit;

      mkReq( req, x"000004", 2 );
      xmit;

      mkReq( req, x"000002", 2 );
      xmit;

      mkReq( req, x"000003", 1 );
      xmit;

      mkReq( req, x"000008", 4 );
      xmit;



      don <= true;
      wait;
   end process P_DRV;

   U_DUT : entity work.Bus2SpiFlash
      generic map (
         LD_PAGE_SIZE_G => 4
      )
      port map (
         clk     => clk,
         rst     => rst,

         busReq  => req,
         busRep  => rep,

         spiReq  => open,
         spiGnt  => open,

         spiVldI => spiVldI,
         spiDatI => spiDatI,
         spiCsel => spiCsel,
         spiRdyI => spiRdyI,

         -- spi controller reply (input of this module)
         spiVldO => spiVldO,
         spiDatO => spiDatO,
         spiRdyO => spiRdyO
      );

   U_SPI : entity work.SpiBitShifter
      port map (
         clk     => clk,
         rst     => rst,

         vldInp  => spiVldI,
         datInp  => spiDatI,
         csbInp  => spiCsel,
         rdyInp  => spiRdyI,

         -- spi controller reply (input of this module)
         vldOut  => spiVldO,
         datOut  => spiDatO,
         rdyOut  => spiRdyO,

	 serClk  => open,
	 serCsb  => open,
	 serInp  => '1',
	 serOut  => open
      );


end architecture sim;
