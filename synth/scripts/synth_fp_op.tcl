# SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

# synth_fp_op.tcl — PER-OPERATOR out-of-context synth + place + route on
# AMD UltraScale+, the Vivado counterpart of the shipped ECP5 harness
# synth/lattice/scripts/synth_fp_ops.sh.
#
# This is the project's FIRST per-operator Vivado gate. It exists because
# the two mappers disagree by construction: the same Cluster RTL maps to
# 103 MULT18X18D under yosys/ECP5 but 39 DSP48E2 under Vivado/UltraScale+,
# and the historical divergence that motivated the ECP5 per-operator gates
# in the first place was "Vivado 35 DSP vs yosys 497 MULT18X18D". A gate
# criterion written for one fabric predicts nothing about the other, so
# every operator that matters is measured on BOTH.
#
# Usage (from the repo root; PART must always be passed explicitly — the
# common.tcl default is a small Zynq part):
#
#   vivado -mode batch -nolog -nojournal \
#          -source synth/scripts/synth_fp_op.tcl -tclargs \
#          TAG=fp_fmalane_bf16 \
#          TOP=FP_FmaLaneBf16_gate_top \
#          SRCS=FP_FmaLaneBf16.v,FP_AddWide.v,synth/lattice/fp_ops/FP_FmaLaneBf16_gate_top.v \
#          PART=xcu55c-fsvh2892-2L-e PERIOD=10.000
#
# or through the Makefile wrapper:
#
#   make synth-fp-op FP_OP=fp_fmalane_bf16 PART=xcu55c-fsvh2892-2L-e
#
# -tclargs (all NAME=value, the synth_pod.tcl convention):
#   TAG     — report basename (required)
#   TOP     — top module, normally the shared *_gate_top wrapper (required)
#   SRCS    — COMMA-separated repo-relative Verilog sources (required).
#             Comma, not space: -tclargs splits on whitespace.
#   PART    — device (required in practice; defaults to xcu55c, EC2 F2's
#             exact silicon). xcu55c-fsvh2892-2L-e and xcu50-fsvh2104-2-e
#             synthesize under the license-free Vivado 2025.2; xcvu47p does
#             NOT (device-string licensing quirk). Do not upgrade Vivado
#             past 2025.2 — it is the last license-free release.
#   PERIOD  — target clock period in ns (default 10.000 = 100 MHz, the
#             spec-risk-2 assumption this gate exists to test)
#   KEEP_DCP— 1 to keep the post-route checkpoint (default 0; .dcp files
#             are gitignored and bulky, and a per-operator gate does not
#             need one)
#   RST_FALSE_PATH — 1 to add `set_false_path -from [get_ports rst]` to the
#             generated clock XDC (default 0). The fp-ops cores are
#             deliberately reset-free, hence the default; the GATE S1
#             system tops (Top_Core/HIU, spec §28) are async-reset
#             designs and DO need it.
#   POST_XDC— COMMA-separated repo-relative XDC files to `source` AFTER
#             synth_design and BEFORE opt_design (default: none). This
#             exists for constraints that must match NETLIST objects and
#             therefore cannot be read pre-elaboration — specifically
#             `synth/constraints/hiu_trng_ro.xdc` (defect D2: the HIU TRNG
#             ring oscillators need ALLOW_COMBINATORIAL_LOOPS /
#             DONT_TOUCH / set_false_path on `g_ro[*]` cells that do not
#             exist until after elaboration). A missing file is a hard
#             error — a gate that silently skipped its constraint would
#             report a DRC status that does not describe the design.
#
# Flow notes:
#   * The SAME *_gate_top wrapper as the ECP5 gate is used, so both fabrics
#     measure an identical netlist boundary (all I/O registered once) and
#     the LUT / FF / DSP / Fmax numbers are directly comparable.
#   * WT_VENDOR_VIVADO=1 is REQUIRED: without it `WT_USE_DSP expands to
#     nothing and the DSP-inference hint is silently lost.
#   * pod.xdc is NOT reusable here — it does `set_false_path -from
#     [get_ports rst]` and the fp-ops cores are deliberately reset-free.
#     A minimal clock-only XDC is GENERATED per run into the report dir so
#     the archived evidence is self-describing.
#   * The gate reports POST-ROUTE timing, never post-synth: on this project
#     the same design measured WNS -1.835 ns after synth and -0.205 ns
#     after route (cross_vendor_fabric_evidence.md §2). Synth-stage timing
#     is not a usable Fmax.

