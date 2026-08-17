# SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
#
# u30_pod_hiu.xdc — Pod+HIU 묶음 gate 제약 (Alveo U30 / xcu30-fbvb900-2-e)
#
# 기준 클럭: 10.000 ns (100 MHz) — synth/constraints/pod.xdc 와 동일 기준으로
# U55C -2L Pod 실측(WNS -0.205 ns)과 직접 비교 가능하게 맞춘다.
#
# 정찰 결함 D2 (HIU TRNG ring oscillator) 의 ALLOW_COMBINATORIAL_LOOPS /
# DONT_TOUCH / set_false_path 는 넷리스트 객체가 존재해야 매칭되므로 이
# 파일이 아니라 u30_pod_hiu.tcl 의 apply_d2_constraints 프로시저에서
# synth_design 직후에 적용한다 (적용 개수를 로그에 찍는다).

create_clock -name clk -period 10.000 [get_ports clk]

# rst 는 두 블록 모두에서 posedge async reset 으로 쓰인다 (pod.xdc 선례).
set_false_path -from [get_ports rst]
