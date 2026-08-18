# SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

# pod.xdc — constraints for OOC synthesis of Pod.v
#
# Out-of-context mode means there are no physical pin assignments — the
# Pod's ports are kept as boundary I/O. We still need a clock definition
# so timing reports are meaningful.
#
# Initial target: 100 MHz (10 ns period). The single-cycle decoder's
# critical path is the EH chain walk inside ISA_Decoder.v; if synthesis
# fails timing at 100 MHz we'll either pipeline that walk or relax to a
# slower clock for the first bring-up.

create_clock -name clk -period 10.000 [get_ports clk]

# Treat reset as asynchronous to the clock domain it deasserts into; the
# decoder uses posedge rst as an async reset, so this matches the RTL
# semantics.
#
# NARROWED TO CLR/PRE — spec §29.7 XDC 정정 (2026-08-18).
#
# 넓은 형태 (`set_false_path -from [get_ports rst]` 단독) 는 참이 아니었다:
# Vivado 는 reset 분기에서 대입되지 않는 레지스터의 `rst` 를 **CE LUT 의
# 데이터 입력**으로 접어 넣는다 (`CE = !rst & enable`; §29.2 C4 의 INIT
# 실측). LUT 데이터 입력은 setup/hold 가 걸리는 **동기 경로**이므로, 넓은
# false_path 는 실리콘에서 데이터 캡처를 게이팅하는 경로를 타이밍 분석에서
# 통째로 빼고 있었다. Pod 문맥에는 PE_Core 68건이 아직 남아 있다
# (§29.7 이월) — 즉 이 정정은 지금 실효가 있다.
#
# **좁힌 형태는 이 파일에 둘 수 없다.** `REF_PIN_NAME == CLR|PRE` 는
# 넷리스트 primitive 핀을 매칭하는데 이 XDC 는 `synth_design` **이전**에
# read 되므로 그 시점에 매칭 대상이 0개다 — 여기에 그대로 적으면 예외가
# **조용히 사라진다** (loud-fault-never-silent 위반, 넓은 형태보다 나쁘다).
# 그래서 `synth/scripts/synth_pod.tcl` 이 `synth_design` 직후에 건다.
# 아래 줄은 의도적으로 남긴 빈 자리이며, 예외의 실물 위치는 그 스크립트다.

# The wide instruction bus (416 bits) and 80-bit tag are I/O for OOC; we
# leave them unconstrained for input/output delay (Vivado will warn about
# unconstrained I/O — expected and ignored at this OOC stage).
