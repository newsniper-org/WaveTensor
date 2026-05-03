# SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

# impl_pod.tcl — opt → place → route after synthesis.
#
# Reads the checkpoint produced by synth_pod.tcl, runs implementation,
# and emits utilization/timing/power reports for the post-route design.
#
# Usage:
#   vivado -mode batch -nolog -nojournal -source synth/scripts/impl_pod.tcl

foreach arg $argv {
    if {[regexp {^([A-Z_][A-Z_0-9]*)=(.*)$} $arg -> key val]} {
        set ::$key $val
    }
}

source [file join [file dirname [info script]] common.tcl]
dump_summary "implementation"

set synth_tag "pod_${::PE_ROWS}x${::PE_COLS}_${::CLUSTER_ROWS}x${::CLUSTER_COLS}_synth"
set impl_tag  "pod_${::PE_ROWS}x${::PE_COLS}_${::CLUSTER_ROWS}x${::CLUSTER_COLS}_impl"
set src_dcp   [file join $CKPT_DIR ${synth_tag}.dcp]

if {![file exists $src_dcp]} {
    puts "ERROR: synthesis checkpoint not found: $src_dcp"
    puts "       run synth_pod.tcl first"
    exit 1
}

print_banner "Loading post-synthesis checkpoint"
open_checkpoint $src_dcp

print_banner "opt_design"
opt_design

print_banner "place_design"
place_design

print_banner "route_design"
route_design

# Post-route reports
report_utilization      -file [file join $REPORT_DIR ${impl_tag}_util.rpt]   -hierarchical
report_timing_summary   -file [file join $REPORT_DIR ${impl_tag}_timing.rpt]
report_power            -file [file join $REPORT_DIR ${impl_tag}_power.rpt]
report_clock_utilization -file [file join $REPORT_DIR ${impl_tag}_clock.rpt]
report_drc              -file [file join $REPORT_DIR ${impl_tag}_drc.rpt]

write_checkpoint -force [file join $CKPT_DIR ${impl_tag}.dcp]

print_banner "implementation complete"
puts "  reports → $REPORT_DIR"
puts "  ckpt    → [file join $CKPT_DIR ${impl_tag}.dcp]"

exit 0
