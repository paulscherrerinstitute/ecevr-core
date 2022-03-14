library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.ESCBasicTypesPkg.all;

package EvrTxPDOPkg is

   type EventMapArray is array (natural range <>) of natural range 0 to 255;

   constant EVENT_MAP_IDENT_C : EventMapArray(-1 downto 0) := (others => 0);

   type SwapType is ( NOSWP, SWP16, SWP32 );

   type MemXferType is record
      num       : unsigned( 9 downto 0); -- max. 2k in data buffer
      swp       : SwapType;
      off       : unsigned(15 downto 0);
   end record MemXferType;

   constant MEM_XFER_INIT_C : MemXferType := (
      num       => (others => '0'),
      swp       => NOSWP,
      off       => (others => '0')
   );

   subtype  MemXferNumType is integer range 0 to 255;

   type MemXferArray is array (MemXferNumType range <>) of MemXferType;

   -- NOTE: empty range 0 downto 1
   constant MEM_XFER_NULL_C : MemXferArray(0 downto 1) := (others => MEM_XFER_INIT_C);

   type EvrTxPDOConfigType is record
      hasTs               : std_logic;
      hasEventCodes       : std_logic;
      hasLatch0P          : std_logic;
      hasLatch0N          : std_logic;
      hasLatch1P          : std_logic;
      hasLatch1N          : std_logic;
      numMaps             : MemXferNumType;
      valid               : std_logic;
   end record EvrTxPDOConfigType;

   constant EVR_TXPDO_CONFIG_INIT_C : EvrTxPDOConfigType := (
      hasTs               => '1',
      hasEventCodes       => '1',
      hasLatch0P          => '1',
      hasLatch0N          => '1',
      hasLatch1P          => '1',
      hasLatch1N          => '1',
      numMaps             =>  0,
      valid               => '0'
   );

   function toSlv08Array(constant x : in MemXferType)
      return Slv08Array;

   function toMemXferType(constant x : in Slv08Array)
      return MemXferType;

   function toSlv08Array(constant x : in EvrTxPDOConfigType)
      return Slv08Array;

   function toEvrTxPDOConfigType(constant x : in Slv08Array)
      return EvrTxPDOConfigType;

   function toString(constant x : in SwapType)
      return string;

end package EvrTxPDOPkg;

package body EvrTxPDOPkg is

   function toSlv08Array(constant x : in EvrTxPDOConfigType)
      return Slv08Array is
      constant c : Slv08Array := (
         0 => "00" & x.hasLatch1N & x.hasLatch1P
              & x.hasLatch0N & x.hasLatch0P & x.hasEventCodes & x.hasTs,
         1 => std_logic_vector( to_unsigned( x.numMaps, 8 ) )
      );
   begin
      return c;
   end function toSlv08Array;

   function toEvrTxPDOConfigType(constant x : in Slv08Array)
      return EvrTxPDOConfigType is
      constant c : EvrTxPDOConfigType := (
         hasTs               => x(0+x'low)(0),
         hasEventCodes       => x(0+x'low)(1),
         hasLatch0P          => x(0+x'low)(2),
         hasLatch0N          => x(0+x'low)(3),
         hasLatch1P          => x(0+x'low)(4),
         hasLatch1N          => x(0+x'low)(5),
         numMaps             => to_integer( unsigned( x(1+x'low) ) ),
         valid               => '0'
      );
   begin
      return c;
   end function toevrtxpdoconfigtype;

   function toslv(constant x : in SwapType)
      return std_logic_vector is
   begin
      return std_logic_vector( to_unsigned( SwapType'pos(x), 2 ) );
   end function toSlv;

   function toSwapType(constant x : in std_logic_vector)
      return SwapType is
   begin
      return SwapType'val( to_integer( unsigned( x ) ) );
   end function toSwapType;

   function toString(constant x : in SwapType)
      return string is
   begin
      case ( x ) is
         when NOSWP => return "NOSWP";
         when SWP16 => return "SWP16";
         when SWP32 => return "SWP32";
      end case;
   end function toString;

   function toSlv08Array(constant x : in MemXferType)
      return Slv08Array is
      constant c : Slv08Array := (
         0  =>  std_logic_vector(x.num( 7 downto 0)),
         1  =>    "00" & toSlv( x.swp )
                & "00" & std_logic_vector( x.num(9 downto 8) ),
         2  =>  std_logic_vector(x.off( 7 downto 0)),
         3  =>  std_logic_vector(x.off(15 downto 8))
      );
   begin
      return c;
   end function toSlv08Array;

   function toMemXferType(constant x : in Slv08Array)
      return MemXferType is
      variable v : MemXferType;
   begin
      v.num := unsigned  ( x(1+x'low)(1 downto 0) ) & unsigned( x(0+x'low) );
      if ( (v.num = 0) or (signed(v.num) = -1) ) then
         -- all ones: assume empty EEPROM
         return MEM_XFER_INIT_C;
      else
         v.swp := toSwapType( x(1+x'low)(5 downto 4) );
         v.off := unsigned  ( x(3+x'low)             ) & unsigned( x(2+x'low) );
      end if;
      return v;
   end function toMemXferType;


end package body EvrTxPDOPkg;
