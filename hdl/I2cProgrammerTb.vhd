-- write stuff to I2C devices; mostly useful for initialization

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.ESCBasicTypesPkg.all;
use work.Lan9254Pkg.all;
use work.EEPROMContentPkg.all;

entity I2cProgrammerTb is 
end entity I2cProgrammerTb;

architecture Sim of I2cProgrammerTb is
   constant NUM_I2C_MST_C    : natural := 2;

   signal i2cStrmMstIb       : Lan9254StrmMstArray(NUM_I2C_MST_C - 1 downto 0);
   signal i2cStrmRdyIb       : std_logic_vector   (NUM_I2C_MST_C - 1 downto 0);
   signal i2cStrmMstOb       : Lan9254StrmMstArray(NUM_I2C_MST_C - 1 downto 0);
   signal i2cStrmRdyOb       : std_logic_vector   (NUM_I2C_MST_C - 1 downto 0);

      -- a stream master locks access to the i2c master once first granted access.
      -- it must de-assert its corresponding bit in i2cStrmLock to relinquish
      -- the master.
   signal i2cStrmLock        : std_logic_vector   (NUM_I2C_MST_C - 1 downto 0) := (others => '0');

   signal strmTxMst, strmRxMst : Lan9254StrmMstType;
   signal strmTxRdy, strmRxRdy : std_logic;

   signal clk : std_logic := '0';
   signal rst : std_logic := '1';
   signal run : boolean   := true;

   signal sdaBus, sdaMst, sdaSrc, sdaDst, scl : std_logic;

   signal don, err, rdy : std_logic;
   signal ack : std_logic := '1';
   signal emu : std_logic := '0';
   signal vld : std_logic := '0';

   signal check : boolean := false;

   type TstArray is array(natural range <>) of std_logic_vector(19 downto 0);

   signal tvld : std_logic := '0';
   signal trdy : std_logic := '0';

   signal cfgAddr : unsigned(15 downto 0) := x"0023";

   
   type ByteArray is array (natural range <>) of std_logic_vector( 7 downto 0);

   constant exp : ByteArray(0 to 1024) := (
       0 => x"ed",
       1 => x"ad",
       2 => x"be",
       3 => x"ef",

     160 => x"01",
     161 => x"02",
     162 => x"03",
     163 => x"04",
     164 => x"05",
     165 => x"06",
     166 => x"07",

     256 => x"af",
     257 => x"fe",
     258 => x"01",
     259 => x"03",
     260 => x"02",
     others => x"ff"
   );

   constant tst : TstArray := (
      0 => x"000A0", -- 'uber'-header; write the rest to source EEPROM
      1 => x"10023", -- destination (= cfgAddr)
      2 => x"004C0",
      3 => x"0ed00",
      4 => x"0bead",
      5 => x"1ffef",
      6 => x"005C2",
      7 => x"0af00",
      8 => x"001fe",
      9 => x"00203",
     10 => x"1ffff"
   );

   constant tstEmu : EEPROMArray(0 to 33) := (

      4 => x"07C0",
      5 => x"01A0",
      6 => x"0302",
      7 => x"0504",
      8 => x"0706",

      others => x"FFFF"
   );

   signal cnt : natural := 0;

   signal tstAddr : natural := 0;
   signal tstData : std_logic_vector(7 downto 0);
   
