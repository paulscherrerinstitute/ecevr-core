library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.Lan9254Pkg.all;
use work.Lan9254ESCPkg.all;
use work.Udp2BusPkg.all;
use work.EvrTxPDOPkg.all;

entity EvrTxPDO is
   generic (
      NUM_EVENT_DWORDS_G  : natural range 0 to 8  := 8;
      EVENT_MAP_G         : EventMapArray         := EVENT_MAP_IDENT_C;
      MEM_BASE_ADDR_G     : unsigned(31 downto 0) := (others => '0');
      MAX_MEM_XFERS_G     : MemXferNumType        := 0;
      TXPDO_ADDR_G        : unsigned(15 downto 0)
   );
   port (
      evrClk              : in  std_logic;
      evrRst              : in  std_logic;

      -- triggers update of the PDO
      pdoTrg              : in  std_logic;
      tsHi                : in  std_logic_vector(31 downto  0);
      tsLo                : in  std_logic_vector(31 downto  0);
      eventCode           : in  std_logic_vector( 7 downto  0);
      eventCodeVld        : in  std_logic;
      eventMapClr         : in  std_logic_vector( 7 downto  0);

      busClk              : in  std_logic;
      busRst              : in  std_logic;

      -- dbufMaps should be part of 'config' but cannot since it is
      -- an unconstrained array.
      dbufMaps            : in  MemXferArray(MAX_MEM_XFERS_G - 1 downto 0) := (others => MEM_XFER_INIT_C);
      config              : in  EvrTxPDOConfigType := EVR_TXPDO_CONFIG_INIT_C; 

      -- LAN9254 HBI bus master IF
      lanReq              : out Lan9254ReqType;
      lanRep              : in  Lan9254RepType;

      -- EVR/UDP bus master IF (for accessing the EVR data buffer)
      busReq              : out Udp2BusReqType;
      busRep              : in  Udp2BusRepType;

      -- diagnostics
      trgCnt              : out unsigned(15 downto 0)
   );
end entity EvrTxPDO;

