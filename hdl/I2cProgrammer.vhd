-- write stuff to I2C devices; mostly useful for initialization

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.ESCBasicTypesPkg.all;
use work.Lan9254Pkg.all;
use work.EEPROMContentPkg.all;

-- EEPROM stream format:
--  { cmdLo, cmdHi, n*data }
--
--  cmdLo[7:1] : i2c address
--  cmdLo[  0] : i2c command (read: '1', write: '0')
--
--  cmdLo      : 0x00 or 0xff => END of program marker
--
--  cmdHi[7]   : no stop condition
--  cmdHi[6]   : reserved (write 0)
--  cmdHi[5:4] : mux bits
--  cmdHi[3:0] : 'n' - number of bytes in this command (-1)
--  

entity I2cProgrammer is 
   generic (
      -- address of device holding the program
      I2C_ADDR_G   : std_logic_vector(7 downto 0) := x"50";
      I2C_MUX_G    : std_logic_vector(3 downto 0) := "0000";
      -- for testing the contents may be specified explicitly
      -- normally we use the version in the EEPROMContentPkg
      EEPROM_INIT_G: EEPROMArray                  := EEPROM_INIT_C
   );
   port (
      clk          : in  std_logic;
      rst          : in  std_logic;

      -- asserting starts the program
      cfgVld       : in  std_logic;
      cfgRdy       : out std_logic;
      cfgAddr      : in  unsigned(15 downto 0);
      cfgEepSz2B   : in  std_logic; -- eep uses 2-byte addressing
      -- read from emulated eeprom
      cfgEmul      : in  std_logic;

      don          : out std_logic;
      err          : out std_logic;
      ack          : in  std_logic := '1';
      
      i2cReq       : out Lan9254StrmMstType;
      i2cReqRdy    : in  std_logic;
      i2cRep       : in  Lan9254StrmMstType;
      i2cRepRdy    : out std_logic;
      i2cLock      : out std_logic
   );
end entity I2cProgrammer;

