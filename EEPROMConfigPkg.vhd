library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.ESCBasicTypesPkg.all;
use work.Lan9254Pkg.all;
use work.Lan9254ESCPkg.all;
use work.IPAddrConfigPkg.all;
use work.EvrTxPDOPkg.all;
use work.Evr320ConfigPkg.all;

package EEPROMConfigPkg is

   constant EEPROM_LAYOUT_VERSION_C : std_logic_vector(7 downto 0) := x"01";

   type EEPROMConfigReqType is record
      version          : std_logic_vector(7 downto 0);
      net              : IPAddrConfigReqType;
      esc              : ESCConfigReqType;
      evr320NumPG      : std_logic_vector(7 downto 0);
      evr320           : Evr320ConfigReqType;
      txPDO            : EvrTxPDOConfigType;
   end record EEPROMConfigReqType;

   constant EEPROM_CONFIG_REQ_INIT_C : EEPROMConfigReqType := (
      version         => EEPROM_LAYOUT_VERSION_C,
      net             => makeIPAddrConfigReq,
      esc             => ESC_CONFIG_REQ_INIT_C,
      evr320NumPG     => std_logic_vector(to_unsigned( EVR320_CONFIG_REQ_INIT_C.pulseGenParams'length, 8 ) ),
      evr320          => EVR320_CONFIG_REQ_INIT_C,
      txPDO           => EVR_TXPDO_CONFIG_INIT_C
   );

   type EEPROMConfigAckType is record
      net              : IPAddrConfigAckType;
      esc              : ESCConfigAckType;
      evr320           : Evr320ConfigAckType;
   end record EEPROMConfigAckType;

   constant EEPROM_CONFIG_ACK_INIT_C : EEPROMConfigAckType := (
      net              => IP_ADDR_CONFIG_ACK_INIT_C,
      esc              => ESC_CONFIG_ACK_INIT_C,
      evr320           => EVR320_CONFIG_ACK_INIT_C
   );

   constant EEPROM_CONFIG_ACK_ASSERT_C : EEPROMConfigAckType := (
      net              => IP_ADDR_CONFIG_ACK_ASSERT_C,
      esc              => ESC_CONFIG_ACK_ASSERT_C,
      evr320           => EVR320_CONFIG_ACK_ASSERT_C
   );

   type EEPROMWriteWordReqType is record
      waddr            : unsigned        (14 downto 0);
      wdata            : std_logic_vector(15 downto 0);
      valid            : std_logic;
   end record EEPROMWriteWordReqtype;

   constant EEPROM_WRITE_WORD_REQ_INIT_C : EEPROMWriteWordReqType := (
      waddr            => (others => '0'),
      wdata            => (others => '0'),
      valid            => '0'
   );

   type EEPROMWriteWordAckType is record
      ack              : std_logic;
   end record EEPROMWriteWordAckType;

   constant EEPROM_WRITE_WORD_ACK_INIT_C : EEPROMWriteWordAckType := (
      ack              => '0'
   );

   constant EEPROM_WRITE_WORD_ACK_ASSERT_C : EEPROMWriteWordAckType := (
      ack              => '1'
   );

   function toSlv08Array(constant x : in EEPROMConfigReqType)
      return Slv08Array;

   function toEEPROMConfigReqType(constant x : in Slv08Array)
      return EEPROMConfigReqType;

end package EEPROMConfigPkg;

package body EEPROMConfigPkg is

   function toSlv08Array(constant x : in EEPROMConfigReqType)
      return Slv08Array is
      constant c : Slv08Array := (
         EEPROM_LAYOUT_VERSION_C  &
         toSlv08Array( x.net    ) &
         x.evr320NumPG            &
         toSlv08Array( x.evr320 ) &
         toSlv08Array( x.esc    ) &
         toSlv08Array( x.txPDO  )
      );
   begin
      return c;
   end function toSlv08Array;

   function toEEPROMConfigReqType(constant x : in Slv08Array)
      return EEPROMConfigReqType is
      -- dummies that should be optimized away...
      constant l0 : natural     := x'low;
      constant l1 : natural     := l0 + 1;
      constant l2 : natural     := l1 + slv08ArrayLen( toSlv08Array(EEPROM_CONFIG_REQ_INIT_C.net)    );
      constant l3 : natural     := l2 + 1;
      constant l4 : natural     := l3 + slv08ArrayLen( toSlv08Array(EEPROM_CONFIG_REQ_INIT_C.evr320) );
      constant l5 : natural     := l4 + slv08ArrayLen( toSlv08Array(EEPROM_CONFIG_REQ_INIT_C.esc)    );
      constant c : EEPROMConfigReqType := (
         version     => x(l0),
         net         => toIPAddrConfigReqType( x(l1 to l2 - 1) ),
         evr320NumPG => x(l2),
         evr320      => toEvr320ConfigReqType( x(l3 to l4 - 1) ),
         esc         => toESCConfigReqType   ( x(l4 to l5 - 1) ),
         txPDO       => toEvrTxPDOConfigType ( x(l5 to x'high) )
      );
   begin
      return c;
   end function toEEPROMConfigReqType;

end package body EEPROMConfigPkg;
