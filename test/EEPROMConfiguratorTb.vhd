library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.ESCBasicTypesPkg.all;
use     work.Lan9254Pkg.all;
use     work.Lan9254ESCPkg.all;
use     work.IPAddrConfigPkg.all;
use     work.EEPROMConfigPkg.all;
use     work.EvrTxPDOPkg.all;
use     work.EEPROMContentPkg.all;
use     work.Evr320ConfigPkg.all;

entity EEPROMConfiguratorTb is
   generic( EMUL_ACTIVE_G : std_logic := '0' );
end entity EEPROMConfiguratorTb;

architecture sim of EEPROMConfiguratorTb is

   constant SIZE_BYTES_C         : natural   := 2048;
   constant MAX_TXPDO_MAPS_C     : natural   := 16;

   constant DC_TARGET_EXP_C      : std_logic_vector(31 downto 0) := x"0EC000ab";

   signal clk                    : std_logic := '0';
   signal rst                    : std_logic := '1';

   signal sda                    : std_logic;
   signal scl                    : std_logic;
   signal scl_m_o                : std_logic;
   signal scl_m_t                : std_logic;
   signal sda_m_o                : std_logic;
   signal sda_m_t                : std_logic;
   signal scl_s_o                : std_logic := '1';
   signal sda_s_o                : std_logic := '1';

   signal run                    : boolean := true;

   signal ack                    : EEPROMConfigAckType := EEPROM_CONFIG_ACK_ASSERT_C;
   signal cfg                    : EEPROMConfigReqType;

   signal dbufMaps               : MemXferArray(MAX_TXPDO_MAPS_C - 1 downto 0);

   function toSlv(x : in Slv08Array) return std_logic_vector is
      variable v : std_logic_vector(8*x'length - 1 downto 0);
   begin
      for i in 0 to x'length - 1 loop
         v(8*i+7 downto 8*i) := x(x'low + i);
      end loop;
      return v;
   end function toSlv;

   constant EEPROM_INIT_0_C : Slv08Array(SIZE_BYTES_C - 1 downto 0) := (

      128    => x"51",
      129    => x"00",
      130    => std_logic_vector( to_unsigned( (160 - 128 - 4) / 2, 8 ) ),
      131    => x"00",
      132    => x"80",
      133    => x"10",
      134    => x"01",
      135    => x"00",

      160    => x"50",
      161    => x"00",
      162    => std_logic_vector( to_unsigned( (170 - 160 - 4) / 2, 8 ) ),
      163    => x"00",
      164    => x"00",
      165    => x"aa",
      166    => x"21",
      167    => x"43",

      170    => x"31", -- sync-manager
      171    => x"00",
      172    => std_logic_vector( to_unsigned( (256 - 170 - 2*4)/2, 8) ),
      173    => x"00",

      174 + 2*8 + 2 => x"04", -- SM2 length
      174 + 2*8 + 3 => x"00",

      174 + 3*8 + 2 => x"88", -- SM3 length
      174 + 3*8 + 3 => x"00",


      252    => x"01", -- category header
      253    => x"00", --
      254    => x"20", -- size (words)
      255    => x"00", --

      256    => x"56", -- mac addr
      257    => x"01",
      258    => x"02",
      259    => x"03",
      260    => x"04",
      261    => x"05",

      262    => x"0a", -- ip addr
      263    => x"0b",
      264    => x"0c",
      265    => x"0d",

      266    => x"40", -- udp port
      267    => x"50",

      268    => x"11", -- txPDO elements
      269    => x"00", -- ignored

      270    => x"04", -- txPDO mapping 0
      271    => x"20",
      272    => x"ef",
      273    => x"be",

      274    => x"00", -- txPDO mapping 1
      275    => x"01",
      276    => x"fe",
      277    => x"ca",
      others => x"FF"
   );

   constant EEPROM_INIT_1_C : Slv08Array(SIZE_BYTES_C - 1 downto 0) := (
      16#00000000# => x"91",
      16#00000001# => x"02",
      16#00000002# => x"01",
      16#00000003# => x"44",
      16#00000004# => x"00",
      16#00000005# => x"00",
      16#00000006# => x"00",
      16#00000007# => x"00",
      16#00000008# => x"00",
      16#00000009# => x"00",
      16#0000000a# => x"00",
      16#0000000b# => x"40",
      16#0000000c# => x"00",
      16#0000000d# => x"00",
      16#0000000e# => x"2b",
      16#0000000f# => x"00",
      16#00000010# => x"37",
      16#00000011# => x"13",
      16#00000012# => x"00",
      16#00000013# => x"00",
      16#00000014# => x"d2",
      16#00000015# => x"04",
      16#00000016# => x"00",
      16#00000017# => x"00",
      16#00000018# => x"00",
      16#00000019# => x"00",
      16#0000001a# => x"00",
      16#0000001b# => x"00",
      16#0000001c# => x"00",
      16#0000001d# => x"00",
      16#0000001e# => x"00",
      16#0000001f# => x"00",
      16#00000020# => x"00",
      16#00000021# => x"00",
      16#00000022# => x"00",
      16#00000023# => x"00",
      16#00000024# => x"00",
      16#00000025# => x"00",
      16#00000026# => x"00",
      16#00000027# => x"00",
      16#00000028# => x"00",
      16#00000029# => x"10",
      16#0000002a# => x"80",
      16#0000002b# => x"00",
      16#0000002c# => x"80",
      16#0000002d# => x"10",
      16#0000002e# => x"80",
      16#0000002f# => x"00",
      16#00000030# => x"00",
      16#00000031# => x"10",
      16#00000032# => x"30",
      16#00000033# => x"00",
      16#00000034# => x"80",
      16#00000035# => x"10",
      16#00000036# => x"30",
      16#00000037# => x"00",
      16#00000038# => x"22",
      16#00000039# => x"00",
      16#0000003a# => x"00",
      16#0000003b# => x"00",
      16#0000003c# => x"00",
      16#0000003d# => x"00",
      16#0000003e# => x"00",
      16#0000003f# => x"00",
      16#00000040# => x"00",
      16#00000041# => x"00",
      16#00000042# => x"00",
      16#00000043# => x"00",
      16#00000044# => x"00",
      16#00000045# => x"00",
      16#00000046# => x"00",
      16#00000047# => x"00",
      16#00000048# => x"00",
      16#00000049# => x"00",
      16#0000004a# => x"00",
      16#0000004b# => x"00",
      16#0000004c# => x"00",
      16#0000004d# => x"00",
      16#0000004e# => x"00",
      16#0000004f# => x"00",
      16#00000050# => x"00",
      16#00000051# => x"00",
      16#00000052# => x"00",
      16#00000053# => x"00",
      16#00000054# => x"00",
      16#00000055# => x"00",
      16#00000056# => x"00",
      16#00000057# => x"00",
      16#00000058# => x"00",
      16#00000059# => x"00",
      16#0000005a# => x"00",
      16#0000005b# => x"00",
      16#0000005c# => x"00",
      16#0000005d# => x"00",
      16#0000005e# => x"00",
      16#0000005f# => x"00",
      16#00000060# => x"00",
      16#00000061# => x"00",
      16#00000062# => x"00",
      16#00000063# => x"00",
      16#00000064# => x"00",
      16#00000065# => x"00",
      16#00000066# => x"00",
      16#00000067# => x"00",
      16#00000068# => x"00",
      16#00000069# => x"00",
      16#0000006a# => x"00",
      16#0000006b# => x"00",
      16#0000006c# => x"00",
      16#0000006d# => x"00",
      16#0000006e# => x"00",
      16#0000006f# => x"00",
      16#00000070# => x"00",
      16#00000071# => x"00",
      16#00000072# => x"00",
      16#00000073# => x"00",
      16#00000074# => x"00",
      16#00000075# => x"00",
      16#00000076# => x"00",
      16#00000077# => x"00",
      16#00000078# => x"00",
      16#00000079# => x"00",
      16#0000007a# => x"00",
      16#0000007b# => x"00",
      16#0000007c# => x"0f",
      16#0000007d# => x"00",
      16#0000007e# => x"01",
      16#0000007f# => x"00",
      16#00000080# => x"01",
      16#00000081# => x"00",
      16#00000082# => x"06",
      16#00000083# => x"00",
      16#00000084# => x"48",
      16#00000085# => x"02",
      16#00000086# => x"03",
      16#00000087# => x"04",
      16#00000088# => x"05",
      16#00000089# => x"66",
      16#0000008a# => x"00",
      16#0000008b# => x"00",
      16#0000008c# => x"00",
      16#0000008d# => x"00",
      16#0000008e# => x"00",
      16#0000008f# => x"00",
      16#00000090# => x"0a",
      16#00000091# => x"00",
      16#00000092# => x"1a",
      16#00000093# => x"00",
      16#00000094# => x"07",
      16#00000095# => x"0b",
      16#00000096# => x"6c",
      16#00000097# => x"61",
      16#00000098# => x"6e",
      16#00000099# => x"39",
      16#0000009a# => x"32",
      16#0000009b# => x"35",
      16#0000009c# => x"32",
      16#0000009d# => x"5f",
      16#0000009e# => x"73",
      16#0000009f# => x"70",
      16#000000a0# => x"69",
      16#000000a1# => x"07",
      16#000000a2# => x"6c",
      16#000000a3# => x"61",
      16#000000a4# => x"6e",
      16#000000a5# => x"39",
      16#000000a6# => x"32",
      16#000000a7# => x"35",
      16#000000a8# => x"32",
      16#000000a9# => x"04",
      16#000000aa# => x"4c",
      16#000000ab# => x"45",
      16#000000ac# => x"44",
      16#000000ad# => x"73",
      16#000000ae# => x"04",
      16#000000af# => x"4c",
      16#000000b0# => x"45",
      16#000000b1# => x"44",
      16#000000b2# => x"30",
      16#000000b3# => x"04",
      16#000000b4# => x"4c",
      16#000000b5# => x"45",
      16#000000b6# => x"44",
      16#000000b7# => x"31",
      16#000000b8# => x"07",
      16#000000b9# => x"42",
      16#000000ba# => x"75",
      16#000000bb# => x"74",
      16#000000bc# => x"74",
      16#000000bd# => x"6f",
      16#000000be# => x"6e",
      16#000000bf# => x"73",
      16#000000c0# => x"07",
      16#000000c1# => x"42",
      16#000000c2# => x"75",
      16#000000c3# => x"74",
      16#000000c4# => x"74",
      16#000000c5# => x"6f",
      16#000000c6# => x"6e",
      16#000000c7# => x"31",
      16#000000c8# => x"1e",
      16#000000c9# => x"00",
      16#000000ca# => x"10",
      16#000000cb# => x"00",
      16#000000cc# => x"01",
      16#000000cd# => x"00",
      16#000000ce# => x"00",
      16#000000cf# => x"02",
      16#000000d0# => x"00",
      16#000000d1# => x"00",
      16#000000d2# => x"00",
      16#000000d3# => x"01",
      16#000000d4# => x"00",
      16#000000d5# => x"00",
      16#000000d6# => x"00",
      16#000000d7# => x"00",
      16#000000d8# => x"00",
      16#000000d9# => x"00",
      16#000000da# => x"01",
      16#000000db# => x"00",
      16#000000dc# => x"11",
      16#000000dd# => x"00",
      16#000000de# => x"00",
      16#000000df# => x"00",
      16#000000e0# => x"00",
      16#000000e1# => x"00",
      16#000000e2# => x"00",
      16#000000e3# => x"00",
      16#000000e4# => x"00",
      16#000000e5# => x"00",
      16#000000e6# => x"00",
      16#000000e7# => x"00",
      16#000000e8# => x"00",
      16#000000e9# => x"00",
      16#000000ea# => x"00",
      16#000000eb# => x"00",
      16#000000ec# => x"28",
      16#000000ed# => x"00",
      16#000000ee# => x"01",
      16#000000ef# => x"00",
      16#000000f0# => x"01",
      16#000000f1# => x"02",
      16#000000f2# => x"29",
      16#000000f3# => x"00",
      16#000000f4# => x"10",
      16#000000f5# => x"00",
      16#000000f6# => x"00",
      16#000000f7# => x"10",
      16#000000f8# => x"30",
      16#000000f9# => x"00",
      16#000000fa# => x"26",
      16#000000fb# => x"00",
      16#000000fc# => x"01",
      16#000000fd# => x"01",
      16#000000fe# => x"80",
      16#000000ff# => x"10",
      16#00000100# => x"30",
      16#00000101# => x"00",
      16#00000102# => x"22",
      16#00000103# => x"00",
      16#00000104# => x"01",
      16#00000105# => x"02",
      16#00000106# => x"00",
      16#00000107# => x"11",
      16#00000108# => x"03",
      16#00000109# => x"00",
      16#0000010a# => x"24",
      16#0000010b# => x"00",
      16#0000010c# => x"01",
      16#0000010d# => x"03",
      16#0000010e# => x"80",
      16#0000010f# => x"11",
      16#00000110# => x"04",
      16#00000111# => x"00",
      16#00000112# => x"20",
      16#00000113# => x"00",
      16#00000114# => x"01",
      16#00000115# => x"04",
      16#00000116# => x"32",
      16#00000117# => x"00",
      16#00000118# => x"08",
      16#00000119# => x"00",
      16#0000011a# => x"00",
      16#0000011b# => x"1a",
      16#0000011c# => x"01",
      16#0000011d# => x"03",
      16#0000011e# => x"00",
      16#0000011f# => x"06",
      16#00000120# => x"00",
      16#00000121# => x"00",
      16#00000122# => x"00",
      16#00000123# => x"60",
      16#00000124# => x"01",
      16#00000125# => x"07",
      16#00000126# => x"01",
      16#00000127# => x"20",
      16#00000128# => x"00",
      16#00000129# => x"00",
      16#0000012a# => x"33",
      16#0000012b# => x"00",
      16#0000012c# => x"0c",
      16#0000012d# => x"00",
      16#0000012e# => x"00",
      16#0000012f# => x"16",
      16#00000130# => x"02",
      16#00000131# => x"02",
      16#00000132# => x"00",
      16#00000133# => x"03",
      16#00000134# => x"00",
      16#00000135# => x"00",
      16#00000136# => x"00",
      16#00000137# => x"70",
      16#00000138# => x"01",
      16#00000139# => x"04",
      16#0000013a# => x"01",
      16#0000013b# => x"08",
      16#0000013c# => x"00",
      16#0000013d# => x"00",
      16#0000013e# => x"00",
      16#0000013f# => x"70",
      16#00000140# => x"02",
      16#00000141# => x"05",
      16#00000142# => x"01",
      16#00000143# => x"08",
      16#00000144# => x"00",
      16#00000145# => x"00",
      16#00000146# => x"ff",
      16#00000147# => x"ff",
      others    => (others => '1')
   );

   constant EEPROM_INIT_2_C : Slv08Array(SIZE_BYTES_C - 1 downto 0) := (
      0 => x"91",
      1 => x"02",
      2 => x"01",
      3 => x"44",
      4 => x"00",
      5 => x"00",
      6 => x"00",
      7 => x"00",
      8 => x"00",
      9 => x"00",
      10 => x"00",
      11 => x"40",
      12 => x"00",
      13 => x"00",
      14 => x"2b",
      15 => x"00",
      16 => x"49",
      17 => x"53",
      18 => x"50",
      19 => x"00",
      20 => x"01",
      21 => x"00",
      22 => x"00",
      23 => x"00",
      24 => x"01",
      25 => x"00",
      26 => x"00",
      27 => x"00",
      28 => x"00",
      29 => x"00",
      30 => x"00",
      31 => x"00",
      32 => x"00",
      33 => x"00",
      34 => x"00",
      35 => x"00",
      36 => x"00",
      37 => x"00",
      38 => x"00",
      39 => x"00",
      40 => x"00",
      41 => x"00",
      42 => x"00",
      43 => x"00",
      44 => x"00",
      45 => x"00",
      46 => x"00",
      47 => x"00",
      48 => x"00",
      49 => x"10",
      50 => x"50",
      51 => x"00",
      52 => x"80",
      53 => x"10",
      54 => x"50",
      55 => x"00",
      56 => x"02",
      57 => x"00",
      58 => x"00",
      59 => x"00",
      60 => x"00",
      61 => x"00",
      62 => x"00",
      63 => x"00",
      64 => x"00",
      65 => x"00",
      66 => x"00",
      67 => x"00",
      68 => x"00",
      69 => x"00",
      70 => x"00",
      71 => x"00",
      72 => x"00",
      73 => x"00",
      74 => x"00",
      75 => x"00",
      76 => x"00",
      77 => x"00",
      78 => x"00",
      79 => x"00",
      80 => x"00",
      81 => x"00",
      82 => x"00",
      83 => x"00",
      84 => x"00",
      85 => x"00",
      86 => x"00",
      87 => x"00",
      88 => x"00",
      89 => x"00",
      90 => x"00",
      91 => x"00",
      92 => x"00",
      93 => x"00",
      94 => x"00",
      95 => x"00",
      96 => x"00",
      97 => x"00",
      98 => x"00",
      99 => x"00",
      100 => x"00",
      101 => x"00",
      102 => x"00",
      103 => x"00",
      104 => x"00",
      105 => x"00",
      106 => x"00",
      107 => x"00",
      108 => x"00",
      109 => x"00",
      110 => x"00",
      111 => x"00",
      112 => x"00",
      113 => x"00",
      114 => x"00",
      115 => x"00",
      116 => x"00",
      117 => x"00",
      118 => x"00",
      119 => x"00",
      120 => x"00",
      121 => x"00",
      122 => x"00",
      123 => x"00",
      124 => x"0f",
      125 => x"00",
      126 => x"01",
      127 => x"00",
      128 => x"01",
      129 => x"00",
      130 => x"1e",
      131 => x"00",
      132 => x"02",
      133 => x"aa",
      134 => x"bb",
      135 => x"cc",
      136 => x"dd",
      137 => x"ee",
      138 => x"ff",
      139 => x"ff",
      140 => x"ff",
      141 => x"ff",
      142 => x"ff",
      143 => x"ff",
      144 => x"ff",
      145 => x"04",
      146 => DC_TARGET_EXP_C( 7 downto  0),
      147 => DC_TARGET_EXP_C(15 downto  8),
      148 => DC_TARGET_EXP_C(23 downto 16),
      149 => DC_TARGET_EXP_C(31 downto 24),
      150 => x"04",
      151 => x"00",
      152 => x"00",
      153 => x"80",
      154 => x"00",
      155 => x"00",
      156 => x"00",
      157 => x"00",
      158 => x"23",
      159 => x"04",
      160 => x"00",
      161 => x"00",
      162 => x"80",
      163 => x"78",
      164 => x"56",
      165 => x"34",
      166 => x"12",
      167 => x"56",
      168 => x"04",
      169 => x"00",
      170 => x"00",
      171 => x"00",
      172 => x"00",
      173 => x"00",
      174 => x"00",
      175 => x"00",
      176 => x"00",
      177 => x"04",
      178 => x"00",
      179 => x"00",
      180 => x"00",
      181 => x"00",
      182 => x"00",
      183 => x"00",
      184 => x"00",
      185 => x"00",
      186 => x"11",
      187 => x"22",
      188 => x"33",
      189 => x"44",
      190 => x"01",
      191 => x"01",
      192 => x"02",
      193 => x"00",
      194 => x"00",
      195 => x"00",
      196 => x"0a",
      197 => x"00",
      198 => x"32",
      199 => x"00",
      200 => x"0b",
      201 => x"07",
      202 => x"4c",
      203 => x"61",
      204 => x"6e",
      205 => x"39",
      206 => x"32",
      207 => x"35",
      208 => x"34",
      209 => x"05",
      210 => x"45",
      211 => x"63",
      212 => x"45",
      213 => x"56",
      214 => x"52",
      215 => x"0f",
      216 => x"45",
      217 => x"43",
      218 => x"41",
      219 => x"54",
      220 => x"20",
      221 => x"45",
      222 => x"56",
      223 => x"52",
      224 => x"20",
      225 => x"52",
      226 => x"78",
      227 => x"44",
      228 => x"61",
      229 => x"74",
      230 => x"61",
      231 => x"06",
      232 => x"4c",
      233 => x"45",
      234 => x"44",
      235 => x"5b",
      236 => x"31",
      237 => x"5d",
      238 => x"06",
      239 => x"4c",
      240 => x"45",
      241 => x"44",
      242 => x"5b",
      243 => x"32",
      244 => x"5d",
      245 => x"06",
      246 => x"4c",
      247 => x"45",
      248 => x"44",
      249 => x"5b",
      250 => x"33",
      251 => x"5d",
      252 => x"0f",
      253 => x"45",
      254 => x"43",
      255 => x"41",
      256 => x"54",
      257 => x"20",
      258 => x"45",
      259 => x"56",
      260 => x"52",
      261 => x"20",
      262 => x"54",
      263 => x"78",
      264 => x"44",
      265 => x"61",
      266 => x"74",
      267 => x"61",
      268 => x"0b",
      269 => x"54",
      270 => x"69",
      271 => x"6d",
      272 => x"65",
      273 => x"73",
      274 => x"74",
      275 => x"61",
      276 => x"6d",
      277 => x"70",
      278 => x"4c",
      279 => x"6f",
      280 => x"0b",
      281 => x"54",
      282 => x"69",
      283 => x"6d",
      284 => x"65",
      285 => x"73",
      286 => x"74",
      287 => x"61",
      288 => x"6d",
      289 => x"70",
      290 => x"48",
      291 => x"69",
      292 => x"03",
      293 => x"66",
      294 => x"6f",
      295 => x"6f",
      296 => x"03",
      297 => x"62",
      298 => x"61",
      299 => x"72",
      300 => x"1e",
      301 => x"00",
      302 => x"10",
      303 => x"00",
      304 => x"01",
      305 => x"00",
      306 => x"01",
      307 => x"02",
      308 => x"00",
      309 => x"00",
      310 => x"00",
      311 => x"01",
      312 => x"00",
      313 => x"00",
      314 => x"00",
      315 => x"04",
      316 => x"00",
      317 => x"00",
      318 => x"01",
      319 => x"00",
      320 => x"11",
      321 => x"00",
      322 => x"00",
      323 => x"00",
      324 => x"00",
      325 => x"00",
      326 => x"00",
      327 => x"00",
      328 => x"00",
      329 => x"00",
      330 => x"00",
      331 => x"00",
      332 => x"00",
      333 => x"00",
      334 => x"00",
      335 => x"00",
      336 => x"28",
      337 => x"00",
      338 => x"02",
      339 => x"00",
      340 => x"01",
      341 => x"02",
      342 => x"03",
      343 => x"00",
      344 => x"29",
      345 => x"00",
      346 => x"10",
      347 => x"00",
      348 => x"00",
      349 => x"10",
      350 => x"50",
      351 => x"00",
      352 => x"26",
      353 => x"00",
      354 => x"01",
      355 => x"01",
      356 => x"80",
      357 => x"10",
      358 => x"50",
      359 => x"00",
      360 => x"22",
      361 => x"00",
      362 => x"01",
      363 => x"02",
      364 => x"00",
      365 => x"11",
      366 => x"03",
      367 => x"00",
      368 => x"24",
      369 => x"00",
      370 => x"01",
      371 => x"03",
      372 => x"80",
      373 => x"11",
      374 => x"10",
      375 => x"00",
      376 => x"20",
      377 => x"00",
      378 => x"01",
      379 => x"04",
      380 => x"32",
      381 => x"00",
      382 => x"14",
      383 => x"00",
      384 => x"00",
      385 => x"1a",
      386 => x"04",
      387 => x"03",
      388 => x"00",
      389 => x"07",
      390 => x"13",
      391 => x"00",
      392 => x"00",
      393 => x"60",
      394 => x"01",
      395 => x"08",
      396 => x"07",
      397 => x"20",
      398 => x"00",
      399 => x"00",
      400 => x"01",
      401 => x"60",
      402 => x"01",
      403 => x"09",
      404 => x"07",
      405 => x"20",
      406 => x"00",
      407 => x"00",
      408 => x"00",
      409 => x"50",
      410 => x"01",
      411 => x"0a",
      412 => x"07",
      413 => x"20",
      414 => x"00",
      415 => x"00",
      416 => x"01",
      417 => x"50",
      418 => x"01",
      419 => x"0b",
      420 => x"07",
      421 => x"20",
      422 => x"00",
      423 => x"00",
      424 => x"33",
      425 => x"00",
      426 => x"10",
      427 => x"00",
      428 => x"00",
      429 => x"16",
      430 => x"03",
      431 => x"02",
      432 => x"00",
      433 => x"03",
      434 => x"13",
      435 => x"00",
      436 => x"00",
      437 => x"20",
      438 => x"01",
      439 => x"04",
      440 => x"05",
      441 => x"08",
      442 => x"00",
      443 => x"00",
      444 => x"00",
      445 => x"20",
      446 => x"02",
      447 => x"05",
      448 => x"05",
      449 => x"08",
      450 => x"00",
      451 => x"00",
      452 => x"00",
      453 => x"20",
      454 => x"03",
      455 => x"06",
      456 => x"05",
      457 => x"08",
      458 => x"00",
      459 => x"00",
      460 => x"02",
      461 => x"00",
      462 => x"03",
      463 => x"00",
      464 => x"a0",
      465 => x"01",
      466 => x"dd",
      467 => x"ff",
      468 => x"ff",
      469 => x"ff",
      470 => x"ff",
      others => x"ff"
   );

   function fillEEPROM return Slv08Array is
      variable v : Slv08Array(SIZE_BYTES_C - 1 downto 0);
   begin
      for i in 0 to SIZE_BYTES_C/2 - 1 loop
         if ( i <  EEPROM_INIT_C'length ) then
            v(2*i + 0) := EEPROM_INIT_C(i)( 7 downto 0);
            v(2*i + 1) := EEPROM_INIT_C(i)(15 downto 8);
         else
            v(2*i + 0) := x"FF";
            v(2*i + 1) := x"FF";
         end if;
      end loop;
      return v;
   end function fillEEPROM;

   constant EEPROM_CONFIGURED_C : Slv08Array(SIZE_BYTES_C - 1 downto 0) := fillEEPROM;

   constant EEPROM_8_INIT_C : Slv08Array := EEPROM_INIT_2_C; --EEPROM_CONFIGURED_C;

   function EEPROM_16_INIT_F(constant x: in Slv08Array) return EEPROMArray is
      variable v : EEPROMArray(0 to x'length/2 - 1);
   begin
      for i in v'range loop
        v(i) := x(2*i+1) & x(2*i);
      end loop;
      return v;
   end function EEPROM_16_INIT_F;

   signal wrReq : EEPROMWriteWordReqType := (
      waddr => to_unsigned(16, 15),
      wdata => x"cafe",
      valid => '1'
   );

   signal wrAck : EEPROMWriteWordAckType;

   signal strmTxMst, strmRxMst : Lan9254StrmMstType;
   signal strmTxRdy, strmRxRdy : std_logic;

   signal progFound            : std_logic;
   signal progAddr             : unsigned(15 downto 0);

   constant pgExp : Evr320PulseGenConfigArray := (
      0 => (
         pulseWidth => EvrDurationType ( to_unsigned( 4, EvrDurationType'length ) ),
         pulseDelay => EvrDurationType ( to_unsigned( 0, EvrDurationType'length ) ),
         pulseEvent => std_logic_vector( to_unsigned( 16#23#, 8 )                 ),
         pulseEnbld => '1',
         pulseInvrt => '0'
      ),
      1 => (
         pulseWidth => EvrDurationType ( to_unsigned( 4, EvrDurationType'length ) ),
         pulseDelay => EvrDurationType ( to_unsigned( 16#12345678#, EvrDurationType'length ) ),
         pulseEvent => std_logic_vector( to_unsigned( 16#56#, 8 )                 ),
         pulseEnbld => '1',
         pulseInvrt => '0'
      ),
      others => (
         pulseWidth => EvrDurationType ( to_unsigned( 4, EvrDurationType'length ) ),
         pulseDelay => EvrDurationType ( to_unsigned( 0, EvrDurationType'length ) ),
         pulseEvent => std_logic_vector( to_unsigned( 16#00#, 8 )                 ),
         pulseEnbld => '0',
         pulseInvrt => '0'
      )
   );

   constant xtraEvtExp : Slv08Array := (
      0 => std_logic_vector( to_unsigned( 16#11#, 8 ) ),
      1 => std_logic_vector( to_unsigned( 16#22#, 8 ) ),
      2 => std_logic_vector( to_unsigned( 16#33#, 8 ) ),
      3 => std_logic_vector( to_unsigned( 16#44#, 8 ) )
   );

begin

   sda <= (sda_m_t or sda_m_o) and sda_s_o;
   scl <= (scl_m_t or scl_m_o) and scl_s_o;

   P_CLK : process is
   begin
      if ( run ) then
         wait for 1.25 us;
         clk <= not clk;
      else
         wait;
      end if;
   end process P_CLK;

   P_DRV : process is
   begin
      wait until rising_edge( clk );
      wait until rising_edge( clk );
      wait until rising_edge( clk );
      rst <= '0';
      wait until rising_edge( clk );
      wait;
   end process P_DRV;

   P_DON : process (clk) is
   begin
      if ( rising_edge( clk ) ) then
         if ( cfg.net.macAddrVld = '1' ) then
            report "MAC: " & toString( cfg.net.macAddr );
         end if;
         if ( cfg.net.ip4AddrVld = '1' ) then
            report "IP4: " & toString( cfg.net.ip4Addr );
         end if;
         if ( cfg.net.udpPortVld = '1' ) then
            report "UDP: " & toString( cfg.net.udpPort );
         end if;
         if ( cfg.esc.valid = '1' ) then
            report "NMAPS:   " & integer'image( cfg.txPDO.numMaps );
            report "SM2 LEN: " & toString( cfg.esc.sm2Len );
            report "SM3 LEN: " & toString( cfg.esc.sm3Len );
            for j in 0 to cfg.txPDO.numMaps - 1 loop
               report "MAP " & integer'image(j) & " : off " & toString( dbufMaps(j).off )
                                                & " : swp " & toString( dbufMaps(j).swp )
                                                & " : num " & toString( dbufMaps(j).num );
            end loop;
         end if;
         if ( cfg.evr320.req = '1' ) then
            report "EVR320: ";
            report "  Pulse Generators:";
            for j in cfg.evr320.pulseGenParams'range loop
              report "    [" & integer'image(j) & "]:";
              report "      Width: " & integer'image(to_integer(unsigned(cfg.evr320.pulseGenParams(j).pulseWidth)));
              report "      Delay: " & integer'image(to_integer(unsigned(cfg.evr320.pulseGenParams(j).pulseDelay)));
              report "      Event: " & integer'image(to_integer(unsigned(cfg.evr320.pulseGenParams(j).pulseEvent)));
              report "      Enable:" & std_logic'image(cfg.evr320.pulseGenParams(j).pulseEnbld);
              assert pgExp(j) = cfg.evr320.pulseGenParams(j) report "Evr Parameter mismatch" severity failure;
            end loop;
            report "  Extra Events:";
            for j in 0 to NUM_EXTRA_EVENTS_C - 1 loop
               report "    [" & integer'image(j) & "]: " & integer'image(to_integer(unsigned(cfg.evr320.extraEvents(j))));
               assert xtraEvtExp(j) = cfg.evr320.extraEvents(j) report "Extra event mismatch" severity failure;
            end loop;
            report "  DC Target: " & integer'image(to_integer(unsigned(cfg.evr320.dcTarget)));
            assert cfg.evr320.dcTarget = DC_TARGET_EXP_C report "DC target mismatch" severity failure;
         end if;
         if ( wrAck.ack = '1' ) then
            run <= false;
            wrReq.valid <= '0';
            if ( progFound = '1' ) then
               report "I2C CONFIGURATION PROGRAM FOUND @" & integer'image(to_integer(progAddr));
               report "TEST PASSED";
            else
               report "NO I2C CONFIGURATION PROGRAM FOUND" severity failure;
            end if;
         end if;
      end if;
   end process P_DON;

   U_EEP : entity work.I2CEEPROM
      generic map (
         SIZE_BYTES_G  => SIZE_BYTES_C,
         EEPROM_INIT_G => toSlv( EEPROM_8_INIT_C ),
         I2C_ADDR_G    => "01010000"
      )
      port map (
         clk       => clk,
         rst       => rst,

         sclSync   => scl,
         sdaSync   => sda,
         sdaOut    => sda_s_o
      );

   -- ClockFrequency_g must be >= 12*I2cFrequency_g
   -- otherwise spurious arbitration-lost will be detected
   -- (probably due to synchronizer delays)
   U_DUT : entity work.EEPROMConfigurator
      generic map (
         EEPROM_OFFSET_G            => 0, --128,
         EEPROM_SIZE_G              => (8*SIZE_BYTES_C),
         EEPROM_INIT_G              => EEPROM_16_INIT_F( EEPROM_8_INIT_C ),
         MAX_TXPDO_MAPS_G           => MAX_TXPDO_MAPS_C,
         I2C_ADDR_G                 => "1010000",
         GEN_ILA_G                  => false
      )
      port map (
         clk             => clk,
         rst             => rst,

         dbufMaps        => dbufMaps,
         configReq       => cfg,
         configAck       => ack,

         eepWriteReq     => wrReq,
         eepWriteAck     => wrAck,

         emulActive      => EMUL_ACTIVE_G,

         i2cProgFound    => progFound,
         i2cProgAddr     => progAddr,
        
         i2cStrmTxMst   => strmTxMst,
         i2cStrmTxRdy   => strmTxRdy,
   
         i2cStrmRxMst   => strmRxMst,
         i2cStrmRxRdy   => strmRxRdy
 
      );

      U_STRM : entity work.PsiI2cStreamIF
         generic map (
            CLOCK_FREQ_G   => 5.0e5,
            I2C_FREQ_G     => 1.0e4
         )
         port map (
            clk            => clk,
            rst            => rst,
   
            strmMstIb      => strmTxMst,
            strmRdyIb      => strmTxRdy,
   
            strmMstOb      => strmRxMst,
            strmRdyOb      => strmRxRdy,
   
            i2c_scl_i      => scl,
            i2c_scl_o      => scl_m_o,
            i2c_scl_t      => scl_m_t,
   
            i2c_sda_i      => sda,
            i2c_sda_o      => sda_m_o,
            i2c_sda_t      => sda_m_t,
   
            debug          => open
         );

end architecture sim;

