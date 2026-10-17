#!/usr/bin/env bash
# Builds the real Ara lane.sv (patched clone expected at /tmp/ara_src) and runs the ML-KEM program on it.
exec bash "$(dirname "$0")/../ara_integration/verilator_kem_program_recipe.sh" "$@"
