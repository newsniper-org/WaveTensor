#!/bin/sh
# SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
#
# synth_pe_core_gate.sh — v1.9 §26.6 GATE V9-3 standalone OOC synth harness.
#
# Runs PE_Core.v standalone (no Cluster, no wrapper) through yosys +
# nextpnr-ecp5 out-of-context, once for each geometry the case_result_s2
# split actually ships in:
#   MU-HOSTED   — MUL_OPS_SUPPORTED=1 DIV_OPS_SUPPORTED=0 NON_MUL_OPS_SUPPORTED=0
#                 (Cluster.v u_matmul_unit's exact parameterization)
#   LPE-NARROW  — MUL_OPS_SUPPORTED=0 DIV_OPS_SUPPORTED=0 NON_MUL_OPS_SUPPORTED=1
#                 (Cluster.v u_lpe's exact parameterization — 16 instances
#                 in a 4x4 grid; this gate measures ONE representative
#                 instance, per this project's own per-operator-gate
#                 precedent of measuring one unit, not N copies)
#
# Same device/flow family as synth_fp_ops.sh (LFE5UM-85F, CABGA381,
# --speed 6, out-of-context). Parameters are overridden post-hierarchy via
# `chparam` (PE_Core.v itself is not edited/duplicated for this).
#
# Invoke from the repo root:
#     sh synth/lattice/scripts/synth_pe_core_gate.sh

set -e

cd "$(dirname "$0")/../../.."

RPT=synth/lattice/reports/pe_core_gate
mkdir -p "$RPT"

DEVICE_ARGS="--um-85k --package CABGA381 --speed 6"
FREQ_MHZ=17.0

SRCS="PE_Core.v FP_StepSeq.v FP_Mul36.v FP_AddWide.v"

run_gate() {
    NAME="$1"
    MUL_SUP="$2"
    DIV_SUP="$3"
    NONMUL_SUP="$4"

    echo "=== $NAME: yosys synth_ecp5 (top PE_Core, MUL=$MUL_SUP DIV=$DIV_SUP NONMUL=$NONMUL_SUP) ==="
    yosys -q -p "\
        read_verilog -defer -sv -DWT_VENDOR_LATTICE_YOSYS -I include $SRCS; \
        hierarchy -top PE_Core; \
        chparam -set MUL_OPS_SUPPORTED $MUL_SUP -set DIV_OPS_SUPPORTED $DIV_SUP -set NON_MUL_OPS_SUPPORTED $NONMUL_SUP PE_Core; \
        hierarchy -check -top PE_Core; \
        synth_ecp5 -run :check; \
        hierarchy -check; \
        check -noinit; \
        blackbox =A:whitebox; \
        tee -o $RPT/${NAME}_synth.rpt stat; \
        write_json $RPT/${NAME}_synth.json"

    echo "=== $NAME: nextpnr-ecp5 out-of-context @ ${FREQ_MHZ} MHz ==="
    nextpnr-ecp5 \
        $DEVICE_ARGS \
        --json "$RPT/${NAME}_synth.json" \
        --out-of-context \
        --report "$RPT/${NAME}_pnr.rpt" \
        --freq $FREQ_MHZ \
        --timing-allow-fail \
        --seed 1 \
        > "$RPT/${NAME}_pnr.log" 2>&1 || {
            tail -30 "$RPT/${NAME}_pnr.log"
            echo "$NAME: nextpnr FAILED — see $RPT/${NAME}_pnr.log"
            exit 1
        }
    echo "$NAME: done."
}

run_gate "pe_core_mu_hosted" 1 0 0
run_gate "pe_core_lpe_narrow" 0 0 1

echo "=== GATE V9-3 done. Reports under $RPT/ ==="