foreach arg $argv {
    if {[regexp {^([A-Z_][A-Z_0-9]*)=(.*)$} $arg -> key val]} {
        set ::$key $val
    }
}

set REPO_ROOT [file normalize [file join [file dirname [info script]] ../..]]
set RPT_DIR   [file join $REPO_ROOT synth reports fp_ops]
set CKPT_DIR  [file join $REPO_ROOT synth checkpoints]
file mkdir $RPT_DIR

foreach req {TAG TOP SRCS} {
    if {![info exists ::$req]} {
        puts "ERROR: missing required -tclargs $req=<value>"
        exit 1
    }
}
if {![info exists ::PART]}     { set ::PART "xcu55c-fsvh2892-2L-e" }
if {![info exists ::PERIOD]}   { set ::PERIOD "10.000" }
if {![info exists ::KEEP_DCP]} { set ::KEEP_DCP 0 }
if {![info exists ::RST_FALSE_PATH]} { set ::RST_FALSE_PATH 0 }
if {![info exists ::POST_XDC]} { set ::POST_XDC "" }

puts ""
puts "================================================================"
puts "  per-operator UltraScale+ gate: $::TAG"
puts "================================================================"
puts "  part      : $::PART"
puts "  top       : $::TOP"
puts "  period    : $::PERIOD ns  ([format %.2f [expr {1000.0/$::PERIOD}]] MHz)"
puts "  sources   : $::SRCS"
puts "  reports   : $RPT_DIR"
puts ""

create_project -in_memory -part $::PART

foreach src [split $::SRCS ","] {
    set p [file join $REPO_ROOT [string trim $src]]
    if {![file exists $p]} {
        puts "ERROR: source not found: $p"
        exit 1
    }
    read_verilog $p
}

# Minimal clock-only OOC constraint, generated so the archive is
# self-describing and the run is reproducible from the report dir alone.
set xdc_file [file join $RPT_DIR ${::TAG}_gate.xdc]
set fh [open $xdc_file w]
puts $fh "# generated by synth/scripts/synth_fp_op.tcl for gate $::TAG"
puts $fh "# out-of-context: no pin placement, clock definition only. The"
puts $fh "# fp-ops cores are reset-free, so there is no reset false path"
puts $fh "# unless RST_FALSE_PATH=1 was passed (GATE S1 system tops)."
puts $fh "create_clock -name clk -period $::PERIOD \[get_ports clk\]"
if {$::RST_FALSE_PATH} {
    # GATE S1 (spec §28): Top_Core/HIU/ISA_Decoder are async-reset designs.
    # The gate_top wrapper deliberately does NOT register rst (registering
    # it would move the reset-release cycle), so the reset distribution net
    # is a top-level input fanning out to every FF. It is not a functional
    # timing path; the pod harness (synth/constraints/pod.xdc) takes the
    # same position for the same reason.
    puts $fh "set_false_path -from \[get_ports rst\]"
}
close $fh
read_xdc $xdc_file

synth_design -top $::TOP \
             -part $::PART \
             -mode out_of_context \
             -include_dirs [file join $REPO_ROOT include] \
             -verilog_define WT_VENDOR_VIVADO=1 \
             -flatten_hierarchy none

report_utilization    -file [file join $RPT_DIR ${::TAG}_synth_util.rpt] \
                      -hierarchical
report_timing_summary -file [file join $RPT_DIR ${::TAG}_synth_timing.rpt]

# ---- POST_XDC: netlist-object constraints (defect D2) --------------------
# Sourced HERE — after synth_design (the netlist exists) and before
# opt_design (so the constraint is honored by every downstream stage,
# including the phys_opt pass that could otherwise collapse the ring
# oscillator loop). See the POST_XDC note in the header.
foreach pxdc [split $::POST_XDC ","] {
    set pxdc [string trim $pxdc]
    if {$pxdc eq ""} { continue }
    set pp [file join $REPO_ROOT $pxdc]
    if {![file exists $pp]} {
        puts "ERROR: POST_XDC file not found: $pp"
        exit 1
    }
    puts "POST_XDC: sourcing $pxdc"
    source $pp
}

opt_design
place_design
phys_opt_design
route_design

report_utilization    -file [file join $RPT_DIR ${::TAG}_impl_util.rpt] \
                      -hierarchical
report_timing_summary -file [file join $RPT_DIR ${::TAG}_impl_timing.rpt]
report_drc            -file [file join $RPT_DIR ${::TAG}_impl_drc.rpt]

