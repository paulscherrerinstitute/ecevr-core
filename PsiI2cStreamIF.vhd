library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.ESCBasicTypesPkg.all;
use work.Lan9254Pkg.all;

use work.IlaWrappersPkg.all;

-- Streaming interface for the PSI i2c master
-- Note: for the psi master to work the clock frequency must be > 12*I2C_FREQ_G

entity PsiI2cStreamIF is
   generic (
      CLOCK_FREQ_G    : real;                -- in Hz
      I2C_FREQ_G      : real    := 100.0E3;  -- in Hz
      BUSY_TIMEOUT_G  : real    := 0.1;      -- in sec
      CMD_TIMEOUT_G   : real    := 100.0e-6; -- in sec     $$ constant=10.0e-6 $$
      GEN_ILA_G       : boolean := false
   );
   port (
      clk             : in  std_logic;
      rst             : in  std_logic;

      -- first beat on this interface transfers transfers the
      -- i2c address (including the read/writeB flag).
      -- The upper byte-lane (6:0) contains the read count - 1.
      -- the lsbit data(15), if set refrains from sending a STOP condition.
      --
      strmMstIb       : in  Lan9254StrmMstType := LAN9254STRM_MST_INIT_C;
      strmRdyIb       : out std_logic          := '1';

      -- Readback data is streamed out here; if an error is detected
      -- (i.e., unability to obtain the bus) then a single, empty
      -- beat (last = '1', ben = "00") is returned. Successful writes
      -- return a zero word (ben="11", data=x"0000")
      strmMstOb       : out Lan9254StrmMstType := LAN9254STRM_MST_INIT_C;
      strmRdyOb       : in  std_logic          := '1';

      i2c_scl_i       : in  std_logic          := '1';
      i2c_scl_t       : out std_logic;
      i2c_scl_o       : out std_logic;

      i2c_sda_i       : in  std_logic          := '1';
      i2c_sda_t       : out std_logic;
      i2c_sda_o       : out std_logic;

      -- asserted if we are unable to acquire the bus for
      -- a long time
      arbError        : out std_logic
   );
end entity PsiI2cStreamIF;

architecture rtl of PsiI2cStreamIF is

   subtype CmdType is std_logic_vector(2 downto 0);

   constant I2C_START     : CmdType := "000";
   constant I2C_STOP      : CmdType := "001";
   constant I2C_RESTART   : CmdType := "010";
   constant I2C_WRITE     : CmdType := "011";
   constant I2C_READ      : CmdType := "100";

   type I2cRspType is record
      busBsy      : std_logic;
      arbLost     : std_logic;
      cmdTimo     : std_logic;
      vld         : std_logic;
      seq         : std_logic;
      dat         : std_logic_vector(7 downto 0);
      ack         : std_logic; -- inverted with respect to i2c levels!
      typ         : CmdType;
   end record I2cRspType;

   function rspErr(constant x : in  I2cRspType) return boolean is
   begin
      -- un-acked write includes slave not responding
      return   (x.arbLost or x.cmdTimo or x.seq ) = '1'
            or ((x.typ = I2C_WRITE) and (x.ack = '0'));
   end function rspErr;

   function rspDon(constant x : in  I2cRspType) return boolean is
   begin
      return (x.vld = '1');
   end function rspDon;

   type I2cCmdType is record
      vld         : std_logic;
      dat         : std_logic_vector(7 downto 0);
      ack         : std_logic; -- inverted with respect to i2c levels!
      typ         : CmdType;
   end record I2cCmdType;

   constant I2C_CMD_INIT_C : I2cCmdType := (
      vld         => '0',
      dat         => (others => '0'),
      ack         => '0',
      typ         => (others => '0')
   );

   function i2cSetCmd(
      constant typ : in  CmdType;
      constant ack : in  std_logic                    := '0';
      constant dat : in  std_logic_vector(7 downto 0) := x"FF";
      constant own : in  boolean                      := false
   ) return I2cCmdType is
      variable v : I2cCmdType := (
         vld => '1',
         typ => typ,
         dat => dat,
         ack => ack
      );
   begin
      if ( (typ = I2C_START) and own ) then
         v.typ := I2C_RESTART;
      end if;
      return v;
   end function i2cSetCmd;

   type StateType is ( IDLE, START, ADDR, RCV_DATA, CMD_WAIT, RESULT, XFER, DONE, STRM_WAIT, STATUS, DRAIN  );

   type RegType is record
      state       : StateType;
      retState    : StateType;
      i2cCmd      : I2cCmdType;
      strmMst     : Lan9254StrmMstType;
      strmRdyIb   : std_logic;
      disStop     : std_logic;
      count       : unsigned        ( 6 downto 0);
      xMst        : Lan9254StrmMstType;
      i2cDest     : std_logic_vector( 7 downto 0);
      err         : std_logic;
      arbCount    : unsigned        (11 downto 0);
      owner       : boolean;
   end record RegType;

   constant REG_INIT_C : RegType := (
      state       => IDLE,
      retState    => IDLE,
      i2cCmd      => I2C_CMD_INIT_C,
      strmMst     => LAN9254STRM_MST_INIT_C,
      strmRdyIb   => '0',
      disStop     => '0',
      count       => (others => '0'),
      xMst        => LAN9254STRM_MST_INIT_C,
      i2cDest     => (others => '0'),
      err         => '0',
      arbCount    => (others => '1'),
      owner       => false
   );

   signal rsp               : I2cRspType;
   signal i2cCmdRdy         : std_logic;

   signal strmRdyIbLoc      : std_logic := '0';

   signal r                 : RegType := REG_INIT_C;
   signal rin               : RegType;

   signal arbErrorLoc       : std_logic;