architecture Impl of I2cProgrammer is

   constant CMD_MAX_C : natural := 16;
   constant CMD_LEN_C : natural := 2;

   subtype CmdBufType is EEPROMArray(0 to (CMD_MAX_C + CMD_LEN_C)/2 - 1);

   type StateType is (IDLE, SET_READ_PTR, SCHED_READ, WAIT_READ, PROC_CMD, EXEC_WRITE, DRAIN, DONE);

   type RegType is record
      state       : StateType;
      retState    : StateType;
      req         : Lan9254StrmMstType ;
      repRdy      : std_logic;
      lock        : std_logic;
      cfgRdy      : std_logic;
      cfgAddr     : unsigned(cfgAddr'range);
      cmdBuf      : CmdBufType;
      count       : unsigned(3 downto 0);
      wrp         : natural range 0 to CmdBufType'length;
      err         : std_logic;
      sz2B        : std_logic;
      emulActive  : boolean;
   end record RegType;

   constant REG_INIT_C : RegType := (
      state       => IDLE,
      retState    => IDLE,
      req         => LAN9254STRM_MST_INIT_C,
      repRdy      => '0',
      lock        => '0',
      cfgRdy      => '1',
      cfgAddr     => (others => '0'),
      cmdBuf      => (others => (others => '0')),
      err         => '0',
      count       => (others => '0'),
      wrp         => 0,
      sz2B        => '0',
      emulActive  => false
   );

   constant I2C_NO_STOP_C : std_logic := '1';
   constant I2C_RD_C      : std_logic := '1';
   constant I2C_WR_C      : std_logic := '0';

   function toSlv(constant i: natural; constant len : natural) return std_logic_vector is
   begin
      return std_logic_vector( to_unsigned(i, len) );
   end function toSlv;

   function mkI2cHdr(
      constant len: unsigned(3 downto 0)         := (others => '0');
      constant adr: std_logic_vector(7 downto 0) := I2C_ADDR_G;
      constant cmd: std_logic                    := I2C_WR_C;
      constant stp: std_logic                    := not I2C_NO_STOP_C
   ) return std_logic_vector is
   begin
      return stp & std_logic_vector( resize( len, 7 ) ) & adr(6 downto 0) & cmd;
   end function mkI2cHdr;

   function mkEepAddr(
      constant eepPtr : unsigned(15 downto 0);
      constant sz2B   : std_logic
   ) return std_logic_vector is
   begin
      if ( sz2B = '1' ) then
         return I2C_ADDR_G;
      else
         return I2C_ADDR_G(7 downto 3) & std_logic_vector( eepPtr(10 downto 8) );
      end if;
   end function mkEepAddr;

   function emulRead(constant a : unsigned(15 downto 0)) return std_logic_vector is
      variable v : std_logic_vector(15 downto 0);
      constant i : natural := to_integer( shift_right( a, 1 ) );
   begin
      if ( a(0) = '0' ) then
         v := EEPROM_INIT_G( i );
      else
         v( 7 downto 0) := EEPROM_INIT_G( i   )(15 downto 8);
         v(15 downto 8) := EEPROM_INIT_G( i+1 )( 7 downto 0);
      end if;
      return v;
   end function emulRead;

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

begin

   P_COMB : process (r, cfgVld, cfgAddr, cfgEmul, cfgEepSz2B, ack, i2cReqRdy, i2cRep) is
      variable v : RegType;
   begin
      v   := r;

      case ( r.state ) is

         when IDLE =>
            if ( cfgVld = '1' ) then
               v.cfgRdy     := '0';
               v.cfgAddr    := cfgAddr;
               v.emulActive := (cfgEmul = '1');
               v.err        := '0';
               v.wrp        := 0;
               v.lock       := '1';
               if ( not v.emulActive ) then
                  v.state    := SET_READ_PTR;
                  v.sz2B     := cfgEepSz2B;
                  -- schedule setting the EEPROM read pointer
                  v.req.data  := mkI2cHdr( stp => I2C_NO_STOP_C, adr => mkEepAddr( v.cfgAddr, v.sz2B ) );
                  v.req.last  := '0';
                  v.req.usr   := I2C_MUX_G;
                  v.req.ben   := "11";
                  v.req.valid := '1';
               else
                  v.count    := to_unsigned( CMD_LEN_C - 1, v.count'length );
                  v.state    := WAIT_READ;
                  v.retState := PROC_CMD;
               end if;
            end if;

         when SET_READ_PTR =>
            if ( r.repRdy = '1' ) then
               -- wait for reply to set read ptr
               if ( i2cRep.valid = '1' ) then
                  -- here it is
                  v.repRdy := '0';
                  if ( i2cRep.ben = "00" ) then
                     v.err   := '1';
                     v.state := DONE;
                  else
                     v.wrp      := 0;
                     v.count    := to_unsigned( CMD_LEN_C - 1, v.count'length );
                     v.state    := SCHED_READ;
                     v.retState := PROC_CMD;
                  end if;
               end if;
            elsif ( i2cReqRdy = '1' ) then
               if ( r.req.last = '0' ) then
                  -- command word has been accepted
                  -- send address
                  if ( r.sz2B = '1' ) then
                    -- big-endian
                    v.req.data := std_logic_vector( r.cfgAddr(7 downto 0) & r.cfgAddr(15 downto 8) ); 
                    v.req.ben  := "11";
                  else
                    v.req.data(7 downto 0) := std_logic_vector( r.cfgAddr(7 downto 0) );
                    v.req.ben              := "01";
                  end if;
                  v.req.last := '1';
               else
                  v.req.valid := '0';
                  -- now wait for reply
                  v.repRdy    := '1';
               end if;
            end if;

         when WAIT_READ =>
            if ( ( r.repRdy = '1' ) or r.emulActive ) then
               if ( i2cRep.valid = '1' or r.emulActive ) then
                  -- here it is
                  if ( r.wrp = r.cmdBuf'length ) then
                     -- buffer overrun
                     v.err := '1';
                     if ( not r.emulActive and ( i2cRep.last = '0' ) ) then
                        v.state := DRAIN;
                     else
                        v.state := DONE;
                     end if;
                  else
                     if ( r.emulActive ) then
                        if ( to_integer(r.cfgAddr) > EEPROM_INIT_G'length*2 - 2 ) then
                           v.err   := '1';
                           v.state := DONE;
                        else
                           v.cmdBuf(r.wrp)  := emulRead( r.cfgAddr );
                           if ( r.count = 0 ) then
                              v.cfgAddr        := r.cfgAddr + 1;
                           else
                              v.cfgAddr        := r.cfgAddr + 2;
                           end if;
                           v.wrp            := r.wrp + 1;
                           if ( r.count < 2 ) then
                              v.state := r.retState;
                              -- restore the original count; we need it for writing
                              v.count := unsigned( v.cmdBuf(0)(11 downto 8) );
                           else
                              v.count := r.count - 2;
                           end if;
                        end if;
                     else
                        v.cmdBuf(r.wrp) := i2cRep.data;
                        v.wrp           := r.wrp + 1;
                        if ( i2cRep.last = '1' ) then
                           v.repRdy := '0';
                           v.state  := r.retState;
                        end if;
                     end if;
                  end if;
               end if;
            end if;

         when DRAIN =>
            if ( ( r.repRdy = '1' ) ) then
               if ( ( i2cRep.valid and i2cRep.last) = '1' ) then
                  v.err   := '1';
                  v.state := DONE;
               end if;
            end if;
 
         when SCHED_READ =>
            if ( not r.emulActive ) then
               if ( r.req.valid = '0' ) then
                  -- schedule readback
                  v.req.data  := mkI2cHdr( len => r.count, adr => mkEepAddr( v.cfgAddr, r.sz2B ), cmd => I2C_RD_C );
                  v.req.last  := '1';
                  v.req.usr   := I2C_MUX_G;
                  v.req.ben   := "11";
                  v.req.valid := '1';
               elsif ( i2cReqRdy = '1' ) then
                  -- has been accepted; wait for reply
                  v.req.valid := '0';
                  v.repRdy    := '1';
                  v.state     := WAIT_READ;
               end if;
            else
               v.state    := WAIT_READ;
            end if;

         when PROC_CMD =>
            -- prepare operation
            if    ( ( r.cmdBuf(0)(7 downto 0) = x"00" ) or ( r.cmdBuf(0)(7 downto 0) = x"FF" ) ) then
               -- found END marker
               v.state := DONE;
            elsif ( ( r.cmdBuf(0)(0) = I2C_RD_C ) or ( r.cmdBuf(0)(15) = I2C_NO_STOP_C ) ) then
               -- too cumbersome to support when sharing a i2c bus and/or master
               v.err   := '1';
               v.state := DONE;
            else
               v.count    := unsigned( r.cmdBuf(0)(11 downto 8) );
               v.retState := EXEC_WRITE;
               v.state    := SCHED_READ;
            end if;

         when EXEC_WRITE =>
            if ( r.repRdy = '1' ) then
               if ( i2cRep.valid = '1' ) then
                  -- got reply
                  -- write was accepted
                  v.repRdy := '0';

                  -- prepare fetching the next command
                  v.wrp      := 0;
                  v.count    := to_unsigned( CMD_LEN_C - 1, v.count'length );
                  v.state    := SCHED_READ;
                  v.retState := PROC_CMD;

                  if ( (i2cRep.ben = "00") or (i2cRep.last = '0') ) then
                     v.err := '1';
                     if ( i2cRep.last = '0' ) then
                        v.repRdy := '1';
                        v.state  := DRAIN;
                     end if;
                  end if;
               end if;
            else
               if ( v.req.valid = '0' ) then
                  v.req.data  := r.cmdBuf(0) and x"8FFF";
                  v.req.usr   := "00" & r.cmdBuf(0)(13 downto 12);
                  v.req.ben   := "11";
                  v.count     := unsigned( r.cmdBuf(0)(11 downto 8) );
                  v.wrp       := 1;
                  v.req.last  := '0';
                  v.req.valid := '1';
               elsif ( i2cReqRdy = '1' ) then
                  if ( r.req.last = '1' ) then
                     -- done
                     v.req.valid := '0';
                     -- wait for reply
                     v.repRdy    := '1';
                  else
                     -- this word was accepted; next one
                     v.req.data := r.cmdBuf( r.wrp );
                     v.wrp      := r.wrp + 1;
                     if ( r.count <= 1 ) then
                        v.req.last   := '1';
                        v.req.ben(1) := r.count(0);
                     else
                        v.count      := r.count - 2;
                     end if;
                  end if;
               end if;
            end if;

         when DONE =>
            v.lock := '0';
            if ( ack = '1' ) then
               v.cfgRdy := '1';
               v.state  := IDLE;
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

   cfgRdy    <= r.cfgRdy;

   don       <= '1' when r.state = DONE else '0';
   err       <= r.err;

   i2cReq    <= r.req;
   i2cRepRdy <= r.repRdy;
   i2cLock   <= r.lock;

end architecture Impl;
