<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors -->

# WT64v1 아키텍처 규범 — 재구현 기준 문서

**지위가 두 겹이고, 두 번째가 더 무겁다.**

1. **소개 자료** — 무엇을 만들고 있고, 어디까지 실측됐으며, 왜 프로토타이핑
   용량이 필요한가 (부록 A).
2. **RTL 전면 재구현의 기준** — 재구현팀이 원본 RTL 을 **보지 않고** 이 문서만으로
   동등한 구현을 만들 수 있어야 한다.

## 빌드

```sh
typst compile main.typ          # → main.pdf (75쪽, A4)
typst watch  main.typ           # 집필 중
```

요구: **Typst ≥ 0.14** (실측 0.14.2) · `Noto Serif/Sans/Sans Mono CJK KR`.

## 구조

```
main.typ                  문서 설정 · 표지 · 목차 · include
lib/template.typ          조판 규약 — 규범/해설/함정/트랙/등급 환경을 여기서만 정의
chapters/00-preface.typ   문서 지위 · **이 기계는 무엇인가** · clean-room 규약 · 이원화 표기
chapters/01-isa-asm.typ   ISA 계약 + 형상 독립성(INV-T1/T2/T3) + 어셈블러
chapters/02-fabric-alu.typ 패브릭 계층 · 상호연결 실체 · 가변 ALU 3기전
chapters/03-hiu.typ       HIU 정의·경계 · 테넌트 임대 · 구성 표면
chapters/04-ext-payload.typ 확장 헤더 순회 · 조각 재조립 · Wave-Ordered Memory
chapters/05-security.typ  주소 마스킹 · 상수 시간성 · 엔트로피원
chapters/06-formal.typ    선-formal → RTL → 후-formal
appendix/a-capacity.typ   프로토타이핑 용량 산정 (실측 전수 + 벤더 질문)
appendix/b-gaps.typ       기존 문서와 어긋나는 지점 — **재구현팀이 먼저 읽을 것**
appendix/c-glossary.typ   국문–영문 용어 대응
appendix/d-properties.typ 형식 속성 카탈로그 (39개 색인 — 선 27 / 후 12)
appendix/e-defined.typ    재구현이 새로 정의한 표면 (계약이 없어서 정한 것)
refs.yml                  Hayagriva 서지 (42항, 전부 본문 인용)
```

## 이 문서가 지키는 제약

| 제약 | 왜 | 검사 |
|---|---|---|
| **clean-room** — 내부 모듈명·신호명·파일/줄 참조·RTL 인용 배제 | 구현 표현이 섞이면 독립 구현 주장이 무너진다 | 아래 스캔 = **0건** |
| **금지 용어** — "마이크로코드"/"microcode" | 번역 계층이 아니다. 정본은 **step sequencer / step** | 금지 선언 자체를 빼면 **0건** |
| **출처 등급** — 실측/유도/목표/미측정 | "합성 도구 출력" 과 "실물 관측" 을 섞지 않기 위해 | 서문 §0.5 |
| **정의 우선** — 각 장은 자기 주제를 먼저 정의한다 | 재구현팀은 문맥을 공유하지 않는다 | 7장 전부 `#정의` 보유 |
| **실측 0건 고지** | 이 프로젝트에 실리콘·FPGA 실물 실측이 **한 건도 없다** | 서문 · 부록 A · 부록 B |

## 검증

```sh
# 1) 컴파일 — 경고 0
typst compile main.typ

# 2) 폰트 임베딩 (CID 서브셋)
pdffonts main.pdf

# 3) clean-room 위반 스캔 — 0 이어야 한다
grep -REn "EHDecode|PE_Core|ISA_Decoder|Top_Core|FP_(StepSeq|Mul36|AddWide|Acc\w+|Train\w+|Fma\w+)|TENSOR_ALU|SIMD_ALU|ALU_Extended|dma_engine|\bpcid\b|\bNUM_PES\b|\bMAX_EH\b|\bTLB_ENTRIES\b|\bNUM_PARTITIONS\b|\bvirt_addr\b|\bdma_req\b|\w+\.(v|py|tcl|xdc):[0-9]+" chapters appendix main.typ

# 4) 금지 용어 — 5건이 나오며 **전부 금지 규율 자체를 서술하는 줄**이어야 한다
#    (서문 2 · 2장 1 · 용어집 1 · 부록 B 1). 그 밖의 용법이 나오면 위반이다.
grep -rn "마이크로코드\|microcode" chapters appendix

# 5) 서지 무결성 — 미정의 인용 0 / 미인용 0

# 6) 속성 수 대조 — 세 수가 전부 같아야 한다 (부록 D 는 색인이지 원천이 아니다)
grep -c '^  \[\(ISA\|FAB\|HIU\|EXT\|SEC\)-' appendix/d-properties.typ   # 색인 행
grep -ho '#속성("[A-Z]*-[0-9]*"' chapters/*.typ | wc -l                 # 각 장 선언
#    그리고 부록 D 의 축별 분류 합계도 같아야 한다.
#    이 검사가 없어서 실제로 드리프트했다 — 표는 27, 실물은 39였다.
```

실측 결과 (2026-08-20): 컴파일 경고 **0**, clean-room 위반 **0**, 서지 42/42,
수치 대조 35/35, `make lint` **exit 0**, `fp_op_gate_check.py` **exit 0**,
tracked 파일 변경 **0**.

정정 후 재실측 (2026-08-20, 판 0.1 결손 수리): 75쪽, 컴파일 경고 **0**,
clean-room 위반 **0**, 금지 용어 **5건 전부 규율 서술 줄**,
속성 수 **39 = 39** (선 27 / 후 12), HIU 속성 **1–11 정렬**.

## 수치의 출처

부록 A 의 모든 실측치는 저장소 산출물과 대조된다.

| 축 | 출처 |
|---|---|
| UltraScale+ 게이트 6종 | `python3 synth/scripts/fp_op_gate_check.py` |
| Pod 규모 (16 PE) | `synth/reports/pod_2x2_2x2_impl_{util,timing}.rpt` |
| ECP5 관측 | `synth/lattice/reports/cluster_v19b_pnr.log` |
| 번들 등급 분리 | spec §39.1 D-37 (실측 기록) |

> ⚠️ **부록 A 의 벤더 쪽 항목은 비어 있다.** 장비 제원을 확인하지 못했으므로
> 추정치 대신 **질문 목록**(A.7)으로 남겼다. 확인하지 못한 것을 적지 않는 것이
> 이 저장소의 규율이다.
