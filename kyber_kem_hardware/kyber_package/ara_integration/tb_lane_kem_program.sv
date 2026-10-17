module tb_lane_kem_program;
  import ara_pkg::*;
  import rvv_pkg::*;

  localparam int unsigned NrLanes = 2;
  localparam int unsigned VLEN    = 65536;
  localparam type vlen_t      = logic [$clog2(VLEN+1)-1:0];
  localparam type exception_t = logic;

  `include "ara/ara_typedef.svh"

  localparam int unsigned PE_REQ_BITS  = $bits(pe_req_t);
  localparam int unsigned PE_RESP_BITS = $bits(pe_resp_t);

  localparam int unsigned VLENB           = VLEN / 8;
  localparam int unsigned MaxVLenBPerLane = VLENB / NrLanes;
  localparam int unsigned VRFBSizePerLane = MaxVLenBPerLane * 32;
  typedef logic [$clog2(VRFBSizePerLane)-1:0] vaddr_t;
  typedef logic [$bits(elen_t)/8-1:0] strb_t;

  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  logic scan_data_o;
  logic [$clog2(NrLanes)-1:0] lane_id_i;
  logic vxsat_flag_o;
  logic [4:0] fflags_ex_o;
  logic fflags_ex_valid_o;
  logic lsu_ex_flush_o;

  pe_req_t  pe_req;
  logic [PE_REQ_BITS-1:0] pe_req_i_bits;
  logic pe_req_valid_i;
  logic [NrVInsn-1:0] pe_vinsn_running_i;
  logic pe_req_ready_o;
  logic [PE_RESP_BITS-1:0] pe_resp_o_bits;
  pe_resp_t pe_resp;
  logic alu_vinsn_done_o, mfpu_vinsn_done_o, pqc_vinsn_done_o;
  logic [NrVInsn-1:0][NrVInsn-1:0] global_hazard_table_i;

  elen_t stu_operand_o;
  logic  stu_operand_valid_o;
  elen_t sldu_addrgen_operand_o;
  logic  sldu_operand_valid_o, addrgen_operand_valid_o;
  sldu_mux_e sldu_mux_sel_i;

  logic   sldu_result_req_i;
  vid_t   sldu_result_id_i;
  vaddr_t sldu_result_addr_i;
  elen_t  sldu_result_wdata_i;
  strb_t  sldu_result_be_i;
  logic   sldu_result_gnt_o;
  logic   sldu_red_valid_i;
  logic   sldu_result_final_gnt_o;

  logic   ldu_result_req_i;
  vid_t   ldu_result_id_i;
  vaddr_t ldu_result_addr_i;
  elen_t  ldu_result_wdata_i;
  strb_t  ldu_result_be_i;
  logic   ldu_result_gnt_o, ldu_result_final_gnt_o;

  elen_t [NrMaskFUnits+2-1:0] mask_operand_o;
  logic  [NrMaskFUnits+2-1:0] mask_operand_valid_o;
  logic  [NrMaskFUnits+2-1:0] mask_operand_ready_i;
  logic   masku_result_req_i;
  vid_t   masku_result_id_i;
  vaddr_t masku_result_addr_i;
  elen_t  masku_result_wdata_i;
  strb_t  masku_result_be_i;
  logic   masku_result_gnt_o, masku_result_final_gnt_o;
  logic   masku_vrgat_req_valid_i;
  logic   masku_vrgat_req_ready_o;
  vrgat_req_t masku_vrgat_req_i;

  strb_t mask_i;
  logic  mask_valid_i;
  logic  mask_ready_o;

  initial begin
    lane_id_i               = '0;
    pe_req_valid_i           = 1'b0;
    pe_vinsn_running_i        = '0;
    global_hazard_table_i     = '0;
    sldu_mux_sel_i            = NO_RED;
    sldu_result_req_i         = 1'b0;
    sldu_result_id_i          = '0;
    sldu_result_addr_i        = '0;
    sldu_result_wdata_i       = '0;
    sldu_result_be_i          = '0;
    sldu_red_valid_i          = 1'b0;
    ldu_result_req_i          = 1'b0;
    ldu_result_id_i           = '0;
    ldu_result_addr_i         = '0;
    ldu_result_wdata_i        = '0;
    ldu_result_be_i           = '0;
    mask_operand_ready_i      = '1;
    masku_result_req_i        = 1'b0;
    masku_result_id_i         = '0;
    masku_result_addr_i       = '0;
    masku_result_wdata_i      = '0;
    masku_result_be_i         = '0;
    masku_vrgat_req_valid_i   = 1'b0;
    masku_vrgat_req_i         = '0;
    mask_i                    = '0;
    mask_valid_i              = 1'b0;
    pe_req                    = '0;
  end

  lane #(
    .NrLanes       (NrLanes),
    .VLEN          (VLEN),
    .pe_req_t_bits (PE_REQ_BITS),
    .pe_resp_t_bits(PE_RESP_BITS)
  ) dut (
    .clk_i                   (clk),
    .rst_ni                  (rst_n),
    .scan_enable_i            (1'b0),
    .scan_data_i              (1'b0),
    .scan_data_o              (scan_data_o),
    .lane_id_i                (lane_id_i),
    .vxsat_flag_o              (vxsat_flag_o),
    .alu_vxrm_i                (2'b00),
    .fflags_ex_o               (fflags_ex_o),
    .fflags_ex_valid_o         (fflags_ex_valid_o),
    .lsu_ex_flush_i            (1'b0),
    .lsu_ex_flush_o            (lsu_ex_flush_o),
    .pe_req_i                  (pe_req_i_bits),
    .pe_req_valid_i            (pe_req_valid_i),
    .pe_vinsn_running_i        (pe_vinsn_running_i),
    .pe_req_ready_o            (pe_req_ready_o),
    .pe_resp_o                 (pe_resp_o_bits),
    .alu_vinsn_done_o          (alu_vinsn_done_o),
    .mfpu_vinsn_done_o         (mfpu_vinsn_done_o),
    .pqc_vinsn_done_o          (pqc_vinsn_done_o),
    .global_hazard_table_i     (global_hazard_table_i),
    .stu_operand_o             (stu_operand_o),
    .stu_operand_valid_o       (stu_operand_valid_o),
    .stu_operand_ready_i       (1'b1),
    .sldu_addrgen_operand_o    (sldu_addrgen_operand_o),
    .sldu_operand_valid_o      (sldu_operand_valid_o),
    .addrgen_operand_valid_o   (addrgen_operand_valid_o),
    .sldu_operand_ready_i      (1'b1),
    .sldu_mux_sel_i            (sldu_mux_sel_i),
    .addrgen_operand_ready_i   (1'b1),
    .sldu_result_req_i         (sldu_result_req_i),
    .sldu_result_id_i          (sldu_result_id_i),
    .sldu_result_addr_i        (sldu_result_addr_i),
    .sldu_result_wdata_i       (sldu_result_wdata_i),
    .sldu_result_be_i          (sldu_result_be_i),
    .sldu_result_gnt_o         (sldu_result_gnt_o),
    .sldu_red_valid_i          (sldu_red_valid_i),
    .sldu_result_final_gnt_o   (sldu_result_final_gnt_o),
    .ldu_result_req_i          (ldu_result_req_i),
    .ldu_result_id_i           (ldu_result_id_i),
    .ldu_result_addr_i         (ldu_result_addr_i),
    .ldu_result_wdata_i        (ldu_result_wdata_i),
    .ldu_result_be_i           (ldu_result_be_i),
    .ldu_result_gnt_o          (ldu_result_gnt_o),
    .ldu_result_final_gnt_o    (ldu_result_final_gnt_o),
    .mask_operand_o            (mask_operand_o),
    .mask_operand_valid_o      (mask_operand_valid_o),
    .mask_operand_ready_i      (mask_operand_ready_i),
    .masku_result_req_i        (masku_result_req_i),
    .masku_result_id_i         (masku_result_id_i),
    .masku_result_addr_i       (masku_result_addr_i),
    .masku_result_wdata_i      (masku_result_wdata_i),
    .masku_result_be_i         (masku_result_be_i),
    .masku_result_gnt_o        (masku_result_gnt_o),
    .masku_result_final_gnt_o  (masku_result_final_gnt_o),
    .masku_vrgat_req_valid_i   (masku_vrgat_req_valid_i),
    .masku_vrgat_req_ready_o   (masku_vrgat_req_ready_o),
    .masku_vrgat_req_i         (masku_vrgat_req_i),
    .mask_i                    (mask_i),
    .mask_valid_i              (mask_valid_i),
    .mask_ready_o              (mask_ready_o)
  );

  assign pe_req_i_bits = pe_req;
  assign pe_resp       = pe_resp_o_bits;
  // ---------------------------------------------------------------
  // Real VRF preload (sldu_result_* port) / passive readback (bank-aware
  // tc_sram peek). See this file's header comment for why the readback
  // needs to be bank-aware here (unlike tb_lane_vpqc_montmul.sv's single
  // hardcoded gen_banks[0]).
  // ---------------------------------------------------------------
  task automatic sldu_preload(input vaddr_t addr, input elen_t data);
    begin
      sldu_result_id_i    = '0;
      sldu_result_addr_i  = addr;
      sldu_result_wdata_i = data;
      sldu_result_be_i    = '1;
      sldu_result_req_i   = 1'b1;
      while (!sldu_result_gnt_o) @(negedge clk);
      @(negedge clk);
      sldu_result_req_i   = 1'b0;
    end
  endtask

  task automatic vrf_write_block(input [4:0] vid, input integer n, input elen_t words [0:127]);
    integer w;
    begin
      for (w = 0; w < n; w = w + 1)
        sldu_preload(vaddr_t'(ara_pkg::vaddr(vid, NrLanes, VLEN) + w), words[w]);
    end
  endtask

  function automatic elen_t vrf_peek(input [4:0] vid, input integer w);
    integer addr, bank, row;
    begin
      addr = ara_pkg::vaddr(vid, NrLanes, VLEN) + w;
      bank = addr % 8;
      row  = addr / 8;
      case (bank)
        0: vrf_peek = dut.i_vrf.gen_banks[0].data_sram.sram[row];
        1: vrf_peek = dut.i_vrf.gen_banks[1].data_sram.sram[row];
        2: vrf_peek = dut.i_vrf.gen_banks[2].data_sram.sram[row];
        3: vrf_peek = dut.i_vrf.gen_banks[3].data_sram.sram[row];
        4: vrf_peek = dut.i_vrf.gen_banks[4].data_sram.sram[row];
        5: vrf_peek = dut.i_vrf.gen_banks[5].data_sram.sram[row];
        6: vrf_peek = dut.i_vrf.gen_banks[6].data_sram.sram[row];
        7: vrf_peek = dut.i_vrf.gen_banks[7].data_sram.sram[row];
      endcase
    end
  endfunction

  // =====================================================================
  // The testbench plays the SCALAR CORE + LOAD/STORE UNIT:
  //  - `mem` is main memory (byte addressable, little-endian words)
  //  - vle()  : memory -> vector register  (written through lane.sv's real
  //             sldu_result_* VRF write port)
  //  - vse()  : vector register -> memory  (passive bank-aware VRF peek)
  //  - exec() : issues ONE real VPQC_* vector instruction through
  //             pe_req_i -> lane_sequencer -> operand_requester -> vfu_pqc
  //             -> VRF write path and waits for its vinsn_done.
  //  - scalar byte stores (building hash inputs such as rho||j||i) are done
  //    directly on `mem`.
  // All cryptographic computation happens inside vfu_pqc.sv.
  // =====================================================================
  reg [7:0] mem [0:262143];

  localparam [4:0] RA = 5'd8, RB = 5'd16, RD = 5'd24;

  // ---- memory map (byte addresses) ----
  localparam int M_SCR   = 0;        // hash input scratch (<=1200 B)
  localparam int M_SCR2  = 2048;     // z||ct scratch (1120 B)
  localparam int M_XOFB  = 4096;     // 840 B
  localparam int M_PRFB  = 5120;     // 128 B
  localparam int M_GB    = 5376;     // 64 B  G output
  localparam int M_HB    = 5504;     // 32 B
  localparam int M_MPB   = 5632;     // 32 B  m'
  localparam int M_RKB   = 5760;     // 32 B rk + 8 B fail word
  localparam int M_KPB   = 5888;     // 32 B kprime + 8 B pad
  localparam int M_SSB   = 6016;     // 32 B
  localparam int M_ABASE = 16384;    // 9 polys (+ctr slack)
  localparam int M_NBASE = 24576;    // 7 noise polys
  localparam int M_SNB   = 32768;    // NTT(s)  3 polys
  localparam int M_ENB   = 36864;    // NTT(e)  3 polys
  localparam int M_T1    = 40960;
  localparam int M_T2    = 41984;
  localparam int M_T3    = 43008;
  localparam int M_PKPV  = 45056;    // 3 polys
  localparam int M_KB    = 49152;    // frommsg poly
  localparam int M_SPN   = 50176;    // 3 polys
  localparam int M_BRAW  = 54272;    // 3 polys
  localparam int M_VRAW  = 58368;
  localparam int M_BADD  = 59392;    // 3 polys
  localparam int M_VADD  = 63488;
  localparam int M_CTP   = 64512;    // (pvcomp+pcomp) ciphertext work area (1088 B + slack)
  localparam int M_SKPV  = 70656;
  localparam int M_BVEC  = 74752;
  localparam int M_VPOLY = 78848;
  localparam int M_BNB   = 79872;
  // external buffers
  localparam int M_KG_D  = 100000, M_KG_Z = 100064;
  localparam int M_PK_O  = 101000;   // 1184
  localparam int M_SK_O  = 103000;   // 2400
  localparam int M_M_IN  = 106000;
  localparam int M_CT_E  = 107000;   // encaps ct out (1088)
  localparam int M_SS_E  = 108400;
  localparam int M_CT_IN = 109000;   // decaps ct in (1088)
  localparam int M_CT_CMP= 110400;
  localparam int M_SS_D  = 111800;
  localparam int M_FAILW = 112000;

  function automatic int nin(input ara_op_e op);
    case (op)
      VPQC_SHA3_512_33: nin = 5;   VPQC_SHA3_512_64: nin = 8;   VPQC_SHA3_256_PK: nin = 148;
      VPQC_SHAKE128_XOF: nin = 5;  VPQC_SHAKE256_PRF: nin = 5;  VPQC_SHAKE256_RK: nin = 140;
      VPQC_CBD2: nin = 16;
      VPQC_NTT, VPQC_INVNTT, VPQC_REDUCE, VPQC_TOMONT, VPQC_PADD, VPQC_PSUB: nin = 64;
      VPQC_BASEMUL_ACC: nin = 192;  VPQC_REJ: nin = 105;
      VPQC_TOBYTES: nin = 192;      VPQC_FROMBYTES: nin = 144;
      VPQC_PVCOMP: nin = 192;       VPQC_PVDECOMP: nin = 120;
      VPQC_PCOMP: nin = 64;         VPQC_PDECOMP: nin = 16;
      VPQC_FROMMSG: nin = 4;        VPQC_TOMSG: nin = 64;
      VPQC_CTVERIFY: nin = 136;     VPQC_CMOV: nin = 5;
      default: nin = 1;
    endcase
  endfunction
  function automatic int nout(input ara_op_e op);
    case (op)
      VPQC_SHA3_512_33: nout = 8;  VPQC_SHA3_512_64: nout = 8;  VPQC_SHA3_256_PK: nout = 4;
      VPQC_SHAKE128_XOF: nout = 105; VPQC_SHAKE256_PRF: nout = 16; VPQC_SHAKE256_RK: nout = 4;
      VPQC_CBD2: nout = 64;
      VPQC_NTT, VPQC_INVNTT, VPQC_REDUCE, VPQC_TOMONT, VPQC_PADD, VPQC_PSUB, VPQC_BASEMUL_ACC: nout = 64;
      VPQC_REJ: nout = 65;
      VPQC_TOBYTES: nout = 144;    VPQC_FROMBYTES: nout = 192;
      VPQC_PVCOMP: nout = 120;     VPQC_PVDECOMP: nout = 192;
      VPQC_PCOMP: nout = 16;       VPQC_PDECOMP: nout = 64;
      VPQC_FROMMSG: nout = 64;     VPQC_TOMSG: nout = 4;
      VPQC_CTVERIFY: nout = 1;     VPQC_CMOV: nout = 4;
      default: nout = 1;
    endcase
  endfunction

  longint unsigned pqc_cycles, n_instr, vmem_words;
  integer disp_li;
  // like dispatch_and_wait but with a larger timeout and cycle accounting
  task exec(input ara_op_e op, input [4:0] vs2, input [4:0] vs1, input [4:0] vd,
            input use_vs1_i, input int nwords_local);
    begin
      pe_req               = '0;
      pe_req.id            = vid_t'(0);
      pe_req.op            = op;
      pe_req.vfu           = VFU_Pqc;
      pe_req.vm            = 1'b1;
      pe_req.vs2           = vs2;  pe_req.use_vs2 = 1'b1;  pe_req.eew_vs2 = EW64;
      pe_req.vs1           = vs1;  pe_req.use_vs1 = use_vs1_i;  pe_req.eew_vs1 = EW64;
      pe_req.vd            = vd;   pe_req.use_vd  = 1'b1;
      pe_req.vl            = vlen_t'(nwords_local * NrLanes);
      pe_req.vstart        = vlen_t'(0);
      pe_req.vtype.vsew    = EW64;
      pe_req.vtype.vlmul   = LMUL_1;
      pe_req_valid_i = 1'b1;
      begin : wait_done
        for (disp_li = 0; disp_li < 400000; disp_li = disp_li + 1) begin
          @(negedge clk);
          if (disp_li == 4) pe_req_valid_i = 1'b0;
          if (pe_resp.vinsn_done[0]) begin
            pqc_cycles = pqc_cycles + disp_li + 1;
            disable wait_done;
          end
        end
        $display("RESULT: FAIL -- vinsn_done never seen for op=%0d", op);
        $finish;
      end
      pe_req_valid_i = 1'b0;
      repeat (2) @(negedge clk);
      n_instr = n_instr + 1;
    end
  endtask

  integer vl_w;
  task vle(input [4:0] vid, input int base, input int nw);
    elen_t wd;
    begin
      for (vl_w = 0; vl_w < nw; vl_w = vl_w + 1) begin
        wd = {mem[base+8*vl_w+7], mem[base+8*vl_w+6], mem[base+8*vl_w+5], mem[base+8*vl_w+4],
              mem[base+8*vl_w+3], mem[base+8*vl_w+2], mem[base+8*vl_w+1], mem[base+8*vl_w+0]};
        sldu_preload(vaddr_t'(ara_pkg::vaddr(vid, NrLanes, VLEN) + vl_w), wd);
      end
      vmem_words = vmem_words + nw;
    end
  endtask

  integer vs_w;
  task vse(input [4:0] vid, input int base, input int nw);
    elen_t wd;
    begin
      for (vs_w = 0; vs_w < nw; vs_w = vs_w + 1) begin
        wd = vrf_peek(vid, vs_w);
        mem[base+8*vs_w+0] = wd[7:0];    mem[base+8*vs_w+1] = wd[15:8];
        mem[base+8*vs_w+2] = wd[23:16];  mem[base+8*vs_w+3] = wd[31:24];
        mem[base+8*vs_w+4] = wd[39:32];  mem[base+8*vs_w+5] = wd[47:40];
        mem[base+8*vs_w+6] = wd[55:48];  mem[base+8*vs_w+7] = wd[63:56];
      end
      vmem_words = vmem_words + nw;
    end
  endtask

  // vle vs2 [, vle vs1], exec, vse vd -- one "vector instruction with its loads/store"
  task vop(input ara_op_e op, input int a_addr, input int b_addr, input int d_addr);
    logic ub;
    begin
      ub = pqc_uses_vs1(op);
      vle(RA, a_addr, nin(op));
      if (ub) vle(RB, b_addr, nin(op));
      exec(op, RA, RB, RD, ub, nin(op));
      vse(RD, d_addr, nout(op));
    end
  endtask

  // scalar byte helpers
  integer cp_i;
  task mcopy(input int dst, input int src, input int n);
    begin for (cp_i = 0; cp_i < n; cp_i = cp_i + 1) mem[dst+cp_i] = mem[src+cp_i]; end
  endtask
  task mzero(input int dst, input int n);
    begin for (cp_i = 0; cp_i < n; cp_i = cp_i + 1) mem[dst+cp_i] = 8'h00; end
  endtask
  integer pb_i;
  task put_bytes(input int dst, input [8*2400-1:0] data, input int n);
    begin for (pb_i = 0; pb_i < n; pb_i = pb_i + 1) mem[dst+pb_i] = data[8*pb_i +: 8]; end
  endtask
  integer cm_i, cm_e;
  function automatic int cmp_bytes(input int addr, input [8*2400-1:0] data, input int n);
    int e;
    begin
      e = 0;
      for (cm_i = 0; cm_i < n; cm_i = cm_i + 1)
        if (mem[addr+cm_i] !== data[8*cm_i +: 8]) e = e + 1;
      cmp_bytes = e;
    end
  endfunction

  reg [4095:0] rn_in; reg rn_start = 0; wire [4095:0] rn_out; wire rn_done;
  ntt_fwd ref_ntt (.clk(clk), .rst_n(rst_n), .start_i(rn_start), .coeffs_in(rn_in), .coeffs_out(rn_out), .done(rn_done));
  integer rn_i;
  task ref_ntt_check(input int src, input int dst);
    int er;
    begin
      for (rn_i = 0; rn_i < 512; rn_i = rn_i + 1) rn_in[8*rn_i +: 8] = mem[src+rn_i];
      rn_start = 1; @(negedge clk); rn_start = 0; wait (rn_done); @(negedge clk);
      er = 0;
      for (rn_i = 0; rn_i < 512; rn_i = rn_i + 1) if (mem[dst+rn_i] !== rn_out[8*rn_i +: 8]) er = er + 1;
      show("  T1(ara)", dst);
      $display("  ref_ntt out[63:0]=%h  rn_in[63:0]=%h", rn_out[63:0], rn_in[63:0]);
      $display("DBG NTT src@%0d -> dst@%0d : %0d byte mismatches vs reference ntt_fwd (dst first=%h%h ref first=%h%h)", src, dst, er, mem[dst+1], mem[dst], rn_out[15:8], rn_out[7:0]);
    end
  endtask
  int a_fails; bit dbg = 0;
  integer ck_i;
  task show(input string name, input int addr);
    logic [63:0] a;
    begin
      a = 0;
      for (ck_i = 0; ck_i < 512; ck_i = ck_i + 1) a = a*31 + mem[addr+ck_i];
      $display("%s first=%h%h%h%h%h%h%h%h cks=%h", name, mem[addr+7],mem[addr+6],mem[addr+5],mem[addr+4],mem[addr+3],mem[addr+2],mem[addr+1],mem[addr+0], a);
    end
  endtask
  task check_ctr(input int polyaddr);
    begin
      // REJ's 65th word (ctr) sits just past the polynomial
      if ({mem[polyaddr+513], mem[polyaddr+512]} !== 16'd256) a_fails = a_fails + 1;
    end
  endtask

  // ------------------------------------------------------------------
  // KeyGen:   d(32B)@M_KG_D, z(32B)@M_KG_Z  ->  pk@M_PK_O (1184 B), sk@M_SK_O (2400 B)
  // ------------------------------------------------------------------
  int kg_i, kg_j, kg_n;
  task prog_keygen;
    begin
      mcopy(M_SCR, M_KG_D, 32); mem[M_SCR+32] = 8'd3;
      vop(VPQC_SHA3_512_33, M_SCR, 0, M_GB);                 // rho = M_GB[0..31], sigma = M_GB[32..63]
      if (dbg) $display("DBG rho mismatches vs pk tail: %0d ; mem=%h %h %h %h ref=%h %h %h %h", cmp_ref(M_GB, R_PK+1152, 32), mem[M_GB],mem[M_GB+1],mem[M_GB+2],mem[M_GB+3], refm[R_PK+1152],refm[R_PK+1153],refm[R_PK+1154],refm[R_PK+1155]);
      for (kg_i = 0; kg_i < 3; kg_i = kg_i + 1)
        for (kg_j = 0; kg_j < 3; kg_j = kg_j + 1) begin
          mcopy(M_SCR, M_GB, 32); mem[M_SCR+32] = kg_j[7:0]; mem[M_SCR+33] = kg_i[7:0];
          vop(VPQC_SHAKE128_XOF, M_SCR, 0, M_XOFB);
          vop(VPQC_REJ, M_XOFB, 0, M_ABASE + (3*kg_i+kg_j)*512);
          check_ctr(M_ABASE + (3*kg_i+kg_j)*512);
        end
      for (kg_n = 0; kg_n < 6; kg_n = kg_n + 1) begin
        mcopy(M_SCR, M_GB+32, 32); mem[M_SCR+32] = kg_n[7:0];
        vop(VPQC_SHAKE256_PRF, M_SCR, 0, M_PRFB);
        vop(VPQC_CBD2, M_PRFB, 0, M_NBASE + kg_n*512);
      end
      for (kg_i = 0; kg_i < 3; kg_i = kg_i + 1) begin
        vop(VPQC_NTT,    M_NBASE + kg_i*512,       0, M_T1);
        if (dbg && kg_i==0) ref_ntt_check(M_NBASE, M_T1);
        vop(VPQC_REDUCE, M_T1,                     0, M_SNB + kg_i*512);
        vop(VPQC_NTT,    M_NBASE + (3+kg_i)*512,   0, M_T1);
        vop(VPQC_REDUCE, M_T1,                     0, M_ENB + kg_i*512);
      end
      for (kg_i = 0; kg_i < 3; kg_i = kg_i + 1) begin
        vop(VPQC_BASEMUL_ACC, M_ABASE + 3*kg_i*512, M_SNB, M_T1);
        vop(VPQC_TOMONT, M_T1, 0, M_T2);
        vop(VPQC_PADD, M_T2, M_ENB + kg_i*512, M_T3);
        vop(VPQC_REDUCE, M_T3, 0, M_PKPV + kg_i*512);
      end
      vop(VPQC_TOBYTES, M_SNB,  0, M_SK_O);                   // sk[0..1151] = tobytes(NTT(s))
      vop(VPQC_TOBYTES, M_PKPV, 0, M_PK_O);                   // pk[0..1151]
      mcopy(M_PK_O + 1152, M_GB, 32);                         // pk[1152..1183] = rho
      mcopy(M_SK_O + 1152, M_PK_O, 1184);
      vop(VPQC_SHA3_256_PK, M_PK_O, 0, M_SK_O + 2336);        // H(pk)
      mcopy(M_SK_O + 2368, M_KG_Z, 32);
      if (dbg) begin
        show("A0", M_ABASE); show("A4", M_ABASE+4*512); show("A8", M_ABASE+8*512);
        show("N0", M_NBASE); show("N3", M_NBASE+3*512); show("N5", M_NBASE+5*512);
        show("SN0", M_SNB); show("SN2", M_SNB+2*512); show("EN0", M_ENB); show("EN2", M_ENB+2*512);
        show("PKV0", M_PKPV); show("PKV2", M_PKPV+2*512);
      end
    end
  endtask

  // ------------------------------------------------------------------
  // IND-CPA encrypt: pk@pk_a, m@m_a, coins@c_a -> ct@ct_a (1088 B)
  // ------------------------------------------------------------------
  int ie_i, ie_j, ie_n;
  task prog_indcpa_enc(input int pk_a, input int m_a, input int c_a, input int ct_a);
    begin
      vop(VPQC_FROMBYTES, pk_a, 0, M_PKPV);
      vop(VPQC_FROMMSG,   m_a,  0, M_KB);
      for (ie_i = 0; ie_i < 3; ie_i = ie_i + 1)
        for (ie_j = 0; ie_j < 3; ie_j = ie_j + 1) begin
          mcopy(M_SCR, pk_a + 1152, 32); mem[M_SCR+32] = ie_i[7:0]; mem[M_SCR+33] = ie_j[7:0];
          vop(VPQC_SHAKE128_XOF, M_SCR, 0, M_XOFB);
          vop(VPQC_REJ, M_XOFB, 0, M_ABASE + (3*ie_i+ie_j)*512);
          check_ctr(M_ABASE + (3*ie_i+ie_j)*512);
        end
      for (ie_n = 0; ie_n < 7; ie_n = ie_n + 1) begin
        mcopy(M_SCR, c_a, 32); mem[M_SCR+32] = ie_n[7:0];
        vop(VPQC_SHAKE256_PRF, M_SCR, 0, M_PRFB);
        vop(VPQC_CBD2, M_PRFB, 0, M_NBASE + ie_n*512);
      end
      for (ie_i = 0; ie_i < 3; ie_i = ie_i + 1) begin
        vop(VPQC_NTT, M_NBASE + ie_i*512, 0, M_T1);
        vop(VPQC_REDUCE, M_T1, 0, M_SPN + ie_i*512);
      end
      for (ie_i = 0; ie_i < 3; ie_i = ie_i + 1)
        vop(VPQC_BASEMUL_ACC, M_ABASE + 3*ie_i*512, M_SPN, M_BRAW + ie_i*512);
      vop(VPQC_BASEMUL_ACC, M_PKPV, M_SPN, M_VRAW);
      for (ie_i = 0; ie_i < 3; ie_i = ie_i + 1) begin
        vop(VPQC_INVNTT, M_BRAW + ie_i*512, 0, M_T1);
        vop(VPQC_PADD, M_T1, M_NBASE + (3+ie_i)*512, M_T2);
        vop(VPQC_REDUCE, M_T2, 0, M_BADD + ie_i*512);
      end
      vop(VPQC_INVNTT, M_VRAW, 0, M_T1);
      vop(VPQC_PADD, M_T1, M_NBASE + 6*512, M_T2);
      vop(VPQC_PADD, M_T2, M_KB, M_T3);
      vop(VPQC_REDUCE, M_T3, 0, M_VADD);
      vop(VPQC_PVCOMP, M_BADD, 0, ct_a);                    // 960 B
      vop(VPQC_PCOMP,  M_VADD, 0, ct_a + 960);              // 128 B
    end
  endtask

  // Encaps: pk@M_PK_O, m@M_M_IN -> ct@M_CT_E, ss@M_SS_E
  task prog_encaps;
    begin
      vop(VPQC_SHA3_256_PK, M_PK_O, 0, M_HB);
      mcopy(M_SCR, M_M_IN, 32); mcopy(M_SCR+32, M_HB, 32);
      vop(VPQC_SHA3_512_64, M_SCR, 0, M_GB);                  // kr = G(m||H(pk))
      mcopy(M_SS_E, M_GB, 32);
      prog_indcpa_enc(M_PK_O, M_M_IN, M_GB + 32, M_CT_E);
    end
  endtask

  // Decaps: sk@M_SK_O, ct@M_CT_IN -> ss@M_SS_D
  int dc_i;
  task prog_decaps;
    begin
      vop(VPQC_FROMBYTES, M_SK_O, 0, M_SKPV);
      vop(VPQC_PVDECOMP, M_CT_IN, 0, M_BVEC);
      vop(VPQC_PDECOMP, M_CT_IN + 960, 0, M_VPOLY);
      for (dc_i = 0; dc_i < 3; dc_i = dc_i + 1) begin
        vop(VPQC_NTT, M_BVEC + dc_i*512, 0, M_T1);
        vop(VPQC_REDUCE, M_T1, 0, M_BNB + dc_i*512);
      end
      vop(VPQC_BASEMUL_ACC, M_SKPV, M_BNB, M_T1);
      vop(VPQC_INVNTT, M_T1, 0, M_T2);
      vop(VPQC_PSUB, M_VPOLY, M_T2, M_T3);
      vop(VPQC_REDUCE, M_T3, 0, M_T1);
      vop(VPQC_TOMSG, M_T1, 0, M_MPB);                        // m'
      mcopy(M_SCR, M_MPB, 32); mcopy(M_SCR+32, M_SK_O + 2336, 32);
      vop(VPQC_SHA3_512_64, M_SCR, 0, M_GB);                  // kr' = G(m'||h)
      prog_indcpa_enc(M_SK_O + 1152, M_MPB, M_GB + 32, M_CT_CMP);
      vop(VPQC_CTVERIFY, M_CT_IN, M_CT_CMP, M_FAILW);
      mcopy(M_SCR2, M_SK_O + 2368, 32); mcopy(M_SCR2 + 32, M_CT_IN, 1088);
      vop(VPQC_SHAKE256_RK, M_SCR2, 0, M_RKB);
      mcopy(M_RKB + 32, M_FAILW, 8);                          // rk(32B) || fail word
      mcopy(M_KPB, M_GB, 32); mzero(M_KPB + 32, 8);
      vop(VPQC_CMOV, M_RKB, M_KPB, M_SSB);
      mcopy(M_SS_D, M_SSB, 32);
    end
  endtask

  // ------------------------------------------------------------------
  // Reference data (byte arrays; Verilator limits $fscanf %h to 8192 bits, so hex is parsed by hand)
  reg [7:0] refm [0:16383];
  localparam int R_COINS=0, R_M=100, R_PK=200, R_SK=1500, R_CT=4000, R_CTBAD=5200, R_CTBAD2=6400,
                 R_SS=7600, R_SSDEC=7700, R_SSBAD=7800, R_SSBAD2=7900;
  reg [7:0] tmpb [0:4095];
  integer tmpn;
  integer ch, hv, hi_nib, have_hi, k, nn;
  task read_hex_field(input int dst);
    begin
      tmpn = 0; have_hi = 0; ch = 32;
      while (ch == 32 || ch == 10 || ch == 13 || ch == 9) ch = $fgetc(fd);
      while ((ch >= 48 && ch <= 57) || (ch >= 97 && ch <= 102) || (ch >= 65 && ch <= 70)) begin
        hv = (ch <= 57) ? ch - 48 : ((ch >= 97) ? ch - 87 : ch - 55);
        if (!have_hi) begin hi_nib = hv; have_hi = 1; end
        else begin tmpb[tmpn] = {hi_nib[3:0], hv[3:0]}; tmpn = tmpn + 1; have_hi = 0; end
        ch = $fgetc(fd);
      end
      // file is byte-reversed: last pair on the line is byte 0
      for (k = 0; k < tmpn; k = k + 1) refm[dst + k] = tmpb[tmpn - 1 - k];
    end
  endtask
  task put_ref(input int dst, input int src, input int n);
    begin for (cp_i = 0; cp_i < n; cp_i = cp_i + 1) mem[dst+cp_i] = refm[src+cp_i]; end
  endtask
  integer cr_i;
  function automatic int cmp_ref(input int maddr, input int raddr, input int n);
    int er;
    begin
      er = 0;
      for (cr_i = 0; cr_i < n; cr_i = cr_i + 1)
        if (mem[maddr+cr_i] !== refm[raddr+cr_i]) er = er + 1;
      cmp_ref = er;
    end
  endfunction

  reg [8*100-1:0] tag;  reg [8*200-1:0] vecfile;
  integer fd, rr, errs, e;
  longint unsigned c0;

  initial begin
    if ($test$plusargs("dbg")) dbg = 1;
    pqc_cycles = 0; n_instr = 0; vmem_words = 0; a_fails = 0; errs = 0;
    if (!$value$plusargs("vec=%s", vecfile)) vecfile = "vectors/vecs_kemtop/kem_vec_1.txt";
    fd = $fopen(vecfile, "r");
    if (fd == 0) begin $display("RESULT: FAIL -- cannot open %0s", vecfile); $finish; end
    while (!$feof(fd)) begin
      rr = $fscanf(fd, "%s", tag);
      if      (tag == "COINS")  read_hex_field(R_COINS);
      else if (tag == "M")      read_hex_field(R_M);
      else if (tag == "PK")     read_hex_field(R_PK);
      else if (tag == "SK")     read_hex_field(R_SK);
      else if (tag == "CT")     read_hex_field(R_CT);
      else if (tag == "SSDEC")  read_hex_field(R_SSDEC);
      else if (tag == "SSBAD2") read_hex_field(R_SSBAD2);
      else if (tag == "SSBAD")  read_hex_field(R_SSBAD);
      else if (tag == "SS")     read_hex_field(R_SS);
      else if (tag == "CTBAD2") read_hex_field(R_CTBAD2);
      else if (tag == "CTBAD")  read_hex_field(R_CTBAD);
    end
    $fclose(fd);
    if (refm[R_PK] === 8'hxx || refm[R_SK] === 8'hxx || refm[R_CT] === 8'hxx || refm[R_SSBAD2] === 8'hxx) begin
      $display("RESULT: FAIL -- vector file not parsed (vacuous-pass guard)"); $finish;
    end

    rst_n = 1'b0;
    repeat (4) @(negedge clk);
    rst_n = 1'b1;
    repeat (2) @(negedge clk);

    // ---------------- KEYGEN ----------------
    put_ref(M_KG_D, R_COINS, 32);  put_ref(M_KG_Z, R_COINS+32, 32);
    c0 = pqc_cycles;
    prog_keygen;
    e = cmp_ref(M_PK_O, R_PK, 1184);
    if (e) begin errs = errs + 1; $display("KEYGEN pk: %0d byte mismatches", e); end else $display("KEYGEN pk (1184 B) byte-exact vs reference");
    e = cmp_ref(M_SK_O, R_SK, 2400);
    if (e) begin errs = errs + 1; $display("KEYGEN sk: %0d byte mismatches", e); end else $display("KEYGEN sk (2400 B) byte-exact vs reference");
    $display("  keygen: PQC-unit busy cycles = %0d  (vector instrs so far = %0d)", pqc_cycles - c0, n_instr);

    // ---------------- ENCAPS (consumes the pk the Ara program just produced) ----------------
    put_ref(M_M_IN, R_M, 32);
    c0 = pqc_cycles;
    prog_encaps;
    e = cmp_ref(M_CT_E, R_CT, 1088);
    if (e) begin errs = errs + 1; $display("ENCAPS ct: %0d byte mismatches", e); end else $display("ENCAPS ct (1088 B) byte-exact vs reference");
    e = cmp_ref(M_SS_E, R_SS, 32);
    if (e) begin errs = errs + 1; $display("ENCAPS ss: %0d byte mismatches", e); end else $display("ENCAPS ss (32 B) byte-exact vs reference");
    $display("  encaps: PQC-unit busy cycles = %0d", pqc_cycles - c0);

    // ---------------- DECAPS valid (consumes Ara's sk and Ara's ct) ----------------
    mcopy(M_CT_IN, M_CT_E, 1088);
    c0 = pqc_cycles;
    prog_decaps;
    e = cmp_ref(M_SS_D, R_SSDEC, 32);
    if (e) begin errs = errs + 1; $display("DECAPS(valid) ss != reference"); end else $display("DECAPS(valid) ss byte-exact vs reference");
    e = 0; for (cm_e = 0; cm_e < 32; cm_e = cm_e + 1) if (mem[M_SS_D+cm_e] !== mem[M_SS_E+cm_e]) e = e + 1;
    if (e) begin errs = errs + 1; $display("DECAPS(valid) ss != ENCAPS ss"); end else $display("DECAPS(valid) ss == ENCAPS ss  (KEM round trip closes on the Ara program)");
    $display("  decaps: PQC-unit busy cycles = %0d", pqc_cycles - c0);

    // ---------------- DECAPS tampered ----------------
    put_ref(M_CT_IN, R_CTBAD, 1088);
    prog_decaps;
    e = cmp_ref(M_SS_D, R_SSBAD, 32);
    if (e) begin errs = errs + 1; $display("DECAPS(tampered b-part) ss != reference reject key"); end else $display("DECAPS(tampered b-part) -> reference implicit-rejection key");
    put_ref(M_CT_IN, R_CTBAD2, 1088);
    prog_decaps;
    e = cmp_ref(M_SS_D, R_SSBAD2, 32);
    if (e) begin errs = errs + 1; $display("DECAPS(tampered v-part) ss != reference reject key"); end else $display("DECAPS(tampered v-part) -> reference implicit-rejection key");

    if (a_fails) begin errs = errs + 1; $display("rejection sampling ctr != 256 in %0d polys", a_fails); end
    $display("totals: %0d vector instructions, %0d PQC-unit busy cycles, %0d words moved by modeled vle/vse", n_instr, pqc_cycles, vmem_words);
    if (errs == 0)
      $display("RESULT: Ara lane KEM program PASS -- keygen, encaps, decaps (valid + 2 tampered) executed as VPQC vector-instruction sequences on the real lane.sv, byte-exact vs reference (%0s)", vecfile);
    else
      $display("RESULT: Ara lane KEM program FAIL -- %0d problems (%0s)", errs, vecfile);
    $finish;
  end
endmodule
