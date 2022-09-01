library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

entity IcapE2Reg is
   port (
      clk       : in  std_logic;
      rst       : in  std_logic;

      addr      : in  std_logic_vector(15 downto 0);
      rdnw      : in  std_logic;
      dInp      : in  std_logic_vector(31 downto 0);
      req       : in  std_logic;

      dOut      : out std_logic_vector(31 downto 0);
      ack       : out std_logic
   );
end entity;

architecture Impl of IcapE2Reg is

   type StateType is ( IDLE, WRITE, READ, DESYNC );

   function brev(constant x : std_logic_vector(31 downto 0))
   return std_logic_vector is
      variable v : std_logic_vector(x'range);
   begin
      for i in 0 to 3 loop
         for j in 0 to 7 loop
            v(8*i + j) := x(8*i + 7 - j);
         end loop;
      end loop;
      return v;
   end function brev;

   type RegType is record
      state     : StateType;
      cnt       : natural;
      iOut      : std_logic_vector(31 downto 0);
      iInp      : std_logic_vector(31 downto 0);
      ack       : std_logic;
      rdnw      : std_logic;
      csb       : std_logic;
   end record RegType;

   constant REG_INIT_C : RegType := (
      state      => IDLE,
      cnt        => 0,
      iOut       => (others => '0'),
      iInp       => (others => '0'),
      rdnw       => '0',
      ack        => '0',
      csb        => '1'
   );

   signal   r      : RegType := REG_INIT_C;
   signal   rin    : RegType;

   signal   iRdDat : std_logic_vector( 31 downto 0 );
   signal   iWrDat : std_logic_vector( 31 downto 0 );

begin

   P_COMB : process ( r, addr, rdnw, dInp, req, iRdDat ) is
      variable v : RegType;
   begin
      v     := r;

      v.cnt := r.cnt + 1;
      v.ack := '0';

      case r.state is
         when IDLE =>
           v.cnt := 0;
           if ( req = '1' ) then
              v.iOut  := x"FFFFFFFF"; -- dummy word
              v.csb   := '0';
              v.state := WRITE;
           end if;

         when WRITE =>
           case ( r.cnt ) is
              when 0 =>
                 v.iOut := x"AA995566"; -- sync
              when 1 => 
                 v.iOut := x"20000000"; -- no-op
              when 2 => 
                 -- type-1 packet, word count 1
                 v.iOut               := x"2000_0001";
                 -- merge register address
                 v.iOut(17 downto 13) := addr(4 downto 0);

                 -- op-code
                 if ( rdnw = '1' ) then
                    v.iOut(27) := '1';
                    v.state    := READ;
                    v.cnt      := 0;
                 else
                    v.iOut(28) := '1';
                 end if;
              when others =>
                 -- send write data
                 v.iOut  := dInp;
                 v.state := DESYNC;
                 v.cnt   := 0;
           end case;

         when READ =>
              case ( r.cnt ) is
                 when 0 =>
                    v.iOut := x"20000000"; -- no-op
                 when 1 =>
                    v.csb  := '1';
                 when 2 =>
                    v.rdnw := '1';
                 when 3 | 4 | 5 | 6 =>
                    v.csb  := '0';
                 when 7 =>
                    v.iInp := brev( iRdDat );
                    v.csb  := '1';
                 when others =>
                    v.rdnw  := '0';
                    v.state := DESYNC;
                    v.cnt   := 0;
              end case;

         when DESYNC =>
            v.csb := '0';
            case ( r.cnt ) is
               when 0 | 1 => -- during read-cycle, cnt=0: r.csb is still '1'
                  v.iOut := x"20000000"; -- no-op
               when 2 =>
                  v.iOut := x"30008001"; -- word to CMD
               when 3 =>
                  v.iOut := x"0000000D"; -- desync
               when 4 | 5 =>
                  v.iOut := x"20000000"; -- no-op
               when 6 =>
                  v.csb   := '1';
                  v.ack   := '1';
               when 7 =>
                  -- ack reset in this state, see above
                  -- somehow, the real/hard ICAPE2 does not like
                  -- back-to-back access; simulation worked but
                  -- for the hard device I had to introduce this
                  -- one wait cycle (7)
                  v.csb   := '1';
               when others =>
                  v.csb   := '1';
                  v.state := IDLE;
            end case;

      end case;
      rin <= v;
   end process P_COMB;

   iWrDat <= brev( r.iOut );

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

   U_ICAP : component ICAPE2
      port map (
         CLK    => clk,
         CSIB   => r.csb,
         I      => iWrDat,
         O      => iRdDat,
         RDWRB  => r.rdnw
      );

   dOut <= r.iInp;
   ack  <= r.ack;

end architecture Impl;
