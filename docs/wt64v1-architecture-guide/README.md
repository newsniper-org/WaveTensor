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
make -C ../.. guide             # → main.pdf (A4) + 렌더 검사 — 쪽수는 check_guide_render 가 낸다
typst watch  main.typ           # 집필 중 (끝나면 make guide 로 마감할 것)
```

> `make guide` 가 정규 진입점이다 — 컴파일 성공과 렌더링 정상은 다른
> 명제이기 때문이다. 부록 B.5 표가 73쪽으로 부풀어 있는 동안 raw
> `typst compile` 은 경고 0 으로 성공했고, 쪽수 보고도 반복됐지만
> *렌더링은 아무도 보지 않았다.* `scripts/check_guide_render.py` 가
> 한 글자 세로 흐름 쪽을 전수 검사한다.

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
appendix/d-properties.typ 형식 속성 카탈로그 (43개 색인 — 선 31 / 후 12)
appendix/e-defined.typ    재구현이 새로 정의한 표면 (계약이 없어서 정한 것)
refs.yml                  Hayagriva 서지 (45항, 전부 본문 인용)
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
# 1) 컴파일 + 렌더 검사 — 경고 0 · 세로 흐름 0
make -C ../.. guide

# 2) 폰트 임베딩 (CID 서브셋)
pdffonts main.pdf

# 3) clean-room 위반 스캔 — 0 이어야 한다
grep -REn "EHDecode|PE_Core|ISA_Decoder|Top_Core|FP_(StepSeq|Mul36|AddWide|Acc\w+|Train\w+|Fma\w+)|TENSOR_ALU|SIMD_ALU|ALU_Extended|dma_engine|\bpcid\b|\bNUM_PES\b|\bMAX_EH\b|\bTLB_ENTRIES\b|\bNUM_PARTITIONS\b|\bvirt_addr\b|\bdma_req\b|\w+\.(v|py|tcl|xdc):[0-9]+" chapters appendix main.typ

# 4) 금지 용어 — 5건이 나오며 **전부 금지 규율 자체를 서술하는 줄**이어야 한다
#    (서문 2 · 2장 1 · 용어집 1 · 부록 B 1). 그 밖의 용법이 나오면 위반이다.
grep -rn "마이크로코드\|microcode" chapters appendix

# 5) 서지 무결성 — 미정의 인용 0 / 미인용 0

# 6) 파생 표 대조 — **기계 검사로 옮겼다.** 손으로 돌리는 검사는 안 돌아간다.
python3 ../../scripts/lint_guide_derived_tables.py
#    각 장 #속성 선언 수 · 부록 D 색인 행 · 축별 분류 세 행과 합계 ·
#    단계별(선/후) 분류 · 진행 현황의 run 수 vs rtl/formal/tla/run.sh 를 대조한다.
#    `make lint` 와 pre-commit 훅에 결선돼 있으므로 별도로 돌릴 필요는 없다.
#
#    이 대조가 셸 스니펫이던 동안 드리프트가 **다섯 번** 났다 (축별 분류 27 vs
#    실물 39, §3.9 요약, README 쪽수, 진행 현황, B.5 해설 산술). 다섯 번 모두
#    컴파일은 통과했고 아무 테스트도 실패하지 않았다 — 파생 표는 틀려도 조용하다.
```

실측 결과 (2026-08-20): 컴파일 경고 **0**, clean-room 위반 **0**, 서지 42/42,
수치 대조 35/35, `make lint` **exit 0**, `fp_op_gate_check.py` **exit 0**,
tracked 파일 변경 **0**.

재실측 (2026-08-27): **170쪽**, 컴파일 경고 **0**, clean-room 위반 **0**,
금지 용어 **전부 규율 서술 줄**, 속성 수 **43 = 43** (선 31 / 후 12),
서지 **45항**.

> **이 수치들은 반드시 낡는다.** authority 는 이 문단이 아니라
> `lint_guide_derived_tables.py`(속성 수·색인 정합)와 `typst compile`
> 출력이다. 산문에 적힌 수는 갱신을 잊는 순간 거짓이 되고, 실제로
> 그렇게 됐다 — 「75쪽 · 속성 40 · 서지 42」가 각각 170·43·45 일 때까지
> 남아 있었다. 세는 것이 기계에 있으면 적지 않는 편이 낫다.

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
