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

# ---- rst false path, CLR/PRE 한정 (spec §29.7 XDC 정정) -------------------
# 여기에 있는 이유: `REF_PIN_NAME == CLR|PRE` 는 넷리스트 primitive 핀을
# 매칭하므로 `synth/constraints/pod.xdc` (synth_design 이전 read) 에서는
# 0개를 매칭해 예외가 조용히 사라진다. 넓은 형태가 왜 틀렸는지는 pod.xdc
# 의 같은 자리 주석 참조 — 요약하면 `rst` 가 CE LUT 의 **데이터 입력**이
# 되어 setup/hold 가 걸리는 동기 경로가 되는데, 넓은 false_path 가 그것을
# 타이밍 분석에서 통째로 빼고 있었다.
#
# 매칭이 0개면 **소리를 낸다** — 조용히 통과시키지 않는다.
set _rst_async_pins [get_pins -quiet -hier \
    -filter {REF_PIN_NAME == CLR || REF_PIN_NAME == PRE}]
if {[llength $_rst_async_pins] == 0} {
    puts "ERROR: spec 29.7 rst false_path — CLR/PRE 핀 매칭 0개."
    puts "       async-reset 설계인데 비동기 reset 핀이 없다는 뜻이므로"
    puts "       제약을 조용히 건너뛰지 않고 여기서 멈춘다."
    exit 1
}
set_false_path -from [get_ports rst] -to $_rst_async_pins
puts "spec 29.7: rst false_path -> [llength $_rst_async_pins] CLR/PRE pins"

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
