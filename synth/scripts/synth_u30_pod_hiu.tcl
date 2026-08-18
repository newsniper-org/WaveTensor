# SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

# synth_u30_pod_hiu.tcl — Pod(2x2 cluster x 2x2 PE) + HIU 묶음을 Alveo U30
# (xcu30-fbvb900-2-e / ZU7EV / speed -2) 에 전 flow(synth+place+route)로 돌려
# 면적·이용률·타이밍·DRC 를 실측한다.
#
# 답하는 질문
# -----------
#   "Alveo U30 카드의 SoC 하나당 (2x2)x(2x2)+HIU 묶음을 각각 합성하는 건
#    어떨지"
#
# U30 는 SoC 2개를 실은 카드이고, 각 SoC 가 ZU7EV 실리콘이다. 따라서 이
# 스크립트는 **SoC 1개분** 을 측정한다.
#
# 기준 선공표 (V9-4 형식)
# -----------------------
#   PART      : xcu30-fbvb900-2-e (LUT 230,400 / FF 460,800 / DSP 1,728 /
#               BRAM 312 / URAM 96 — Vivado get_parts 실측 확인)
#   PERIOD    : 10.000 ns (100 MHz) — synth/constraints/pod.xdc 와 동일 기준
#   FLOW      : opt_design -> place_design -> route_design
#               (phys_opt 없음 — synth/scripts/impl_pod.tcl 의 U55C Pod
#                기준선과 flow 를 일치시켜 speed grade 차이만 비교한다.
#                1차 route 가 WNS<0 이면 그 수치를 확정 보고한 뒤 별도로
#                post-route phys_opt 를 돌려 "닫히는가" 를 추가 실측한다.)
#   비교 기준선: Pod 단독 xcu55c-2L = 170,850 LUT / WNS -0.205 ns
#               HIU 단독 xcu55c-2L =   2,631 LUT / WNS +5.505 ns
#               단순 합 173,481 LUT = U30 의 75.3%
#
# 선행 조건 (결함 D1)
# -------------------
# HIU.v:32 의 `output reg dma_data_out` 는 서브모듈(dma_inst) 출력에 연결된
# Verilog-2001 위반이고, 계통 전체를 막는 유일한 hard error 다. 이 스크립트가
# 돌기 위해서는 그 한 줄이 `output` (wire) 로 되어 있어야 한다. 최초 실측은
# 그 수리가 repo 에 반영되기 전이었으므로 /tmp 사본에 D1 만 적용해서 돌렸다
# (본체가 구동하지 않는 포트이므로 의미 보존). D1 수리가 landing 된 뒤에는
# 이 스크립트를 repo 소스 그대로 재현 실행할 수 있다.
#
# 사용법
#   vivado -mode batch -nolog -nojournal \
#          -source synth/scripts/synth_u30_pod_hiu.tcl
#
# 대형 run 이다. nohup setsid + done-marker 로 detach 하고 완주를 확인할 것.

foreach arg $argv {
    if {[regexp {^([A-Z_][A-Z_0-9]*)=(.*)$} $arg -> key val]} {
        set ::$key $val
    }
}

set REPO_ROOT [file normalize [file join [file dirname [info script]] ../..]]
set SYNTH_DIR [file join $REPO_ROOT synth]
set RPTDIR    [file join $SYNTH_DIR reports]
file mkdir $RPTDIR

if {![info exists ::PART]}   { set ::PART   "xcu30-fbvb900-2-e" }
if {![info exists ::PERIOD]} { set ::PERIOD "10.000" }
if {![info exists ::TAG]}    { set ::TAG    "u30_pod_hiu" }
set TOP "Pod_HIU_gate_top"

# 46GB 공유 머신이다. 다른 Vivado 와 동시 실행될 수 있으니 스레드를 캡한다.
if {![info exists ::MAXTHREADS]} { set ::MAXTHREADS 4 }
set_param general.maxThreads $::MAXTHREADS

set ::T0 [clock seconds]
proc phase {msg} {
    set dt [expr {[clock seconds] - $::T0}]
    puts ""
    puts "################################################################"
    puts "# \[+[format %5d $dt]s\] PHASE: $msg"
    puts "################################################################"
    flush stdout
}

proc snap {label} {
    set wns [get_property -quiet SLACK \
                 [get_timing_paths -quiet -delay_type max -max_paths 1]]
    set whs [get_property -quiet SLACK \
                 [get_timing_paths -quiet -delay_type min -max_paths 1]]
    puts "SNAP $label : WNS=$wns WHS=$whs"
    flush stdout
}

# =========================================================================
phase "part 확인 (PART=$::PART)"
# =========================================================================
create_project -in_memory -part $::PART

set pobj [get_parts -quiet $::PART]
if {[llength $pobj] == 0} {
    puts "FATAL: part $::PART 를 찾을 수 없다"
    exit 1
}
puts "PART_INFO name=[get_property NAME $pobj] speed=[get_property SPEED $pobj] family=[get_property FAMILY $pobj]"
puts "PART_INFO LUT=[get_property LUT_ELEMENTS $pobj] FF=[get_property FLIPFLOPS $pobj] DSP=[get_property DSP $pobj] BRAM=[get_property BLOCK_RAMS $pobj] URAM=[get_property -quiet ULTRA_RAMS $pobj]"
flush stdout

