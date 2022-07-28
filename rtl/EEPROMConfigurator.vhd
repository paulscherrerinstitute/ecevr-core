library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.ESCBasicTypesPkg.all;
use work.Lan9254Pkg.all;
use work.Lan9254ESCPkg.all;
use work.IPAddrConfigPkg.all;
use work.EvrTxPDOPkg.all;
use work.Evr320ConfigPkg.all;
use work.EEPROMConfigPkg.all;

use work.IlaWrappersPkg.all;

entity EEPROMConfigurator is
   generic (
      CLOCK_FREQ_G       : real;               --Hz; at least 12*i2c freq
      I2C_FREQ_G         : real    := 100.0E3; --Hz
      I2C_BUSY_TIMEOUT_G : real    := 0.1;     -- sec
      I2C_CMD_TIMEOUT_G  : real    := 1.0E-3;  -- sec
      MAX_TXPDO_MAPS_G   : natural := 16;
      EEPROM_OFFSET_G    : natural := 0;       -- address of the configuration area
                                               -- if set to 0 then the SII category
                                               -- headers are scanned.
      CATEGORY_ID_G      : std_logic_vector(15 downto 0) := x"0001";
                                               -- category ID to scan for; use a device-
                                               -- (or vendor-) specific ID according to
                                               -- the SII spec. Ignored if EEPROM_OFFSET_G
                                               -- is nonzero.
      EEPROM_SIZE_G      : natural := 16384;   -- in bits; it's probably a good idea
                                               -- to always use the maximum. Smaller
                                               -- devices will not respond if the higher
                                               -- bits don't match (but could be banked).
                                               -- OTOH, setting this generic to a small
                                               -- value renders larger devices unusable!
                                               -- 1- vs. 2-byte addressing can be switched
                                               -- dynamically.
      I2C_ADDR_G         : std_logic_vector(6 downto 0) := "1010000";
      GEN_ILA_G          : boolean := true
   );
   port (
      clk                : in  std_logic;
      rst                : in  std_logic;

      -- the SM configuration is released
      -- last which starts the ESC
      configReq          : out EEPROMConfigReqType;
      configAck          : in  EEPROMConfigAckType;
      dbufMaps           : out MemXferArray(MAX_TXPDO_MAPS_G - 1 downto 0);

      i2cAddr2BMode      : in  std_logic := toSl( EEPROM_SIZE_G >= 32768 );
                                                 -- assert if eeprom used 2 address bytes
                                                 -- (>= 32kbit devices).

      emulActive         : in  std_logic := '0';

      eepWriteReq        : in  EEPROMWriteWordReqType := EEPROM_WRITE_WORD_REQ_INIT_C;
      eepWriteAck        : out EEPROMWriteWordAckType;

      i2cSclInp          : in  std_logic := '1';
      i2cSclOut          : out std_logic;
      i2cSclHiZ          : out std_logic;

      i2cSdaInp          : in  std_logic := '1';
      i2cSdaOut          : out std_logic;
      i2cSdaHiZ          : out std_logic;

      retries            : out unsigned(3 downto 0);

      debug              : out std_logic_vector(31 downto 0)
   );
end entity EEPROMConfigurator;