begin

   i2cStrmMstIb(1).data   <=  tst(cnt)(15 downto 0);
   i2cStrmMstIb(1).ben    <=  not tst(cnt)(16) & '1';
   i2cStrmMstIb(1).usr    <=  "00" & tst(cnt)(19 downto 18);
   i2cStrmMstIb(1).valid  <=  tvld;
   i2cStrmMstIb(1).last   <= '1' when cnt = tst'length - 1 else '0';

   i2cStrmRdyOb(1)        <= trdy;

   process is
   begin
      wait for 5 ns;
      clk <= not clk;
      if not run then wait; end if;
   end process;

   P_CHECK : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( check ) then
            assert i2cStrmLock = "00" severity failure;
            if ( tstAddr = exp'length - 1 ) then
               run <= false;
               report "TEST PASSED";
            else
                 assert tstData    =  exp(tstAddr) report "Failed at " & integer'image(tstAddr) severity failure;
                 tstAddr <= tstAddr + 1;
            end if;
         end if;
      end if;
   end process P_CHECK;


   P_FEED : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( (vld and rdy) = '1' ) then
            vld <= '0';
         end if;
         if ( (don and ack) = '1' ) then
            assert err = '0'          severity failure;
            if ( emu = '1' ) then
               ack   <= '0';
               check <= true;
            else
               cfgAddr <= x"0008";
               emu     <= '1';
               vld     <= '1';
            end if;
         end if;
         if ( rst = '1' ) then
            cnt <= cnt + 1;
            if ( cnt = 5 ) then
               rst <= '0';
               cnt <= 0;
            end if;
         else
            if ( tvld = '0' ) then
               if ( cnt = 0 ) then
                  tvld <= '1';
                  i2cStrmLock(1) <= '1';
               elsif ( ( trdy and i2cStrmMstOb(1).valid ) = '1' ) then
                  assert i2cStrmMstOb(1).last = '1' and i2cStrmMstOb(1).ben /= "00" severity failure;
                  trdy <= '0';
                  vld  <= '1';
                  ack  <= '1';
                  i2cStrmLock(1) <= '0';
               end if;
            elsif ( i2cStrmRdyIb(1) = '1' ) then
               if ( cnt = tst'length - 1 ) then
                  tvld <= '0';
                  trdy <= '1';
               else
                  cnt <= cnt + 1;
               end if;
            end if;
         end if;
      end if;
   end process P_FEED;


   U_DUT  : entity work.I2cProgrammer
      generic map (
         EEPROM_INIT_G => tstEmu
      )
      port map (
         clk          => clk,
         rst          => rst,

         -- asserting starts the program
         cfgVld       => vld,
         cfgRdy       => rdy,
         cfgAddr      => cfgAddr,
         cfgEepSz2B   => '0',
         -- read from emulated eeprom
         cfgEmul      => emu,

         don          => don,
         err          => err,
         ack          => ack,
         
         i2cReq       => i2cStrmMstIb(0),
         i2cReqRdy    => i2cStrmRdyIb(0),
         i2cRep       => i2cStrmMstOb(0),
         i2cRepRdy    => i2cStrmRdyOb(0),
         i2cLock      => i2cStrmLock(0)
      );

   U_MUX  : entity work.StrmMux
      generic map (
         NUM_MSTS_G      => NUM_I2C_MST_C
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

         debug           => open
      );

      U_STRM : entity work.PsiI2cStreamIF
         generic map (
            CLOCK_FREQ_G   => 2.0E6
         )
         port map (
            clk            => clk,
            rst            => rst,
   
            strmMstIb      => strmTxMst,
            strmRdyIb      => strmTxRdy,
   
            strmMstOb      => strmRxMst,
            strmRdyOb      => strmRxRdy,
   
            i2c_scl_i      => scl,
            i2c_scl_o      => open,
            i2c_scl_t      => scl,
   
            i2c_sda_i      => sdaBus,
            i2c_sda_o      => open,
            i2c_sda_t      => sdaMst,
   
            debug          => open
         );

   U_SRC : entity work.I2CEEPROM
      generic map (
         I2C_ADDR_G => x"50"
      )
      port map (
         clk        => clk,
         rst        => rst,

         sclSync    => scl,
         sdaSync    => sdaBus,
         sdaOut     => sdaSrc
      );

   U_DST : entity work.I2CEEPROM
      generic map (
         I2C_ADDR_G => x"60"
      )
      port map (
         clk        => clk,
         rst        => rst,

         sclSync    => scl,
         sdaSync    => sdaBus,
         sdaOut     => sdaDst,

         addrInp    => tstAddr,
         dataOut    => tstData
      
      );

   sdaBus <= sdaSrc and sdaDst and sdaMst;

end architecture Sim;
