library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

-- mostly for simulation purposes; no sophisticated de-bouncing nor
-- delays that ensure setup/hold times.
-- Any synchronizers must be provided externally.

entity I2CEEPROM is
   generic (
      SIZE_BYTES_G : natural                      := 1024;
      I2C_ADDR_G   : std_logic_vector(7 downto 0) := x"55";
      -- eeprom is filled from this optional initialization vector
      EEPROM_INIT_G: std_logic_vector             := ""
   );
   port (
       clk          : in  std_logic;
       rst          : in  std_logic;

       sclSync      : in  std_logic;
       sdaSync      : in  std_logic;
       sdaOut       : out std_logic
   );
end entity I2CEEPROM;

architecture rtl of I2CEEPROM is

   function ADDR_W_F return natural is
   begin
      if ( SIZE_BYTES_G <= 2048 ) then return 8; else return 16; end if;
   end function ADDR_W_F;

   function aBits return integer is
   begin
      if    ( SIZE_BYTES_G <= 256  ) then
         return 0;
      elsif ( SIZE_BYTES_G <= 512  ) then
         return 1;
      elsif ( SIZE_BYTES_G <= 1024 ) then
         return 2;
      elsif ( SIZE_BYTES_G <= 2048 ) then
         return 3;
      else
         return 0;
      end if;
   end function aBits;

   function addrMatch(constant x : std_logic_vector(7 downto 0)) return boolean is
   begin
      return ( x(7 downto aBits) = I2C_ADDR_G(7 downto aBits) );
   end function addrMatch;

   constant ADDR_BITS_C : natural := integer( floor( log2( real(SIZE_BYTES_G * 8) ) ) ) + 1;

   subtype AddrType     is unsigned(ADDR_BITS_C - 1 downto 0);

   type    Slv8Array    is array(natural range <>) of std_logic_vector(7 downto 0);

   type StateType is (IDLE, START, ASHF, ADDH, ADDL, SFHL, SFLH, CONT, AINC);

   type RegType is record
      state           : stateType;
      retState        : stateType;
      addr            : AddrType;
      sr              : std_logic_vector(8 downto 0);
      bitCount        : natural range 0 to 8;
      lstScl          : std_logic;
      lstSda          : std_logic;
      dirRead         : boolean;
      sdaOut          : std_logic;
   end record RegType;

   constant REG_INIT_C: RegType := (
      state           => IDLE,
      retState        => IDLE,
      addr            => (others => '0'),
      sr              => (others => '0'),
      bitCount        => 0,
      lstScl          => '1',
      lstSda          => '1',
      dirRead         => true,
      sdaOut          => '1'
   );

   signal r           : RegType := REG_INIT_C;
   signal rin         : RegType;

   function EEPROM_INIT_F return Slv8Array is
      variable v : Slv8Array(SIZE_BYTES_G - 1 downto 0) := (others => (others => '0'));
      constant c : std_logic_vector(EEPROM_INIT_G'high downto EEPROM_INIT_G'low) := EEPROM_INIT_G;
   begin
      for i in 0 to c'length/8 - 1 loop
         v(i) := c(7+8*i downto 8*i);
      end loop;
      return v;
   end function EEPROM_INIT_F;

   signal eeprom      : Slv8Array(SIZE_BYTES_G - 1 downto 0) := EEPROM_INIT_F;
   signal eepromWen   : std_logic := '0';
begin
   
   P_COMB : process (r, sclSync, sdaSync, eeprom) is
      variable v : RegType;
   begin

      v         := r;

      v.lstSda  := sdaSync;
      v.lstScl  := sclSync;

      eepromWen <= '0';

      case ( r.state) is
         when IDLE =>
            -- release SDA once scl goes low
            if ( (not sclSync and r.lstScl ) = '1' ) then
               v.sdaOut := '1';
            end if;

         when SFHL =>
            -- wait for negative clock
            if ( (not sclSync and r.lstScl ) = '1' ) then
               v.sdaOut := r.sr(r.sr'left);
               v.state  := SFLH;
            end if;

         when SFLH =>
            -- wait for positive clock
            if ( (sclSync and not r.lstScl ) = '1' ) then
               v.sr := r.sr(r.sr'left - 1 downto 0) & sdaSync;
               if ( 0 = r.bitCount ) then
                  v.state := r.retState;
               else
                  v.bitCount := r.bitCount - 1;
                  v.state := SFHL;
               end if;
            end if;

         when START =>
            -- check address and ACK/NACK accordingly
            v.bitCount := 0;
            v.state    := SFHL; -- shift ACK bit
            if ( not addrMatch('0' & r.sr(7 downto 1)) ) then
               -- shift the ACK bit
               v.sr(v.sr'left) := '1'; -- NAK
               v.retState      := IDLE;
            else
               if ( r.sr(0) = '0' ) then
                  v.addr(ADDR_BITS_C - 1 downto 8) := (others => '0');
                  if ( aBits > 0 ) then
                    v.addr(8+aBits - 1 downto 8) := unsigned(r.sr(aBits downto 1));
                  end if;
               end if;
               v.dirRead := ( r.sr(0) = '1' );
               v.sr(v.sr'left) := '0'; -- ACK

               if ( v.dirRead ) then
                  v.retState := CONT;
               else
                  v.retState := ASHF;
               end if;
            end if;

         when ASHF =>
            v.sr       := (0 => '0', others => '1');
            v.state    := SFHL;
            v.bitCount := 8;
            if ( ADDR_W_F > 8 ) then
               v.retState := ADDH;
            else
               v.retState := ADDL;
            end if;
               
         when ADDH =>
            v.addr(15 downto 8) := unsigned(r.sr(8 downto 1));
            v.sr       := (0 => '0', others => '1');
            v.state    := SFHL;
            v.bitCount := 8;
            v.retState := ADDL;
            
         when ADDL =>
            v.addr( 7 downto 0) := unsigned(r.sr(8 downto 1));
            v.state    := CONT;
 
         when CONT =>
            if ( r.dirRead ) then
               v.sr := eeprom( to_integer( r.addr ) ) & '1';
            else
               v.sr := ( 0 => '0', others => '1' );
            end if;
            v.bitCount := 8;
            v.retState := AINC;
            v.state    := SFHL;
            
         when AINC =>
            -- shifted a word
            v.state := CONT;
            if ( r.dirRead ) then
               if ( r.sr(0) = '1' ) then
                  -- master NAK
                  v.state := IDLE;
               end if;
            else
               eepromWen <= '1';
            end if;
            v.addr     := r.addr + 1;

      end case;

      if ( (sclSync and r.lstScl) = '1' ) then
         if ( (r.lstSda and not sdaSync) = '1' ) then
               -- start cond.
               v.state    := SFHL;
               v.retState := START;
               v.bitCount := 7;
               v.sr       := ( others => '1' );
               v.dirRead  := false;
         elsif ( (not r.lstSda and sdaSync) = '1' ) then
            -- stop cond
            v.state := IDLE;
         end if;
      end if;

      rin <= v;
   end process P_COMB;

   P_WR : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( eepromWen = '1' ) then
            eeprom( to_integer( r.addr ) ) <= r.sr(8 downto 1);
         end if;
      end if;
   end process P_WR;

   P_SEQ : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( rst = '1' ) then
            r <= REG_INIT_C;
         else
            r <= rin;
         end if;
      end if;
   end process P_SEQ;

   sdaOut <= r.sdaOut;

end architecture rtl;
