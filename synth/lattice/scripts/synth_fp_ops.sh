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
#   GATE F1 — FP_FmaLaneBf16 (v2.0 TRAIN, spec §23.1): the unified bf16/f16
#                         fused-FMA lane — <=1300 LUT4 (= the 894 LUT4
#                         Gate-2 FP_AddWide archive, which this lane
#                         instantiates VERBATIM, + a 406 LUT4 nominal
#                         ceiling for the narrow unpack/classify, the f16
#                         subnormal normalizer, the static align mux and
#                         the IEEE special-case injector; the delta against
#                         894 is recorded), <=1 MULT18X18D (an 11x11 needs
#                         AT MOST one — 2 or more means the mapper
#                         decomposed a multiply this small, the
#                         Vivado-vs-yosys divergence class the per-operator
#                         gates exist for; 0 is a PASS and means yosys
#                         LUT-mapped it, which is the load-bearing datum
#                         for the per-fabric FP_LANES ceiling), <=520 FF
#                         net of the 97 wrapper I/O flops, 0 EBR, Fmax >=
#                         40 MHz. Criteria pre-declared BEFORE the first
#                         run, per the §23.8 merge-blocker lesson.
#
# The gates above are the ECP5 GATES (they gate this script's exit status).
# Named-only MEASUREMENT targets follow them in the body and never affect
# the verdict — spec §27.6 (V20-2/V20-3 ECP5 halves) and spec §28
# (`sys_top_core` = the GATE S1 ECP5 half, the system-integration top
# Top_Core = ISA_Decoder + HIU).
#
# Invoke from the repo root:
#     sh synth/lattice/scripts/synth_fp_ops.sh                 # all gates
#     sh synth/lattice/scripts/synth_fp_ops.sh fp_fmalane_bf16 # one gate
#
# With no arguments every gate re-runs. With gate names as arguments only
# those gates re-run; gate_check.py still evaluates ALL criteria, reading
# the already-archived reports for the gates that were skipped — so a
# partial re-run cannot silently drop a merge blocker, and it does not
# churn the committed evidence of untouched gates.
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

# Optional gate filter (see the usage note in the header).
WANT="$*"

want() {
    [ -z "$WANT" ] && return 0
    for w in $WANT; do
        [ "$w" = "$1" ] && return 0
    done
    return 1
}

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

if want fp_mul36; then
    run_gate fp_mul36 FP_Mul36_gate_top \
        "FP_Mul36.v synth/lattice/fp_ops/FP_Mul36_gate_top.v"
fi

if want fp_addwide; then
    run_gate fp_addwide FP_AddWide_gate_top \
        "FP_AddWide.v synth/lattice/fp_ops/FP_AddWide_gate_top.v"
fi

# Gate C3 reads the generated ROM/coefficient sidecars and the shared
# narrow function through the same -I include path (include/generated/*.vh
# + include/fp_narrow_f32.vh — localparam bit vectors synthesize as
# distributed LUT ROM, never EBR). Seed sweep 1-5 per 23.10.10(g).
if want fp_stepseq; then
    run_gate fp_stepseq FP_StepSeq_gate_top \
        "FP_StepSeq.v FP_Mul36.v FP_AddWide.v synth/lattice/fp_ops/FP_StepSeq_gate_top.v" \
        "1 2 3 4 5"
fi

# GATE F1 — the v2.0 bf16/f16 fused-FMA lane. It instantiates FP_AddWide
# VERBATIM (pack_mode tied to PACK_FINAL, so the PACK_WIDE round-to-odd
# cone and the whole wide output register group constant-fold away here),
# plus its own 11x11 significand multiplier. Seed sweep 1-5 per the
# §23.10.10(g) convention — archive = the first passing seed.
if want fp_fmalane_bf16; then
    run_gate fp_fmalane_bf16 FP_FmaLaneBf16_gate_top \
        "FP_FmaLaneBf16.v FP_AddWide.v synth/lattice/fp_ops/FP_FmaLaneBf16_gate_top.v" \
        "1 2 3 4 5"
fi

