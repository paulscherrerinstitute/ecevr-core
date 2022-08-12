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
   end record FlashFileType;

   type FlashFileArray is array (natural range <>) of FlashFileType;

   constant FLASH_FILE_ARRAY_EMPTY_C : FlashFileArray(0 downto 1) := (
      others => ( id      => (others => '0'),
                  begAddr => (others => '0'),
                  endAddr => (others => '0')
                )
   );

   function toFoEFileNameMap(constant a : FlashFileArray) return FoEFileNameArray;

end package FoE2SpiPkg;

package body FoE2SpiPkg is

   function toFoEFileNameMap(
      constant a : FlashFileArray
   ) return FoEFileNameArray is
      variable v : FoEFileNameArray(a'range);
   begin
      for i in a'range loop
         v(i) := a(i).id;
      end loop;
      return v;
   end function toFoEFileNameMap;

end package body FoE2SpiPkg;
