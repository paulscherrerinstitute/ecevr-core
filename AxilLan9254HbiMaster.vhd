library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.StdRtlPkg.all;
use     work.AxiLitePkg.all;
use     work.Lan9254Pkg.all;

entity AxilLan9254HbiMaster is
   generic (
      TPD_G              : time                 := 1 ns;
      AXIL_CLK_PERIOD_G  : real;
      LOC_REG_ADDR_G     : std_logic_vector(15 downto 0) := x"3000";
      LOC_REG_INIT_G     : std_logic_vector(31 downto 0) := x"0000_0000"
   );
   port (
      axilClk            : in  std_logic;
      axilRst            : in  std_logic;
      axilReadMaster     : in  AxiLiteReadMasterType;
      axilReadSlave      : out AxiLiteReadSlaveType;
      axilWriteMaster    : in  AxiLiteWriteMasterType;
      axilWriteSlave     : out AxiLiteWriteSlaveType;

      hbiOut             : out Lan9254HBIOutType;
      hbiInp             : in  Lan9254HBIInpType;

      locRegRW           : out std_logic_vector(31 downto 0)
   );
end entity AxilLan9254HbiMaster;

architecture rtl of AxilLan9254HbiMaster is

   constant NUM_ABITS_C : natural := 14; -- byte address space of lan9254

   -- AXI does not support byte-enable for reads; use different address spaces
   -- to signal read-size
   type ASpaceType      is (RW32, RW16, RW8, UNKNOWN);

   function space(constant a : in std_logic_vector) return ASpaceType is
      constant SP : std_logic_vector(1 downto 0) := a(NUM_ABITS_C + 1 downto NUM_ABITS_C);
   begin
      case SP is
        when "00"   => return RW32;
        when "01"   => return RW16;
        when "10"   => return RW8;
        when others => return UNKNOWN;
      end case;
   end function space;

   type AAlignType      is (OK, MISALIGNED, INVALID);
   function aalignCheck(constant a : in std_logic_vector) return AAlignType is
   begin
      case space(a) is
         when RW32 =>
            if ( std_match( a(1 downto 0), "00") ) then
               return OK;
            end if;
         when RW16 =>
            if ( std_match( a(0 downto 0), "0" ) ) then
               return OK;
            end if;
         when RW8  =>
            return OK;
         when others =>
            return INVALID;
      end case;
      return MISALIGNED;
   end function aalignCheck;

   function calcBE(constant a : in  std_logic_vector) return std_logic_vector is
      variable be : std_logic_vector(3 downto 0);
   begin
      be := (others => not HBI_BE_ACT_C);
      case space(a) is
         when RW8  =>
            be( to_integer(unsigned(a(1 downto 0))) ) := HBI_BE_ACT_C;
         when RW16 =>
            if ( a(1) = '1' ) then
               be(3 downto 2) := (others => HBI_BE_ACT_C);
            else
               be(1 downto 0) := (others => HBI_BE_ACT_C);
            end if;
         when others =>
            be := (others => HBI_BE_ACT_C);
      end case;
      return be;
   end function calcBE;

   signal hbiRep        : Lan9254RepType;

   type StateType       is (AXIL, HBI);

   type RegType is record
      hbiReq            : Lan9254ReqType;
      accessWidth       : ASpaceType;
      state             : StateType;
      axilReadSlave     : AxiLiteReadSlaveType;
      axilWriteSlave    : AxiLiteWriteSlaveType;
      locReg3000        : std_logic_vector(31 downto 0);
   end record RegType;

   signal rin                     : RegType;

   constant REG_INIT_C : RegType := (
      hbiReq            => LAN9254REQ_INIT_C,
      accessWidth       => UNKNOWN,
      state             => AXIL,
      axilReadSlave     => AXI_LITE_READ_SLAVE_INIT_C,
      axilWriteSlave    => AXI_LITE_WRITE_SLAVE_INIT_C,
      locReg3000        => LOC_REG_INIT_G
   );

   signal r                       : RegType := REG_INIT_C;

