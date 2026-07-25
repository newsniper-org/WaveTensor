#!/bin/sh
# SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
#
# synth_fp_ops.sh — v1.8.0c per-operator synth gate harness (spec §23.10.7,
# merge blocker). Runs yosys + nextpnr-ecp5 standalone gates for the shared
# fp32 operator blocks on the exact Stage-1 target (LFE5UM-85F, CABGA381,
# --speed 6, out-of-context — same device/flow family as pnr_pod.sh).
#
#   GATE 1 — FP_Mul36   : <=4 MULT18X18D (hard fail on more), <=300 LUT4,
#                         Fmax >= 40 MHz
#   GATE 2 — FP_AddWide : <=900 LUT4, 0 MULT18X18D, Fmax >= 40 MHz
#   GATE C3 — FP_StepSeq: whole unit incl. both operator blocks + seed/coeff
#                         ROMs + the v1.8.0d OPS_CVT/OPS_ACCEW extension
#                         (spec 23.10.10(g)) + the v1.8.0e OPS_DEQ fused
#                         DEQUANT program (spec 25.2.2) — <=4909 LUT4
#                         (= 4,409 v1.8.0d C3 archive + the spec-25.5.1
#                         OPS_DEQ itemization nominal ceiling +500; delta
#                         recorded vs the +250-500 band, above +500 ->
#                         cut-ladder rung 3 two-pass reuse), EXACTLY 4
#                         MULT18X18D (0 new — the fused program rides the
#                         ONE FP_Mul36), <=900 FF (net of the 147 wrapper
#                         I/O flops), 0 EBR (distributed ROM; documented
#                         1-EBR fallback only), Fmax >= 40 MHz with a
#                         seed sweep 1-5 (archive = first passing seed —
#                         the 23.10.7 Gate-3 precedent showed 39.79 ->
#                         40.84 MHz is placement noise; the 0e re-run's
#                         failing-seed paths sit inside untouched
#                         FP_AddWide stages)
#
# Invoke from the repo root:
#     sh synth/lattice/scripts/synth_fp_ops.sh
#
# Reports are archived under synth/lattice/reports/fp_ops/ so the spec's
# hw_cost table cites measurements, not literature:
#     <name>_synth.rpt   yosys stat (LUT4 / MULT18X18D / TRELLIS_FF)
#     <name>_synth.json  netlist for nextpnr
#     <name>_pnr.rpt     nextpnr JSON report (fmax)
#     <name>_pnr.log     nextpnr log
#     gate_summary.txt   measured numbers + PASS/FAIL per gate criterion
#
# Flow notes:
#   * Plain `synth_ecp5` (no -run :check AUTONAME bypass): these blocks are
#     a few hundred cells, so the stock check/autoname tail that had to be
#     skipped for the ~2.5M-wire pod netlist (see synth_pod.ys) is cheap
#     here. If a future variant grows enough for AUTONAME to hurt, reuse
#     the synth_pod.ys manual tail (hierarchy -check; check -noinit;
#     blackbox =A:whitebox; tee stat; write_json).
#   * Each gate synthesizes core + a registration wrapper top
#     (synth/lattice/fp_ops/*_gate_top.v) so all measured paths are
#     FF-to-FF; the wrapper adds flops only (~0 LUT4).
#   * yosys 0.64 synth_ecp5 infers MULT18X18D by default (synth_lattice
#     -nodsp would disable it) — Gate 1's MULT count is measured under the
#     same inference the Cluster/Pod flow uses.

set -e

cd "$(dirname "$0")/../../.."

RPT=synth/lattice/reports/fp_ops
mkdir -p "$RPT"

DEVICE_ARGS="--um-85k --package CABGA381 --speed 6"
FREQ_MHZ=40

run_gate() {
    NAME="$1"
    TOP="$2"
    SRCS="$3"
    SEEDS="${4:-1}"

    echo "=== $NAME: yosys synth_ecp5 (top $TOP) ==="
    yosys -q -p "\
        read_verilog -defer -DWT_VENDOR_LATTICE_YOSYS -I include $SRCS; \
        hierarchy -check -top $TOP; \
        synth_ecp5; \
        tee -o $RPT/${NAME}_synth.rpt stat; \
        write_json $RPT/${NAME}_synth.json"

    # Seed sweep (spec 23.10.10(g): 1-5 allowed for the C3 Fmax line,
    # archive = the FIRST PASSING seed's report/log; single-seed gates
    # pass "1"). Each attempt overwrites the report files, so breaking on
    # the first pass leaves exactly the archived-seed artifacts in place.
    for SEED in $SEEDS; do
        echo "=== $NAME: nextpnr-ecp5 out-of-context @ ${FREQ_MHZ} MHz (seed $SEED) ==="
        # NOTE: no --textcfg — bitstream/textcfg generation is rejected in
        # --out-of-context mode (these gates only need the timing report).
        nextpnr-ecp5 \
            $DEVICE_ARGS \
            --json "$RPT/${NAME}_synth.json" \
            --out-of-context \
            --report "$RPT/${NAME}_pnr.rpt" \
            --freq $FREQ_MHZ \
            --timing-allow-fail \
            --seed $SEED \
            > "$RPT/${NAME}_pnr.log" 2>&1 || {
                tail -20 "$RPT/${NAME}_pnr.log"
                echo "$NAME: nextpnr FAILED — see $RPT/${NAME}_pnr.log"
                exit 1
            }
        FMAX_MET=$(python3 -c "import json,sys; \
r = json.load(open('$RPT/${NAME}_pnr.rpt')); \
print(1 if min(v['achieved'] for v in r['fmax'].values()) >= $FREQ_MHZ else 0)")
        if [ "$FMAX_MET" = "1" ]; then
            echo "$NAME: Fmax target met at seed $SEED (archived)"
            break
        fi
        echo "$NAME: Fmax below target at seed $SEED"
    done
}

run_gate fp_mul36 FP_Mul36_gate_top \
    "FP_Mul36.v synth/lattice/fp_ops/FP_Mul36_gate_top.v"

run_gate fp_addwide FP_AddWide_gate_top \
    "FP_AddWide.v synth/lattice/fp_ops/FP_AddWide_gate_top.v"

# Gate C3 reads the generated ROM/coefficient sidecars and the shared
# narrow function through the same -I include path (include/generated/*.vh
# + include/fp_narrow_f32.vh — localparam bit vectors synthesize as
# distributed LUT ROM, never EBR). Seed sweep 1-5 per 23.10.10(g).
run_gate fp_stepseq FP_StepSeq_gate_top \
    "FP_StepSeq.v FP_Mul36.v FP_AddWide.v synth/lattice/fp_ops/FP_StepSeq_gate_top.v" \
    "1 2 3 4 5"

# --- Evaluate the gate criteria from the measured reports -----------------
python3 synth/lattice/fp_ops/gate_check.py "$RPT"
