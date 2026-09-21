---
name: lint-section-refs-gotchas
description: lint_section_refs.py(R5)는 git 인덱스만 스캔한다 — untracked 신규 파일은 git add 전엔 안 걸린다. lint_witness_map 의 cover 라벨은 cover( 과 반드시 같은 줄.
metadata:
  type: feedback
  originSessionId: e7f99d7a-a6eb-46be-b7eb-fd78237e02a7
  modified: 2026-09-20T17:08:21.865Z
---

임대별 마스크 키 파도(commit `ca3c496`) 착지 중 실측한 두 함정.

## ⑴ `lint_section_refs.py` 의 R5 래칫은 **git 인덱스**를 스캔한다

`iter_scan_files()` 가 git 인덱스와 교차한다([[rolling-asset-pin-trap]] 계보와
무관한, 이 스크립트 자신의 「세 번째 파도」 수리 — 스크립트 주석에 이력
있음). 그 결과: 새 파일(예 `rtl/formal/tla/Mask.tla`)을 만들어 두고
`make lint` 를 working tree 에서 돌리면 **그 파일은 정의역 밖**이라 조용히
통과한다. 그런데 `git add` 로 스테이징한 순간 인덱스에 들어가고, pre-commit
훅이 다시 `make lint` 를 돌리면 **그제서야** R5(따옴표 없는 §/file:line
인용 상한, 신규 파일은 상한 0)가 걸려 커밋이 막힌다.

**Why:** 사람이 보기엔 "방금 통과했는데 왜 막히지" 로 보이지만, 실은 두
실행이 **다른 정의역**을 스캔한 것 — working tree 냐 인덱스냐.

**How to apply:** 새 `.tla`/`.scala`/`.sv` 파일을 새로 만들어 정본 좌표를
인용하는 편집을 할 때는, `git add` **로 스테이징한 뒤** `make lint` 를 한
번 더 돌려서 확인하라. working tree 에서의 `make lint` 통과는 신규
untracked 파일에 대해서는 아무것도 보증하지 않는다.

R5 위반 시 처분은 둘 중 하나 — ① 좌표 인용 뒤 30자 안에 「축자 인용」을
붙여 R3/R4/R6 축으로 옮기거나 ② `AX1_UNMEASURED_HARD_MAX`/
`AX2_UNMEASURED_HARD_MAX` 딕셔너리(스크립트 자신 안의 상수)를 실측치로
올리고 날짜+사유 주석을 남긴다. 이 파도는 전부 ②를 택했다 — 해설 산문이
인용 *앞*에 이미 산문 요약(「…」)을 달고 있어서 R6 의 「좌표 *뒤*」 결속
관용구와 안 맞았기 때문(축자 재구성이 더 위험한 고비용 작업이었다).

## ⑵ `lint_witness_map.py` 의 cover 라벨은 `cover(` 과 **같은 줄**이어야 한다

내부 정규식 `_LABELED = re.compile(r"\b([a-z][a-z0-9_]*)\s*:\s*cover\s*\(")`
이 **줄 단위**로 매칭한다(`parse_covers()` 가 `line.split("//",1)[0]` 로
한 줄씩 검사). SystemVerilog 문법상 `label:` 과 `cover(...)` 을 다른 줄에
적어도 **컴파일은 완벽히 유효**하고 yosys 도 라벨을 올바로 단다 — 그런데
이 lint 스크립트는 그 형태를 "무명 cover"(라벨 없음)로 오판하고, 동시에
그 태그(`// W16 ← ...` 선언)를 "라벨이 하나도 없다"로 오판한다.

**Why:** 정규식이 문법을 파싱하지 않고 줄 단위 텍스트 매칭만 하기 때문.
이 저장소의 다른 모든 cover 문(`w1_rsp:` ~ `w18_rekey_busy_reject:`)이
전부 한 줄 관용구를 지켜 왔던 이유가 바로 이 정규식이었다 — 아무도
명시적으로 규칙을 적지 않았지만 코드베이스가 암묵적으로 그 형태로
수렴해 있었다.

**How to apply:** 새 `cover` 문을 쓸 때 `if (cond) label: cover(expr);`
형태를 **한 줄에** 적어라(줄이 길어져도). `if (cond)\n  label:\n
cover(...)` 처럼 줄을 나누면 lint 가 실패하고, 원인 메시지("무명 cover"·
"라벨이 하나도 없다")가 진짜 원인(줄바꿈)을 직접 가리키지 않아 헷갈리기
쉽다.

관련: [[confession-outside-the-machine]] (같은 부류 — 검사 스크립트
자신의 정의역/파싱 한계가 결함을 가린다) · [[wt64v1-rtl-reimplementation]].
