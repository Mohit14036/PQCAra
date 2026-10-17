// stub_riscv_axi_pkg.sv -- NOT part of the PQC integration design.
//
// `riscv` (CVA6's RISC-V CSR/instruction-encoding package) and `axi_pkg`
// (pulp-platform/axi) are real external packages Ara's own ara_pkg.sv /
// rvv_pkg.sv depend on for things entirely unrelated to this PQC
// extension (standard Vector-extension CSR addresses, the I-type
// instruction encoding, and one AXI request struct used by Ara's
// load/store address generator, not by the lane datapath this
// integration touches). Only the handful of symbols rvv_pkg.sv/ara_pkg.sv
// actually reference are stubbed here, with their real, spec-defined
// values (RISC-V "V" extension CSR addresses per the ratified vector
// spec; the standard 32-bit I-type field layout; AXI4 size/len/addr
// widths per the AMBA AXI spec) rather than placeholders -- but this is
// still a hand-written stand-in for the real CVA6/axi packages, not those
// packages themselves. See stub_cva6_config_pkg.sv and
// ARA_INTEGRATION.md for why the real repos were not cloned in full.

package riscv;
  typedef logic [11:0] csr_reg_t;

  localparam csr_reg_t CSR_VSTART = 12'h008;
  localparam csr_reg_t CSR_VXSAT  = 12'h009;
  localparam csr_reg_t CSR_VXRM   = 12'h00A;
  localparam csr_reg_t CSR_VCSR   = 12'h00F;
  localparam csr_reg_t CSR_VL     = 12'hC20;
  localparam csr_reg_t CSR_VTYPE  = 12'hC21;
  localparam csr_reg_t CSR_VLENB  = 12'hC22;

  // Standard RISC-V I-type instruction encoding (32 bits)
  typedef struct packed {
    logic [31:20] imm;
    logic [19:15] rs1;
    logic [14:12] funct3;
    logic [11:7]  rd;
    logic [6:0]   opcode;
  } itype_t;
endpackage

package axi_pkg;
  typedef logic [63:0] largest_addr_t;
  typedef logic [2:0]  size_t;
  typedef logic [7:0]  len_t;
endpackage
