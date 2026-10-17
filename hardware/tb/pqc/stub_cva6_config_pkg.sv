// stub_cva6_config_pkg.sv -- NOT part of the PQC integration design.
//
// Ara takes `config_pkg::cva6_cfg_t` as an opaque pass-through parameter
// (default `cva6_config_pkg::cva6_cfg`) on `vector_fus_stage`/`vmfpu`/`lane`,
// only to forward it unmodified into `fpnew_top` deeper inside `vmfpu.sv`
// (confirmed by grep: nothing in Ara's own lane/ files reads a field off
// CVA6Cfg directly). The real `pulp-platform/cva6` package is thousands of
// lines, templated by a SystemC/Python config generator, and is a genuinely
// separate large repository (pulp-v2 branch, per Ara's own Bender.lock), so
// it is stubbed here rather than cloned and generated for these testbenches.
//
// This stub supplies the minimum real shape fpnew_top actually reads out of
// CVA6Cfg (its `FpuFeatures`- and `FpuImplementation`-shaped fields go
// through Ara's own `fpu_support_e`/`fpnew_pkg` parameters instead -- CVA6Cfg
// itself is NOT read field-by-field anywhere in the files this integration
// touches or in fpnew_top's instantiation inside vmfpu.sv), so an empty
// struct with the right name is sufficient to let the real files elaborate.
// This is a real, load-bearing gap: it means fpnew_top elaborates against a
// fabricated config type, not CVA6's real one. See ARA_INTEGRATION.md.

package config_pkg;
  typedef struct packed {
    logic dummy;
  } cva6_cfg_t;
endpackage

package cva6_config_pkg;
  import config_pkg::*;
  localparam cva6_cfg_t cva6_cfg = '{dummy: 1'b0};
endpackage
