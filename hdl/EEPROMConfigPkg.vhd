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

   constant EEPROM_LAYOUT_VERSION_C : std_logic_vector(7 downto 0) := x"02";

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

   function toSlv08Array(constant x : in EEPROMConfigReqType)
      return Slv08Array;

   function toEEPROMConfigReqType(constant x : in Slv08Array)
      return EEPROMConfigReqType;

   function toSlv08Array(constant x : in std_logic_vector)
      return Slv08Array;

   function toSlv(constant x : Slv08Array)
      return std_logic_vector;

end package EEPROMConfigPkg;

package body EEPROMConfigPkg is

   function toSlv08Array(constant x : in EEPROMConfigReqType)
      return Slv08Array is
      constant c : Slv08Array := (
         EEPROM_LAYOUT_VERSION_C    &
         toSlv08Array( x.net      ) &
         x.evr320NumPG              &
         toSlv08Array( x.evr320   ) &
         toSlv08Array( x.esc      ) &
         toSlv08Array( x.txPDO    )
      );
   begin
      return c;
   end function toSlv08Array;

   function toEEPROMConfigReqType(constant x : in Slv08Array)
      return EEPROMConfigReqType is
      -- dummies that should be optimized away...
      constant l0 : natural     := x'low;
      constant l1 : natural     := l0 + 1;
      constant l2 : natural     := l1 + slv08ArrayLen( toSlv08Array(EEPROM_CONFIG_REQ_INIT_C.net     ) );
      constant l3 : natural     := l2 + 1;
      constant l4 : natural     := l3 + slv08ArrayLen( toSlv08Array(EEPROM_CONFIG_REQ_INIT_C.evr320  ) );
      constant l5 : natural     := l4 + slv08ArrayLen( toSlv08Array(EEPROM_CONFIG_REQ_INIT_C.esc     ) );
      constant l6 : natural     := l5 + slv08ArrayLen( toSlv08Array(EEPROM_CONFIG_REQ_INIT_C.txPDO   ) );
      constant c : EEPROMConfigReqType := (
         version     => x(l0),
         net         => toIPAddrConfigReqType( x(l1 to l2 - 1) ),
         evr320NumPG => x(l2),
         evr320      => toEvr320ConfigReqType( x(l3 to l4 - 1) ),
         esc         => toESCConfigReqType   ( x(l4 to l5 - 1) ),
         txPDO       => toEvrTxPDOConfigType ( x(l5 to l6 - 1) )
      );
   begin
      return c;
   end function toEEPROMConfigReqType;

   function toSlv08Array(constant x : in std_logic_vector)
      return Slv08Array
   is
      constant PAD_C : natural := (8 - (x'length mod 8)) mod 8;

      variable v : std_logic_vector(x'length + PAD_C - 1 downto 0);
      variable r : Slv08Array(0 to v'length/8 - 1);
   begin
      v := (others => '0');
      v(x'length - 1 downto 0) := x;
      for i in r'range loop
         r(i) := x(8*i + 7 + x'right downto 8*i + x'right);
      end loop;
      return r;
   end function toSlv08Array;

   function toSlv(constant x : Slv08Array)
      return std_logic_vector
   is
      variable r : std_logic_vector(8*x'length - 1 downto 0);
   begin
      for i in 0 to x'length - 1 loop
         r(8*i + 7 downto 8*i) := x(i + x'low);
      end loop;
      return r;
   end function toSlv;

end package body EEPROMConfigPkg;