begin

   arbErrorLoc <= toSl( r.arbCount = 0 );

   P_COMB : process ( r, rsp, i2cCmdRdy, strmMstIb, strmRdyOb, arbErrorLoc ) is
      variable v : RegType;
   begin

      v := r;

      if ( rsp.busBsy = '0' ) then
         v.owner := false;
      end if;

      C_STATE : case ( r.state ) is
         when IDLE =>
            v.strmRdyIb := '1';
            if ( ( r.strmRdyIb and strmMstIb.valid ) = '1' ) then
               v.count   := unsigned(strmMstIb.data(14 downto 8));
               v.disStop := strmMstIb.data( 15 );
               v.i2cDest := strmMstIb.data( 7 downto 0);
               if ( strmMstIb.last = v.i2cDest(0) ) then
                  -- either read with no payload "11" or write with more data coming "00"
                  v.strmRdyIb  := '0';
                  v.state      := START;
               else
                  -- write with no data or read with extra data
                  v.err        := '1';
                  if ( strmMstIb.last = '0' ) then
                     v.retState := DONE;
                     v.state    := DRAIN;
                  else
                     v.state    := DONE;
                  end if;
               end if;
            end if;

         when START =>
            -- wait for bus to become available
            if ( ( rsp.busBsy = '0' ) or r.owner ) then
               v.i2cCmd        := i2cSetCmd( I2C_START, own => v.owner );
               v.state         := CMD_WAIT;
               v.strmMst.ben   := "00";
               v.strmMst.last  := '0';
               v.err           := '0';
               v.retState      := ADDR;
            end if;

         when DRAIN =>
            v.strmRdyIb := '1';
            if ( ( r.strmRdyIb and strmMstIb.valid and strmMstIb.last ) = '1' ) then
               v.strmRdyIb := '0';
               v.state     := r.retState;
            end if;

         when ADDR =>
            v.i2cCmd    := i2cSetCmd( I2C_WRITE, '0', r.i2cDest );
            v.state     := CMD_WAIT;
            -- this is a tricky corner case; since this is a write
            -- but subsequent transfers could be either read or write
            -- depending on i2cDest(0).
            v.xMst.last := '0';
            -- we set xMst.ben = "11" here so that the RESULT check
            -- proceeds to the next transaction;
            -- in XACT, we check the i2cDest(0) bit and do the right
            -- thing from there
            if ( r.i2cDest(0) = '1' ) then
               v.xMst.ben  := "11"; -- this causes RESULT to proceed to XACT
                                    -- where a new READ will be issued
            else
               v.xMst.ben  := "00"; -- this causes RESULT to proceed to RCV_DATA
            end if;
                     
         when RCV_DATA =>
            v.strmRdyIb := '1';
            if ( ( r.strmRdyIb and strmMstIb.valid ) = '1' ) then
               -- doesn't matter if we latch a bogus address
               v.strmRdyIb := '0';
               v.xMst      := strmMstIb;
               v.state     := XFER;
               if ( strmMstIb.ben = "00" ) then
                  -- skip this word
                  if ( strmMstIb.last = '1' ) then
                     v.state := DONE;
                  else
                     -- wait for the next one
                     v.strmRdyIb := '1';
                  end if;
               else
                  v.state := XFER;
               end if;
            end if;

         when CMD_WAIT =>
            -- wait for command to be accepted
            if ( ( r.i2cCmd.vld and i2cCmdRdy ) = '1' ) then
               v.i2cCmd.vld := '0';
               v.state      := RESULT;
            end if;

         when XFER =>
            v.state := CMD_WAIT;
            if ( v.i2cDest(0) = '1' ) then
              -- READ; do not ack the last transfer
              v.i2cCmd := i2cSetCmd( I2C_READ, toSl( r.count /= 0 ) );
            else
              -- WRITE
              if    ( r.xMst.ben(0) = '1' ) then
                 v.i2cCmd      := i2cSetCmd( I2C_WRITE, '0', r.xMst.data( 7 downto 0) );
                 v.xMst.ben(0) := '0';
              else
                 assert r.xMst.ben(1) = '1' report "Internal Error" severity failure;
                 v.i2cCmd      := i2cSetCmd( I2C_WRITE, '0', r.xMst.data(15 downto 8) );
                 v.xMst.ben(1) := '0';
              end if;
            end if;

         when RESULT =>
            -- wait for execution of the command by the i2c master
            if ( rspDon( rsp ) ) then
               -- evaluate the result
               if ( rspErr( rsp ) ) then
                  if ( rsp.arbLost = '1' and ( (r.i2cCmd.typ = I2C_START) or (r.i2cCmd.typ = I2C_RESTART) ) ) then
                     if ( arbErrorLoc = '0' ) then
                        v.arbCount := r.arbCount - 1;
                     end if;
                     v.state := START; -- try again
                  else
                     v.err   := '1';
                     v.state := DONE;
                  end if;
                  if ( r.xMst.last = '0' ) then
                     v.retState := v.state;
                     v.state    := DRAIN;
                  end if;
               else
                  if    ( r.i2cCmd.typ = I2C_READ ) then
                     -- I2C_READ
                     if ( v.strmMst.ben(0) = '0' ) then
                        v.strmMst.data( 7 downto 0) := rsp.dat;
                        v.strmMst.ben(0)            := '1';
                     else
                        v.strmMst.data(15 downto 8) := rsp.dat;
                        v.strmMst.ben(1)           := '1';
                     end if;
                     if ( ( r.count = 0 ) ) then
                        v.state         := STRM_WAIT;
                        v.strmMst.last  := '1';
                        v.strmMst.valid := '1';
                        v.retState      := DONE;
                     else
                        v.count    := r.count - 1;
                        if ( v.strmMst.ben(1) = '1' ) then
                           v.state         := STRM_WAIT;
                           v.strmMst.valid := '1';
                           v.retState      := XFER;
                        else
                           v.state    := XFER;
                        end if;
                     end if;
                  elsif  ( r.i2cCmd.typ = I2C_WRITE) then
                     -- I2C_WRITE
                     if ( r.xMst.ben = "00" ) then
                        if ( r.xMst.last = '1' ) then
                           v.state := DONE;
                        else
                           v.state := RCV_DATA;
                        end if;
                     else
                        v.state := XFER;
                     end if;
                  else
                     if ( r.i2cCmd.typ = I2C_START ) then
                        v.owner := true;
                     end if;
                     v.state := r.retState;
                  end if;
               end if;
            end if;

         when DONE =>
            if ( ( r.i2cDest(0) and not r.err ) = '1' ) then
               v.retState := IDLE;
            else
               v.retState := STATUS;
            end if;
            if ( (r.disStop and not r.err) = '1' ) then
               v.state := v.retState;
            else
               v.i2cCmd   := i2cSetCmd( I2C_STOP );
               v.state    := CMD_WAIT;
            end if;

         when STATUS =>
            v.strmMst.data  := (others => '0');
            v.strmMst.last  := '1';
            v.strmMst.ben   := (others => not r.err);
            v.strmMst.valid := '1';
            v.retState      := IDLE;
            v.state         := STRM_WAIT;

         when STRM_WAIT =>
            if ( ( r.strmMst.valid and strmRdyOb ) = '1' ) then
               v.strmMst.valid := '0';
               -- reset ben for the next possible transaction
               v.strmMst.ben   := "00";
               v.state         := r.retState;
            end if;

      end case C_STATE;

      rin <= v;
   end process P_COMB;

   P_SEQ  : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( rst = '1' ) then
            r <= REG_INIT_C;
         else
            r <= rin;
         end if;
      end if;
   end process P_SEQ;

   U_MST : entity work.psi_common_i2c_master
      generic map (
         ClockFrequency_g   => CLOCK_FREQ_G,
         I2cFrequency_g     => I2C_FREQ_G,
         BusBusyTimeout_g   => BUSY_TIMEOUT_G,
         CmdTimeout_g       => CMD_TIMEOUT_G,
         InternalTriState_g => false
      )
      port map (
         -- Control Signals
         Clk        => clk,
         Rst        => rst,

         -- Command Interface
         CmdRdy     => i2cCmdRdy,
         CmdVld     => r.i2cCmd.vld,
         CmdType    => r.i2cCmd.typ,
         CmdData    => r.i2cCmd.dat,
         CmdAck     => r.i2cCmd.ack,
         -- Response Interface
         RspVld     => rsp.vld,
         RspType    => rsp.typ,
         RspData    => rsp.dat,
         RspAck     => rsp.ack,
         RspArbLost => rsp.arbLost,
         RspSeq     => rsp.seq,
         -- Status Interface 
         BusBusy    => rsp.busBsy,
         TimeoutCmd => rsp.cmdTimo,
         -- I2c Interface with internal Tri-State (InternalTriState_g = true)
         I2cScl     => open,
         I2cSda     => open,
         -- I2c Interface with external Tri-State (InternalTriState_g = false)
         I2cScl_I   => i2c_scl_i,
         I2cScl_O   => i2c_scl_o,
         I2cScl_T   => i2c_scl_t,

         I2cSda_I   => i2c_sda_i,
         I2cSda_O   => i2c_sda_o,
         I2cSda_T   => i2c_sda_t

      );

   G_ILA : if ( GEN_ILA_G ) generate
      signal p0 : std_logic_vector(63 downto 0) := (others => '0');
      signal p1 : std_logic_vector(63 downto 0) := (others => '0');
      signal p2 : std_logic_vector(63 downto 0) := (others => '0');
      signal p3 : std_logic_vector(63 downto 0) := (others => '0');
   begin

      p0( 3 downto  0) <= std_logic_vector( to_unsigned( StateType'pos( r.state ), 4 ) );
      p0(           4) <= r.i2cCmd.vld;
      p0( 7 downto  5) <= r.i2cCmd.typ;
      p0(           8) <= i2cCmdRdy;
      p0(           9) <= rsp.vld;
      p0(          10) <= rsp.ack;
      p0(          11) <= rsp.arbLost;
      p0(          12) <= rsp.seq;
      p0(          13) <= rsp.busBsy;
      p0(          14) <= rsp.cmdTimo;
      p0(          15) <= toSl( r.owner );
      p0(          16) <= r.strmMst.valid;
      p0(          17) <= r.strmMst.last;
      p0(19 downto 18) <= r.strmMst.ben;
      p0(          20) <= strmRdyOb;
      p0(23 downto 21) <= (others => '0');
      p0(          24) <= strmMstIb.valid;
      p0(          25) <= strmMstIb.last;
      p0(27 downto 26) <= strmMstIb.ben;
      p0(          28) <= r.strmRdyIb;
      p0(31 downto 29) <= (others => '0');
      p0(          32) <= r.xMst.valid;
      p0(          33) <= r.xMst.last;
      p0(35 downto 34) <= r.xMst.ben;
      p0(51 downto 36) <= r.xMst.data;
      p0(59 downto 52) <= r.i2cCmd.dat;
      p0(63 downto 60) <= (others => '0');

      U_ILA : component Ila_256
         port map (
            clk    => clk,
            probe0 => p0,
            probe1 => p1,
            probe2 => p2,
            probe3 => p3
         );
   end generate G_ILA;

   strmRdyIb <= r.strmRdyIb;
   strmMstOb <= r.strmMst;
   arbError  <= arbErrorLoc;
end architecture rtl;
