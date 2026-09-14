---
name: dev-platform-and-rust-baseline-policy
description: 권장 개발환경 5종(목록 열림) · musl/Bionic/glibc 3-ABI · asm 의 pure Rust 포팅(착수 시기 미정, 동결 금지) · 모든 Rust 는 2024 Edition + stable >= 1.97 · Y4 ABI 확정이 Y4용 드라이버/SDK 의 블로커 (사용자 방침 2026-08-30)
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 09e02def-fe68-4449-8866-9db15ac81932
  modified: 2026-08-30T05:42:09.991Z
---

# 개발환경 · ABI · Rust 기준 방침 (사용자 2026-08-30)

방침 원문의 **축자 사본**과 이 저장소 실측·미결 등재표는
`.claude-memos/dev_platform_axis.md` 에 있다. 여기는 색인이다 —
**해석이 원문을 대체하지 않도록 원문은 그 문서 §0 에만 둔다.**

## 네 조항 (요지)

1. **권장 개발환경** — Alpine(musl ABI) · LineageOS 23.2/AOSP 16(Bionic ABI) ·
   openSUSE Slowroll(glibc ABI) · NetBSD 11.0 · DragonFlyBSD 6.4.2.
   ⚠️ 원문이 `...` 로 **목록을 열어 두었다 — 닫지 마라.** 「이 다섯이 전부」로
   적으면 방침을 왜곡한다. 「현재까지 명시된 것」으로 적어라.
   ⚠️ 「**권장**」이지 「지원 대상」이 아니다. 개발환경 축과 빌드 타깃 축을
   섞지 마라 (다만 세 ABI 를 명시로 가른 것은 빌드 타깃 분할로 읽힌다).
2. **asm 포팅** — Python 어셈블러를 pure Rust 로 port **예정**.
   **착수 시기 미정** — 「진행 중」·「다음 단계」로 승격하지 마라.
3. **Rust 기준** — 모든 Rust 코드는 2024 Edition, stable toolchain **>= 1.97**.
   ⚠️ **하한이지 핀이 아니다.**
4. **Y4 ABI 는 블로커** (`!!`) — 구체적 Y4 ABI 확정 **전에는** Y4용 드라이버/SDK
   개발에 착수할 수 없다.

## 이미 내려진 판정 — 미결로 적지 마라

- **유보** (작업 큐 #37): Y4 Rust 하한 정합은 **지금 맞추지 않는다.**
  「일단 verus-fork 쪽 개발 작업들(custom backends, 최신 Verus upstream으로부터
  rebase 등...) 부터 먼저 해놓고 나서 추후 결정.」 → 「미정」이 아니라
  **선행 조건이 명명된 유보**다.
- **결정 A** (#38): Bionic 축의 소비자는 **드라이버와 NDK**다.
  「Bionic은 드라이버 및 NDK에서 필요로 하잖나?」 (JVM 은 그 축의 칸이 아니다.)
- **결정 B** (#38): Python 어셈블러를 **동결하지 않는다.**
  「Python 어셈블러는 내가 명시적으로 지시하기 전까지는 동결하지 말도록.」
  ⇒ Phase C 비트-동등 기준선은 **움직이는 표적**이고, 델타 통지는 반복 이벤트다.

## 이 저장소에서 실제로 걸리는 것 (실측 2026-08-30)

- **Rust 실물이 0 이다** — `.rs` 0 · `Cargo.toml` 0 · `rust-toolchain*` 0.
  `lint_toolchain_pins.py` 의 핀 계통에도 Rust 축이 없다.
  ⇒ **지금 Rust lint 축을 세우면 공허 게이트다** (「안 돌면서 OK 를 인쇄」).
  방침의 Rust 조항은 이 저장소에서 「지금 재는 것」이 아니라 **「착수 시 걸리는 것」**.
- **포팅이 건드리는 것은 오라클 지위 하나가 아니다 — 역할 일곱이다.**
  가장 급한 것은 `scripts/lint_guide_derived_tables.py` 로, 정본 §1.3.1·§4.5·부록 B
  의 일관성 게이트인데 진실 원천이 `asm/wavetensor_asm.py` 의 **Python 문법**
  (`^INSTR_WORDS_REAL\s*=\s*(\d+)\s*$`)에 박혀 있다. Rust 상수는 불일치 →
  경고가 아니라 **`sys.exit(1)`**. 그리고 `scripts/lint_section_refs.py` 의
  `asm/` 은 **hard 구역 래칫**이라 파일이 떠나면 *하강도* 실패한다.
  ⇒ **이 처분은 포팅 착수 *전에* 나야 한다.**
- **OS/ABI 축은 선례 없는 신설 축이다** — musl/Bionic/glibc/openSUSE/LineageOS
  전수 grep 0건. 이름이 겹치는 Alpine/NetBSD/DragonFly 3건은 **전부 다른 뜻**
  (원격 호스트 OS 후보 · Y4 드라이버 소스 계보).

## How to apply

- 이 방침을 문서에 옮길 때 **`...` 를 닫지 말고**, 「권장」을 「지원 타깃」으로
  승격하지 말고, 「예정」을 「진행 중」으로 승격하지 마라.
- 방침이 답하지 않은 것은 **미결로 등재**하라 (`dev_platform_axis.md` §6,
  11건 — Q1~Q9 · Q11 · Q12. Q10 은 결정 B 로 닫혀 결번이다).
  그럴듯한 값을 채워 넣는 것이 이 프로젝트가 반복해 밟은 함정이다.
- 형제 저장소(Y4 · wavetensor-sdk · wavetensor-drivers)의 핀이 방침과 어긋나면
  **조용히 맞추지 말고 충돌로 보고**하라. Y4 의 셋은 이미 #37 로 유보됐다.
- 관련: [[wavetensor-sdk-lives-in-its-own-local-repo]] · [[y4-hypervisor-lives-in-its-own-local-repo]] · [[rolling-asset-pin-trap]]

**2026-09-14 — 「Y4 ABI」의 범위(후보 ⒜ B 단독 / ⒝ B+D / ⒞ B·C·D, Y4 `glossary.md` §11)는
**Y4 측이 직접 블로커 해소 작업 중**이다. 사용자 지시 축자: 「지금 Y4 측에서 이 문제에 대한
블로커 해소 작업을 하고 있으니, 기다리는 게 좋겠어.」 ⇒ WaveTensor 쪽에서 질의 파도를 띄우지
마라(하나 띄웠다가 중단했고 Y4 에 흔적은 남지 않았다). Y4 의 답이 `design_decisions.md` 나
`glossary.md` §11 에 착지하면 그때 WaveTensor·SDK·drivers 의 미결 등재처 넷을 닫는다.