# ---- machine-readable summary (the gate checker reads THIS) --------------
# RAW CELL counts from the routed netlist, by REF_NAME, so the numbers do
# not depend on report_utilization's table layout across Vivado releases.
# NOTE lut_cells is the raw LUT1..LUT6 CELL count and is LARGER than the
# "Total LUTs" row of the hierarchical report, which counts LUT SITES after
# two LUT5s are combined into one LUT6 site. Both are archived; the site
# count is the one comparable to a device's LUT budget, the cell count is
# the one comparable to a yosys LUT4 count. fp_op_gate_check.py reads the
# site count out of ${TAG}_impl_util.rpt and reports the pair.
proc count_ref {pat} {
    return [llength [get_cells -quiet -hierarchical -filter "REF_NAME =~ {$pat}"]]
}

set n_lut   [count_ref "LUT?"]
set n_ff    [count_ref "FD*"]
set n_dsp   [count_ref "DSP48E*"]
set n_dspx  [count_ref "DSP_*"]
set n_carry [count_ref "CARRY*"]
set n_bram  [expr {[count_ref "RAMB18*"] + [count_ref "RAMB36*"]}]
set n_srl   [count_ref "SRL*"]

set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
set fmax [expr {1000.0 / ($::PERIOD - $wns)}]

# ---- CRITICAL WARNING census (GATE S1 axis, spec §28) --------------------
# WHY THIS IS A GATE AXIS: on this project a CRITICAL WARNING is exactly
# what a synthesizability regression looks like BEFORE it becomes an error
# — the HIU ring-oscillator timing loops (defect D2) surfaced as `[Synth
# 8-295] found timing loop` x8 plus `[DRC LUTLP-1] Combinatorial Loop
# Alert` x8, and the second set was a real missing constraint.
#
# THE CENSUS IS DELIBERATELY *NOT* TAKEN HERE. The obvious tcl form,
#     get_msg_config -count -severity {CRITICAL WARNING}
# was tried first and MEASURED WRONG: on Vivado 2025.2.1 it returned 0 for
# a run whose log contained 8 `CRITICAL WARNING: [Synth 8-295]` lines (the
# ring oscillators). It reports message *configuration*, not the number of
# messages issued. A census that silently answers 0 is worse than no
# census — it is a false PASS on the one axis whose entire purpose is to
# be loud. So the count is taken by the gate checker from the ARCHIVED
# RUN LOG (`synth-sys-gate` passes `-log`), where the number and the
# listing come from the same artifact and a reviewer can grep it.
# fp_op_gate_check.py treats a missing run log as UNMEASURED = FAIL for
# any gate that declares the axis.

set js [file join $RPT_DIR ${::TAG}_impl_summary.json]
set fh [open $js w]
puts $fh "{"
puts $fh "  \"tag\": \"$::TAG\","
puts $fh "  \"top\": \"$::TOP\","
puts $fh "  \"part\": \"$::PART\","
puts $fh "  \"period_ns\": $::PERIOD,"
puts $fh "  \"lut_cells\": $n_lut,"
puts $fh "  \"ff\": $n_ff,"
puts $fh "  \"dsp48\": $n_dsp,"
puts $fh "  \"dsp_split_cells\": $n_dspx,"
puts $fh "  \"carry\": $n_carry,"
puts $fh "  \"bram\": $n_bram,"
puts $fh "  \"srl\": $n_srl,"
puts $fh "  \"wns_ns\": $wns,"
puts $fh "  \"whs_ns\": $whs,"
puts $fh "  \"fmax_mhz\": [format %.2f $fmax],"
puts $fh "  \"msg_census\": \"run_log\""
puts $fh "}"
close $fh

puts ""
puts "================================================================"
puts "  $::TAG post-route summary ($::PART)"
puts "================================================================"
puts [format "  LUT cells  = %d  (raw LUT1..LUT6; see _impl_util.rpt for LUT sites)" $n_lut]
puts [format "  FF         = %d" $n_ff]
puts [format "  DSP48      = %d  (split DSP_* cells: %d)" $n_dsp $n_dspx]
puts [format "  CARRY      = %d" $n_carry]
puts [format "  BRAM       = %d" $n_bram]
puts [format "  WNS        = %.3f ns @ %s ns  ->  Fmax %.2f MHz" \
             $wns $::PERIOD $fmax]
puts "  MSG        = census taken by fp_op_gate_check.py from the archived"
puts "               run log (see the CRITICAL WARNING note above)"
puts "  summary    -> $js"
puts ""

if {$::KEEP_DCP} {
    file mkdir $CKPT_DIR
    write_checkpoint -force [file join $CKPT_DIR ${::TAG}_fp_op_impl.dcp]
}

exit 0
