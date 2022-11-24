library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

use     work.ESCBasicTypesPkg.all;
use     work.Lan9254Pkg.all;
use     work.ESCFoEPkg.all;
use     work.ESCMbxPkg.all;
use     work.FoE2SpiPkg.all;
use     work.Udp2BusPkg.all;

entity FoE2SpiTb is
end entity FoE2SpiTb;

architecture Sim of FoE2SpiTb is

  constant W_C  : natural  := 8;
  constant BSZ  : natural  := 65536;
  constant PSZ  : natural  := 256;
  constant D_C  : natural  := 2*BSZ;

  signal clk : std_logic := '0';
  signal rst : std_logic := '1';

  signal eraseFailure : boolean := false;
  signal writeFailure : boolean := false;

  signal cnt   : natural   := 0;
  signal don   : boolean   := false;
  signal phas  : integer   := 2;

  type   MemArray is array(natural range <>) of std_logic_vector(7 downto 0);

  signal mem   : MemArray(0 to D_C - 1) := (others => (others => '1'));
  signal buf   : MemArray(0 to PSZ - 1) := (others => (others => '1'));
  signal lcsel : std_logic := '1';
  signal lsclk : std_logic := '0';
  signal cmd   : std_logic_vector(7 downto 0);
  signal sr    : std_logic_vector(7 downto 0) := (others => '0');
  signal scnt  : natural   := 7;

  type SpiStateType is ( IDLE, A3, A2, A1, DROP, WRITE, READ );

  signal spiState : SpiStateType := IDLE;

  signal blk : natural  := 0;
  signal pag : natural  := 0;
  signal idx : natural  := 0;


  signal foeMst : FoEMstType := FOE_MST_INIT_C;
  signal foeSub : FoESubType := FOE_SUB_ASSERT_C;

  signal busReq : Udp2BusReqType := UDP2BUSREQ_INIT_C;
  signal busRep : Udp2BusRepType;

  signal spiSclk : std_logic;
  signal spiMosi : std_logic;
  signal spiMiso : std_logic;
  signal spiCsel : std_logic;

  signal raddr   : natural;

  signal ser : std_logic;
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

  foeMst.strmMst.data <= std_logic_vector( to_unsigned(cnt mod 2**16, 16 ) );
  foeMst.strmMst.ben  <= "01";
  foeMst.strmMst.usr  <= (others => '0');

  P_CTL : process (clk ) is
  begin
    if ( rising_edge( clk ) ) then
       if ( (foeMst.strmMst.valid and foeSub.strmRdy and foeMst.strmMst.last ) = '1' ) then
          foeMst.strmMst.valid <= '0';
       end if;
       if ( foeMst.strmMst.valid = '0' or foeSub.strmRdy = '1' ) then
          cnt <= cnt + 1;
       end if;
       if ( ( foeMst.doneAck and foeSub.done ) = '1' ) then
          foeMst.doneAck       <= '0';
          foeMst.strmMst.last  <= '0';
          -- if the DUT aborts due to an error we have 'valid' still asserted and
          -- need to get rid of it...
          foeMst.strmMst.valid <= '0';
          phas                 <= phas - 1;
          cnt                  <= 0;
          rst                  <= '1';
          if     ( phas = 2 ) then
             assert foeSub.err = FOE_NO_ERROR_C report "Errors encountered" severity failure;
             eraseFailure   <= true;
          elsif  ( phas = 1 ) then
             eraseFailure   <= false;
             writeFailure   <= true;
             assert foeSub.err = FOE_ERR_CODE_PROGRAM_ERROR_C report "Expected erase error" severity failure;
          elsif  ( phas = 0 ) then
             assert foeSub.err = FOE_ERR_CODE_CHECKSUM_ERROR_C report "Expected verifiation error" severity failure;
             writeFailure   <= false;
             don            <= true;
             report "TEST PASSED";
          end if;
       end if;
       if    ( cnt = 1 ) then
          rst <= '0';
          foeMst.doneAck <= '1';
       elsif    ( cnt = 3 ) then
          foeMst.strmMst.valid <= '1';
       elsif ( cnt =  317 ) then
          foeMst.strmMst.last  <= '1';
       end if;
    end if;
  end process P_CTL;


  U_DUT : entity work.FoE2Spi
    generic map (
      FILE_MAP_G          => (
         0 => (
            id       => x"00",
            begAddr  => x"000000",
            endAddr  => x"01ffff",
            flags    => FLASH_FILE_FLAGS_NONE_C
              )
      ),
      CLOCK_FREQ_G   => 20.0E6
    )
    port map (
      clk     => clk,
      rst     => rst,

      foeMst  => foeMst,
      foeSub  => foeSub,

      busReq  => busReq,
      busRep  => busRep,

      sclk    => spiSclk,
      scsb    => spiCsel,
      miso    => spiMiso,
      mosi    => spiMosi
    );

    spiMiso <= sr(sr'left);

    P_SPI : process ( clk ) is
    begin
       if ( rising_edge( clk ) ) then
          lcsel <= spiCsel;
          lsclk <= spiSclk;
          if ( spiCsel = '1' and lcsel = '0' ) then
             if ( spiState = WRITE ) then
                mem(BSZ * blk + PSZ * pag to BSZ * blk + PSZ * pag + PSZ - 1 ) <= buf;
             end if;
             spiState <= IDLE;
          elsif ( spiCsel = '0' and lcsel = '1' ) then
             assert ( spiSclk = '0' and lsclk = '0' ) report "invalid CSEL change" severity failure;
             scnt     <= 7;
             spiState <= IDLE;
          end if;
          if ( spiSclk = '1' and lsclk = '0' ) then
             if ( spiCsel = '0' ) then
                sr <= sr(6 downto 0) & spiMosi;
             end if;
          elsif ( spiSclk = '0' and lsclk = '1' ) then
             if ( spiCsel = '0' ) then
                if ( scnt = 0 ) then
                   scnt <= 7;
                   case ( spiState ) is
                      when DROP =>
                         -- wait for CSEL to deassert
                      when IDLE =>
                         spiState <= DROP;
                         if ( sr = x"02" or sr = x"d8" or sr = x"03" )  then
                            spiState <= A3;
                            cmd      <= sr;
                         elsif ( sr = x"05" ) then
                            -- status 1 read
                            sr <= x"00";
                         end if;
                      when A3 =>
                         blk <= to_integer( unsigned( sr ) );
                         spiState <= A2;
                      when A2 =>
                         pag <= to_integer( unsigned( sr ) );
                         spiState <= A1;
                      when A1 =>
                         idx <= to_integer( unsigned( sr ) );
                         if ( cmd = x"02" ) then
                            spiState <= WRITE;
                            --report "SPI write @" & integer'image(BSZ*blk + PSZ*pag + idx);
                            buf <= mem(BSZ * blk + PSZ * pag to BSZ * blk + PSZ * pag + PSZ - 1 );
                         elsif ( cmd = x"d8" ) then
                            --report "SPI erase @" & integer'image(BSZ*blk + PSZ*pag + idx);
                            for i in BSZ*blk to BSZ*blk + BSZ - 1 loop
                               mem(i) <= (others => '1');
                               if ( i = BSZ*blk + 44 and eraseFailure ) then
                                  mem(i)(3) <= '0';
                               end if;
                            end loop;
                            spiState <= DROP;
                         elsif ( cmd = x"05" ) then
                         elsif ( cmd = x"03" ) then
                            --report "SPI read @" & integer'image(BSZ*blk + PSZ*pag + idx);
                            spiState <= READ;
                            sr       <= mem(BSZ * blk + PSZ * pag + to_integer( unsigned( sr ) ));
                            raddr    <= BSZ * blk + PSZ * pag + to_integer(unsigned(sr)) + 1;
                         end if;
                      when WRITE =>
                         assert ( idx < PSZ ) report "INDEX OVERFLOW @" & integer'image( BSZ * blk + PSZ * pag ) & " index " & integer'image(idx) severity failure;
                         buf(idx) <= sr;
                         idx      <= (idx + 1); -- mod PSZ => would overwrite page
                         if ( writeFailure and idx = 4 ) then
                            buf(idx) <= not sr;
                         end if;
                      when READ =>
                         sr       <= mem(raddr);
                         raddr    <= raddr + 1;
                   end case;
                else
                   scnt <= scnt - 1;
                end if;
             end if;
          end if;
       end if;
    end process P_SPI;

    U_MON : entity work.SpiMonitor
      port map (
         clk     => clk,
         rst     => rst,
         spiSclk => spiSclk,
         spiMosi => spiMosi,
         spiMiso => spiMiso,
         spiCsel => spiCsel
      );

end architecture Sim;
