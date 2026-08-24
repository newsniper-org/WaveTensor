---
name: yosys-bind-trap
description: yosys 0.66 이 SVA bind 를 조용히 무시 — 하네스가 제거돼 공허 PASS. expose+래퍼로 대체
metadata: 
  node_type: memory
  type: feedback
  originSessionId: e7f99d7a-a6eb-46be-b7eb-fd78237e02a7
  modified: 2026-08-24T03:16:10.139Z
---

yosys 0.66 네이티브 프런트엔드는 SystemVerilog `bind` 지시를 **오류 없이 파싱하되 조용히 무시**한다 (2026-08-24, 최소 재현 3변형 실측 — 파일 꼭대기·모듈 스코프·-defer 무관). 하네스 모듈이 「Removing unused module」로 제거되어 **모든 sby 태스크가 공허 PASS** 가 된다. WT64v1 후-formal 1차 파도에서 에이전트 3팀이 독립적으로 같은 함정을 밟고 각자 적발했다.

**Why:** bind 미지원이 경고조차 없어서, 증명이 "돌았고 통과했다"는 관측이 아무것도 보증하지 않는다.

**How to apply:**
1. WT64v1 의 하네스는 `bind` 가능한 형태를 유지하되 sby [script] 의 `expose` + `<Module>_formal` 래퍼(또는 텍스트 전개)로 부착한다 — 선례: `rtl/sv/assert/*.sv` 및 각 `.sby` 의 경위 주석.
2. **공허 검출법**: `model/design_smt2.smt2` 의 `yosys-smt2-assert` 셀 수 확인 + cover 태스크의 reached 증인. 새 하네스마다 이 확인을 완료 기준에 포함.
3. 부수 함정: generate 루프 안 단언 라벨 유일화 실패("Cannot add procedural assertion") — 라벨 제거·주석 유지. proc_rom ROM 은 귀납 상태 비구속 — `memory_map` 필요.
