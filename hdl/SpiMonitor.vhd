library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

entity SpiMonitor is
   port (
      clk     : in  std_logic;
      rst     : in  std_logic;

      spiSclk : in  std_logic;
      spiCsel : in  std_logic;
      spiMosi : in  std_logic;
      spiMiso : in  std_logic;

      status  : out std_logic_vector(7 downto 0);

      state   : out std_logic_vector(3 downto 0)
   );
end entity SpiMonitor;

architecture Impl of SpiMonitor is

   type StateType is (IDLE, A2, A1, A0, WRITE, SKIP);

   type RegType is record
      state      : StateType;
      laddr      : unsigned(23 downto 0);
      addr       : unsigned(23 downto 0);
      lcsel      : std_logic;
      lsclk      : std_logic;
      sr         : std_logic_vector(7 downto 0);
      bitCnt     : unsigned(2 downto 0);
      wrClks     : natural;
   end record RegType;

   constant REG_INIT_C : RegType := (
      state      => IDLE,
      laddr      => (others => '0'),
      addr       => (others => '0'),
      lcsel      => '1',
      lsclk      => '0',
      sr         => (others => '0'),
      bitCnt     => (others => '0'),
      wrClks     => 0
   );

   constant SPICMD_WRITE_C : std_logic_vector(7 downto 0) := x"02";
   constant SPICMD_READ_C  : std_logic_vector(7 downto 0) := x"03";
   constant SPICMD_WRENA_C : std_logic_vector(7 downto 0) := x"06";
   constant SPICMD_ER_64_C : std_logic_vector(7 downto 0) := x"D8";
   constant SPICMD_RSTAT_C : std_logic_vector(7 downto 0) := x"05";

   signal r         : RegType := REG_INIT_C;
   signal rin       : RegType;

begin

   P_COMB : process ( r, spiCsel, spiSclk, spiMosi, spiMiso) is
      variable v : RegType;
   begin
      v := r;
      v.lcsel := spiCsel;
      v.lsclk := spiSclk;

      status <= (others => '0');

      if    ( (spiCsel and not r.lcsel) = '1' ) then

        -- rising CSEL
        status(0) <= (spiSclk or r.lsclk);
        v.state   := IDLE;
        if ( r.state = WRITE ) then
           v.laddr := r.addr; -- record last written address

           if ( r.wrClks > 8*(1 + 3 + 256) ) then
             status(5) <= '1';
           end if;
        end if;

      elsif ( (not spiCsel and r.lcsel) = '1' ) then 

        -- falling CSEL
        status(1) <= (spiSclk or r.lsclk);
        v.state   := IDLE;
        v.bitCnt  := to_unsigned(7, v.bitCnt'length);
        v.wrClks  := 0;

      end if;

      if ( spiCsel = '0' ) then
         if    ( ( spiSclk and not r.lsclk ) = '1' ) then
            -- sclk rising
            v.sr     := r.sr(6 downto 0) & spiMosi;
            v.wrClks := r.wrClks + 1;
         elsif ( ( not spiSclk and  r.lsclk ) = '1' ) then
            -- sclk falling
            if ( r.bitCnt = 0 ) then
               v.bitCnt := to_unsigned(7, v.bitCnt'length);
               case ( r.state ) is
                  when IDLE =>
                    -- command byte
                    if   ( SPICMD_WRITE_C = r.sr ) then 
                       v.state := A2;
                    else
                       v.state := SKIP;
                       if    ( r.sr = SPICMD_READ_C  ) then
                       elsif ( r.sr = SPICMD_WRENA_C ) then
                       elsif ( r.sr = SPICMD_ER_64_C ) then
                       elsif ( r.sr = SPICMD_RSTAT_C ) then
                       else
                          -- unknown command
                          status(2) <= '1';
                       end if;
                    end if;
                  when A2 =>
                    v.addr(23 downto 16) := unsigned(r.sr);
                    v.state := A1;
                  when A1 =>
                    v.addr(15 downto  8) := unsigned(r.sr);
                    v.state := A0;
                  when A0 =>
                    v.addr( 7 downto  0) := unsigned(r.sr);
                    v.state := WRITE;
                    if ( v.addr < r.laddr ) then
                       -- write to address already written
                       status(3) <= '1';
                    end if;
                    v.laddr := v.addr;
                
                  when WRITE =>
                    if ( r.addr(8) /= r.laddr(8) ) then 
                       -- page wrap-around
                       status(4) <= '1';
                    end if;
                    v.addr  := r.addr  + 1;

                  when SKIP  =>

               end case;
            else
               v.bitCnt := r.bitCnt - 1;
            end if;
         end if;
      end if;
        
      rin <= v;
   end process P_COMB;

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

   state <= std_logic_vector( to_unsigned( StateType'pos( r.state ), state'length ) );
 
end architecture Impl;

