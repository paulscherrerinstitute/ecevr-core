library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;

entity SpiBitShifter is
  generic (
    WIDTH_G : natural  := 8;
    DIV2_G  : positive := 1 -- half-period of pre-scaler
  );
  port (
    clk     : in  std_logic;
    rst     : in  std_logic;

    -- parallel data in
    datInp  : in  std_logic_vector(WIDTH_G - 1 downto 0);
    -- chip-select; if deasserted (high) nothing
    -- will be shifted
    csbInp  : in  std_logic;
    vldInp  : in  std_logic;
    rdyInp  : out std_logic;

    -- parallel data out
    datOut  : out std_logic_vector(WIDTH_G - 1 downto 0);
    -- valid/ready handshake
    vldOut  : out std_logic;
    rdyOut  : in  std_logic := '1';

    serClk  : out std_logic;
    serCsb  : out std_logic;
    serInp  : in  std_logic;
    serOut  : out std_logic
  );
end entity SpiBitShifter;

architecture Impl of SpiBitShifter is
  constant LD_W_C : natural := natural( ceil( log2( real( WIDTH_G ) ) ) ) + 1;
  type StateType is ( IDLE, CHIPSEL, CHIPSELB, SHIFT, DONE );

  type RegType is record
    state    : StateType;
    clkCnt   : unsigned(LD_W_C - 1 downto 0);
    sreg     : std_logic_vector(WIDTH_G downto 0);
    scsb     : std_logic;
    prsc     : natural range 0 to DIV2_G - 1;
  end record RegType;

  constant REG_INIT_C : RegType := (
    state    => IDLE,
    clkCnt   => (others => '0'),
    sreg     => (others => '1'),
    scsb     => '1',
    prsc     => 0
  );

  signal  r   : RegType := REG_INIT_C;
  signal  rin : RegType;
  
begin

  P_COMB : process ( r, datInp, csbInp, serInp, vldInp, rdyOut ) is
    variable v : RegType;
  begin
    v := r;
    if ( r.prsc > 0 ) then
      v.prsc := r.prsc - 1;
    end if;
    vldOut <= '0';
    rdyInp <= '0';
    case ( r.state ) is
      when IDLE =>
        rdyInp <= '1';
        if ( vldInp = '1' ) then
          -- if chip-select changes then handle this first
          v.sreg  := datInp & '0';
          v.prsc  := DIV2_G - 1;
          if ( csbInp = '0' ) then
            v.scsb := '0';
            v.state := CHIPSEL;
          else
            v.state := CHIPSELB;
          end if;
        end if;

      when CHIPSELB =>
        if ( r.prsc = 0 ) then
          v.prsc  := DIV2_G - 1;
          v.scsb  := '1';
          if ( r.scsb = '1' ) then
            v.state := DONE;
          end if;
        end if;

      when CHIPSEL =>
        if ( r.prsc = 0 ) then
          if ( r.scsb = '0' ) then
            v.state   := SHIFT;
            v.clkCnt  := to_unsigned(2*WIDTH_G - 1, v.clkCnt'length);
            v.prsc    := DIV2_G - 1;
            -- this causes a positive edge; register input
            v.sreg(0) := serInp;
          else
            v.state  := DONE;
          end if;
        end if;

      when SHIFT =>
        if ( r.prsc = 0 ) then
          v.clkCnt := r.clkCnt - 1;
          if ( r.clkCnt = 1 ) then
            v.state := DONE;
          else
            v.prsc := DIV2_G - 1;
            if ( r.clkCnt(0) = '1' ) then
              -- negative edge, shift out
              v.sreg := r.sreg( r.sreg'left - 1 downto 0 ) & '0';
            else
              -- positive edge, register serial input
              v.sreg(0) := serInp;
            end if;
          end if;
        end if;

      when DONE =>
        vldOut <= '1';
        if ( rdyOut = '1' ) then
          v.state := IDLE;
        end if;
    end case;

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

  -- assign outputs
  serClk <= std_logic( r.clkCnt(0) );
  serOut <= r.sreg( r.sreg'left );
  serCsb <= r.scsb;
  datOut <= r.sreg( datOut'range );
end architecture Impl;
