#!/bin/sh
# SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
#
# pnr_pod.sh — nextpnr-ecp5 place-and-route driver for WaveTensor Pod on ULX3S
#
# Consumes the JSON netlist produced by `synth/lattice/scripts/synth_pod.ys`
# and produces a bitstream loadable onto ULX3S (LFE5U-85F, TQFP-208 package).
#
# Invoke via: `make MOD=impl-pod-ecp5` or manually:
#     sh synth/lattice/scripts/pnr_pod.sh
#
# Expected output:
#     synth/lattice/reports/pod_<GEOM>_pnr.config    (nextpnr text config)
#     synth/lattice/reports/pod_<GEOM>.bit           (ECP5 bitstream)
#     synth/lattice/reports/pod_<GEOM>_pnr.rpt       (timing / utilization report)
#
# Load onto ULX3S with:
#     openFPGALoader -c ft232 synth/lattice/reports/pod_<GEOM>.bit

set -e

GEOM="${GEOM:-2x2_2x2}"
JSON_IN="synth/lattice/reports/pod_${GEOM}_synth.json"
LPF="synth/lattice/constraints/pod_ulx3s.lpf"
CONFIG_OUT="synth/lattice/reports/pod_${GEOM}_pnr.config"
BIT_OUT="synth/lattice/reports/pod_${GEOM}.bit"
REPORT="synth/lattice/reports/pod_${GEOM}_pnr.rpt"

# ULX3S CS-ULX3S-03 uses LFE5U-85F-6BG381C (CABGA381 package, speed grade 6).
# For nextpnr-ecp5 this is:
#     --um-85k          (LFE5UM-85F, without -5G SerDes — matches LFE5U-85F fabric)
#     --package CABGA381
#     --speed 6
DEVICE_ARGS="--um-85k --package CABGA381 --speed 6"

if [ ! -f "$JSON_IN" ]; then
    echo "pnr_pod.sh: netlist $JSON_IN not found — run yosys first."
    exit 1
fi

# --- Place and route ----------------------------------------------------
nextpnr-ecp5 \
    $DEVICE_ARGS \
    --json "$JSON_IN" \
    --lpf "$LPF" \
    --textcfg "$CONFIG_OUT" \
    --report "$REPORT" \
    --freq 100 \
    --seed 1

# --- Pack into bitstream -----------------------------------------------
ecppack "$CONFIG_OUT" "$BIT_OUT"

echo ""
echo "pnr_pod.sh: bitstream ready — $BIT_OUT"
echo "  Load via: openFPGALoader -c ft232 $BIT_OUT"

# TODO(Stage 1 Board bring-up):
#   * Verify --um-85k selector maps correctly to the LFE5U-85F fabric.
#     LFE5U-85F (no SerDes, no PCS) and LFE5UM-85F (with SerDes) share
#     the FPGA logic fabric — nextpnr often uses the -UM part as the
#     device model for the -U counterpart. Confirm this maps correctly.
#   * If nextpnr fails placement / routing at 100 MHz, try --freq 80
#     and iterate. The critical path in ISA_Decoder.v was measured at
#     ~7.9 ns on XCAU25P → ~126 MHz margin; ECP5 uses a different node
#     and may need re-tuning.
#   * Add `--placer heap` explicitly if default placer struggles at
#     high geometries (Stage 2 will use different device; not urgent here).
