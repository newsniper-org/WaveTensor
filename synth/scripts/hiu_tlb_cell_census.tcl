# SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

# hiu_tlb_cell_census.tcl — "TLB 가 실리콘에 존재하는가" 를 `get_cells` 로
# 직접 세는 스크립트 (spec §28.2 / §29.3 의 판정 근거를 재현 가능하게 만든다).
#
# 왜 이 파일이 존재하는가
# ----------------------
# 결함 D4 의 판정 문장은 "넷리스트 실측 cells=0 — 합성에서 전부 소멸한다"
# 였다. 그 문장은 참이었지만 **재현 절차가 repo 안에 없었다** — 즉 다음
# 사람이 같은 질문을 다시 하려면 처음부터 하네스를 짜야 했다. 이 스크립트가
# 그 공백을 메운다. D4 수리 이후에는 같은 명령이 cells > 0 을 답해야 하며,
# 그 대조가 "수리됐다" 의 유일한 직접 증거다.
#
# 사용:
#   vivado -mode batch -nolog -nojournal \
#          -source synth/scripts/hiu_tlb_cell_census.tcl \
#          -tclargs SRC=HIU.v PART=xcu55c-fsvh2892-2L-e TAG=post
#
#   SRC  — 합성할 HIU 소스 (기본 HIU.v). 수리 전 사본을 가리키면 대조군이
#          된다 (`git show <rev>:HIU.v > /tmp/HIU_pre.v`).
#   TAG  — 리포트 접미사 (기본 census)

foreach arg $argv {
    if {[regexp {^([A-Z_][A-Z_0-9]*)=(.*)$} $arg -> key val]} {
        set ::$key $val
    }
}

set REPO_ROOT [file normalize [file join [file dirname [info script]] ../..]]
if {![info exists ::SRC]}  { set ::SRC [file join $REPO_ROOT HIU.v] }
if {![info exists ::PART]} { set ::PART "xcu55c-fsvh2892-2L-e" }
if {![info exists ::TAG]}  { set ::TAG "census" }

create_project -in_memory -part $::PART
read_verilog $::SRC
synth_design -top HIU \
             -part $::PART \
             -mode out_of_context \
             -include_dirs [file join $REPO_ROOT include] \
             -verilog_define WT_VENDOR_VIVADO=1 \
             -flatten_hierarchy none

proc census {label pattern} {
    set n [llength [get_cells -quiet -hierarchical -filter $pattern]]
    puts [format "TLB_CENSUS %-28s %6d   (%s)" $label $n $pattern]
    return $n
}

puts ""
puts "================================================================"
puts "  HIU TLB storage cell census — TAG=$::TAG  SRC=$::SRC"
puts "================================================================"

# 수리 후 이름 (distributed RAM + flat valid vector)
set n_tlbmem  [census "tlb_mem cells"       {NAME =~ *tlb_mem*}]
set n_tlbval  [census "tlb_valid cells"     {NAME =~ *tlb_valid*}]
set n_lutram  [census "RAM* primitives"     {REF_NAME =~ RAM*}]
# 폐기된 2D 배열 이름 (대조군에서 0 이 아니면 그것이 D4 의 실물이다)
set n_part    [census "partitioned_tlb_*"   {NAME =~ *partitioned_tlb*}]

set total [expr {$n_tlbmem + $n_tlbval + $n_part}]
puts ""
puts [format "TLB_CENSUS_TOTAL %d   (tlb_mem %d + tlb_valid %d + partitioned_tlb %d)" \
             $total $n_tlbmem $n_tlbval $n_part]
if {$total == 0} {
    puts "TLB_CENSUS_VERDICT ABSENT — TLB 저장소가 실리콘에 존재하지 않는다 (D4 상태)"
} else {
    puts "TLB_CENSUS_VERDICT PRESENT — TLB 저장소가 실리콘에 존재한다"
}
puts ""

exit 0