architecture rtl of EEPROMConfigurator is

   constant VERSION_OFF_C         : natural       := 0;
   constant NET_CFG_OFF_C         : natural       := VERSION_OFF_C + 1;
   constant EVR_NPG_OFF_C         : natural       := NET_CFG_OFF_C + slv08ArrayLen( toSlv08Array( makeIPAddrConfigReq      ) );
   constant EVR_CFG_OFF_C         : natural       := EVR_NPG_OFF_C + 1;
   constant TXP_CFG_OFF_C         : natural       := EVR_CFG_OFF_C + slv08ArrayLen( toSlv08Array( EVR320_CONFIG_REQ_INIT_C ) );
   constant CFG_LEN_C             : natural       := TXP_CFG_OFF_C + slv08ArrayLen( toSlv08Array( EVR_TXPDO_CONFIG_INIT_C  ) );

   constant ELM_LEN_C             : natural       := slv08ArrayLen( toSlv08Array( MEM_XFER_INIT_C ) );
   constant MAP_LEN_C             : natural       := MAX_TXPDO_MAPS_G * ELM_LEN_C;
   constant PROM_LEN_C            : natural       := MAP_LEN_C + CFG_LEN_C;

   -- maximum length of a single transfer operation by PsiI2cStrmIF
   constant MAX_CHUNK_C           : natural       := 128;

   constant I2C_RD_C              : std_logic     := '1';
   constant I2C_WR_C              : std_logic     := '0';

   constant NO_STOP_C             : std_logic     := '1';
   constant GEN_STOP_C            : std_logic     := '0';

   constant CAT_SM_C              : std_logic_vector(15 downto 0) := x"0029";
   constant CAT_END_C             : std_logic_vector(15 downto 0) := x"FFFF";
   constant CAT_OFF_C             : natural                       := 16#80#;
   constant CAT_HDR_L_C           : natural                       := 4;
   constant SM3_LEN_OFF_C         : natural                       := 8*3 + 2;
   constant SM2_LEN_OFF_C         : natural                       := 8*2 + 2;
   constant SM_LEN_LEN_C          : natural                       := 2;

   constant MAX_CATS_C            : natural                       := 63;

   function i2cHeader(
      constant a2b        : in std_logic;
      constant op         : in std_logic;
      constant count      : in unsigned(6 downto 0)          := (others => '0'); -- desired count - 1
      constant noStop     : in std_logic                     := GEN_STOP_C;
      constant addr       : in unsigned        (15 downto 0) := (others => '0')
   )  return std_logic_vector is
      variable a : std_logic_vector( 6 downto 0) := I2C_ADDR_G;
   begin
      if ( ( a2b = '0' ) and ( EEPROM_SIZE_G > 2048 ) and ( op = I2C_WR_C ) ) then
         if    ( EEPROM_SIZE_G <= 4096 ) then
            a(0 downto 0) := std_logic_vector( addr( 8 downto 8) );
         elsif ( EEPROM_SIZE_G <= 8192 ) then
            a(1 downto 0) := std_logic_vector( addr( 9 downto 8) );
         elsif ( EEPROM_SIZE_G <= 16384 ) then
            a(2 downto 0) := std_logic_vector( addr(10 downto 8) );
         end if;
      end if;
      return noStop & std_logic_vector(count) & a & op;
   end function i2cHeader;

   type StateType is (INIT, START, ADDR, ADDR_RESP, READ, RCV, STORE_UPPER, DRAIN, CHECK, DONE, I2C_WRA, I2C_WRD);

   type RegType is record
      state     : StateType;
      retState  : StateType;
      strmTxMst : Lan9254StrmMstType;
      smCfg     : ESCConfigReqType;
      smCfg32   : std_logic_vector(1 downto 0);
      eepAddr   : unsigned(15 downto 0);
      cfgAddr   : unsigned(15 downto 0);
      eepNext   : unsigned(15 downto 0);
      strmRxRdy : std_logic;
      macVld    : std_logic;
      ip4Vld    : std_logic;
      udpVld    : std_logic;
      evrCfgVld : std_logic;
      txPdoVld  : std_logic;
      wrp       : natural range 0 to CFG_LEN_C; -- CFG_LEN_C - 1 would suffice but v.wrp := r.wrp + 1
      lwrp      : natural range 0 to CFG_LEN_C; -- fails simulation even if OOR value is never used later.
      wcnt      : natural range 0 to PROM_LEN_C;
      lwcnt     : natural range 0 to PROM_LEN_C;
      eepEnd    : natural range 0 to PROM_LEN_C - 1;
      cfgEnd    : natural range 0 to PROM_LEN_C - 1;
      cnt       : unsigned(6 downto 0);
      allOnes   : std_logic;
      allZeros  : std_logic;
      cfgImg    : Slv08Array(0 to CFG_LEN_C - 1);
      mapImg    : Slv08Array(0 to ELM_LEN_C - 1);
      tmp       : std_logic_vector(7 downto 0);
      maps      : MemXferArray(MAX_TXPDO_MAPS_G - 1 downto 0);
      nMaps     : natural range 0 to MAX_TXPDO_MAPS_G;
      lnMaps    : natural range 0 to MAX_TXPDO_MAPS_G;
      catDone   : boolean;
      cfgFound  : boolean;
      retries   : unsigned( 3 downto 0);
      catsFound : natural range 0 to MAX_CATS_C;
      eepWrAck  : EEPROMWriteWordAckType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      state     => INIT,
      retState  => INIT,
      strmTxMst => LAN9254STRM_MST_INIT_C,
      smCfg     => ESC_CONFIG_REQ_NULL_C,
      smCfg32   => "00",
      eepAddr   => to_unsigned( CAT_OFF_C      , 16),
      cfgAddr   => to_unsigned( EEPROM_OFFSET_G, 16),
      eepNext   => to_unsigned( 0              , 16),
      strmRxRdy => '0',
      macVld    => '0',
      ip4Vld    => '0',
      udpVld    => '0',
      evrCfgVld => '0',
      txPdoVld  => '0',
      wrp       =>  0,
      lwrp      =>  0,
      wcnt      =>  0,
      lwcnt     =>  0,
      eepEnd    => CAT_HDR_L_C - 1,
      cfgEnd    => PROM_LEN_C  - 1,
      allOnes   => '0',
      allZeros  => '0',
      cnt       => (others => '0'),
      cfgImg    => ( others => (others => '1') ), -- emulate blank eeprom
      mapImg    => ( others => (others => '1') ),
      maps      => ( others => MEM_XFER_INIT_C ),
      tmp       => (others => '0'),
      nMaps     => 0,
      lnMaps    => 0,
      catDone   => (EEPROM_OFFSET_G /= 0),
      cfgFound  => false,
      retries   => (others => '0'),
      catsFound => 0,
      eepWrAck  => EEPROM_WRITE_WORD_ACK_INIT_C
   );

   procedure storeByte(
      variable v : inout RegType;
      constant r : in    RegType;
      constant d : in    std_logic_vector(7 downto 0)
   ) is
   begin
      v               := v;
      v.wcnt          := r.wcnt + 1;
      v.cnt           := r.cnt  - 1;
      if ( r.wcnt < CFG_LEN_C ) then
         v.cfgImg(r.wrp) := d;
         v.wrp           := r.wrp  + 1;
      elsif ( r.wcnt = CFG_LEN_C ) then
         v.wrp           := 1;
         v.mapImg(0)     := d;
      else
         v.mapImg( r.wrp ) := d;
         if ( r.wrp = ELM_LEN_C - 1 ) then
            if ( toMemXferType( v.mapImg ).num /= 0 ) then
               v.maps( r.nMaps ) := toMemXferType( v.mapImg );
               v.nMaps           := r.nMaps + 1;
            end if;
            v.wrp := 0;
         else
            v.wrp := r.wrp  + 1;
         end if;
      end if;

   end procedure storeByte;

   function toU16(
      constant x : in Slv08Array;
      constant i : in natural
   ) return unsigned is
      constant c : unsigned(15 downto 0) := unsigned(x(i+1)) & unsigned(x(i));
   begin
      return c;
   end function toU16;

   function versionMatch(constant x : RegType) return std_logic is
   begin
      return toSl( x.cfgImg(VERSION_OFF_C) = EEPROM_LAYOUT_VERSION_C );
   end function versionMatch;

   signal r                 : RegType := REG_INIT_C;
   signal rin               : RegType;

   signal configReqLoc      : EEPROMConfigReqType := EEPROM_CONFIG_REQ_INIT_C;

   signal strmRxMst         : Lan9254StrmMstType;
   signal strmTxRdy         : std_logic;

