// stub_serdiv.sv -- NOT part of the PQC integration design.
//
// `serdiv` is CVA6's serial integer divider (pulp-platform/cva6, ariane_pkg
// / fu/serdiv.sv), pulled in transitively by Ara's simd_div.sv (used by the
// MFPU VFU's integer divide instructions, not by anything the PQC VFU
// touches). It is stubbed here so the PQC lane testbenches build without
// cloning the full CVA6 repo to reach this one file (see
// stub_cva6_config_pkg.sv).
//
// This is a behavioral stand-in with serdiv's real, publicly-documented
// port list (clk_i/rst_ni/id_i/op_a_i/op_b_i/opcode_i/in_vld_i/in_rdy_o/
// flush_i/out_vld_o/out_rdy_i/id_o/res_o), sized by the WIDTH parameter
// simd_div.sv passes it. It is NOT cycle-accurate or algorithmically
// faithful to the real iterative divider -- it exists only so the real
// Ara files that reference it (which the PQC VFU does not exercise) can
// elaborate. No PQC-path claim in ARA_INTEGRATION.md relies on this file.
module serdiv #(
    parameter config_pkg::cva6_cfg_t CVA6Cfg          = cva6_config_pkg::cva6_cfg,
    parameter int unsigned            WIDTH            = 64,
    parameter bit                     STABLE_HANDSHAKE = 0,
    parameter type                    id_t             = logic [3:0]
  ) (
    input  logic             clk_i,
    input  logic             rst_ni,
    input  id_t               id_i,
    input  logic [WIDTH-1:0]  op_a_i,
    input  logic [WIDTH-1:0]  op_b_i,
    input  logic [1:0]        opcode_i,
    input  logic              in_vld_i,
    output logic              in_rdy_o,
    input  logic              flush_i,
    output logic              out_vld_o,
    input  logic              out_rdy_i,
    output id_t                id_o,
    output logic [WIDTH-1:0]  res_o
  );
    assign in_rdy_o = out_rdy_i;
    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        out_vld_o <= 1'b0;
        res_o     <= '0;
        id_o      <= '0;
      end else if (flush_i) begin
        out_vld_o <= 1'b0;
      end else if (in_vld_i && in_rdy_o) begin
        out_vld_o <= 1'b1;
        id_o      <= id_i;
        res_o     <= (op_b_i == '0) ? '1 : (op_a_i / op_b_i);
      end else if (out_vld_o && out_rdy_i) begin
        out_vld_o <= 1'b0;
      end
    end
endmodule
