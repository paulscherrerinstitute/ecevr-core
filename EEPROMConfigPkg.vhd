library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.ESCBasicTypesPkg.all;
use work.Lan9254Pkg.all;
use work.Lan9254ESCPkg.all;
use work.IPAddrConfigPkg.all;
use work.EvrTxPDOPkg.all;

package EEPROMConfigPkg is

   type EEPROMConfigReqType is record
      net              : IPAddrConfigReqType;
      esc              : ESCConfigReqType;
      txPDO            : EvrTxPDOConfigType;
   end record EEPROMConfigReqType;

   constant EEPROM_CONFIG_REQ_INIT_C : EEPROMConfigReqType := (
      net             => makeIPAddrConfigReq,
      esc             => ESC_CONFIG_REQ_INIT_C,
      txPDO           => EVR_TXPDO_CONFIG_INIT_C
   );

   type EEPROMConfigAckType is record
      net              : IPAddrConfigAckType;
      esc              : ESCConfigAckType;
   end record EEPROMConfigAckType;

   constant EEPROM_CONFIG_ACK_INIT_C : EEPROMConfigAckType := (
      net              => IP_ADDR_CONFIG_ACK_INIT_C,
      esc              => ESC_CONFIG_ACK_INIT_C
   );

   constant EEPROM_CONFIG_ACK_ASSERT_C : EEPROMConfigAckType := (
      net              => IP_ADDR_CONFIG_ACK_ASSERT_C,
      esc              => ESC_CONFIG_ACK_ASSERT_C
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
         toSlv08Array( x.net )   &
         toSlv08Array( x.esc )   &
         toSlv08Array( x.txPDO )
      );
   begin
      return c;
   end function toSlv08Array;

   function toEEPROMConfigReqType(constant x : in Slv08Array)
      return EEPROMConfigReqType is
      -- dummies that should be optimized away...
      constant l0 : natural     := slv08ArrayLen( toSlv08Array(EEPROM_CONFIG_REQ_INIT_C.net) );
      constant l1 : natural     := l0 + slv08ArrayLen( toSlv08Array(EEPROM_CONFIG_REQ_INIT_C.esc) );
      constant c : EEPROMConfigReqType := (
         net   => toIPAddrConfigReqType( x( 0 to l0 - 1) ),
         esc   => toESCConfigReqType   ( x(l0 to l1 - 1) ),
         txPDO => toEvrTxPDOConfigType ( x(l1 to x'high) )
      );
   begin
      return c;
   end function toEEPROMConfigReqType;

end package body EEPROMConfigPkg;