architecture rtl of EvrTxPDO is

   type Slv32Array        is array (natural range <>) of std_logic_vector(31 downto 0);

   type EvrRegType is record
      eventCodesLst       : std_logic_vector(32*NUM_EVENT_DWORDS_G - 1 downto 0);
      eventCodes          : std_logic_vector(32*NUM_EVENT_DWORDS_G - 1 downto 0);
      tsHi                : std_logic_vector(31 downto 0);
      tsLo                : std_logic_vector(31 downto 0);
      pdoTrg              : std_logic;
   end record EvrRegType;

   constant EVR_REG_INIT_C: EvrRegType := (
      eventCodesLst       => (others => '0'),
      eventCodes          => (others => '0'),
      tsHi                => (others => '0'),
      tsLo                => (others => '0'),
      pdoTrg              => '0'
   );

   procedure mapEvent(
      constant e : in    std_logic_vector(7 downto 0);
      variable v : inout std_logic_vector(32*NUM_EVENT_DWORDS_G - 1 downto 0)
   ) is
      variable idx : natural range 0 to 255;
   begin
      idx := to_integer( unsigned( e ) );
      if ( EVENT_MAP_G'length /= 0 ) then
         idx := EVENT_MAP_G( idx );
      end if;
      v := v;
      if ( idx < 32*NUM_EVENT_DWORDS_G ) then
         v(idx) := '1';
      end if;
   end procedure mapEvent;

   type BusStateType is ( IDLE, X_TS, X_EV, X_DC_LATCH, READ_LAN, X_MEM, READ_MEM, WRITE_PDO );

   type BusRegType is record
      state               : BusStateType;
      retState            : BusStateType;
      lanReq              : Lan9254ReqType;
      busReq              : Udp2BusReqType;
      pdoDwAddr           : unsigned(11 downto 0);
      pdoTrg              : std_logic;
      count               : unsigned(3 downto 0);
      xferIdx             : natural range 0 to MAX_MEM_XFERS_G;
      trgCnt              : unsigned(15 downto 0);
   end record BusRegType;

   constant COUNT_ZERO_C  : unsigned(3 downto 0) := (others => '0');

   constant BUS_REG_INIT_C: BusRegType := (
      state               => IDLE,
      retState            => IDLE,
      lanReq              => LAN9254REQ_INIT_C,
      busReq              => UDP2BUSREQ_INIT_C,
      pdoDwAddr           => (others => '0'),
      pdoTrg              => '0',
      count               => COUNT_ZERO_C,
      xferIdx             => 0,
      trgCnt              => (others => '0')
   );

   function mkLan9254Addr(
      constant b : in unsigned;
      constant o : in unsigned := "0";
      constant l : in positive := 16
   ) return std_logic_vector is
      variable a : unsigned(l - 1 downto 0) := resize( b, l );
   begin
      a(a'left downto 2) := a(a'left downto 2) + resize( o, a'length - 2 );
      return std_logic_vector( a );
   end function mkLan9254Addr;

   function DCLatchAddr(constant n : in unsigned) return std_logic_vector is
      constant BASE_C : unsigned              := x"9B0";
   begin
      return mkLan9254Addr( BASE_C, n );
   end function DCLatchAddr;

   function swap32(
      constant s : in  SwapType;
      constant v : in  std_logic_vector
   ) return std_logic_vector is
      variable r : std_logic_vector(v'range);
   begin
      case ( s ) is
         when SWP16 =>
            for i in 0 to v'length/16 - 1 loop
               r(15 + 16*i downto 16*i) := v( 7 + 16*i downto 16*i) & v(15 + 16*i downto 8 + 16*i);
            end loop;
         when SWP32 =>
            for i in 0 to v'length/32 - 1 loop
               r(31 + 32*i downto 32*i) :=    v( 7 + 32*i downto  0 + 32*i) & v(15 + 32*i downto  8 + 32*i) 
                                           &  v(23 + 32*i downto 16 + 32*i) & v(31 + 32*i downto 24 + 32*i) ;
            end loop;
         when others =>
            r := v;
      end case;
      return r;
   end function swap32;

   procedure write32(
      variable    req : inout Lan9254ReqType;
      signal      rep : in    Lan9254RepType;
      constant    dwa : in    unsigned;
      constant    val : in    std_logic_vector(31 downto 0);
      constant    lck : in    std_logic := '0'
   ) is
      variable byteAddr : std_logic_vector(15 downto 0);
   begin
      byteAddr := std_logic_vector( resize( dwa & "00", byteAddr'length ) );
      lan9254HBIWrite( req, rep, byteAddr, val, HBI_BE_DW_C, lck );
   end procedure write32;

   procedure setDWAddr(
      variable a : inout std_logic_vector;
      constant b : in    unsigned;
      constant o : in    unsigned
   ) is
   begin
      a := std_logic_vector( resize( shift_right( b + resize( o, b'length ), 2 ), a'length ) );
   end procedure setDWAddr;

   signal rEvr            : EvrRegType := EVR_REG_INIT_C;
   signal rinEvr          : EvrRegType;

   signal pdoTrgBus       : std_logic;

   signal rBus            : BusRegType := BUS_REG_INIT_C;
   signal rinBus          : BusRegType;

   signal tsArray         : Slv32Array(1 downto 0);
   signal hasLatch        : std_logic_vector(3 downto 0);
   signal ecArray         : Slv32Array(NUM_EVENT_DWORDS_G - 1 downto 0);

begin

   assert EVENT_MAP_G'length = 0 or EVENT_MAP_G'length = 256 report "EVENT_MAP_G must have 0 or 256 elements" severity failure;

   tsArray    <= ( 0 => rEvr.tsHi,  1 => rEvr.tsLo );
   hasLatch   <= ( 0 => config.hasLatch0P, 1 => config.hasLatch0N, 2 => config.hasLatch1P, 3 => config.hasLatch1N );

   GEN_EC_MAP : for i in ecArray'range generate
      ecArray(i) <= rEvr.eventCodesLst( 31 + 32 * i downto 32 * i );
   end generate;

   P_EVR_COMB : process ( rEvr, pdoTrg, tsHi, tsLo, eventCode, eventCodeVld, eventMapClr ) is
      variable v : EvrRegType;
   begin
      v := rEvr;

      if ( eventCodeVld = '1' ) then
         if ( eventCode = eventMapClr ) then
            v.eventCodes := (others => '0');
         end if;
         mapEvent( eventCode, v.eventCodes );
      end if;

      if ( pdoTrg = '1' ) then
         v.eventCodes    := (others => '0');
         v.eventCodesLst := rEvr.eventCodes;
         v.tsHi          := tsHi;
         v.tsLo          := tsLo;
         v.pdoTrg        := not rEvr.pdoTrg;
      end if;

      rinEvr <= v;
   end process P_EVR_COMB;

   P_EVR_SEQ : process ( evrClk ) is
   begin
      if ( rising_edge( evrClk ) ) then
         if ( evrRst = '1' ) then
            rEvr <= EVR_REG_INIT_C;
         else
            rEvr <= rinEvr;
         end if;
      end if;
   end process P_EVR_SEQ;

   B_SYNC_PDO_TRG : entity work.SynchronizerBit
      port map (
         clk        => busClk,
         rst        => busRst,
         datInp(0)  => rEvr.pdoTrg,
         datOut(0)  => pdoTrgBus
      );

   P_BUS_COMB : process ( rBus,
                          pdoTrgBus,
                          busRep, lanRep,
                          tsArray,
                          ecArray,
                          hasLatch,
                          dbufMaps, config ) is
      variable v : BusRegType;
   begin
      v := rBus;

      v.retState := rBus.state;

      case ( rBus.state ) is
         when IDLE =>
            v.pdoTrg    := pdoTrgBus;
            v.pdoDwAddr := resize( shift_right( TXPDO_ADDR_G, 2 ), v.pdoDwAddr'length );
            v.count     := COUNT_ZERO_C;
            v.xferIdx   := 0;
            if ( rBus.pdoTrg /= pdoTrgBus ) then
               v.state  := X_TS;
               v.trgCnt := rBus.trgCnt + 1;
            end if;

         when X_TS =>
            if ( (config.valid and config.hasTs) /= '0' ) then
               v.state  := WRITE_PDO;
               v.count  := rBus.count + 1;
               write32( v.lanReq, lanRep, rBus.pdoDwAddr, tsArray( to_integer( rBus.count ) ) );
               -- if this is the last write we don't return here but instead
               -- proceed to copy events
               if ( rBus.count = tsArray'length - 1 ) then
                  v.retState := X_EV;
                  v.count    := COUNT_ZERO_C;
               end if;
            else
               v.state  := X_EV;
            end if;

         when X_EV =>
            if ( ( NUM_EVENT_DWORDS_G > 0 ) and ( (config.valid and config.hasEventCodes) /= '0' ) ) then
               v.state  := WRITE_PDO;
               v.count  := rBus.count + 1;
               write32( v.lanReq, lanRep, rBus.pdoDwAddr, ecArray( to_integer( rBus.count ) ) );
               -- if this is the last write we don't return here but instead
               -- proceed to the DC latch
               if ( rBus.count = NUM_EVENT_DWORDS_G - 1 ) then
                  v.retState := X_DC_LATCH;
                  v.count    := COUNT_ZERO_C;
               end if;
            else
               v.state  := X_DC_LATCH;
            end if;

         when X_DC_LATCH =>
            if ( (config.valid = '1') and (hasLatch /= "0000") ) then
               v.count       := rBus.count + 1;
               -- is this the last transfer?
               if ( rBus.count = 2*hasLatch'length - 1 ) then
                  v.state    := X_MEM;          -- set to READ_LAN if we transfer this latch register
                  v.retState := X_MEM;          -- proceed to X_MEM after the write operation
                  v.count    := COUNT_ZERO_C;   -- incremented to zero in WRITE_PDO or reset to rBus.count + 2
                                                -- if this latch is not transferred
               end if;
               if ( hasLatch( to_integer( rBus.count(rBus.count'left downto 1) ) ) = '1' ) then
                  v.state  := READ_LAN;
                  -- lock others out to make sure we get the 64 bits atomically. The lan9254 latches
                  -- all 64 bits when byte(0) is read. Note; our sequence
                  --   read lower latch word
                  --   write lower word to TXPDO
                  --   read upper latch word
                  --   write upper word to TXPDO
                  -- is OK, we just must prevent others from reading the lower word again before
                  -- we get the associated upper word.
                  lan9254HBIRead( v.lanReq, lanRep, DCLatchAddr( rBus.count ), HBI_BE_DW_C, lock => not rBus.count(0) );
               end if;
            else
               v.state  := X_MEM;
            end if;

         when X_MEM =>
            if ( (config.valid = '1') and (rBus.xferIdx < config.numMaps) ) then
               v.busReq.be    := (others => '1');
               v.busReq.rdnwr := '1';
               v.busReq.valid := '1';
               v.state        := READ_MEM;
               if ( rBus.count = 0 ) then
                  if ( dbufMaps( rBus.xferIdx ).num = 0 ) then
                     -- skip empty entry
                     v.xferIdx      := rBus.xferIdx + 1;
                     v.state        := X_MEM;
                     v.busReq.valid := '0';
                  else
                     setDWAddr( v.busReq.dwaddr, MEM_BASE_ADDR_G, dbufMaps(rBus.xferIdx).off );
                  end if;
               else
                  v.busReq.dwAddr := std_logic_vector( unsigned(rBus.busReq.dwAddr) + 1 );
               end if;
            else
               v.state := IDLE;
            end if;

         when READ_MEM =>
            -- don't change the return state in 'READ_MEM' state
            v.retState := rBus.retState;
            if ( busRep.valid = '1' ) then
               v.busReq.valid := '0';
               v.state        := WRITE_PDO;
               v.count        := rBus.count + 1;
               write32( v.lanReq, lanRep, rBus.pdoDwAddr, swap32( dbufMaps(rBus.xferIdx).swp, busRep.rdata ) );
               if ( rBus.count = dbufMaps( rBus.xferIdx ).num - 1 ) then
                  v.count   := COUNT_ZERO_C;
                  v.xferIdx := rBus.xferIdx + 1;
               end if;
            end if;

         when READ_LAN =>
            -- don't change the return state in 'READ_LAN' state
            v.retState := rBus.retState;
            if ( lanRep.valid = '1' ) then
               v.lanReq.valid := '0';
               v.state        := WRITE_PDO;
               write32( v.lanReq, lanRep, rBus.pdoDwAddr, lanRep.rdata, v.lanReq.lock );
            end if;

         when WRITE_PDO =>
            -- don't change the return state in 'WRITE_PDO' state
            v.retState := rBus.retState;
            if ( lanRep.valid = '1' ) then
               v.lanReq.valid := '0';
               v.state        := rBus.retState;
               v.pdoDWAddr    := rBus.pdoDWAddr + 1;
            end if;
      end case;

      rinBus <= v;
   end process P_BUS_COMB;

   P_BUS_SEQ : process ( busClk ) is
   begin
      if ( rising_edge( busClk ) ) then
         if ( busRst = '1' ) then
            rBus <= BUS_REG_INIT_C;
         else
            rBus <= rinBus;
         end if;
      end if;
   end process P_BUS_SEQ;

   lanReq <= rBus.lanReq;
   busReq <= rBus.busReq;

   trgCnt <= rBus.trgCnt;

end architecture rtl;