# --- GATE V20-2 ECP5 half — feasibility MEASUREMENTS, NOT gates (§27.6) ---
# The ECP5 half of GATE V20-2 carries no merge-blocker binding: whatever
# these runs measure — including "does not fit" or "PnR did not finish" —
# is a valid recorded result, never a gate FAIL (user directive 2026-08-15,
# spec §27.6; the merge-blocker binding of GATE V20-2 sits entirely on the
# xcu55c half). Consequences for the harness:
#   * they run ONLY when named explicitly, so the default all-gates
#     invocation keeps its runtime;
#   * nextpnr failure is RECORDED (log archived) instead of aborting the
#     script — run_meas below, unlike run_gate, must not exit 1 on a
#     placement/routing death, because that death IS the measurement;
#   * a premap stat is archived (<name>_premap.rpt) so the §27.6 "premap
#     $mul delta 0" pin is measured on the operator-level netlist, before
#     techmap can hide an inferred multiply;
#   * gate_check.py reports them as MEASUREMENT rows that never affect the
#     exit status.
# Targets:
#   fp_acclattice_n8    — the v2.0 SHIPPING shape (spec §27.2.1 amendment
#                         2026-08-16): beat-serial FP_AccLattice.v at
#                         PRODUCTS_PER_BEAT=8 (4 beats, beat-0 merged
#                         carry-in, parallel 1-cycle 576-bit resolve).
#   fp_acclattice_n2    — the same RTL at PRODUCTS_PER_BEAT=2: the
#                         parameterization-consistency point against the
#                         archived Beat2 measurement (which differs
#                         structurally: separate carry beat + 9-cycle
#                         serial resolve).
#   fp_acclattice_beat2 — the original §27.6-declared ECP5 target shape:
#                         beat-serialized 2 products/beat x 16 beats (+1
#                         carry-in beat) + 9-cycle serial resolve
#                         (synth/lattice/fp_ops/FP_AccLatticeBeat2.v,
#                         measurement-only variant, kept as provenance).
#   (the retired fp_acclattice full-parallel target's reports remain
#   archived — the rewritten FP_AccLattice.v no longer has that shape.)

run_meas() {
    NAME="$1"
    TOP="$2"
    SRCS="$3"
    CHPARAM="$4"   # optional yosys hierarchy -chparam text, e.g.
                   # "-chparam PRODUCTS_PER_BEAT 2" — the v2.0 beat-serial
                   # FP_AccLattice is measured at two parameter points
                   # through ONE wrapper (amendment 2026-08-16).
    SEED=1   # single-seed convention of the non-sweep gates (fp_mul36/
             # fp_addwide): no pass target exists here, so no sweep either.

    echo "=== $NAME: yosys premap stat (operator-level, pre-techmap) ==="
    yosys -q -p "\
        read_verilog -defer -DWT_VENDOR_LATTICE_YOSYS -I include $SRCS; \
        hierarchy -check $CHPARAM -top $TOP; \
        proc; flatten; opt_clean; \
        tee -o $RPT/${NAME}_premap.rpt stat"

    echo "=== $NAME: yosys synth_ecp5 (top $TOP) ==="
    yosys -q -p "\
        read_verilog -defer -DWT_VENDOR_LATTICE_YOSYS -I include $SRCS; \
        hierarchy -check $CHPARAM -top $TOP; \
        synth_ecp5; \
        tee -o $RPT/${NAME}_synth.rpt stat; \
        write_json $RPT/${NAME}_synth.json"

    echo "=== $NAME: nextpnr-ecp5 out-of-context @ ${FREQ_MHZ} MHz (seed $SEED, measurement) ==="
    if nextpnr-ecp5 \
            $DEVICE_ARGS \
            --json "$RPT/${NAME}_synth.json" \
            --out-of-context \
            --report "$RPT/${NAME}_pnr.rpt" \
            --freq $FREQ_MHZ \
            --timing-allow-fail \
            --seed $SEED \
            > "$RPT/${NAME}_pnr.log" 2>&1; then
        echo "$NAME: nextpnr completed (measurement archived)"
    else
        tail -20 "$RPT/${NAME}_pnr.log"
        echo "$NAME: nextpnr DID NOT COMPLETE — that outcome is itself the"
        echo "$NAME: measurement (spec 27.6); log archived at $RPT/${NAME}_pnr.log"
        rm -f "$RPT/${NAME}_pnr.rpt"   # never leave a stale/partial report
    fi
}

# fp_acclattice (인자 없는 옛 타깃) — 903351c full-parallel 기본형의 측정
# 이름이었다. v2.0 amendment (2026-08-16) 로 FP_AccLattice.v 가 beat-serial
# 로 재작성되어 그 인터페이스는 소멸 — 기존 fp_acclattice_* 리포트는
# full-parallel provenance 로 동결 보존하고 (§27.6 재실측 선언), 재실측은
# 아래의 새 파일명 fp_acclattice_n8 / fp_acclattice_n2 로 아카이브한다.

