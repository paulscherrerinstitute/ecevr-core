library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.ESCFoEPkg.all;

package FoE2SpiPkg is

   subtype A24Type is unsigned(23 downto 0);

   type FlashFileType is record
      id        : std_logic_vector(7 downto 0);
      -- start address -- must be aligned to erase block size
      begAddr   : A24Type;
      -- last address; endAddr + 1 must be aligned to erase block size
      endAddr   : A24Type;
      flags     : std_logic_vector(0 downto 0);
   end record FlashFileType;

   type FlashFileArray is array (natural range <>) of FlashFileType;

   constant FLASH_FILE_ARRAY_EMPTY_C : FlashFileArray(0 downto 1) := (
      others => ( id      => (others => '0'),
                  begAddr => (others => '0'),
                  endAddr => (others => '0'),
                  flags   => (others => '0')
                )
   );

   constant FLASH_FILE_FLAG_WP_C    : std_logic_vector(0 downto 0) := "1";
   constant FLASH_FILE_FLAGS_NONE_C : std_logic_vector(0 downto 0) := (others => '0');

   function toFoEFileMap(constant a : in FlashFileArray) return FoEFileArray;

   function isFoEFileWriteProtected(constant x : in FlashFileType) return boolean;

   subtype Foe2SpiErrorType  is std_logic_vector(3 downto 0);

   constant FOE2SPI_ERR_NONE_C              : Foe2SpiErrorType := "0000";
   -- attempt to write beyond configured file size
   constant FOE2SPI_ERR_NOSPACE_C           : Foe2SpiErrorType := "0001";
   -- internal error (csel deasserted during clock transition)
   constant FOE2SPI_ERR_INTERNAL_C          : Foe2SpiErrorType := "0010";
   -- erase failure (readback detected non-blank data)
   constant FOE2SPI_ERR_NOT_BLANK_C         : Foe2SpiErrorType := "0011";
   -- readback/verification failure
   constant FOE2SPI_ERR_VERIFY_C            : Foe2SpiErrorType := "0100";


end package FoE2SpiPkg;

package body FoE2SpiPkg is

   function toFoEFileMap(
      constant a : in FlashFileArray
   ) return FoEFileArray is
      variable v : FoEFileArray(a'range);
   begin
      for i in a'range loop
         v(i).id := a(i).id;
         v(i).wp := isFoEFileWriteProtected( a(i) );
      end loop;
      return v;
   end function toFoEFileMap;

   function isFoEFileWriteProtected(constant x : in FlashFileType)
   return boolean is
      constant z : std_logic_vector(x.flags'range) := (others => '0');
   begin
      return ( (x.flags and FLASH_FILE_FLAG_WP_C) /=  z );
   end function isFoEFileWriteProtected;

end package body FoE2SpiPkg;
