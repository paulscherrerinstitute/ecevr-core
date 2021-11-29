library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.ESCBasicTypesPkg.all;
use work.Lan9254Pkg.all;
use work.Lan9254ESCPkg.all;
use work.IPAddrConfigPkg.all;
use work.EvrTxPDOPkg.all;
use work.EEPROMConfigPkg.all;

entity EEPROMConfigurator is
   generic (
      CLOCK_FREQ_G       : real;               --Hz; at least 12*i2c freq
      I2C_FREQ_G         : real    := 100.0E3; --Hz
      I2C_BUSY_TIMEOUT_G : real    := 0.1;     -- sec
      I2C_CMD_TIMEOUT_G  : real    := 1.0E-3;  -- sec
      MAX_TXPDO_MAPS_G   : natural := 16;
      EEPROM_OFFSET_G    : natural := 0;
      EEPROM_SIZE_G      : natural := 4096;    -- in BITs; determines how many address bytes are used
      I2C_ADDR_G         : std_logic_vector(6 downto 0) := "1010000"
   );
   port (
      clk                : in  std_logic;
      rst                : in  std_logic;

      -- the SM configuration is released
      -- last which starts the ESC
      configReq          : out EEPROMConfigReqType;
      configAck          : in  EEPROMConfigAckType;
      dbufMaps           : out MemXferArray(MAX_TXPDO_MAPS_G - 1 downto 0);

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

   constant NETCFG_LEN_C          : natural       := slv08ArrayLen( toSlv08Array( makeIPAddrConfigReq     ) );
   constant TXPCFG_LEN_C          : natural       := slv08ArrayLen( toSlv08Array( EVR_TXPDO_CONFIG_INIT_C ) );

   constant CFG_LEN_C             : natural       := NETCFG_LEN_C + TXPCFG_LEN_C;
   constant ELM_LEN_C             : natural       := slv08ArrayLen( toSlv08Array( MEM_XFER_INIT_C ) );
   constant MAP_LEN_C             : natural       := MAX_TXPDO_MAPS_G * ELM_LEN_C;
   constant PROM_LEN_C            : natural       := MAP_LEN_C + CFG_LEN_C;

   -- maximum length of a single transfer operation by PsiI2cStrmIF
   constant MAX_CHUNK_C           : natural       := 128;
   constant ADDR_2B_C             : boolean       := (EEPROM_SIZE_G > 16384);

   constant I2C_RD_C              : std_logic     := '1';
   constant I2C_WR_C              : std_logic     := '0';

   constant NO_STOP_C             : std_logic     := '1';
   constant GEN_STOP_C            : std_logic     := '0';

   constant CAT_DEV_ME_C          : std_logic_vector(15 downto 0) := x"0001";
   constant CAT_SM_C              : std_logic_vector(15 downto 0) := x"0029";
   constant CAT_END_C             : std_logic_vector(15 downto 0) := x"FFFF";
   constant CAT_OFF_C             : natural                       := 16#80#;
   constant CAT_HDR_L_C           : natural                       := 4;
   constant SM3_LEN_OFF_C         : natural                       := 8*3 + 2;
   constant SM2_LEN_OFF_C         : natural                       := 8*2 + 2;
   constant SM_LEN_LEN_C          : natural                       := 2;

   function i2cHeader(
      op         : std_logic;
      count      : unsigned(6 downto 0)          := (others => '0'); -- desired count - 1
      noStop     : std_logic                     := GEN_STOP_C;
      addr       : unsigned        (15 downto 0) := (others => '0')
   )  return std_logic_vector is
      variable a : std_logic_vector( 6 downto 0) := I2C_ADDR_G;
   begin
      if ( ( EEPROM_SIZE_G > 2048 ) and ( op = I2C_WR_C ) ) then
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

   type StateType is (START, ADDR, ADDR_RESP, READ, RCV, STORE_UPPER, DRAIN, CHECK, DONE);

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
   end record RegType;

   constant REG_INIT_C : RegType := (
      state     => START,
      retState  => START,
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
      retries   => (others => '0')
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
      configReqLoc.net            <= toIPAddrConfigReqType( r.cfgImg(0            to NETCFG_LEN_C - 1 ) );
      configReqLoc.txPDO          <= toEvrTxPDOConfigType ( r.cfgImg(NETCFG_LEN_C to CFG_LEN_C    - 1 ) );
      configReqLoc.esc            <= r.smCfg;
      configReqLoc.net.macAddrVld <= r.macVld;
      configReqLoc.net.ip4AddrVld <= r.ip4Vld;
      configReqLoc.net.udpPortVld <= r.udpVld;
      configReqLoc.txPDO.numMaps  <= r.nMaps;
   end process P_MAP;

   P_COMB : process ( r, configReqLoc, configAck, strmTxRdy, strmRxMst )
      variable v : RegType;
   begin

      v := r;

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


      v.retState := r.state;

      case ( r.state ) is
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
               v.strmTxMst.data  := i2cHeader( I2C_WR_C, noStop => NO_STOP_C, addr => r.eepAddr );
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
               v.wcnt    := 0;
               v.wrp     := 0;
               -- skip to next category
               v.eepAddr := r.eepAddr + shift_left( resize( toU16( r.cfgImg, 2 ) , v.eepAddr'length ), 1 );

               if ( (r.cfgImg(1) & r.cfgImg(0)) = CAT_END_C ) then
                  v.catDone := true;
                  if ( r.cfgFound ) then
                     -- go read the 'real' configuration
                     v.eepAddr := r.cfgAddr;
                     v.eepEnd  := r.cfgEnd;
                  else
                     -- fall back
                     v.state    := CHECK;
                     v.allZeros := '0';
                     v.allOnes  := '0';
                     v.cnt      := to_unsigned( 0, v.cnt'length );
                  end if;
               elsif ( ( r.cfgImg(1) & r.cfgImg(0) ) = CAT_DEV_ME_C ) then
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
               v.macVld   := not v.allOnes and not v.allZeros;
               v.allOnes  := '1';
               v.allZeros := '1';
            elsif ( r.cnt = 9 ) then
               v.ip4Vld   := not v.allOnes and not v.allZeros;
               v.allOnes  := '1';
               v.allZeros := '1';
            elsif ( r.cnt = 11 ) then
               v.udpVld   := not v.allOnes and not v.allZeros;
               v.allOnes  := '1';
            elsif ( r.cnt = CFG_LEN_C - 1 ) then
               v.state         := DONE;
               -- let the ESC start
               v.smCfg.valid   := '1';
            end if;
            v.cnt := r.cnt + 1;

         when DONE =>
            -- do nothing

         when ADDR =>
            -- send EEPROM read address
            if ( strmTxRdy = '1' ) then
               if ( ADDR_2B_C ) then
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
               v.strmTxMst.data  := i2cHeader( I2C_RD_C, r.cnt );
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

   dbufMaps  <= r.maps;
   configReq <= configReqLoc;

   retries   <= r.retries;

   debug(31 downto 4) <= (others => '0');
   debug( 3 downto 0) <= std_logic_vector( to_unsigned( StateType'pos( r.state ), 4 ) );

end architecture rtl;
