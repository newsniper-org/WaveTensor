# SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

# synth_pod.tcl — out-of-context synthesis of Pod.v
#
# Usage:
#   vivado -mode batch -nolog -nojournal -source synth/scripts/synth_pod.tcl
#
# Optional overrides via `vivado -tclargs`:
#   PART=<device>            — synthesize against a different chip
#   PE_ROWS / PE_COLS        — geometry override (∈ {(2,2),(2,4),(4,2),(4,4)})
#   CLUSTER_ROWS / CLUSTER_COLS
#
# Reports land in synth/reports/, checkpoint in synth/checkpoints/.

# Process -tclargs of the form NAME=value.
foreach arg $argv {
    if {[regexp {^([A-Z_][A-Z_0-9]*)=(.*)$} $arg -> key val]} {
        set ::$key $val
    }
}

source [file join [file dirname [info script]] common.tcl]

dump_summary "synthesis"

# Read sources fresh into an in-memory project (no .xpr clutter).
create_project -in_memory -part $::PART
foreach src $::POD_SOURCES { read_verilog $src }
read_xdc $::XDC_FILE

print_banner "Running synth_design (out-of-context, top=Pod)"
synth_design -top Pod \
             -part $::PART \
             -mode out_of_context \
             -include_dirs [file join $REPO_ROOT include] \
             -verilog_define WT_VENDOR_VIVADO=1 \
             -generic PE_ROWS=$::PE_ROWS \
             -generic PE_COLS=$::PE_COLS \
             -generic CLUSTER_ROWS=$::CLUSTER_ROWS \
             -generic CLUSTER_COLS=$::CLUSTER_COLS \
             -flatten_hierarchy none

# Reports
set tag "pod_${::PE_ROWS}x${::PE_COLS}_${::CLUSTER_ROWS}x${::CLUSTER_COLS}_synth"

report_utilization     -file [file join $REPORT_DIR ${tag}_util.rpt]    -hierarchical
report_timing_summary  -file [file join $REPORT_DIR ${tag}_timing.rpt]
report_design_analysis -file [file join $REPORT_DIR ${tag}_analysis.rpt] -timing -setup
report_methodology     -file [file join $REPORT_DIR ${tag}_methodology.rpt]

# Checkpoint for downstream impl_pod.tcl
write_checkpoint -force [file join $CKPT_DIR ${tag}.dcp]

print_banner "synthesis complete"
puts "  reports → $REPORT_DIR"
puts "  ckpt    → [file join $CKPT_DIR ${tag}.dcp]"

exit 0