if [ -n "$WANT" ] && want fp_acclattice_n8; then
    run_meas fp_acclattice_n8 FP_AccLattice_gate_top \
        "FP_AccLattice.v synth/lattice/fp_ops/FP_AccLattice_gate_top.v" \
        "-chparam PRODUCTS_PER_BEAT 8"
fi

if [ -n "$WANT" ] && want fp_acclattice_n2; then
    run_meas fp_acclattice_n2 FP_AccLattice_gate_top \
        "FP_AccLattice.v synth/lattice/fp_ops/FP_AccLattice_gate_top.v" \
        "-chparam PRODUCTS_PER_BEAT 2"
fi

if [ -n "$WANT" ] && want fp_acclattice_beat2; then
    run_meas fp_acclattice_beat2 FP_AccLatticeBeat2_gate_top \
        "synth/lattice/fp_ops/FP_AccLatticeBeat2.v synth/lattice/fp_ops/FP_AccLatticeBeat2_gate_top.v"
fi

# --- GATE V20-3 ECP5 half — MEASUREMENT, NOT a gate (spec §27.6 "④ GATE
# V20-3 기준 선공표" 블록) -------------------------------------------------
# The v2.0 TRAIN full-cluster datapath (FP_TrainCluster: FMA lane wide-
# product tap x8 + FP_AccLattice N=8 + FP_AccBank + beat dispatch skeleton
# + FILL/DRAIN/ZERO cmd path). Same regime as the V20-2 measurements above:
# the merge-blocker binding of GATE V20-3 sits entirely on the xcu55c half;
# whatever this run measures — including "PnR did not complete", which the
# §27.6 block PRE-RECORDS as the realistic outcome (placed COMB projection
# 69-76% + glue vs the v1.9b routing-saturation precedent at 39.6%) — is a
# recorded MEASUREMENT, never a gate FAIL. The discriminating pin here is
# premap $mul == 8 (tap당 정확히 1 x 8 lanes; lattice 0 / bank 0);
# MULT18X18D is a record axis (yosys share discretion allowed — §26.6).
if [ -n "$WANT" ] && want fp_traincluster; then
    run_meas fp_traincluster FP_TrainCluster_gate_top \
        "FP_TrainCluster.v FP_AccLattice.v FP_AccBank.v synth/lattice/fp_ops/FP_TrainCluster_gate_top.v"
fi

# --- GATE S1 ECP5 half — MEASUREMENT, NOT a gate (spec §28) ---------------
# The system-integration top (Top_Core = ISA_Decoder + HIU). The xcu55c
# half carries the entire merge-blocker binding of GATE S1; this half is a
# feasibility MEASUREMENT under the V20-2/V20-3 regime — whatever it
# measures, INCLUDING "yosys/nextpnr rejected it" or "PnR did not
# complete", is a recorded result and never a gate FAIL.
#
# Two outcomes are PRE-DECLARED as realistic here, so that neither can be
# spun after the fact:
#   (a) the HIU TRNG ring oscillators (`g_ro[*]`, defect D2) are a
#       deliberate combinational feedback. Vivado accepts them once the
#       netlist property ALLOW_COMBINATORIAL_LOOPS is set
#       (synth/constraints/hiu_trng_ro.xdc); the yosys/nextpnr flow has NO
#       equivalent constraint, so a loop rejection or a timing-analysis
#       complaint is an expected, recorded outcome of this half — not a
#       defect in either the RTL or the ECP5 flow.
#   (b) Top_Core carries a whole PE_Core + FP_StepSeq. The v1.9b full
#       Cluster was already routing-dominated on the 85F at 39.6% COMB
#       (11.34 MHz — synth/lattice/reports/cluster_v19b_pnr.log), so a low
#       Fmax here is the fabric's answer, not a regression.
# The load-bearing datum of this half is the FRONT of the flow, not the
# back: does the same RTL elaborate and map under a NON-Vivado frontend?
# That is precisely the question defect D1 (Verilog-2001 violation Vivado
# rejects) and defect D3 (use-before-declare Vivado tolerates) put on the
# table, and it is why the archived premap stat matters even if PnR dies.
if [ -n "$WANT" ] && want sys_top_core; then
    run_meas sys_top_core Top_Core_gate_top \
        "Top_Core.v ISA_Decoder.v EHDecode.v PE_Core.v FP_StepSeq.v FP_Mul36.v FP_AddWide.v HIU.v synth/gate/Top_Core_gate_top.v"
fi

# --- Evaluate the gate criteria from the measured reports -----------------
python3 synth/lattice/fp_ops/gate_check.py "$RPT"
