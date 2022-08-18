library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

entity SpiMonitorTb is
end entity SpiMonitorTb;

architecture Sim of SpiMonitorTb is
  constant W_C  : natural  := 8;
  constant D2_C : positive := 10;

  type EPType is record 
    vldReq : std_logic;
    datWr  : std_logic_vector(7 downto 0);
    rdyRep : std_logic;
    datRd  : std_logic_vector(7 downto 0);
    csb    : std_logic;
  end record EPType;

  constant EP_INIT_C : EPType := (
    vldReq => '0',
    datWr  => (others => '0'),
    rdyRep => '0',
    datRd  => (others => '0'),
    csb    => '1'
  );

  signal clk : std_logic := '0';
  signal rst : std_logic := '1';

  signal datRep : std_logic_vector(7 downto 0);

  signal spiSclk, spiMosi, spiMiso, spiCsel : std_logic;
  signal rdyReq, vldRep : std_logic;

  signal status : std_logic_vector(7 downto 0);
  signal errl   : std_logic_vector(status'range) := (others => '0');

  procedure cslo(signal cs : inout std_logic) is
  begin
    cs <= '0';
    wait until rising_edge( clk );
  end procedure cslo;

  procedure cshi(signal cs : inout std_logic) is
  begin
    cs <= '1';
    wait until rising_edge( clk );
  end procedure cshi;

  procedure send(signal ep : inout EPType; constant val : std_logic_vector := "") is
  begin
     ep.vldReq <= '1';
     if ( val'length /= 8 ) then
       ep.csb   <= '1';
       ep.datWr <= (others => '1');
     else
       ep.datWr  <= val;
       ep.csb   <= '0';
     end if;
     wait until rising_edge( clk );
     while ( rdyReq = '0' ) loop
       wait until rising_edge( clk );
     end loop;
     ep.vldReq <= '0';
     ep.rdyRep <= '1';
     wait until rising_edge( clk );
     while ( vldRep = '0' ) loop
       wait until rising_edge( clk );
     end loop;
     ep.datRd  <= datRep;
     ep.rdyRep <= '0';
     wait until rising_edge( clk );
  end procedure send;

  signal ep  : EPType  := EP_INIT_C;

  signal cnt : natural := 10;
  signal don : boolean := false;

begin

  P_CLK : process is
  begin
    if ( don ) then
      wait;
    else
      wait for 10 ns;
      clk <= not clk;
    end if;
  end process;

  P_ERR : process ( clk ) is
  begin
    if ( rising_edge( clk ) ) then
       errl <= errl or status;
    end if;
  end process P_ERR;

  P_DRV : process is
  begin
    wait until rising_edge( clk );
    wait until rising_edge( clk );
    rst <= '0';
    wait until rising_edge( clk );

    send( ep, x"02" );
    send( ep, x"00" );
    send( ep, x"00" );
    send( ep, x"F0" );
    send( ep, x"01" );
    send( ep, x"02" );
    send( ep, x"03" );
    send( ep ); -- raise CSEL

    assert errl = "00000" severity failure;

    send( ep, x"02" );
    send( ep, x"00" );
    send( ep, x"00" );
    send( ep, x"fe" );
    send( ep, x"01" );
    send( ep, x"02" );
    send( ep, x"03" );
    send( ep ); -- raise CSEL


    assert errl = "10000" severity failure;

    send( ep, x"02" );
    send( ep, x"00" );
    send( ep, x"00" );
    send( ep, x"F0" );
    send( ep, x"01" );
    send( ep, x"02" );
    send( ep, x"03" );
    send( ep ); -- raise CSEL

    assert errl = "11000" severity failure;

    don <= true;
    wait;
  end process P_DRV;

  U_SND : entity work.SpiBitShifter
    generic map (
      WIDTH_G => W_C,
      DIV2_G  => D2_C
    )
    port map (
      clk     => clk,
      rst     => rst,

      csbInp  => ep.csb,
      datInp  => ep.datWr,
      vldInp  => ep.vldReq,
      rdyInp  => rdyReq,

      datOut  => datRep,
      vldOut  => vldRep,
      rdyOut  => ep.rdyRep,

      serClk  => spiSclk,
      serCsb  => spiCsel,
      serInp  => spiMiso,
      serOut  => spiMosi
    );

  U_DUT : entity work.SpiMonitor
    port map (
      clk      => clk,
      rst      => rst,
      spiSclk  => spiSclk,
      spiCsel  => spiCsel,
      spiMiso  => spiMiso,
      spiMosi  => spiMosi,
      status   => status
    );

end architecture Sim;