# ---- 소스 ----------------------------------------------------------------
# Pod 계보 전부 + HIU + gate 래퍼.
foreach src [list \
        [file join $REPO_ROOT Pod.v] \
        [file join $REPO_ROOT Cluster.v] \
        [file join $REPO_ROOT ISA_Decoder.v] \
        [file join $REPO_ROOT EHDecode.v] \
        [file join $REPO_ROOT PE_Core.v] \
        [file join $REPO_ROOT FP_StepSeq.v] \
        [file join $REPO_ROOT FP_Mul36.v] \
        [file join $REPO_ROOT FP_AddWide.v] \
        [file join $REPO_ROOT HIU.v] \
        [file join $SYNTH_DIR gate Pod_HIU_gate_top.v] ] {
    if {![file exists $src]} { puts "FATAL: source not found: $src"; exit 1 }
    read_verilog $src
}

read_xdc [file join $SYNTH_DIR constraints u30_pod_hiu.xdc]

# =========================================================================
phase "synth_design (top=$TOP, out_of_context, flatten=none)"
# =========================================================================
synth_design -top $TOP \
             -part $::PART \
             -mode out_of_context \
             -include_dirs [file join $REPO_ROOT include] \
             -verilog_define WT_VENDOR_VIVADO=1 \
             -flatten_hierarchy none

# ---- 결함 D2: HIU TRNG RO 제약 ------------------------------------------
# 넷리스트 객체가 있어야 매칭되므로 synth_design 직후에 source 한다
# (hiu_trng_ro.xdc 의 "적용 시점" 주석이 규정한 순서).
phase "D2 TRNG RO 제약 적용 (hiu_trng_ro.xdc)"
source [file join $SYNTH_DIR constraints hiu_trng_ro.xdc]

report_utilization    -file [file join $RPTDIR ${::TAG}_synth_util.rpt] -hierarchical
report_utilization    -file [file join $RPTDIR ${::TAG}_synth_util_flat.rpt]
report_timing_summary -file [file join $RPTDIR ${::TAG}_synth_timing.rpt]
snap "post-synth"

# =========================================================================
phase "opt_design"
# =========================================================================
opt_design
snap "post-opt"

# =========================================================================
phase "place_design (예상 이용률 ~75% — 실패하면 그것이 답이다)"
# =========================================================================
if {[catch {place_design} place_err]} {
    puts "PLACE_FAILED: $place_err"
    report_utilization -file [file join $RPTDIR ${::TAG}_placefail_util.rpt] -hierarchical
    puts "VERDICT_INPUT: place_design 실패 — U30 SoC 1개에 배치 불가"
    exit 2
}
report_utilization     -file [file join $RPTDIR ${::TAG}_place_util.rpt] -hierarchical
report_timing_summary  -file [file join $RPTDIR ${::TAG}_place_timing.rpt]
report_design_analysis -file [file join $RPTDIR ${::TAG}_place_analysis.rpt] \
                       -timing -setup -congestion
snap "post-place"

# =========================================================================
phase "route_design"
# =========================================================================
if {[catch {route_design} route_err]} {
    puts "ROUTE_FAILED: $route_err"
    report_route_status -file [file join $RPTDIR ${::TAG}_routefail_status.rpt]
    report_utilization  -file [file join $RPTDIR ${::TAG}_routefail_util.rpt] -hierarchical
    puts "VERDICT_INPUT: route_design 실패 — U30 SoC 1개에 라우팅 불가"
    exit 3
}

# =========================================================================
phase "post-route 리포트 (1차 — U55C 기준선과 동일 flow)"
# =========================================================================
report_utilization       -file [file join $RPTDIR ${::TAG}_impl_util.rpt] -hierarchical
report_utilization       -file [file join $RPTDIR ${::TAG}_impl_util_flat.rpt]
report_timing_summary    -file [file join $RPTDIR ${::TAG}_impl_timing.rpt]
report_route_status      -file [file join $RPTDIR ${::TAG}_impl_route_status.rpt]
report_drc               -file [file join $RPTDIR ${::TAG}_impl_drc.rpt]
report_clock_utilization -file [file join $RPTDIR ${::TAG}_impl_clock.rpt]
report_power             -file [file join $RPTDIR ${::TAG}_impl_power.rpt]
report_methodology       -file [file join $RPTDIR ${::TAG}_impl_methodology.rpt]
snap "post-route(1차)"

set wns1 [get_property -quiet SLACK \
              [get_timing_paths -quiet -delay_type max -max_paths 1]]
puts "RESULT_PRIMARY_WNS=$wns1"
flush stdout

# 1차가 미달이면 닫힘 가능성만 추가 실측한다 (1차 리포트는 이미 확정 저장).
if {$wns1 != "" && $wns1 < 0} {
    phase "post-route phys_opt_design (닫힘 가능성 추가 실측)"
    if {[catch {phys_opt_design} po_err]} {
        puts "PHYSOPT_FAILED: $po_err"
    } else {
        report_timing_summary -file [file join $RPTDIR ${::TAG}_physopt_timing.rpt]
        set wns2 [get_property -quiet SLACK \
                      [get_timing_paths -quiet -delay_type max -max_paths 1]]
        puts "RESULT_PHYSOPT_WNS=$wns2"
    }
} else {
    puts "1차 route 에서 타이밍 충족 — phys_opt 생략"
}

phase "완주"
puts "DONE_OK"
exit 0