begin

   assert EEPROM_OFFSET_G + PROM_LEN_C <= EEPROM_SIZE_G / 8
      report "EEPROM too small" severity failure;

   P_MAP  : process ( r ) is
   begin
      configReqLoc.version        <= r.cfgImg(VERSION_OFF_C);
      configReqLoc.net            <= toIPAddrConfigReqType( r.cfgImg(NET_CFG_OFF_C to EVR_NPG_OFF_C - 1 ) );
      configReqLoc.evr320NumPG    <= r.cfgImg(EVR_NPG_OFF_C);
      configReqLoc.evr320         <= toEvr320ConfigReqType( r.cfgImg(EVR_CFG_OFF_C to TXP_CFG_OFF_C - 1 ) );
      configReqLoc.txPDO          <= toEvrTxPDOConfigType ( r.cfgImg(TXP_CFG_OFF_C to CFG_LEN_C     - 1 ) );
      configReqLoc.esc            <= r.smCfg;
      configReqLoc.net.macAddrVld <= r.macVld;
      configReqLoc.net.ip4AddrVld <= r.ip4Vld;
      configReqLoc.net.udpPortVld <= r.udpVld;
      configReqLoc.evr320.req     <= r.evrCfgVld;
      configReqLoc.txPDO.numMaps  <= r.nMaps;
      configReqLoc.txPDO.valid    <= r.txPdoVld;
   end process P_MAP;

   P_COMB : process ( r, configReqLoc, configAck, strmTxRdy, strmRxMst, i2cAddr2BMode, eepWriteReq, emulActive ) is
      variable v     : RegType;
      variable a2b   : std_logic;
      variable baddr : unsigned(15 downto 0);
   begin

      v := r;

      -- abbreviation
      a2b   := i2cAddr2BMode;
      baddr := (eepWriteReq.waddr & '0');

      -- ack flags
      if ( ( r.strmTxMst.valid and strmTxRdy ) = '1' ) then
         v.strmTxMst.valid := '0';
      end if;

      if ( ( r.macVld and configAck.net.macAddrAck ) = '1' ) then
         v.macVld := '0';
      end if;
      if ( ( r.ip4Vld and configAck.net.ip4AddrAck ) = '1' ) then
         v.ip4Vld := '0';
      end if;
      if ( ( r.udpVld and configAck.net.udpPortAck ) = '1' ) then
         v.udpVld := '0';
      end if;
      if ( ( r.smCfg.valid and configAck.esc.ack ) = '1' ) then
         v.smCfg.valid := '0';
      end if;
      if ( ( r.evrCfgVld and configAck.evr320.ack ) = '1' ) then
         v.evrCfgVld := '0';
      end if;

      v.eepWrAck.ack := '0';

      v.retState := r.state;

      case ( r.state ) is
         when INIT  =>
            if ( emulActive = '1' ) then
               v.state := DONE; 
               -- we don't support reading the real emulated eeprom contents;
               -- just supply the hard-coded SM defaults.
               v.smCfg := ESC_CONFIG_REQ_INIT_C;
            else
               v.state := START;
            end if;

         when START =>
            v.lwcnt     := r.wcnt;
            v.lwrp      := r.wrp;
            v.lnMaps    := r.nMaps;
            -- while processing categories we assume nothing bad happens if we read
            -- a few words ahead (assume eeprom 'wraps' around if we hit the 0xffff
            -- end marker if that happens to be at the very end of the PROM)...
            if ( r.wcnt <= r.eepEnd ) then
               -- 'cnt' is the actual count - 1
               if ( r.eepEnd - r.wcnt > MAX_CHUNK_C - 1 ) then
                  v.cnt := to_unsigned(MAX_CHUNK_C - 1   , v.cnt'length);
               else
                  v.cnt := to_unsigned(r.eepEnd - r.wcnt, v.cnt'length);
               end if;
               v.eepNext         := r.eepAddr + v.cnt + 1;
               v.strmTxMst.last  := '0';
               v.strmTxMst.data  := i2cHeader( a2b, I2C_WR_C, noStop => NO_STOP_C, addr => r.eepAddr );
               v.strmTxMst.ben   := "11";
               v.strmTxMst.valid := '1';
               v.state           := ADDR;
            elsif ( r.smCfg32 /= "00" ) then
               -- store sync manager info
               v.wcnt := 0;
               v.wrp  := 0;
               if ( r.smCfg32(1) = '1' ) then
                  v.smCfg.sm3Len := r.cfgImg(1) & r.cfgImg(0);
                  v.smCfg32(1)   := '0';
                  -- set up to read SM2 length
                  v.eepAddr      := r.eepAddr - SM_LEN_LEN_C - (SM3_LEN_OFF_C - SM2_LEN_OFF_C);
               elsif ( r.smCfg32(0) = '1' ) then
                  v.smCfg.sm2Len := r.cfgImg(1) & r.cfgImg(0);
                  v.smCfg32(0)   := '0';
                  -- skip to next category; this category's length is still in cfgImg(3:2)
                  v.eepAddr      := r.eepAddr - SM_LEN_LEN_C - SM2_LEN_OFF_C
                                  + shift_left( resize( toU16( r.cfgImg, 2 ) , v.eepAddr'length ), 1 );
                  v.eepEnd       := CAT_HDR_L_C - 1;
               end if;
            elsif ( not r.catDone ) then
               -- we now have a category header
               v.wcnt      := 0;
               v.wrp       := 0;
               -- skip to next category
               v.eepAddr   := r.eepAddr + shift_left( resize( toU16( r.cfgImg, 2 ) , v.eepAddr'length ), 1 );
               v.catsFound := r.catsFound + 1;

               if ( ( (r.cfgImg(1) & r.cfgImg(0)) = CAT_END_C ) or (r.catsFound = MAX_CATS_C) ) then
                  v.catDone     := true;
                  v.catsFound   := r.catsFound;
                  if ( r.cfgFound ) then
                     -- go read the 'real' configuration
                     v.eepAddr  := r.cfgAddr;
                     v.eepEnd   := r.cfgEnd;
                  else
                     -- fall back
                     v.state    := CHECK;
                     v.allZeros := '0';
                     v.allOnes  := '0';
                     v.cnt      := to_unsigned( 0, v.cnt'length );
                  end if;
               elsif ( ( r.cfgImg(1) & r.cfgImg(0) ) = CATEGORY_ID_G ) then
                  -- that's us! set the reader up for the 'real' data
                  v.cfgFound := true;
                  v.cfgAddr  := r.eepAddr;
                  v.cfgEnd   := to_integer( shift_left( toU16( r.cfgImg, 2 ), 1 ) ) - 1;
                  if ( v.cfgEnd > PROM_LEN_C - 1 ) then
                     v.cfgEnd := PROM_LEN_C - 1;
                  end if;
               elsif ( ( r.cfgImg(1) & r.cfgImg(0) ) = CAT_SM_C ) then
                  -- sync manager
                  if    ( toU16(r.cfgImg, 2) >= 32/2 ) then
                     v.smCfg32 := "11";
                     v.eepAddr := r.eepAddr + SM3_LEN_OFF_C;
                     v.eepEnd  := SM_LEN_LEN_C - 1;
                  elsif ( toU16(r.cfgImg, 2) >= 24/2 ) then
                     v.smCfg32 := "01";
                     v.eepAddr := r.eepAddr + SM2_LEN_OFF_C;
                     v.eepEnd  := SM_LEN_LEN_C - 1;
                  else
                     -- no SM2 nor SM3 info; skip
                  end if;
               else
                  -- some other category; skip
               end if;
            else
               -- we are DONE raise the valid flags...
               v.state    := CHECK;
               v.allZeros := '1';
               v.allOnes  := '1';
               v.cnt      := to_unsigned( 0, v.cnt'length );
            end if;

         when CHECK =>
            v.allZeros := r.allZeros and toSl( r.cfgImg( to_integer( r.cnt ) ) = x"00" );
            v.allOnes  := r.allOnes  and toSl( r.cfgImg( to_integer( r.cnt ) ) = x"FF" );
            if    ( r.cnt = 5 ) then
               v.macVld   := not v.allOnes and not v.allZeros and versionMatch( r );
               v.allOnes  := '1';
               v.allZeros := '1';
            elsif ( r.cnt = 9 ) then
               v.ip4Vld   := not v.allOnes and not v.allZeros and versionMatch( r );
               v.allOnes  := '1';
               v.allZeros := '1';
            elsif ( r.cnt = 11 ) then
               v.udpVld   := not v.allOnes and not v.allZeros and versionMatch( r );
               v.allOnes  := '1';
            elsif ( r.cnt = CFG_LEN_C - 1 ) then
               v.state         := DONE;
               -- let the ESC start
               v.smCfg.valid   := '1';
               v.evrCfgVld     := versionMatch( r );
               v.txPdoVld      := '1';
            end if;
            v.cnt := r.cnt + 1;

         when DONE =>
            if ( eepWriteReq.valid = '1' ) then
               v.strmTxMst.data  := i2cHeader( a2b, I2C_WR_C, noStop => GEN_STOP_C, addr => baddr );
               v.strmTxMst.last  := '0';
               v.strmTxMst.ben   := "11";
               v.strmTxMst.valid := '1';
               v.state           := I2C_WRA;
            end if;

         when I2C_WRA =>
            if ( strmTxRdy = '1' ) then
               if ( i2cAddr2BMode = '1' ) then
                  -- address is expected as big-endian
                  v.strmTxMst.data             := std_logic_vector( bswap( baddr ) );
               else
                  v.strmTxMst.data(7 downto 0) := std_logic_vector( baddr(7 downto 0) );
                  v.strmTxMst.ben(1)           := '0';
               end if;
               v.strmTxMst.valid := '1';
               v.state           := I2C_WRD;
            end if;

         when I2C_WRD =>
            if ( r.strmRxRdy = '1' ) then
               if ( strmRxMst.valid = '1' ) then
                  -- reply from I2C master arrived; ready
                  -- to accept the next command.
                  -- Assume the last TX transaction is accepted
                  -- before we receive this reply.
                  v.strmRxRdy    := '0';
                  v.state        := DONE;
               end if;
            elsif ( strmTxRdy = '1' ) then
               v.strmTxMst.data  := eepWriteReq.wdata;
               v.strmTxMst.ben   := "11";
               v.strmTxMst.last  := '1';
               v.strmTxMst.valid := '1';
               v.strmRxRdy       := '1';
               v.eepWrAck.ack    := '1';
            end if;

         when ADDR =>
            -- send EEPROM read address
            if ( strmTxRdy = '1' ) then
               if ( i2cAddr2BMode = '1' ) then
                  -- address is expected as big-endian
                  v.strmTxMst.data               := std_logic_vector( bswap( r.eepAddr ) );
               else
                  v.strmTxMst.data(7 downto 0)   := std_logic_vector( r.eepAddr(7 downto 0) );
                  v.strmTxMst.ben(1)             := '0';
               end if;
               v.strmTxMst.valid := '1';
               v.strmTxMst.last  := '1';
               v.state           := ADDR_RESP;
               v.strmRxRdy       := '1';
            end if;

         when ADDR_RESP =>
            -- handle reply to writing EEPROM read address
            if ( ( r.strmRxRdy and strmRxMst.valid ) = '1' ) then
               v.strmRxRdy := '0';
               if ( strmRxMst.ben = "00" ) then
                  -- error; retry
                  v.retState           := START;
                  if ( r.retries /= unsigned(to_signed(-1, r.retries'length)) ) then
                     v.retries   := r.retries + 1;
                  end if;
               else
                  v.retState           := READ;
               end if;
            end if;
            if ( ( r.strmTxMst.valid and strmTxRdy ) = '1' ) then
               v.strmTxMst.valid := '0';
            end if;
            if ( ( v.strmTxMst.valid or v.strmRxRdy ) = '0' ) then
               v.state  := v.retState;
            end if;

         when READ =>
            if ( strmTxRdy = '1' ) then
               v.strmTxMst.data  := i2cHeader( a2b, I2C_RD_C, r.cnt );
               v.strmTxMst.ben   := "11";
               v.strmTxMst.valid := '1';
               v.strmTxMst.last  := '1';
               v.state           := RCV;
               v.strmRxRdy       := '1';
            end if;

         when RCV =>
            v.strmRxRdy := '1';
            if ( (r.strmRxRdy and strmRxMst.valid) = '1' ) then
               if ( strmRxMst.ben = "00" ) then
                  -- this is an error condition and we'll retry
                  if ( strmRxMst.last = '0' ) then
                     v.state     := DRAIN;
                  else
                     v.state     := START; -- retry
                     v.strmRxRdy := '0';
                  end if;
                  -- restore write-pointer and counters
                  v.wrp       := r.lwrp;
                  v.wcnt      := r.lwcnt;
                  v.nMaps     := r.lnMaps;
                  if ( r.retries /= unsigned(to_signed(-1, r.retries'length)) ) then
                     v.retries   := r.retries + 1;
                  end if;
               else

                  if ( (strmRxMst.last = '1') or ( r.cnt = 0 ) or ( ( r.cnt = 1 ) and ( strmRxMst.ben = "11" ) )  ) then
                     -- termination condition
                     if ( strmRxMst.last = '0' ) then
                        -- requested number of data arrived but there is more to come
                        -- (for unknown reasons?); drain
                        v.state     := DRAIN;
                        v.eepAddr   := r.eepNext;
                     else
                        -- If r.cnt > 0 we might not have received everything;
                        -- we must adjust the 'next' pointer by the missing amount
                        v.eepAddr   := r.eepNext - r.cnt;
                        -- however, if r.cnt > 0 and ben = "11" then there is still one element
                        -- that we'll process in STORE_UPPER
                        if ( ( r.cnt > 0 ) and ( strmRxMst.ben = "11" ) ) then
                           v.eepAddr := v.eepAddr + 1;
                        end if;
                        v.state     := START;
                        v.strmRxRdy := '0';
                     end if;
                  end if;

                  if    ( strmRxMst.ben(0) = '1' ) then
                     storeByte( v, r, strmRxMst.data(7 downto 0) );
                     if ( ( strmRxMst.ben(1) = '1' ) and ( r.cnt > 0 ) ) then
                        v.retState  := v.state;
                        v.state     := STORE_UPPER;
                        v.strmRxRdy := '0';
                        v.tmp       := strmRxMst.data(15 downto 8);
                     end if;
                  elsif ( strmRxMst.ben(1) = '1' ) then
                     storeByte( v, r, strmRxMst.data(15 downto 8) );
                  end if;

               end if;
            end if;

         when STORE_UPPER =>
            storeByte( v, r, r.tmp );
            v.state := r.retState;

         when DRAIN =>
            v.strmRxRdy := '1';
            if ( (r.strmRxRdy and strmRxMst.last and strmRxMst.valid) = '1' ) then
               v.strmRxRdy := '0';
               v.state     := START;
            end if;

      end case;

      rin       <= v;
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

   U_STRM : entity work.PsiI2cStreamIF
      generic map (
         CLOCK_FREQ_G   => CLOCK_FREQ_G,
         I2C_FREQ_G     => I2C_FREQ_G,
         BUSY_TIMEOUT_G => I2C_BUSY_TIMEOUT_G,
         CMD_TIMEOUT_G  => I2C_CMD_TIMEOUT_G
      )
      port map (
         clk            => clk,
         rst            => rst,

         strmMstIb      => r.strmTxMst,
         strmRdyIb      => strmTxRdy,

         strmMstOb      => strmRxMst,
         strmRdyOb      => r.strmRxRdy,

         i2c_scl_i      => i2cSclInp,
         i2c_scl_o      => i2cSclOut,
         i2c_scl_t      => i2cSclHiZ,

         i2c_sda_i      => i2cSdaInp,
         i2c_sda_o      => i2cSdaOut,
         i2c_sda_t      => i2cSdaHiZ
      );

   dbufMaps    <= r.maps;
   configReq   <= configReqLoc;

   retries     <= r.retries;

   eepWriteAck <= r.eepWrAck;

   debug(31 downto 4) <= (others => '0');
   debug( 3 downto 0) <= std_logic_vector( to_unsigned( StateType'pos( r.state ), 4 ) );

   G_ILA : if ( GEN_ILA_G ) generate
      signal p0 : std_logic_vector(63 downto 0) := (others => '0');
      signal p1 : std_logic_vector(63 downto 0) := (others => '0');
      signal p2 : std_logic_vector(63 downto 0) := (others => '0');
      signal p3 : std_logic_vector(63 downto 0) := (others => '0');
   begin
      p0( 3 downto  0) <= std_logic_vector( to_unsigned( StateType'pos( r.state ), 4 ) );
      p0( 7 downto  4) <= std_logic_vector( to_unsigned( StateType'pos( r.retState ), 4 ) );
      p0(23 downto  8) <= r.strmTxMst.data;
      p0(          24) <= r.strmTxMst.valid;
      p0(          25) <= r.strmTxMst.last;
      p0(27 downto 26) <= r.strmTxMst.ben;
      p0(43 downto 28) <= std_logic_vector( r.eepAddr );
      p0(59 downto 44) <= std_logic_vector( r.cfgAddr );
      p0(61 downto 60) <= r.smCfg32;
      p0(          62) <= strmTxRdy;
      p0(          63) <= r.macVld;

      p1( 3 downto  0) <= std_logic_vector( to_unsigned( r.wrp,  4 ) );
      p1( 7 downto  4) <= std_logic_vector( to_unsigned( r.lwrp, 4 ) );
      p1(15 downto  8) <= std_logic_vector( to_unsigned( r.wcnt, 8 ) );
      p1(23 downto 16) <= std_logic_vector( to_unsigned( r.lwcnt, 8 ) );
      p1(31 downto 24) <= std_logic_vector( to_unsigned( r.eepEnd, 8 ) );
      p1(39 downto 32) <= std_logic_vector( to_unsigned( r.cfgEnd, 8 ) );
      p1(46 downto 40) <= std_logic_vector( r.cnt );
      p1(          47) <= toSl(r.catDone);
      p1(51 downto 48) <= std_logic_vector( to_unsigned( r.nMaps, 4 ) );
      p1(55 downto 52) <= std_logic_vector( to_unsigned( r.lnMaps, 4 ) );
      p1(63 downto 56) <= r.tmp;

      p2( 7 downto  0) <= r.cfgImg(0);
      p2(15 downto  8) <= r.cfgImg(1);
      p2(23 downto 16) <= r.cfgImg(2);
      p2(31 downto 24) <= r.cfgImg(3);
      p2(39 downto 32) <= r.cfgImg(4);
      p2(47 downto 40) <= r.cfgImg(5);
      p2(55 downto 48) <= r.cfgImg(6);
      p2(63 downto 56) <= r.cfgImg(7);

      p3( 7 downto  0) <= r.mapImg(0);
      p3(15 downto  8) <= r.mapImg(1);
      p3(23 downto 16) <= r.mapImg(2);
      p3(31 downto 24) <= r.mapImg(3);
      p3(          32) <= toSl( r.cfgFound );
      p3(          33) <= r.strmRxRdy;
      p3(          34) <= r.macVld;
      p3(          35) <= r.ip4Vld;
      p3(          36) <= r.udpVld;
      p3(          37) <= r.evrCfgVld;
      p3(43 downto 38) <= std_logic_vector( to_unsigned( r.catsFound, 6 ) );
      p3(          44) <= strmRxMst.valid;
      p3(          45) <= strmRxMst.last;
      p3(47 downto 46) <= strmRxMst.ben;
      p3(63 downto 48) <= strmRxMst.data;

      U_ILA : Ila_256
         port map (
            clk    => clk,
            probe0 => p0,
            probe1 => p1,
            probe2 => p2,
            probe3 => p3
         );
   end generate G_ILA;

end architecture rtl;
