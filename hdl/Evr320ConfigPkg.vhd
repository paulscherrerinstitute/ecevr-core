library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.ESCBasicTypesPkg.all;

package Evr320ConfigPkg is
   constant MAX_DURATION_LD_C      : natural := 32;

   subtype EvrDurationType     is std_logic_vector(MAX_DURATION_LD_C - 1 downto 0);
   
   function toEvrDuration(constant x : in natural)
   return EvrDurationType;

   constant PULSE_WIDTH_DEFAULT_C  : EvrDurationType := toEvrDuration( 20 );

   constant NUM_PULSE_EVENTS_C     : natural := 4;
   constant NUM_EXTRA_EVENTS_C     : natural := 4;

   type Evr320PulseGenConfigType is record 
      pulseWidth : EvrDurationType;
      pulseDelay : EvrDurationType;
      pulseEvent : std_logic_vector(                7 downto 0);
      pulseEnbld : std_logic;
      pulseInvrt : std_logic;
   end record Evr320PulseGenConfigType;

   constant EVR320_PULSE_GEN_CONFIG_INIT_C : Evr320PulseGenConfigType := (
      pulseWidth => PULSE_WIDTH_DEFAULT_C,
      pulseDelay => (others => '0'),
      pulseEvent => (others => '0'),
      pulseEnbld => '0',
      pulseInvrt => '0'
   );

   type Evr320PulseGenConfigArray is array (natural range 0 to NUM_PULSE_EVENTS_C - 1) of Evr320PulseGenConfigType;

   type Evr320ConfigReqType is record
      dcTarget       : std_logic_vector(31 downto 0);
      pulseGenParams : Evr320PulseGenConfigArray;
      extraEvents    : Slv08Array(NUM_EXTRA_EVENTS_C - 1 downto 0);
      req            : std_logic;
   end record Evr320ConfigReqType;

   constant EVR320_CONFIG_REQ_INIT_C : Evr320ConfigReqType := (
      dcTarget       => (others => '0'),
      pulseGenParams => (others => EVR320_PULSE_GEN_CONFIG_INIT_C),
      extraEvents    => (others => (others => '0')),
      req            => '0'
   );

   type Evr320ConfigAckType is record
      ack            : std_logic;
   end record Evr320ConfigAckType;


   constant EVR320_CONFIG_ACK_INIT_C : Evr320ConfigAckType := (
      ack            => '0'
   );

   constant EVR320_CONFIG_ACK_ASSERT_C : Evr320ConfigAckType := (
      ack            => '1'
   );

   function toSlv08Array(constant x : in Evr320ConfigReqType)
      return Slv08Array;

   function toEvr320ConfigReqType(constant x : in Slv08Array)
      return Evr320ConfigReqType;

end package Evr320ConfigPkg;

package body Evr320ConfigPkg is

   constant SZ_C : natural := 9;

   function toSlv08Array(constant x : in Evr320ConfigReqType)
      return Slv08Array is
      variable v : Slv08Array(0 to x.pulseGenParams'length*SZ_C + x.extraEvents'length + x.dcTarget'length/8 - 1) := (others => (others => '0'));
      variable o : integer;
   begin
      o := 0;
      for j in 0 to 3 loop
         v(o) := x.dcTarget(8*j + 7 downto 8*j);
         o    := o + 1;
      end loop;
      for i in x.pulseGenParams'range loop
         for j in 0 to 3 loop
            v(o      + 0*4 + j) := x.pulseGenParams(i).pulseWidth(8*j + 7 downto 8*j);
            v(o      + 1*4 + j) := x.pulseGenParams(i).pulseDelay(8*j + 7 downto 8*j);
         end loop;
         v(o      + 2*4 + 0) := x.pulseGenParams(i).pulseEvent;
         -- reuse bit 31/30 of width for 'enable'/'invert'
         v(o      + 0*4 + 3)(7) := x.pulseGenParams(i).pulseEnbld;
         v(o      + 0*4 + 3)(6) := x.pulseGenParams(i).pulseInvrt;
         o                      := o + SZ_C;
      end loop;
      for i in 0 to  x.extraEvents'length - 1 loop
         v(o) := x.extraEvents(i);
         o    := o + 1;
      end loop;
      return v;
   end function toSlv08Array;

   function toEvr320ConfigReqType(constant x : in Slv08Array)
      return Evr320ConfigReqType is
      variable v : Evr320ConfigReqType := EVR320_CONFIG_REQ_INIT_C;
      variable o : integer;
   begin
      o := x'low;
      for j in 0 to 3 loop
         v.dcTarget(8*j + 7 downto 8*j) := x(o);
         o                              := o + 1;
      end loop;
      for i in v.pulseGenParams'range loop
         for j in 0 to 3 loop
            v.pulseGenParams(i).pulseWidth(8*j + 7 downto 8*j) := x(o + 0*4 + j);
            v.pulseGenParams(i).pulseDelay(8*j + 7 downto 8*j) := x(o + 1*4 + j);
         end loop;
         v.pulseGenParams(i).pulseEvent     := x(o + 2*4 + 0);
         v.pulseGenParams(i).pulseEnbld     := v.pulseGenParams(i).pulseWidth(31);
         v.pulseGenParams(i).pulseInvrt     := v.pulseGenParams(i).pulseWidth(30);
         v.pulseGenParams(i).pulseWidth(31) := '0';
         v.pulseGenParams(i).pulseWidth(30) := '0';
         o                                  := o + SZ_C;
      end loop;
      for i in 0 to v.extraEvents'length - 1 loop
         v.extraEvents(i) := x(o);
         o                := o + 1;
      end loop;
      return v;
   end function toEvr320ConfigReqType;
   
   function toEvrDuration(constant x : in natural) return EvrDurationType is
   begin
      return EvrDurationType( to_unsigned( x, EvrDurationType'length ) );
   end function toEvrDuration;

end package body Evr320ConfigPkg;