begin

   P_COMB : process(axilReadMaster, axilWriteMaster, axilRst, r, hbiRep, hbiInp) is
      variable v          : RegType;
      variable axilStatus : AxiLiteStatusType;

      variable aSpc       : ASpaceType;
      variable extTxn     : std_logic;
      variable axilResp   : std_logic_vector(1 downto 0);
      constant BE_DEASS_C : std_logic_vector(3 downto 0) := (others => not HBI_BE_ACT_C);
   begin
      v := r;

      axilStatus := AXI_LITE_STATUS_INIT_C;
      extTxn     := '0';
      axilResp   := AXI_RESP_OK_C;

      case r.state is
         when AXIL =>

            axiSlaveWaitTxn(axilWriteMaster, axilReadMaster, v.axilWriteSlave, v.axilReadSlave, axilStatus);

            if ( axilStatus.readEnable = '1' ) then
               if ( axilReadMaster.araddr(13 downto 2) = LOC_REG_ADDR_G(13 downto 2) ) then
                  v.axilReadSlave.rdata := r.locReg3000;
                  axiSlaveReadResponse( v.axilReadSlave );
               else
                  case aalignCheck( axilReadMaster.araddr ) is
                     when MISALIGNED =>
                           axiSlaveReadResponse( v.axilReadSlave, AXI_RESP_SLVERR_C );
                     when OK =>
                           v.hbiReq.addr        := axilReadMaster.araddr(v.hbiReq.addr'range);
                           v.hbiReq.noAck       := axilReadMaster.araddr(16);
                           -- for smaller alignments we use BE and align the address
                           v.hbiReq.addr(1 downto 0) := (others => '0');
                           v.hbiReq.be          := calcBE( axilReadMaster.araddr );
                           v.hbiReq.rdnwr       := '1';
                           v.hbiReq.valid       := '1';
                           v.accessWidth        := space( axilReadMaster.araddr );
                           -- block AXI response until read is back
                           extTxn               := '1';
                           v.state              := HBI;
                     when others =>
                  end case;
               end if;
            end if;

            if ( axilStatus.writeEnable = '1' ) then
               if ( axilWriteMaster.awaddr(13 downto 2) = LOC_REG_ADDR_G(13 downto 2) ) then
                  for i in axilWriteMaster.wstrb'range loop
                     if ( axilWriteMaster.wstrb(i) = '1' ) then
                        v.locReg3000(8*i+7 downto 8*i) := axilWriteMaster.wdata(8*i+7 downto 8*i);
                     end if;
                  end loop;
                  axiSlaveWriteResponse( v.axilWriteSlave );
               else
                  case aalignCheck( axilWriteMaster.awaddr ) is
                     when MISALIGNED =>
                           axiSlaveWriteResponse( v.axilWriteSlave, AXI_RESP_SLVERR_C );
                     when OK =>
                           v.hbiReq.addr        := axilWriteMaster.awaddr(v.hbiReq.addr'range);
                           v.hbiReq.noAck       := axilWriteMaster.awaddr(16);
                           -- for smaller alignments we use BE and align the address
                           v.hbiReq.addr(1 downto 0) := (others => '0');
                           v.hbiReq.wdata       := axilWriteMaster.wdata;
                           v.hbiReq.be          := ( BE_DEASS_C xor axilWriteMaster.wstrb );
                           v.hbiReq.rdnwr       := '0';
                           v.hbiReq.valid       := '1';
                           v.accessWidth        := space( axilWriteMaster.awaddr );
                           -- block AXI response until read is back
                           -- NOTE: posted write NOT OK, since we have to wait until the posting is done!
                           extTxn               := '1';
                           v.state              := HBI;
                     when others =>
                  end case;
               end if;
            end if;
            axiSlaveDefault(axilWriteMaster, axilReadMaster, v.axilWriteSlave, v.axilReadSlave, axilStatus, AXI_RESP_DECERR_C, extTxn);

         when HBI =>
            if ( hbiRep.valid = '1' ) then
               v.hbiReq.valid := '0';
               v.state        := AXIL;
               if ( hbiRep.berr(0) = '1' ) then
                  axilResp := AXI_RESP_SLVERR_C;
               end if;

               if ( r.hbiReq.rdnwr = '1' ) then

--                  case ( r.accessWidth ) is
--                     when RW8 =>
--                        if    ( r.hbiReq.be(0) = HBI_BE_ACT_C ) then
--                           v.axilReadSlave.rdata(7 downto 0) := hbiRep.rdata( 7 downto  0);
--                        elsif ( r.hbiReq.be(1) = HBI_BE_ACT_C ) then
--                           v.axilReadSlave.rdata(7 downto 0) := hbiRep.rdata(15 downto  8);
--                        elsif ( r.hbiReq.be(2) = HBI_BE_ACT_C ) then
--                           v.axilReadSlave.rdata(7 downto 0) := hbiRep.rdata(23 downto 16);
--                        elsif ( r.hbiReq.be(3) = HBI_BE_ACT_C ) then
--                           v.axilReadSlave.rdata(7 downto 0) := hbiRep.rdata(31 downto 24);
--                        end if;
--                     when RW16 =>
--                        if    ( (r.hbiReq.be(0) = HBI_BE_ACT_C) and (r.hbiReq.be(1) = HBI_BE_ACT_C) ) then
--                           v.axilReadSlave.rdata(15 downto 0) := hbiRep.rdata(15 downto  0);
--                        elsif ( (r.hbiReq.be(2) = HBI_BE_ACT_C) and (r.hbiReq.be(3) = HBI_BE_ACT_C) ) then
--                           v.axilReadSlave.rdata(15 downto 0) := hbiRep.rdata(31 downto 16);
--                        end if;
--                     when others =>
--                        v.axilReadSlave.rdata := hbiRep.rdata;
--                  end case;
                  v.axilReadSlave.rdata := hbiRep.rdata;

                  axiSlaveReadResponse( v.axilReadSlave, axilResp );
               else
                  axiSlaveWriteResponse( v.axilWriteSlave, axilResp );
               end if;
            end if;
      end case;

      rin <= v;
   end process P_COMB;

   P_SEQ : process (axilClk ) is
   begin
      if ( rising_edge( axilClk ) ) then
         if ( axilRst = '1' ) then
            r <= REG_INIT_C;
         else
            r <= rin;
         end if;
      end if;
   end process P_SEQ;


   U_HBI : entity work.Lan9254Hbi
      generic map (
         CLOCK_FREQ_G => (1.0/AXIL_CLK_PERIOD_G)
      )
      port map (
         clk          => axilClk,
         cen          => '1',
         rst          => axilRst,

         req          => r.hbiReq,
         rep          => hbiRep,

         hbiOut       => hbiOut,
         hbiInp       => hbiInp
      );

   axilReadSlave  <= r.axiLReadSlave;
   axilWriteSlave <= r.axiLWriteSlave;

   locRegRW       <= r.locReg3000;

end architecture rtl;
