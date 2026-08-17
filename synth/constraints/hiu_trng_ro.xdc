# SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

# hiu_trng_ro.xdc — HIU TRNG 링 오실레이터(`g_ro[*]`) 전용 제약.
#
# 배경 (결함 D2). HIU.v:377-386 의 generate 블록 `g_ro` 는 RO 8개를 각각
# 3단 인버터 루프로 구현한다. 이것은 의도된 조합 피드백이며 RTL 결함이
# **아니다** — 엔트로피 원천 자체가 자유 발진 루프다. 빠져 있던 것은
# XDC 쪽 인정(acknowledgement)이고, HIU.v:337-338 주석이 이미
# "합성 시 XDC 가 추가해야 한다" 고 규정해 둔 항목이다. 그 규정이 이
# 파일로 실현된다. RTL 은 한 줄도 바뀌지 않는다.
#
# 이 제약 없이 xcu55c OOC 를 돌리면 다음이 뜬다 (정찰 A 실측):
#   * CRITICAL WARNING [Synth 8-295] found timing loop  x8
#     → Vivado 가 루프마다 `set_disable_timing` 을 자동 추론하므로
#       타이밍 분석 자체는 이미 닫힌다. RO 8개면 정확히 8건이 정상이며,
#       gate 체커는 이 8건을 **그 수만큼만** 화이트리스트해야 한다.
#       `set_msg_config` 로 메시지를 전역 강등하지 **말 것** — 다른
#       곳의 진짜 조합 루프를 함께 숨긴다 (loud-fault-never-silent).
#   * CRITICAL WARNING [DRC LUTLP-1] Combinatorial Loop Alert  x8
#     → 아래 ALLOW_COMBINATORIAL_LOOPS 로 해소된다. Vivado 가 제시하는
#       공식 해소 경로가 정확히 이 property 다.
#
# ---------------------------------------------------------------------------
# 적용 시점: **synth_design 이후**, opt_design/route_design 이전.
#   `g_ro[*].ro_s{1,2,3}` 은 넷리스트 객체이므로 elaborate 전에는 존재하지
#   않는다. 따라서 pre-synth XDC 로 read_xdc 하면 0건 매칭으로 실패한다.
#   gate 하네스에서 다음처럼 쓴다:
#
#       synth_design -top <TOP> ... -mode out_of_context
#       source $REPO_ROOT/synth/constraints/hiu_trng_ro.xdc
#       opt_design ; place_design ; phys_opt_design ; route_design
#       report_drc ...
#
# 계층 무관: HIU 단독 OOC 에서는 `g_ro[0].ro_s1`, Top_Core / Pod 안에서는
#   `u_hiu/g_ro[0].ro_s1` 로 이름이 붙는다. -hierarchical + 와일드카드
#   패턴이 두 경우를 모두 잡으므로 하네스가 계층 접두어를 알 필요가 없다.
# ---------------------------------------------------------------------------

# ---- 1. 루프 넷 인정 → DRC LUTLP-1 해소 ----------------------------------
set wt_ro_nets [get_nets -quiet -hierarchical -filter {NAME =~ *g_ro*ro_s*}]

if {[llength $wt_ro_nets] == 0} {
    # loud-fault-never-silent: 이 파일을 source 한다는 것은 넷리스트에
    # TRNG RO 가 있다는 주장이다. 0건이면 옵티마이저가 RO 를 잘라낸
    # 것이고 (attributes.vh 의 WT_KEEP/WT_DONT_TOUCH 미정의 = 벤더 매크로
    # 누락이 대표 원인) 엔트로피 원천이 사라진 실제 결함이다. 조용히
    # 넘기지 않는다.
    error "hiu_trng_ro.xdc: g_ro ring-oscillator nets NOT FOUND. TRNG was optimized away — check that synth_design passed -verilog_define WT_VENDOR_VIVADO=1 (see include/attributes.vh)."
}

set_property ALLOW_COMBINATORIAL_LOOPS TRUE $wt_ro_nets
puts "WT-XDC hiu_trng_ro: ALLOW_COMBINATORIAL_LOOPS TRUE on [llength $wt_ro_nets] g_ro net(s)"

# ---- 2. RO 셀 보존 (HIU.v:337 이 규정한 DONT_TOUCH) ----------------------
# RTL 의 `WT_DONT_TOUCH attribute 가 이미 같은 일을 하지만, XDC 쪽에도
# 걸어 두면 벤더 매크로가 누락된 채로 합성됐을 때 phys_opt_design 단계에서
# 루프가 붕괴하는 2차 경로를 막는다.
set wt_ro_cells [get_cells -quiet -hierarchical -filter {NAME =~ *g_ro*ro_s*}]
if {[llength $wt_ro_cells] > 0} {
    set_property DONT_TOUCH TRUE $wt_ro_cells
    puts "WT-XDC hiu_trng_ro: DONT_TOUCH TRUE on [llength $wt_ro_cells] g_ro cell(s)"
}

# ---- 3. RO 경로 타이밍 제외 (HIU.v:338 이 규정한 set_false_path) ---------
# RO 는 clk 과 무관하게 자유 발진하는 비동기 소스다. RO → ro_meta_q
# (HIU.v:395-407 의 2단 동기화 플롭) 캡처 경로를 타이밍 대상으로 두는 것은
# 의미가 없고, 인버터 체인 지연이 clk 경로 예산에 섞여 들어가는 것도
# 막아야 한다. RO 셀은 ro_meta_q 외에는 아무것도 구동하지 않으므로 이
# false path 가 동기 논리를 가리는 부작용은 없다.
if {[llength $wt_ro_cells] > 0} {
    set wt_ro_pins [get_pins -quiet -of_objects $wt_ro_cells]
    if {[llength $wt_ro_pins] > 0} {
        set_false_path -through $wt_ro_pins
        puts "WT-XDC hiu_trng_ro: set_false_path -through [llength $wt_ro_pins] g_ro pin(s)"
    }
}

unset -nocomplain wt_ro_nets wt_ro_cells wt_ro_pins
