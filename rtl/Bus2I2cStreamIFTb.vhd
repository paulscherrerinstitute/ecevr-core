library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.ESCBasicTypesPkg.all;
use work.Lan9254Pkg.all;
use work.Udp2BusPkg.all;

entity Bus2I2cStreamIFTb is
end entity Bus2I2cStreamIFTb;

architecture sim of Bus2I2cStreamIFTb is
   signal clk : std_logic := '0';
   signal rst : std_logic := '1';
   signal don : boolean   := false;
   signal req : Udp2BusReqType := UDP2BUSREQ_INIT_C;
   signal rep : Udp2BusRepType := UDP2BUSREP_INIT_C;
   signal mOb, mIb : Lan9254StrmMstType;
   signal rOb, rIb : std_logic;

   signal scl, eepSda, mstSda, sdaLIne : std_logic;

   signal cnt  : natural := 0;
   signal rcnt : natural := 10;

   procedure mkReq(
      signal   reqOut: out Udp2BusReqType;
      constant addr  : in  std_logic_vector;
      constant val   : in  std_logic_vector := ""
   ) is
      variable a : std_logic_vector(1 downto 0);
      variable l : natural;
   begin
      reqOut.valid  <= '1';
      reqOut.dwaddr <= std_logic_vector( shift_right( resize( unsigned(addr), reqOut.dwaddr'length ), 2 ) );
      a := std_logic_vector( resize( unsigned( addr ), 2 ) );
      if    ( a(1 downto 0) = "00" ) then
         reqOut.be <= "0001";
         l         :=  0;
      elsif ( a(1 downto 0) = "01" ) then
         reqOut.be <= "0010";
         l         :=  8;
      elsif ( a(1 downto 0) = "10" ) then
         reqOut.be <= "0100";
         l         := 16;
      else
         reqOut.be <= "1000";
         l         := 24;
      end if;
      reqOut.data  <= (others => '0');
      if ( val'length = 0 ) then
        reqOut.rdnwr <= '1';
      else
        reqOut.data  <= (others => '0');
        reqOut.data( l + 7 downto l ) <= std_logic_vector( resize( unsigned( val ), 8 ) );
        reqOut.rdnwr <= '0';
      end if;
   end procedure mkReq;

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

   P_DRV : process ( clk ) is
      variable lidx : natural;
   begin
      if ( rising_edge( clk ) ) then
         if ( (cnt = 0) and (req.valid = '0') ) then
            mkReq( req, x"55000", std_logic_vector( to_unsigned( 21, 8 )  ) );
            cnt <= cnt + 1;
         end if;

         if ( rcnt > 0 ) then
            rst  <= '1';
            rcnt <= rcnt - 1;
            cnt  <= 0;
            req.valid <= '0';
            if ( rcnt = 1 ) then
               rst  <= '0';
            end if;
         end if;
         
        if ( ( req.valid and rep.valid ) = '1' ) then
           if    ( req.be(0) = '1' ) then lidx :=  0;
           elsif ( req.be(1) = '1' ) then lidx :=  8;
           elsif ( req.be(2) = '1' ) then lidx := 16;
           else                           lidx := 24;
           end if;
           report "Readback BERR " & std_logic'image(rep.berr) & " value " & integer'image( to_integer( unsigned( rep.rdata(7 + lidx downto lidx) ) ) );
           cnt <= cnt + 1;
           case cnt is
              when 1 => 
                 mkReq( req, x"55001", std_logic_vector( to_unsigned( 32, 8 )  ) );
              when 2 => 
                 mkReq( req, x"55002", std_logic_vector( to_unsigned( 54, 8 )  ) );
              when 3 => 
                 mkReq( req, x"55003", std_logic_vector( to_unsigned( 76, 8 )  ) );
              when 4 =>
                 mkReq( req, x"55000" );
              when 5 =>
                 mkReq( req, x"55001" );
              when 6 =>
                 mkReq( req, x"55002" );
              when 7 =>
                 mkReq( req, x"55003" );
              when others =>
                 req.valid <= '0';
                 don       <= true;
           end case;
         end if;
      end if;
   end process P_DRV;

   U_DUT : entity work.Bus2I2cStreamIF
      port map (
         clk    => clk,
         rst    => rst,

         busReq => req,
         busRep => rep,

         strmMstOb => mOb,
         strmRdyOb => rOb,

         strmMstIb => mIb,
         strmRdyIb => rIb
      );

   U_STRM : entity work.PsiI2cStreamIF
      generic map (
         CLOCK_FREQ_G => 2.0E6,
         GEN_ILA_G    => false
      )
      port map (
         clk       => clk,
         rst       => rst,

         strmMstIb => mOb,
         strmRdyIb => rOb,

         strmMstOb => mIb,
         strmRdyOb => rIb,

         i2c_scl_t => scl,
         i2c_scl_i => scl,

         i2c_sda_t => mstSda,
         i2c_sda_i => sdaLine
      );

   sdaLine <= mstSda and eepSda;

   U_EEP : entity work.I2CEEPROM
      port map (
         clk       => clk,
         rst       => rst,

         sclSync   => scl,
         sdaSync   => sdaLine,
         sdaOut    => eepSda
      );
end architecture sim;
