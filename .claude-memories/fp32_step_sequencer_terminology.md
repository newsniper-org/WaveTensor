---
name: fp32-step-sequencer-terminology
description: "v1.8.0c fp32 유닛은 \"마이크로코드\"가 아니라 \"스텝 시퀀서(step sequencer)\"로 지칭 — 사용자 지시 (2026-07-16)"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 09e02def-fe68-4449-8866-9db15ac81932
---

# fp32 유닛 용어: "스텝 시퀀서(step sequencer)" (마이크로코드 금지)

v1.8.0c fp32 유닛(FSCALAR/FRSQRT32/FEXP2_32)의 실행 구조 — fp_step
카운터가 붙은 고정 FSM이 공유 곱셈기/adder에 패스를 순서대로 흘리는
하드와이어드 시퀀스 — 를 지칭할 때 "마이크로코드(microcode)"라는 용어를
쓰지 않는다. 대신 **"스텝 시퀀서(step sequencer)"** / 영문 산문에서는
"step-sequenced FSM", 개별 패스는 "micro-op" 대신 **"step"** 으로 쓴다.

**Why:** 사용자 지시 (2026-07-16, v1.8.0c 착수 직후): "용어 혼동 우려가
있으니 '마이크로코드' 대신에 다른 용어로 지칭하는 게 좋겠어."
프로그래머블 마이크로코드 저장소(ROM/RAM 제어 스토어)가 있는 것으로
오해될 수 있음 — 실제로는 Verilog case 문의 고정 시퀀스.

**How to apply:** spec(§23.10), RTL 주석, commit 메시지, 테스트 이름,
memory 파일 전부에 적용. 설계안 명칭도 "sequential-microcode-mu" 대신
"MU-hosted fp32 step sequencer"로 표기. 신호명 fp_step, generate 블록
g_v180c_fp 는 그대로 유효. DIV 의 "bit-serial FSM"과 같은 명명 계열.
관련: [[wt64v1-precision-recovery-roadmap]]
