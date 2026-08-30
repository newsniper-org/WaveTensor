#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""인용 좌표의 **실재**와 **대상** 검사 — 세 축.

## 게이트의 이름과 정의역 (§6.7 — 과대 명명 금지)

이 스크립트의 이름은 「절 인용 실재성 검사」였고, 그 이름이 정확했다. 지금은
셋을 잰다:

    축 0  `@sec:라벨 N.M`   — 라벨·절 실재 + 따옴표 대조   (원래 있던 축)
    축 1  `파일:줄[-줄]`     — 좌표 실재 + **따옴표 대조**   (신설)
    축 2  `§N.M[.K]`        — 절 실재 + **따옴표 대조**     (실재만 있었다)
    축 2b 「N.M 함정」        — 그 절 안의 블록 **종류**

**세 축 전부 「따옴표가 붙은 인용」만 대상을 잰다.** 따옴표 없는 인용은
*통과가 아니라* 「안 잰다」로 별도 계수해 인쇄한다 (§6.6.5 「대상 오인」 —
거짓 음성은 우는 소리를 내지 않으므로 세지 않은 것을 통과로 인쇄하면 그
숫자가 거짓 확신의 근거가 된다).

## 게이트의 정의역 — **누가 썼는가**에 따라 처분이 다르다 (2026-08-30)

발신 구역 셋을 구분한다 (아래 `sender_zone()`):

    hard      정본 · `rtl/` · `proofs/`   — 상한(R4·R5·R6)과 하한이 전부 건다
    curated   그 밖의 `docs/`             — **축 1 덮임 하한**이 여기까지 센다
    volatile  `.claude-memos/` 등         — 래칫 없음. **인쇄만** 한다

이 구분이 없던 동안 이 스크립트는 스스로 F-52 뇌관을 심고 있었다: R5 상한은
volatile 구역을 「매 커밋 거짓 실패한다」며 면제했는데 **덮임 하한은 면제하지
않았다.** 축 1 의 대조 41건 중 35건이 volatile 발신이었으므로, 메모 두 줄을
의역하는 평범한 편집이 정본 부록 두 개의 하한을 깨고 커밋을 막았다. 반대
방향도 성립했다 — `a-capacity.typ` 의 하한 1 은 **손상된 인용 하나**로만
충족되고 있었고, 그것을 옳게 되돌리는 순간 `make lint` 가 실패했다. 게이트가
잘못된 인용을 *보존하도록* 압력을 만든 것이다.

오늘 실측으로 이 게이트가 **덮지 않는 것**:

  · 따옴표 없는 좌표 인용 — 축 1 약 860건 · 축 2(hard 구역) 509건.
    실재만 확인되고 **대상은 재지 않는다.** 재번호·삽입에 무방비다.
    (수 자체는 R5 가 파일별로 잠근다 — 「새 인용은 따옴표를 달고 태어나라」.)
  · 비정본 문서의 `§N.M` — `token-pressure.md` 류는 **자기 `### N.M` 번호
    체계**를 갖는다 (약 1,200건). 자기 번호와 정본 번호를 문법으로 구별할
    방법이 없어 정의역 밖으로 둔다. **예외 하나**: 인용 바로 앞 창에 정본의
    이름/경로가 있으면 문면이 스스로 「이것은 정본 번호다」라 말하므로 대조
    한다 (그 예외가 없는 동안 W6 이 밟은 자리가 검사 밖에 있었다 — 아래).
  · **축 1 의 미추적 파일** — 정의역은 `git ls-files`, 즉 **인덱스**다.
    「저장소 전역」이 아니다. `git add` 되지 않은 파일의 좌표는 하나도 보지
    않으며, 그 파일 수와 좌표 수를 OK 줄에 따로 인쇄한다.
  · **반증력 없는 대조** — 보통명사 인용(「형식 속성」은 정본 12개 절이
    소유한다)과 묶음의 일부 적중은 통과로 두되 **덮임에서 뺀다.** 어느 절
    번호로 바꿔도 통과하므로 재번호를 잡지 못한다 (오늘 15건).
  · **의미의 적합성** — 문장이 그 절에 있어도 그 인용이 옳은 근거인지는
    재지 않는다.
  · **태어날 때부터 틀린 좌표** — 따옴표가 없으면 이력 축(`--drift`)도
    「내용이 바뀌었다」만 재지 「인용이 옳았는가」를 재지 않는다.
  · **맨 줄 좌표** — `` `02-fabric-alu.typ:597-599` … (`:601-602`) `` 처럼
    앞 인용의 파일을 물려받는 형태. 2026-08-30 실측 **225건**이고 축 1 은
    이것의 **실재를 재지 않는다** (결속을 *끊는* 데에는 쓴다 — 아래 축 1
    인라인 결속기). **일부러 넣지 않았다**: 「같은 줄의 가장 가까운
    파일 언급을 물려받는다」는 규칙으로 시제품을 돌렸더니 실재성 위반이 6건
    나왔는데 **6건 전부 오탐**이었다 — `wt64v1_spec.md` 처럼 *자기 자신*의
    절 배너를 `` §23 배너(`:2589`) `` 로 가리키는 문서에서 규칙이 엉뚱한
    파일을 물려준다. 참을 하나도 못 잡으면서 거짓만 내는 검사를 켜면 F-52
    (「하드 게이트가 거짓 실패하고 그 반작용으로 게이트를 끈다」)다.
    ⇒ 이 부류의 **실재 검사**는 사람 검토에 남는다.

    > 그리고 이 부류가 실제로 오검을 만들었다 (2026-08-30). 축 1 의 인라인
    > 결속기가 따옴표 **앞**만 막고 **뒤**를 막지 않아, 「좌표 A … 「인용」
    > (`:B`)」 형태에서 B 의 인용이 A 에 붙어 A 를 거짓 STALE 로 판정했다.
    > 그 거짓 STALE 3건을 「재조준」한 편집이 **옳던 좌표 셋을 틀린 좌표로
    > 바꿨다.** 축 0·2 가 쓰는 `bind_quote()` 는 앞뒤 양쪽을 막는데 축 1 만
    > 한쪽이었다 — 그 비대칭이 결함이었고, 지금은 양쪽을 막는다.

## 왜 이 검사가 있는가

2026-08-27 실측 — 정본이 토큰 비증식 규범(ISA-9)을 **§1.4.6 으로 가리키는
자리가 열두 곳**이었다. 실제 자리는 §1.4.2 이고 §1.4.6 은 「OPREF 의 포트
인덱스 — 폐지」다. **그중 여섯은 하루 사이에 생겼다** — 그 규범을 개정하던
사람이 개정하면서 틀린 번호를 새로 여섯 번 적었다.

같은 날 두 번째 사례도 나왔다: `01-isa-asm.typ` 이 「순회를 멈추는 것이
아니라 효과를 멈춘다」를 §4.3 이 적은 것으로 인용했는데 그 문장은 §4.2.1 에
산다. 같은 파도의 `b-gaps.typ` 은 4.2.1 로 옳게 인용했다 — **정본이 같은
문장을 두 절 번호로 불렀다.**

근본 원인은 오탈자가 아니라 **배치**다. 한 절의 제목이 그 절이 담은 규범을
예고하지 않으면(ISA-9 는 「입력 포트 마스크 — 폐지」라는 제목의 절 안에 산다)
인용하는 쪽은 번호를 *확인하지 않고 짐작한다.* 그리고 절은 문서를 고칠 때마다
움직인다.

정본이 재구현의 유일한 기준인데 그 기준이 자기 안에서 어긋난 좌표를 가리키면,
그것을 밟는 쪽은 기준을 따랐다고 말할 수 있다.

## 축 1·2 를 왜 뒤늦게 더했는가 — 정본 환류 8파도가 남긴 최대 결손

**축 1** — W4·W5·W7a·W7b·W8 이 **연속으로** 「이름 붙은 형제 문서 인용 N건은
대조 대상 밖」을 밟았고 매번 손으로 25곳 안팎을 고쳤다. W7b 는 편집 전
스냅숏 → 이동 후 238/238 내용 동일로 기계 검증했으나 **그 스크립트가 저장소에
남지 않았다.** 그리고 그 방법이 보장하는 것은 내용 보존뿐이다 — 맞던 것은
계속 맞고 **이미 틀렸던 것은 계속 틀리다.**

**축 2** — W6 실측: on-wire 절 삽입으로 §3.11 이 형식 속성에서 원격 표면으로
바뀌었을 때 그 부류 **6건이 「파손 0」인 채로 틀려 있었다**(정본 3 + `rtl/` 3).
그 파도의 「파손 0」은 이 부류에 대해 **무증거**였다. 실재만 재는 검사는
재번호 후에도 통과한다.

> **그런데 축 2 를 켠 뒤에도 W6 그 자리는 움직이지 않았다** (2026-08-30 재현
> 실측). `03-hiu.typ:1330`(= W6 이 절을 삽입한 정확한 자리) 앞에 절을 하나
> 넣어 §3.11 을 재번호해도 세 축이 한 자리도 울지 않았다. 원인은 정의역
> 이었다 — 오늘 저장소의 `§3.11` 인용은 전부 `.claude-memos/onwire_format_spec.md`
> 에 살고, 그 문서가 자기 `## 3.` 절 체계를 갖는다는 이유로 `selfnum` 필터가
> 통째로 걸러 냈다. **이 검사의 동기가 된 자리가 검사되지 않고 있었다.**
> ⇒ 두 가지를 더했다: ① 정본을 이름으로 지목한 인용은 `selfnum` 을 넘어
> 대조한다. ② 비-hard 발신의 대상 대조를 켜고 R4′ 로 잠근다 (실측 오탐 0).
> 이제 그 자리를 재현하면 `onwire_format_spec.md:9` 가 실패로 뜬다.

2026-08-30 전수 실측이 오늘의 기준선을 세웠다 (아래 래칫 표).

## 오탐을 낮춘 다섯 규칙 (실측이 강제한 것)

무보호 시제품은 hard 구역에서 non-OK 21건 중 참 4건 — **오탐 81%** 였다.
그대로 켰으면 F-52 가 이름한 형태(「하드 게이트가 거짓 실패하고 그 반작용으로
게이트를 끈다」)를 그대로 밟았을 것이다. 다섯을 넣어 7건/참 3 → 0건/참 0 까지
내렸다:

 1. **자기 인용 제외** — 같은 파일 안의 인용이면 인용문 자신을 대조 대상에서
    뺀다. 없으면 정본 안 인용 5건이 전부 거짓 실패한다.
 2. **번호 개입 시 미결속** — 인용과 따옴표 사이(또는 따옴표 바로 뒤)에 다른
    절 번호가 있으면 「안 잰다」. `MmioConfig_props.sv:4` 가 그 형태였다 —
    따옴표가 뒤따르는 `(§3.7.1)` 의 것인데 앞 `§1.4.5` 에 결속됐다.
 3. **문단 경계 차단** — 빈 줄을 넘어 결속하지 않는다. `01-isa-asm.typ:976`
    이 그 형태였다.
 4. **목록 인용의 묶음 판정** — `(§1.4.2 · §1.4.6)가 … 「…」` 은 따옴표가 두
    번호에 *함께* 걸린다. 묶음의 어느 하나가 소유하면 통과.
 5. **조상 절 허용 + 전 파일 소유자 탐색** — `§1.7` 인용이 `§1.7.3` 에
    적중하면 통과. 그리고 「대상 파일에 없다」와 「**다른 장**에 있다」를
    구별해야 참/거짓이 갈린다 — `Fabric.tla` 의 §6.7 → 실제 §1.2.2 는 다른
    *파일*에 있어야만 잡힌다.

## 사각지대 하나를 실제로 밟았다 (2026-08-27)

이 검사를 만든 날, 같은 사람이 `.claude-memos/di_calculus_extension.md` 의
§4.4.4 를 §4.4.3 으로 **틀리게 「고쳤다」.** 헤딩(`=== `)이 아니라 *본문 언급*을
세었기 때문이다 — `04-ext-payload.typ:631` 이 「§4.4.4 가 … 택했고」라 적는데
그 줄 자체는 §4.4.3 안에 있고, 문자열 검색이 헤딩보다 먼저 그것을 잡았다.

**이 검사는 그것을 놓쳤다** — `@sec:` 형태만 보고 `§N.M.K` 는 보지 않았기
때문이다. 잡은 것은 `Di` 설계의 적대적 검증(사람 쪽)이었다.
⇒ 그날 `§N.M.K` 형태를 검사에 넣었다. **검사가 놓친 자리를 검사에 넣는 것이
이 저장소의 규율이다** (`claude.md` §7.2).

> 그리고 위 문장의 좌표 자체가 낡아 있었다 — 원래 `:602` 라 적혀 있었고 실제
> 자리는 `:631` 이다(Δ+29). **검사기 자신의 근거 좌표가 낡아 있었다.** 축 1
> 이 그것을 잡았다.

## 모드

    (인자 없음)   축 0·1·2 — 빠르다(약 1초). `make lint` 가 이것을 돈다.
    --drift       축 1 의 **이력** 대조. `git blame` 으로 「그 인용을 쓴 커밋
                  시점의 대상 줄 내용」을 뽑아 오늘과 비교한다. 따옴표가
                  필요 없는 대신 약 12초가 걸리고 **전체 이력**을 요구한다.
    --self-test   음성 시험. 기준 문면이 먼저 통과하는지 확인한 뒤 변이를 건다.
                  **래칫을 픽스처 기준선에서 재보정해 켠 채로** 돈다 — 켜지
                  않았던 동안 래칫 집행 코드 전체(R1·R3·R4·R4b·R5·덮임 하한)가
                  이 시험의 정의역 밖이었고, 통째로 지워도 두 게이트가 다
                  통과했다 (§6.3.2 가드 삭제 실험 불통과).
                  **대가는 시간이다** — 2026-08-30 실측 약 6.5초(변이 16개,
                  변이마다 픽스처 전체를 다시 훑는다). 기본 실행은 약 1초다.
                  이 수를 적어 두는 이유: 훅이 느려지면 `--no-verify` 로
                  우회되고, 우회되는 훅은 없는 훅보다 나쁘다. 더 늘릴 때는
                  변이를 더하는 것이 아니라 **가드 삭제 실험으로 정의역을
                  확인**하고 중복 변이를 빼는 쪽을 먼저 본다.

**왜 `--drift` 가 기본 실행이 아닌가** — 둘 다 실측이다. ① pre-commit 훅의
속도 규율이 「합계 약 3초」이고 느린 훅은 `--no-verify` 로 우회된다(우회되는
훅은 없는 훅보다 나쁘다). ② `actions/checkout` 의 기본 `fetch-depth: 1` 에서
blame 은 전 줄을 한 커밋으로 돌려주고, 그러면 이 축은 **조용히 공허하게
통과**한다 — `--drift` 는 그 상태를 감지하면 통과가 아니라 실패한다(공허
게이트 방지). 기본 실행은 `--drift` 를 돌지 않았다는 사실을 인쇄한다.
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

TAG = "lint_section_refs"


# ---------------------------------------------------------------------------
# 정의역
# ---------------------------------------------------------------------------
#
# 인용을 담을 수 있는 파일 — 정본 + 정본을 인용하는 층 (축 0·2)
#
# **`docs/extensions` 가 여기 있어야 하는 이유** (2026-08-29 실측): `Ctrl-min`
# 명세를 `.claude-memos/ctrl_proposal.md` 에서 `docs/extensions/wt64v1-ctrl.md`
# 로 *승격*하면서 이 검사를 잃었다 — 메모 시절에는 `.claude-memos/*.md` 글롭에
# 걸려 §4.2.3·§4.3·§1.4.1·§5.1·§4.4.4 인용이 전부 검사되고 있었는데, 승격이
# 그 문서를 훑지 않는 자리로 옮긴 것이다. 먼저 승격한 확장 명세 넷
# (`di`·`c`·`lf64min`·`lf64di`)도 같은 상태였다. **승격은 검사를 늘려야지
# 줄여서는 안 된다** — 확장 명세는 메모보다 더 정본을 인용한다.
#
# **`proofs/tla` 를 2026-08-30 에 더했다** (§6.7 「검사의 정의역」): `rtl/formal/tla`
# 와 같은 부류인데 글롭에 없어서 `AccBank.tla` 와 `proofs/tla/README.md` 의
# 정본 인용이 통째로 검사 밖에 있었다. 정의역을 손으로 유지하면 새 부류는
# 자동으로 검사 밖에 태어난다.
SCAN_GLOBS_REL = [
    ("docs/wt64v1-architecture-guide", "**/*.typ"),
    ("rtl/formal/tla", "*.tla"),
    ("rtl/formal/sby", "**/*.sby"),
    ("rtl/sv/assert", "*.sv"),
    ("proofs/tla", "**/*.tla"),
    ("proofs/tla", "**/*.md"),
    (".claude-memos", "**/*.md"),
    ("docs/research", "**/*.md"),
    ("docs/extensions", "**/*.md"),
]
# **글롭을 재귀로 바꾼 이유** (2026-08-30 실측): 비재귀 `*.md` 라
# `.claude-memos/generated/isa_tables_frag.md` 가 축 0·2 의 정의역 밖에 있었다.
# 하위 디렉토리는 「새 부류가 자동으로 검사 밖에 태어난다」의 가장 흔한 형태다.

# 축 1 은 **저장소 전역**이 정의역이다 — 좌표 인용은 어디에나 산다.
AX1_SKIP_DIRS = {".git", "__pycache__", "node_modules", ".pytest_cache",
                 ".venv", ".mypy_cache", "sby_out", "sim_build"}
# 합성 도구 산출물 — 좌표가 17,000건 가까이 들어 있지만 **산문 인용이 아니다.**
AX1_SKIP_PREFIX = ("synth/lattice/reports/",)
AX1_SKIP_SUFFIX = {
    ".pdf", ".png", ".jpg", ".jpeg", ".zst", ".gz", ".jar", ".bit", ".hex",
    ".rpt", ".log", ".jou", ".dcp", ".svg", ".vcd", ".fst", ".bin", ".o",
}


# ---------------------------------------------------------------------------
# 정규식
# ---------------------------------------------------------------------------
# `@sec:label N.M[.K]` — 절 번호가 붙은 인용만 본다. 번호 없는 장 참조는 대상 아님.
REF_RE = re.compile(r"@sec:([a-z][a-z0-9-]*)\s+((?:\d+|부록\s*[A-Z])(?:\.\d+)*)")

# 인용 직후의 따옴표 내용.
#
# **거리를 30자로 좁힌 이유** (2026-08-27 실측): 120자로 열었더니 B.5 표의
# *요약 서술*을 축자 인용으로 오인해 오탐이 30건 넘게 났다. B.5 는 미결의
# 제목을 자기 말로 적으므로 그 문자열이 정본에 없는 것이 정상이다.
# 「A 가 적은 「…」」 형태의 진짜 인용은 사이가 짧다.
QUOTE_RE = re.compile(r"^.{0,30}?「([^」]{6,120})」", re.S)

LABEL_DECL_RE = re.compile(r"<(sec:[a-z][a-z0-9-]*)>")

# `§N.M[.K]` — 라벨 없이 절 번호만 쓴 인용. 장 번호 N 이 어느 파일인지는
# 장 번호 → 파일 맵으로 푼다. 2026-08-27 에 이 형태를 놓쳐 개악이 났다.
BARE_RE = re.compile(r"§(\d+\.\d+(?:\.\d+)?)")

# **이름이 붙은 형제 문서 인용** — `` `Di` §4.7 `` · `` `lf_extension_split.md`
# §3.1 `` 처럼 *다른 문서의* 절을 가리키는 형태다. 정본 좌표가 아니므로 정본
# 절 맵과 대조하면 안 된다: 대조하면 우연히 같은 번호가 정본에 있을 때 **조용히
# 통과해 거짓 확신을 준다** (`Di` §4.2·§1.3 이 실제로 그 형태였다 — 정본에도
# §4.2·§1.3 이 있어서 통과했다).
#
# 예외 하나 — 이름이 *정본 자신*을 가리키는 경우
# (`` `docs/wt64v1-architecture-guide` §2.7 ``, `rtl/formal/tla` 의 관례)는
# 그대로 검사한다. 이 예외를 두지 않으면 하드 검사 셋을 잃는다.
NAMED_REF_RE = re.compile(r"(?:`([^`\n]{1,60})`|([A-Za-z0-9_./-]+\.md))\s*$")
GUIDE_NAME = "wt64v1-architecture-guide"

# 비정본 문서의 자기 절 번호 — `### 4.2 규범 …` 형태의 자기 헤딩.
SELF_HEAD_RE = re.compile(r"^#{2,5}\s*(\d+)(?:\.\d+){0,2}[ .]", re.M)

# 축 1 — `파일:줄` · `파일:줄-줄`
#
# **확장자를 열거하는 이유**: `\.[A-Za-z]\w{0,6}` 로 열어 두면
# `wavetensor.local:5050`(호스트:포트)이나 `v1.9.1:` 같은 것을 좌표로 읽는다.
# 열거는 「새 확장자는 자동으로 검사 밖에 태어난다」는 대가를 치르므로,
# 그 대가를 알고 적는다 (§6.7 검사의 정의역).
AX1_EXTS = (
    "v|sv|svh|vh|py|tla|cfg|sby|md|typ|scala|sbt|yml|yaml|json|sh|fish|"
    "tcl|xdc|sdc|java|c|h|cc|cpp|rs|toml|mk|txt|log|ini|csv|typst"
)
LINECITE_RE = re.compile(
    r"(?<![\w/.\-])((?:[\w.+\-]+/)*[\w.+\-]+\.(?:" + AX1_EXTS + r"))"
    r":(\d+)(?:[-–](\d+))?(?![\w:])"
)
# 따옴표 결속 창 — 좌표 바로 뒤 30자 안의 「」 하나.
AX1_QUOTE_RE = re.compile(r"^.{0,30}?「([^」]{5,140})」", re.S)

# 결속 방해 요소
SECNUM_ANY_RE = re.compile(r"§?\d+\.\d+(?:\.\d+)?")
PARA_BREAK_RE = re.compile(r"\n[ \t]*\n")

# **맨 줄 좌표** — `` (`:601-602`) `` 처럼 파일명 없이 줄만 적는 형태.
# 결속을 *끊는* 데에만 쓴다(실재 검사는 하지 않는다 — 위 「덮지 않는 것」 참조).
BARE_LINE_RE = re.compile(r"`\s*:\d+(?:[-–]\d+)?")

# 축 2b — `@sec:` 도 `§` 도 없는 맨 번호 (「3.11 함정」 형태)
BARE2_RE = re.compile(r"(?<![§\d.\w])(\d{1,2}\.\d{1,2}(?:\.\d{1,2})?)(?![\d.])")
BLOCK_WORD_RE = re.compile(r"^[\s의이가은는을를,)\]]{0,4}(함정)")

# 이 수 이상의 절이 같은 문자열을 소유하면 그 대조는 **반증력이 없다** —
# 어느 절 번호로 바꿔도 통과하므로 재번호를 잡지 못한다. 「형식 속성」이
# 12개 절에 사는 것이 실측된 형태다 (2026-08-30).
WEAK_OWNERS_MIN = 4


# ---------------------------------------------------------------------------
# 발신 구역 — 「누가 그 인용을 썼는가」. **래칫의 정의역이 이 구분에 걸린다.**
#
# 2026-08-30 실측이 이 구분을 강제했다. 축 1 의 대조 가능 인용 41건의 발신
# 분포는 `.claude-memos` 35 · `docs/` 6 · **정본·rtl·proofs 0** 이었다.
# 그런데 덮임 하한은 「정본 장 X 를 겨냥한 대조 가능 인용이 0 이 되면 실패」였다
# — 즉 **메모 한 줄의 의역이 정본 부록의 하한을 깨고 커밋을 막는** 상태였다.
# 스크립트 자신이 R5 상한에서 그 구역을 「매 커밋 거짓 실패한다」며 면제했는데
# 하한은 면제하지 않았다. F-52(「하드 게이트가 거짓 실패하고 그 반작용으로
# 게이트를 끈다」)의 뇌관을 스스로 심은 것이다.
#
#   hard      정본 · `rtl/` · `proofs/` — 큐레이트되고 리뷰를 거친다.
#             R5·R6 상한이 여기만 건다.
#   curated   그 밖의 `docs/` — 승격된 확장 명세·연구 노트. 버전 관리되는
#             문서이고 세션마다 새로 태어나지 않는다. **덮임 하한이 여기까지**.
#   volatile  나머지(`.claude-memos/` 등) — 세션마다 새 분석이 태어난다.
#             **어떤 래칫도 걸지 않는다. 인쇄만 한다.**
# ---------------------------------------------------------------------------
_G = "docs/wt64v1-architecture-guide/"


def sender_zone(rel: str) -> str:
    if rel.startswith(_G) or rel.startswith(("rtl/", "proofs/")):
        return "hard"
    if rel.startswith("docs/"):
        return "curated"
    return "volatile"


# ---------------------------------------------------------------------------
# 래칫 — 낮추는 편집만 정당하다. 올리려면 그 자체가 리뷰 대상이다.
#
# 형식은 저장소 선례 둘을 섞었다:
#   · `lint_estimate_index.py` — `*_MAX` 상수 + 사유 주석
#   · `lint_forbidden_terms.py` — 파일별 표. **어느 파일의 몇 건인지가 표
#     자체에 산다.** 이 검사가 그 형식을 쓰는 이유: 상한만 잠그면 한 파일이
#     고쳐지고 다른 파일이 그 자리를 조용히 채운다.
#
# **표 전체를 하나의 객체(`Ratchet`)로 묶는 이유**: 묶기 전에는 래칫 집행
# 코드가 통째로 음성 시험의 정의역 밖이었다 — 자기시험이 `check_ratchet=False`
# 로 돌았기 때문에 R1·R3·R4·R4b·R5·덮임 하한을 **통째로 삭제해도** `make lint`
# 와 `--self-test` 가 둘 다 통과했다(§6.3.2 가드 삭제 실험 불통과). 자기시험이
# 래칫을 켤 수 없었던 이유는 이 표들이 실 트리 전용 상수였고 부분 사본
# 픽스처에서는 맞지 않기 때문이다. ⇒ 표를 인자로 만들어 픽스처 기준선에서
# **재보정한 래칫**으로 변이를 걸 수 있게 했다.
#
# 2026-08-30 전수 실측 → 재조준 착지 후의 값이다.
# ---------------------------------------------------------------------------
class Ratchet:
    def __init__(self, **kw):
        self.missing_max: dict[str, int] = kw.get("missing_max", {})
        self.range_max: int = kw.get("range_max", 0)
        self.stale_max: dict[str, int] = kw.get("stale_max", {})
        self.wrong_max: dict[str, int] = kw.get("wrong_max", {})
        self.wrong_out_max: dict[str, int] = kw.get("wrong_out_max", {})
        self.kind_max: dict[str, int] = kw.get("kind_max", {})
        self.ax1_unmeasured_max: dict[str, int] = kw.get("ax1_unmeasured_max", {})
        self.ax2_unmeasured_max: dict[str, int] = kw.get("ax2_unmeasured_max", {})
        self.ax1_soft_max: dict[str, int] = kw.get("ax1_soft_max", {})
        self.ax2_soft_max: dict[str, int] = kw.get("ax2_soft_max", {})
        self.ax1_cover_floor: dict[str, int] = kw.get("ax1_cover_floor", {})
        self.ax2_cover_floor: dict[str, int] = kw.get("ax2_cover_floor", {})


# R1 — 좌표 실재. 저장소 안 대상을 가리키는데 그 파일이 없다.
#
# 남은 16건은 전부 `.claude-memos/wt64v1_spec.md` 의 **기록**이고 두 부류다:
#   · 12건 — 「그때 그 자리에서 이렇게 보였다」는 서술이고 대상(`TENSOR_ALU.v`
#     등)은 C-2 파도가 실제로 폐기했다. 재조준하면 기록이 거짓이 된다.
#   · 4건 — **형제 저장소** `/home/ybi/Y4` 의 좌표다 (`hiu_abi.md` 49행 ×2 ·
#     `glossary.md` 32행 · `docs/phase_plan.md` 70행). 인용문 자신이
#     「Y4 hiu_abi.md …」라 적는다. 폐기된 RTL 이 아니라 **다른 저장소**다.
#     (여기에 그 좌표를 `파일:줄` 꼴로 옮겨 적지 않는다 — 적는 순간 이 파일이
#      같은 부류의 위반을 하나 더 만든다. 실제로 초고가 그것을 했고 이 검사가
#      물었다.)
# ⇒ 둘 다 고칠 수 없는 것이 아니라 **고쳐서는 안 되는 것**이므로 0 이 목표가
#    아니다. 형제 저장소 부류를 `AX1_OUT_OF_TREE` 로 옮기지 **않는** 이유는
#    그 표가 *파일 이름*으로 매칭하기 때문이다 — `glossary.md` 를 등재하면
#    저장소 안의 같은 이름 인용까지 통째로 눈이 먼다(과대 면제).
AX1_MISSING_MAX: dict[str, int] = {
    # `TENSOR_ALU.v` ×4 · `SIMD_ALU.v` ×2 · `test_tensor_alu.py` ×3 ·
    # `sys_top_core_run.log` ×3 (= 폐기 12) · Y4 좌표 4
    ".claude-memos/wt64v1_spec.md": 16,
}

# 좌표가 파일 밖을 가리킨다. **오탐 0 이고 의도가 기계로 확정된다** — 0 이 목표.
AX1_RANGE_MAX = 0

# R3 — 따옴표를 동반한 좌표 인용의 대상. **정본을 겨냥한 것만 hard.**
# 「그 내용이 대상 파일의 *다른 줄*에 있다」 = 재조준 가능 = 결함.
# 「대상 파일 어디에도 없다」 = 의역일 수 있다 = R6 이 상한만 건다.
AX1_STALE_MAX: dict[str, int] = {}

# R4 — 축 2 대상 대조. **정본 + `rtl/` + `proofs/` 만.**
# 참 3건(`Fabric.tla` ×2 · `Walk.tla`)을 재조준하고 거짓 4건을 결속 규칙으로
# 없앴다. 이 축은 **0 으로 잠글 수 있는 유일한 래칫**이다.
AX2_WRONG_MAX: dict[str, int] = {}

# R4′ — 축 2 대상 대조의 **비-hard 발신**. 2026-08-30 신설.
#
# 이 부류를 켠 이유는 W6 이다 — 이 검사의 동기가 된 자리(`§3.11` 이 형식
# 속성에서 원격 표면으로 바뀐 사건)의 인용이 전부 `.claude-memos/` 에 살아서
# **동기가 된 그 자리가 정의역 밖**이었다. 실측: 이 바구니의 따옴표 인용
# 3건 전부 ok, 오탐 0. 예외(기록으로서 옛 번호를 적는 인용)는 여기 등재한다.
AX2_WRONG_OUTZONE_MAX: dict[str, int] = {}

# 축 2b — 「N.M 함정」의 블록 종류. `04-ext-payload.typ:836·839` 가 「4.2.2
# 규범」이라 적었는데 §4.2.2 에는 `#규범(` 이 0건이고 `#함정(` 이 2건이었다.
# 「규범」은 보통명사로도 쓰여 정밀도가 낮다 — **`함정` 만** 센다.
AX2B_KIND_MAX: dict[str, int] = {}

# R5 — 「안 잰다」(따옴표 없음)의 상한. **hard 구역 발신만** 건다.
#
# 왜 hard 구역만인가: `.claude-memos/` 는 세션마다 새 분석이 태어나는 자리라
# 거기에 상한을 걸면 이 검사는 **매 커밋 거짓 실패**하고 그 반작용으로 꺼진다
# (F-52). 정본·형식 모델은 큐레이트되는 문면이므로 「새 인용은 따옴표를 달고
# 태어나라」를 요구할 수 있다. 메모 구역은 상한 없이 **인쇄만** 한다 —
# 통과로 인쇄하지 않는다는 것이 §6.6.5 의 요구이지 실패시키라는 요구가 아니다.
#
# **스칼라에서 파일별 표로 바꾼 이유** (2026-08-30 실측 둘):
#   ① 스칼라 상한은 위반 자리를 지목하지 못했다. `Walk.tla` 에 따옴표 없는
#      인용 하나를 더하면 실패 메시지 12줄이 전부 `b-gaps.typ` 를 가리켰다
#      (`unmeasured_hard[:12]` = 스캔 순서 앞 12건). 편집자는 건드린 적 없는
#      파일의 오류를 보게 되고, 그것이 게이트를 끄게 만드는 F-52 반작용의
#      정확한 형태다.
#   ② 스칼라는 **하강에 침묵**했다. 한 파일에서 인용이 사라지면 그만큼 슬랙이
#      쌓여 다른 파일이 조용히 그 자리를 채울 수 있었다. `ratchet()` 은
#      하강도 「상한을 함께 내려라」로 실패시킨다 — 저장소 자신의 규율
#      (`lint_synth_coverage.py:63`)이 비대칭 적용돼 있었다.
AX1_UNMEASURED_HARD_MAX: dict[str, int] = {
    "proofs/tla/AccBank.tla": 5,
    "proofs/tla/README.md": 14,
    "rtl/README.md": 2,
    "rtl/formal/sby/HiuMask/hiumask.sby": 3,
    "rtl/formal/sby/Reassembly/props.sby": 3,
    "rtl/formal/sby/XlateStore/xlatestore.sby": 7,
    "rtl/formal/tla/Decode.tla": 1,
    "rtl/sim/README.md": 17,
    "rtl/sim/run_wt64.py": 11,
    "rtl/sim/test_mask_golden.py": 14,
    "rtl/sim/test_shape_equiv.py": 14,
    "rtl/sv/assert/HiuMask_props.sv": 3,
    "rtl/sv/assert/Reassembly_props.sv": 4,
}
AX2_UNMEASURED_HARD_MAX: dict[str, int] = {
    "docs/wt64v1-architecture-guide/appendix/b-gaps.typ": 33,
    "docs/wt64v1-architecture-guide/appendix/d-properties.typ": 2,
    "docs/wt64v1-architecture-guide/chapters/01-isa-asm.typ": 30,
    "docs/wt64v1-architecture-guide/chapters/02-fabric-alu.typ": 1,
    "docs/wt64v1-architecture-guide/chapters/04-ext-payload.typ": 15,
    "proofs/tla/README.md": 12,
    "proofs/tla/trace_to_directed.md": 2,
    "rtl/formal/sby/CompletionUnit/descriptor.sby": 1,
    "rtl/formal/sby/DecodeWalk/walk_decode.sby": 1,
    "rtl/formal/sby/FabricMerge/contracts.sby": 1,
    "rtl/formal/sby/HiuMask/hiumask.sby": 1,
    "rtl/formal/sby/MmioConfig/mmio_config.sby": 2,
    "rtl/formal/sby/MmioConfig/mmio_deep.sby": 1,
    "rtl/formal/sby/OperandDecode/body_judge.sby": 7,
    "rtl/formal/sby/OwnershipTable/ownershiptable.sby": 3,
    "rtl/formal/sby/RouteJudge/route_judge.sby": 3,
    "rtl/formal/sby/RouteMmio/route_mmio.sby": 2,
    "rtl/formal/sby/SharedUnit/depth0.sby": 1,
    "rtl/formal/tla/Decode.tla": 44,
    "rtl/formal/tla/Fabric.tla": 40,
    "rtl/formal/tla/Isolation.tla": 59,
    "rtl/formal/tla/MemOrder.tla": 20,
    "rtl/formal/tla/NoLoss.tla": 5,
    "rtl/formal/tla/Payload.tla": 47,
    "rtl/formal/tla/Platform.tla": 9,
    "rtl/formal/tla/ResultBank.tla": 4,
    "rtl/formal/tla/Route.tla": 18,
    "rtl/formal/tla/SharedUnit.tla": 11,
    "rtl/formal/tla/Walk.tla": 20,
    "rtl/formal/tla/XlateStore.tla": 5,
    "rtl/sv/assert/CompletionUnit_props.sv": 5,
    "rtl/sv/assert/DecodeWalk_props.sv": 15,
    "rtl/sv/assert/FabricMerge_props.sv": 9,
    "rtl/sv/assert/HiuMask_props.sv": 3,
    "rtl/sv/assert/MmioConfig_props.sv": 14,
    "rtl/sv/assert/OperandDecode_props.sv": 36,
    "rtl/sv/assert/OwnershipTable_props.sv": 2,
    "rtl/sv/assert/Reassembly_props.sv": 2,
    "rtl/sv/assert/ResultBank_props.sv": 3,
    "rtl/sv/assert/RouteJudge_props.sv": 9,
    "rtl/sv/assert/RouteMmio_props.sv": 6,
    "rtl/sv/assert/SharedUnitDepth0_props.sv": 2,
    "rtl/sv/assert/SharedUnit_props.sv": 2,
    "rtl/sv/assert/XlateStore_props.sv": 1,
}

# R6 — 「의역으로 보임」의 상한. **hard 구역 발신만.**
#
# 왜 필요한가 (2026-08-30 실측): `b-gaps.typ:400` 의 `§3.2 「…게이트한다」` 를
# `§3.5` 로 바꾸면 R4 가 문다(rc=1). 그런데 같은 오기에서 따옴표를 한 글자만
# 의역하면(「게이트한다」→「게이팅한다」) 그 인용은 `wrong` 이 아니라 `soft`
# 로 떨어지고 **rc=0 이 된다** — soft 부류에는 상한이 없었기 때문이다.
# 즉 「따옴표를 한 글자 흐리면 틀린 절 번호가 통과한다」는 우회로가 있었다.
# ⇒ hard 구역에서 「따옴표를 썼으면 축자로 써라」를 요구한다. 요약을 적고
#    싶으면 따옴표를 떼면 되고, 그러면 R5 가 그것을 「안 잰다」로 계수한다.
AX1_SOFT_HARD_MAX: dict[str, int] = {
    "rtl/sim/test_shape_equiv.py": 1,
    "rtl/sv/assert/HiuMask_props.sv": 1,
}
AX2_SOFT_HARD_MAX: dict[str, int] = {
    "docs/wt64v1-architecture-guide/appendix/b-gaps.typ": 2,
    "docs/wt64v1-architecture-guide/chapters/01-isa-asm.typ": 2,
    "docs/wt64v1-architecture-guide/chapters/04-ext-payload.typ": 1,
    "rtl/formal/tla/Fabric.tla": 1,
    "rtl/formal/tla/MemOrder.tla": 1,
    "rtl/formal/tla/Payload.tla": 1,
    "rtl/formal/tla/ResultBank.tla": 1,
    "rtl/formal/tla/Route.tla": 1,
    "rtl/formal/tla/SharedUnit.tla": 1,
    "rtl/sv/assert/DecodeWalk_props.sv": 1,
    "rtl/sv/assert/OperandDecode_props.sv": 1,
}

# 덮임 하한 — **이 래칫의 알맹이.** 상한만 두면 「인용을 안 쓰면 통과」다.
#
# 2026-08-30 변이 실측이 그것을 실증했다: `01-isa-asm.typ` 200행에 40줄을
# 삽입하면 10건이 잡히는데 같은 변이를 `06-formal.typ` 에 걸면 **0건** 잡힌다
# — 그 장을 겨냥한 옳은 따옴표 인용이 하나도 없기 때문이다. 그 장에 대한
# 「파손 0」은 **무증거**다.
#
# **하한의 발신 정의역은 curated 이상**이다 (위 「발신 구역」). 하한을 볼모로
# 잡을 수 있는 문서가 volatile 구역에 있으면 그 구역의 평범한 편집이 정본의
# 게이트를 깬다. 그리고 그 반대도 성립했다 — 오늘 `a-capacity.typ` 의 하한
# 1 은 **손상된 인용 하나**로만 충족되고 있었고, 그것을 옳게 되돌리는 순간
# `make lint` 가 실패했다. 게이트가 잘못된 인용을 **보존하도록** 압력을 만든
# 것이다. 두 방향 다 같은 원인이다.
#
# 값은 **오늘 실측**이다. 0 은 「이 장에 대한 파손 0 은 무증거다」를 뜻하고
# 그대로 인쇄된다. 0 을 1 로 올리는 편집은 래칫을 올리는 것이므로 사유를 남긴다.
# ── 축 1 (`파일:줄`) — **curated 이상 발신만.** ────────────────────────────
# 2026-08-30 실측: 축 1 의 대조 41건 중 curated 발신은 6건뿐이고 hard 발신은
# 0건이다. 즉 **정본은 자기 자신을 줄 좌표 + 따옴표로 인용하지 않는다.**
# 그 사실이 여기 0 으로 인쇄된다 — 0 인 장에 대한 「파손 0」은 무증거다.
# volatile(`.claude-memos/`) 발신 덮임은 표 밖에서 인쇄만 한다.
AX1_COVER_FLOOR: dict[str, int] = {
    _G + "chapters/01-isa-asm.typ": 2,
    _G + "chapters/02-fabric-alu.typ": 0,   # curated 발신 0 — 무증거
    _G + "chapters/03-hiu.typ": 1,
    _G + "chapters/04-ext-payload.typ": 0,  # curated 발신 0 — 무증거
    _G + "chapters/05-security.typ": 1,
    _G + "chapters/06-formal.typ": 0,       # curated 발신 0 — 무증거
    _G + "appendix/a-capacity.typ": 0,      # curated 발신 0 — 무증거
    _G + "appendix/b-gaps.typ": 0,          # curated 발신 0 — 무증거
    _G + "appendix/c-glossary.typ": 1,
    _G + "appendix/d-properties.typ": 0,    # curated 발신 0 — 무증거
    _G + "appendix/e-defined.typ": 0,       # curated 발신 0 — 무증거
    _G + "refs.yml": 1,
}

# ── 축 2 (`§N.M`) — 발신이 정의상 전부 hard 구역이다. ──────────────────────
# 그래서 이 축의 하한은 volatile 구역의 편집에 흔들리지 않는다 — **축 1 이
# 잃은 것을 이 축이 갖는다.** W6 이 동기한 축이 정확히 이것이고, 상한
# (R4·R5)만 갖고 하한이 없던 것이 결손이었다: 「상한만 두면 인용을 안 쓰면
# 통과」라는 논증이 이 축에 그대로 적용된다.
#
# 값은 **반증력 있는 대조**만 센다 (보통명사 인용·묶음 일부 적중은 제외 —
# 위 `WEAK_OWNERS_MIN` 주석). 2026-08-30 실측 50건의 장별 분포다.
AX2_COVER_FLOOR: dict[str, int] = {
    _G + "chapters/01-isa-asm.typ": 9,
    _G + "chapters/02-fabric-alu.typ": 12,
    _G + "chapters/03-hiu.typ": 6,
    _G + "chapters/04-ext-payload.typ": 17,
    _G + "chapters/05-security.typ": 2,
    _G + "chapters/06-formal.typ": 4,
}


# ---------------------------------------------------------------------------
# 정의역 밖 — 「안 잰다」로 별도 계수한다. 통과가 아니다.
# ---------------------------------------------------------------------------
# 저장소 밖 도구 소스를 가리키는 좌표. 원리상 검사 대상이 아니다 —
# 파일이 없다고 실패시키면 옳은 기록을 막는다.
AX1_OUT_OF_TREE = {
    "TLC.java": "TLA+ 도구 소스 — 저장소 밖",
    "runner.py": "cocotb_tools 소스 — 저장소 밖",
    "check_results.py": "cocotb 소스 — 저장소 밖",
    "_xunit_reporter.py": "cocotb 소스 — 저장소 밖",
    "props_only.sv": "sby 가 작업 디렉토리에 만드는 파생 파일명",
    "props.sv": "sby 태스크 작업 디렉토리 안의 이름 — 저장소에는 `*_props.sv` 로 산다",
}


# 실 트리용 래칫. `--self-test` 는 픽스처에서 **재보정한** 것을 쓴다.
DEFAULT_RATCHET = Ratchet(
    missing_max=AX1_MISSING_MAX,
    range_max=AX1_RANGE_MAX,
    stale_max=AX1_STALE_MAX,
    wrong_max=AX2_WRONG_MAX,
    wrong_out_max=AX2_WRONG_OUTZONE_MAX,
    kind_max=AX2B_KIND_MAX,
    ax1_unmeasured_max=AX1_UNMEASURED_HARD_MAX,
    ax2_unmeasured_max=AX2_UNMEASURED_HARD_MAX,
    ax1_soft_max=AX1_SOFT_HARD_MAX,
    ax2_soft_max=AX2_SOFT_HARD_MAX,
    ax1_cover_floor=AX1_COVER_FLOOR,
    ax2_cover_floor=AX2_COVER_FLOOR,
)


# ---------------------------------------------------------------------------
# 공용
# ---------------------------------------------------------------------------
def norm(s: str) -> str:
    """대조용 정규화 — 공백·강조(*)·코드스팬(`)을 지운다.

    **인용부호(「」)는 지우지 않는다.** 지웠더니 `b-gaps.typ:1395` 가 거짓
    실패했다 (2026-08-30 실측): 대상은 「판정 이전」 창 이라 적고 인용은
    「판정 이전 창」이라 적는데, 부호를 지우면 둘이 같아져 **다른 절이
    소유한 것처럼** 보인다.
    """
    return re.sub(r"\s+", "", s).replace("*", "").replace("`", "")


def norm_index(lines: list[str]) -> tuple[str, list[int]]:
    """정규화 문자열과 「그 문자가 온 줄 번호」 색인을 함께 만든다.

    좌표 인용의 대상 대조는 **인용문이 시작하는 줄**을 알아야 한다. 창을
    미끄러뜨리며 세면 `di_design_v1.md:156` 처럼 여러 줄에 걸친 인용이
    「낡음」으로 거짓 판정된다 (창 시작줄 ≠ 인용 시작줄).
    """
    buf: list[str] = []
    pos: list[int] = []
    for i, line in enumerate(lines, 1):
        for ch in line:
            if ch.isspace() or ch in "*`":
                continue
            buf.append(ch)
            pos.append(i)
    return "".join(buf), pos


def start_lines(flat: str, pos: list[int], needle: str) -> list[int]:
    """`needle` 이 시작하는 줄 번호를 전부 돌려준다."""
    out: list[int] = []
    i = flat.find(needle)
    while i >= 0:
        out.append(pos[i])
        i = flat.find(needle, i + 1)
    return out


def uncomment(t: str) -> str:
    """TLA+ `(* … *)` 테두리와 줄 주석 접두어를 지운다 — 결속 창 계산용."""
    return re.sub(r"\*\)|\(\*|^[ \t]*(?://|#)", "", t, flags=re.M)


def chapter_number(path: Path) -> str | None:
    """파일명에서 장 번호를 유도한다. 01-isa-asm.typ → '1', a-capacity.typ → '부록 A'."""
    m = re.match(r"(\d+)-", path.name)
    if m:
        n = int(m.group(1))
        return None if n == 0 else str(n)  # 00-preface 는 번호 없는 장
    m = re.match(r"([a-e])-", path.name)
    if m:
        return "부록 " + m.group(1).upper()
    return None


def build_section_map(path: Path) -> dict[str, tuple[int, int]]:
    """파일의 `==`/`===` 를 세어 {'1.4.2': (시작줄, 끝줄)} 를 만든다 (1-indexed, 끝 배타)."""
    ch = chapter_number(path)
    if ch is None:
        return {}
    lines = path.read_text(encoding="utf-8").splitlines()
    out: dict[str, tuple[int, int]] = {}
    sec = sub = 0
    open_keys: list[tuple[str, int]] = []

    def close(upto: int) -> None:
        while open_keys:
            k, start = open_keys.pop()
            out[k] = (start, upto)

    for i, line in enumerate(lines, 1):
        if line.startswith("=== "):
            sub += 1
            # 같은 깊이 이하만 닫는다
            while open_keys and open_keys[-1][0].count(".") >= 2:
                k, s = open_keys.pop()
                out[k] = (s, i)
            open_keys.append((f"{ch}.{sec}.{sub}", i))
        elif line.startswith("== "):
            sec += 1
            sub = 0
            close(i)
            open_keys.append((f"{ch}.{sec}", i))
    close(len(lines) + 1)
    return out


class Guide:
    """정본의 절 지도 + 소유자 색인."""

    def __init__(self, root: Path):
        self.root = root
        self.guide = root / "docs" / "wt64v1-architecture-guide"
        self.labels: dict[str, tuple[Path, str | None]] = {}
        self.secmaps: dict[Path, dict[str, tuple[int, int]]] = {}
        self.contents: dict[Path, list[str]] = {}
        self.chap_files: dict[str, Path] = {}
        self._body_cache: dict[Path, dict[str, str]] = {}
        if not self.guide.exists():
            return
        for p in sorted(self.guide.rglob("*.typ")):
            txt = p.read_text(encoding="utf-8")
            for m in LABEL_DECL_RE.finditer(txt):
                self.labels.setdefault(m.group(1), (p, chapter_number(p)))
            self.secmaps[p] = build_section_map(p)
            self.contents[p] = txt.splitlines()
            c = chapter_number(p)
            if c and c.isdigit():
                self.chap_files.setdefault(c, p)

    def _bodies(self, p: Path) -> dict[str, str]:
        """절별 정규화 본문 — 인용마다 다시 만들면 O(인용×절×파일크기) 가 된다."""
        if p not in self._body_cache:
            lines = self.contents[p]
            self._body_cache[p] = {
                key: norm("\n".join(lines[a - 1:b - 1]))
                for key, (a, b) in self.secmaps[p].items()
            }
        return self._body_cache[p]

    def owners(self, needle: str, exclude: tuple[Path, int] | None = None
               ) -> list[tuple[Path, str]]:
        """정본 **전 파일**에서 그 문자열을 소유한 절을 찾는다.

        전 파일을 도는 것이 규칙 5 다 — 「대상 파일에 없다」와 「다른 장에
        있다」를 구별해야 참/거짓이 갈린다.
        """
        hits: list[tuple[Path, str]] = []
        for p, secmap in self.secmaps.items():
            if exclude and exclude[0] == p:
                # 자기 인용 제외 — 인용문 자신을 「실제 자리」로 오인하지 않게.
                lines = list(self.contents[p])
                for k in range(max(0, exclude[1] - 2),
                               min(exclude[1] + 2, len(lines))):
                    lines[k] = ""
                bodies = {key: norm("\n".join(lines[a - 1:b - 1]))
                          for key, (a, b) in secmap.items()}
            else:
                bodies = self._bodies(p)
            for key, body in bodies.items():
                if needle in body:
                    hits.append((p, key))
        # 자식이 맞았으면 부모는 뺀다 — 인쇄를 좁힌다
        return [(p, k) for p, k in hits
                if not any(p2 == p and k2 != k and k2.startswith(k + ".")
                           for p2, k2 in hits)]


def iter_scan_files(root: Path):
    """축 0·2 의 정의역."""
    for rel_dir, pat in SCAN_GLOBS_REL:
        d = root / rel_dir
        if not d.exists():
            continue
        for src in sorted(d.glob(pat)):
            try:
                yield src, src.read_text(encoding="utf-8")
            except (UnicodeDecodeError, OSError):
                continue


def _repo_paths(root: Path) -> list[Path]:
    """추적되는 파일만. `.private/` 처럼 무시되는 자리는 정의역이 아니다 —
    사람의 사설 메모를 게이트가 붙잡으면 그 게이트는 곧 꺼진다."""
    r = subprocess.run(["git", "ls-files", "-z"], cwd=root,
                       capture_output=True, text=True)
    if r.returncode == 0 and r.stdout.strip("\0"):
        return [root / s for s in r.stdout.split("\0") if s]
    # git 이 없는 자리(자기시험 픽스처) — 트리를 그대로 훑는다
    return [p for p in root.rglob("*") if p.is_file()]


def untracked_domain(root: Path) -> tuple[int, int]:
    """**정의역 밖**: 추적되지 않는 파일에 사는 좌표 인용의 수를 센다.

    축 1 은 `git ls-files`(인덱스)를 정의역으로 쓴다 — 그래서 `git add` 되지
    않은 파일의 좌표는 **하나도 보지 않는다.** 그 사실이 인쇄되지 않으면
    「축 1 은 저장소 전역을 본다」는 거짓 확신이 남는다 (§6.7 검사의 정의역).
    Returns (파일 수, 좌표 인용 수) — 통과가 아니라 「안 잰다」로 인쇄한다.
    """
    r = subprocess.run(["git", "ls-files", "-o", "--exclude-standard", "-z"],
                       cwd=root, capture_output=True, text=True)
    if r.returncode != 0:
        return (0, 0)
    nf = nc = 0
    for s in r.stdout.split("\0"):
        if not s:
            continue
        p = root / s
        if any(part in AX1_SKIP_DIRS for part in Path(s).parts):
            continue
        if s.startswith(AX1_SKIP_PREFIX) or p.suffix.lower() in AX1_SKIP_SUFFIX:
            continue
        try:
            t = p.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        n = len(LINECITE_RE.findall(t))
        if n:
            nf += 1
            nc += n
    return (nf, nc)


def iter_repo_files(root: Path):
    """축 1 의 정의역 — **추적되는** 저장소 전역 (생성 산출물·바이너리 제외).

    「전역」이 아니다 — 미추적 파일은 정의역 밖이고 그 수는 `untracked_domain()`
    이 따로 세어 인쇄한다.
    """
    for p in sorted(_repo_paths(root)):
        if not p.is_file():
            continue
        rel = p.relative_to(root)
        if any(part in AX1_SKIP_DIRS for part in rel.parts):
            continue
        s = str(rel)
        if s.startswith(AX1_SKIP_PREFIX):
            continue
        if p.suffix.lower() in AX1_SKIP_SUFFIX:
            continue
        try:
            yield p, p.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue


# ---------------------------------------------------------------------------
# 결속 — 인용과 따옴표를 잇는다. 오탐을 낮추는 다섯 규칙 중 2·3 이 여기 산다.
# ---------------------------------------------------------------------------
def bind_quote(tail: str, window: int = 220) -> tuple[str | None, str]:
    """인용 뒤 창에서 따옴표 하나를 결속한다.

    Returns (따옴표 내용 | None, 사유). 사유는 'ok' · 'none'(따옴표 없음) ·
    'ambig'(다른 절 번호가 개입 — 안 잰다).
    """
    t = uncomment(tail[:window])
    # ③ 문단 경계 차단 — 빈 줄을 넘어 결속하지 않는다.
    br = PARA_BREAK_RE.search(t)
    if br:
        t = t[:br.start()]
    m = re.search(r"[「“]([^」”\n]{5,140}|[^」”]{5,140})[」”]", t)
    if not m or m.start() > 30:
        return None, "none"
    # ② 번호 개입 — 인용과 따옴표 *사이*
    if SECNUM_ANY_RE.search(t[:m.start()]):
        return None, "ambig"
    # ② 번호 개입 — 따옴표 *바로 뒤*. `「…」 원자성(§3.7.1)` 이 그 형태다.
    if SECNUM_ANY_RE.search(t[m.end():m.end() + 16]):
        return None, "ambig"
    return m.group(1), "ok"


def group_members(text: str, m: re.Match) -> tuple[list[str], bool]:
    """`(§1.4.2 · §1.4.6)` 같은 **목록 인용**의 묶음을 구한다.

    Returns (묶음의 절 번호들, 이 인용이 묶음의 마지막인가).
    따옴표는 묶음 전체에 걸리므로 마지막 항만 결속을 수행한다 (규칙 ④).
    """
    sep = r"[\s·,、/과와및및이나또는]{1,6}"
    members = [m.group(1)]
    # 뒤로
    pos = m.end()
    last = True
    while True:
        nxt = re.match(sep + r"§(\d+\.\d+(?:\.\d+)?)", text[pos:pos + 20])
        if not nxt:
            break
        last = False
        members.append(nxt.group(1))
        pos += nxt.end()
    # 앞으로
    pos = m.start()
    while True:
        prv = re.search(r"§(\d+\.\d+(?:\.\d+)?)" + sep + r"$",
                        text[max(0, pos - 20):pos])
        if not prv:
            break
        members.insert(0, prv.group(1))
        pos = max(0, pos - 20) + prv.start()
    return members, last


def is_ancestor_or_self(cited: str, owner: str) -> bool:
    return owner == cited or owner.startswith(cited + ".") or cited.startswith(owner + ".")


def _binding_blocked(s: str) -> bool:
    """이 문자열이 좌표와 따옴표 **사이**(또는 따옴표 바로 뒤)에 있으면 결속을 끊는다.

    끊는 이유는 「그 따옴표가 이 좌표의 것이 아닐 수 있다」이지 「틀렸다」가
    아니다 — 끊긴 인용은 실패가 아니라 「안 잰다」로 계수된다 (§6.6.5).
    """
    return bool(LINECITE_RE.search(s) or BARE_LINE_RE.search(s)
                or SECNUM_ANY_RE.search(s) or "@sec:" in s)


# ---------------------------------------------------------------------------
# 축 0 — `@sec:라벨 N.M`
# ---------------------------------------------------------------------------
def axis0(root: Path, g: Guide, files) -> dict:
    hard: list[str] = []
    soft: list[str] = []
    sites: list[tuple] = []      # 자기시험이 변이를 **실제 자리**에서 고르게 한다
    checked = quoted = 0
    for src, text in files:
        rel = src.relative_to(root)
        for m in REF_RE.finditer(text):
            checked += 1
            label, num = "sec:" + m.group(1), m.group(2)
            line_no = text[: m.start()].count("\n") + 1

            if label not in g.labels:
                hard.append(f"{rel}:{line_no} — 라벨 `@{label}` 이 정본에 선언되지 않았다")
                continue
            tgt_path, tgt_ch = g.labels[label]

            if tgt_ch is not None and not num.startswith(tgt_ch):
                hard.append(
                    f"{rel}:{line_no} — `@{label} {num}` 의 장 번호가 어긋난다. "
                    f"`{label}` 은 {tgt_ch}장({tgt_path.name})이다"
                )
                continue

            secmap = g.secmaps.get(tgt_path, {})
            if num not in secmap:
                near = sorted(k for k in secmap if k.startswith(num.rsplit(".", 1)[0]))
                hard.append(
                    f"{rel}:{line_no} — `@{label} {num}` 이 실재하지 않는다. "
                    f"{tgt_path.name} 의 이웃: {', '.join(near[:6]) or '(없음)'}"
                )
                continue

            tail = text[m.end(): m.end() + 120]
            q = QUOTE_RE.search(tail)
            if not q:
                continue
            quoted += 1
            needle = norm(q.group(1))
            s, e = secmap[num]
            lines_tgt = list(g.contents[tgt_path])
            if tgt_path == src:
                for k in range(line_no - 1, min(line_no + 2, len(lines_tgt))):
                    lines_tgt[k] = ""
            body = norm("".join(lines_tgt[s - 1: e - 1]))
            if needle in body:
                sites.append((str(rel), line_no, label, num, tgt_path, needle))
                continue
            whole = norm("".join(lines_tgt))
            if needle in whole:
                # **축약 인용 완화** (2026-08-27 실측): 「적중·대체·미적중」처럼
                # 구분자로 이은 축약형은 인용된 절에 조각이 *흩어져* 있고
                # 붙여 쓴 형태만 다른 절에 있을 수 있다. 그때 인용은 옳다.
                parts = [x for x in re.split(r"[·/,]", q.group(1)) if len(x.strip()) >= 2]
                if len(parts) >= 2 and all(norm(x) in body for x in parts):
                    soft.append(
                        f"{rel}:{line_no} — `@{label} {num}` 의 축약 인용 "
                        f"「{q.group(1)[:30]}…」 — 조각은 그 절에 있고 붙인 형태만 밖에 있다"
                    )
                    continue
                owner = next(
                    (k for k, (a, b) in secmap.items()
                     if k.count(".") >= 2 and needle in norm("".join(lines_tgt[a - 1:b - 1]))),
                    "(항 밖)",
                )
                hard.append(
                    f"{rel}:{line_no} — `@{label} {num}` 이 인용한 「{q.group(1)[:34]}…」는 "
                    f"그 절에 없다. 실제 자리는 **{owner}** 다"
                )
            else:
                soft.append(
                    f"{rel}:{line_no} — `@{label} {num}` 뒤의 「{q.group(1)[:30]}…」가 "
                    f"{tgt_path.name} 에 축자로 없다 (요약이면 정상)"
                )
    return {"hard": hard, "soft": soft, "checked": checked, "quoted": quoted,
            "sites": sites}


# ---------------------------------------------------------------------------
# 축 1 — `파일:줄[-줄]`
# ---------------------------------------------------------------------------
def resolve_target(root: Path, src_rel: str, tgt: str, tracked: set[str]) -> str | None:
    if tgt in tracked:
        return tgt
    d = src_rel.rsplit("/", 1)[0] if "/" in src_rel else ""
    cand = (d + "/" + tgt).lstrip("/")
    if cand in tracked:
        return cand
    hits = [f for f in tracked if f.endswith("/" + tgt)]
    if hits:
        return sorted(hits, key=len)[0]
    return None


def axis1(root: Path) -> dict:
    files = list(iter_repo_files(root))
    tracked = {str(p.relative_to(root)) for p, _ in files}
    body_cache: dict[str, list[str]] = {}
    idx_cache: dict[str, tuple[str, list[int]]] = {}

    def lines_of(rel: str) -> list[str]:
        if rel not in body_cache:
            body_cache[rel] = (root / rel).read_text(
                encoding="utf-8", errors="replace").splitlines()
        return body_cache[rel]

    r = {
        "total": 0, "outoftree": 0,
        "missing": [], "range": [],
        "ok": [], "stale": [], "soft": [], "unmeasured": [],
        "unmeasured_hard": [], "soft_hard": [],
        "cover": {}, "cover_curated": {},
        "untracked": untracked_domain(root),
    }
    for src, text in files:
        src_rel = str(src.relative_to(root))
        src_lines = text.splitlines()
        zone = sender_zone(src_rel)
        hard_zone = zone == "hard"
        for m in LINECITE_RE.finditer(text):
            tgt, a = m.group(1), int(m.group(2))
            b = int(m.group(3)) if m.group(3) else a
            line_no = text[: m.start()].count("\n") + 1
            r["total"] += 1

            base = tgt.rsplit("/", 1)[-1]
            if base in AX1_OUT_OF_TREE:
                r["outoftree"] += 1
                continue

            res = resolve_target(root, src_rel, tgt, tracked)
            if res is None:
                r["missing"].append((src_rel, line_no, f"{tgt}:{a}"))
                continue
            tl = lines_of(res)
            if a < 1 or b > len(tl) or b < a:
                r["range"].append(
                    (src_rel, line_no, f"{tgt}:{m.group(2)}"
                     + (f"-{m.group(3)}" if m.group(3) else ""), len(tl)))
                continue

            # 따옴표 결속 — 좌표가 있는 **그 줄**에서만 (좌표 인용은 한 줄에 산다)
            ln = src_lines[line_no - 1] if line_no - 1 < len(src_lines) else ""
            tok = m.group(0)
            i = ln.find(tok)
            q = None
            if i >= 0:
                tail = re.sub(r"^[`\)\]]*", "", ln[i + len(tok):])
                qm = AX1_QUOTE_RE.search(tail)
                # ② 번호 개입 시 미결속 — 다른 좌표 인용이나 **절 번호**가
                #    사이에 있으면 그 따옴표는 이 좌표의 것이 아니다.
                #    `…typ:358-360 (§2.4.1 규범 「확정 — 조각별 슬롯」 1–2항)`
                #    이 그 형태다 (2026-08-30 실측): 따옴표는 규범 *블록의
                #    이름*이고 좌표는 그 블록의 일부 줄을 가리킨다. 결속하면
                #    「그 줄에 없다」로 거짓 실패한다.
                #    그리고 따옴표 **뒤**도 같은 이유로 막는다. 축 0·2 가 쓰는
                #    `bind_quote()` 는 앞뒤 양쪽을 보는데(위 567행 부근) 축 1
                #    인라인 결속기는 오래도록 `pre` 만 보았다. 그 비대칭이
                #    2026-08-30 에 **거짓 STALE 3건**을 만들었고, 그것을
                #    「재조준」한 편집이 **옳던 좌표 셋을 틀린 좌표로 바꿨다**
                #    (`budget_axis.md` B2·B4·C3). 형태는 이렇다:
                #      `` 규범 「이름」 `X.typ` 597-599행 | … 「본문」(`:601-602`) ``
                #    뒤 따옴표의 진짜 주인은 바로 뒤 괄호의 맨 좌표 `:601-602`
                #    인데, 앞 좌표에 결속돼 「그 줄에 없다」로 거짓 실패했다.
                pre = tail[:qm.start(1)] if qm else ""
                post = tail[qm.end(1): qm.end(1) + 18] if qm else ""
                if qm and not (_binding_blocked(pre) or _binding_blocked(post)):
                    q = qm.group(1)
            if q is None:
                r["unmeasured"].append((src_rel, line_no, res, hard_zone))
                if hard_zone:
                    r["unmeasured_hard"].append((src_rel, line_no, f"{tgt}:{a}"))
                continue

            needle = norm(q)
            if res == src_rel:
                # 자기 인용 제외 — 인용문 자신을 「실제 자리」로 오인하지 않게
                view = list(tl)
                view[line_no - 1] = ""
                flat, pos = norm_index(view)
            else:
                if res not in idx_cache:
                    idx_cache[res] = norm_index(tl)
                flat, pos = idx_cache[res]
            starts = start_lines(flat, pos, needle)
            if any(a <= s <= b for s in starts):
                r["ok"].append((src_rel, line_no, res, a))
                r["cover"][res] = r["cover"].get(res, 0) + 1
                if zone != "volatile":
                    r["cover_curated"][res] = r["cover_curated"].get(res, 0) + 1
            elif starts:
                # 대상 파일의 **다른 줄**에 있다 — 재조준 가능한 결함
                actual = min(starts, key=lambda s: abs(s - a))
                r["stale"].append((src_rel, line_no, res, a, actual, q))
            else:
                # 어디에도 없다 — 의역일 수 있다. 대상은 재지 못하지만
                # hard 구역에서는 **수(R6)를 잠근다** (따옴표를 흐려서 틀린
                # 좌표를 통과시키는 우회로를 막는다).
                r["soft"].append((src_rel, line_no, res, a, q))
                if hard_zone:
                    r["soft_hard"].append((src_rel, line_no, res, a, q))
    return r


# ---------------------------------------------------------------------------
# 축 2 — `§N.M[.K]`
# ---------------------------------------------------------------------------
def axis2(root: Path, g: Guide, files) -> dict:
    r = {
        "checked": 0, "crossdoc": 0, "selfnum": 0, "outofdomain": 0,
        "nonexist_hard": [], "nonexist_soft": [],
        "ok": 0, "ok_weak": 0, "wrong": [], "soft": 0, "soft_hard": [],
        "ambig": 0, "unmeasured": 0, "unmeasured_hard": [], "group": 0,
        "cover": {},
        "ok_out": 0, "ok_out_sites": [], "wrong_out": [], "soft_out": 0,
    }
    for src, text in files:
        rel = str(src.relative_to(root))
        selfch = {m.group(1) for m in SELF_HEAD_RE.finditer(text)}
        canon = rel.startswith(_G)
        hard_zone = sender_zone(rel) == "hard"
        for m in BARE_RE.finditer(text):
            num = m.group(1)
            ch = num.split(".")[0]
            tgt = g.chap_files.get(ch)
            if tgt is None:
                continue          # 그 장이 없다 — 다른 문서의 절일 수 있다
            prewin = text[max(0, m.start() - 80): m.start()]
            nm = NAMED_REF_RE.search(prewin)
            if nm and GUIDE_NAME not in (nm.group(1) or nm.group(2) or ""):
                r["crossdoc"] += 1   # 이름 붙은 형제 문서 인용 — 정본 좌표가 아니다
                continue
            line_no = text[: m.start()].count("\n") + 1

            # 비정본 문서의 **자기 번호 체계** — 문법으로 구별 불가. 정의역 밖.
            #
            # **예외 — 정본을 이름으로 지목한 인용**(2026-08-30). 인용 바로 앞
            # 창에 정본의 이름/경로가 있으면 그것이 자기 절이 아님을 문면이
            # 스스로 말한다. 이 예외가 필요한 이유가 W6 그 자체다:
            # `onwire_format_spec.md:9` 의 `정본 …guide/ 3장 §3.11 「원격 표면」`
            # 은 W6 이 밟은 바로 그 인용인데, 그 문서가 자기 `## 3.` 절 체계를
            # 가진다는 이유로 통째로 정의역 밖이었다. 즉 이 검사의 동기가 된
            # 자리가 검사되지 않았다.
            # 실측(2026-08-30): 이 예외가 대조 대상에 더하는 것은 16건, 그중
            # 따옴표 인용 1건이고 **오탐 0** 이다.
            if not hard_zone and ch in selfch and GUIDE_NAME not in prewin:
                r["selfnum"] += 1
                continue

            r["checked"] += 1
            secmap = g.secmaps.get(tgt, {})
            if num not in secmap:
                near = sorted(k for k in secmap if k.startswith(num.rsplit(".", 1)[0]))
                msg = (f"{rel}:{line_no} — `§{num}` 이 실재하지 않는다 "
                       f"({tgt.name}). 이웃: {', '.join(near[:6]) or '(없음)'}")
                # **비정본은 자기 절 번호를 가진다.** 2026-08-27 첫 실행에서
                # 이 부류로 오탐 16건이 났다. ⇒ hard 구역만 하드로 본다.
                if hard_zone:
                    r["nonexist_hard"].append(msg)
                else:
                    r["nonexist_soft"].append(msg + " — 비정본이라 자기 절일 수 있다")
                continue

            members, is_last = group_members(text, m)
            if not is_last:
                r["group"] += 1       # 묶음의 마지막 항이 대표로 결속한다
                continue
            q, why = bind_quote(text[m.end():])
            if why == "ambig":
                r["ambig"] += 1
                continue
            if q is None:
                r["unmeasured"] += 1
                if hard_zone:
                    r["unmeasured_hard"].append((rel, line_no, num))
                else:
                    r["outofdomain"] += 1
                continue
            needle = norm(q)

            # ── 비-hard 발신의 대상 대조 ── (2026-08-30 신설)
            #
            # 오래도록 이 부류는 「비정본은 자기 절 번호를 가진다」를 이유로
            # 대조를 통째로 건너뛰었다. 그런데 **자기 번호를 가진 문서는 이미
            # 위 `selfnum` 필터가 걸러 낸다.** 남은 것은 정본 절을 정본 번호로
            # 부르는 인용이고, 그것은 대조할 수 있다.
            #
            # 이것을 켠 이유는 W6 이다. W6 은 on-wire 절 삽입으로 §3.11 이
            # 형식 속성에서 원격 표면으로 바뀌었을 때 그 부류 6건이 「파손 0」인
            # 채 틀려 있었다고 실측했다 — 그런데 그 자리를 오늘 그대로 재현해도
            # **세 축이 한 자리도 움직이지 않았다.** 그 부류의 인용
            # (`.claude-memos/onwire_format_spec.md` 의 `§3.11 「원격 표면」`)이
            # 전부 이 「대조하지 않는」 바구니에 들어 있었기 때문이다.
            # 즉 이 검사의 동기가 된 바로 그 자리가 정의역 밖이었다.
            #
            # 2026-08-30 전수 실측: 이 바구니의 따옴표 인용 3건 — **전부 ok,
            # 오탐 0.** 그래서 실패로 승격하되, 예외는 아래 표에 등재해 남긴다
            # (기록으로서 옛 번호를 적는 인용이 있을 수 있다).
            if not hard_zone:
                owners = g.owners(needle)
                if any(p == tgt and any(is_ancestor_or_self(mm, k)
                                        for mm in members)
                       for p, k in owners):
                    r["ok_out"] += 1
                    # 마지막 칸 = 「이 발신 문서는 그 장 번호에 대해 **자기 번호
                    # 체계**를 갖는가」. 참이면 이 대조는 `selfnum` 예외
                    # (정본을 이름으로 지목한 인용)에만 걸려 있다 — W6 부류다.
                    r["ok_out_sites"].append(
                        (rel, line_no, num, str(tgt.relative_to(root)), ch in selfch))
                elif not owners:
                    r["soft_out"] += 1
                else:
                    r["wrong_out"].append(
                        (rel, line_no, "·".join(members), q,
                         ", ".join(f"{p.name} §{k}" for p, k in owners[:4])))
                continue

            exclude = (src, line_no) if canon else None
            owners = g.owners(needle, exclude=exclude)
            if any(p == tgt and any(is_ancestor_or_self(mm, k) for mm in members)
                   for p, k in owners):
                # ── 반증력 판정 ── (§6.6.5 「대조 수가 반증력의 척도로 읽힌다」)
                # 「대조 65건」에 반증력 0 인 대조가 섞여 있었다. 둘이다:
                #   ⓐ **보통명사 인용** — 「형식 속성」은 정본 12개 절이 소유
                #      한다. 어느 절로 바꿔도 통과하므로 재번호를 못 잡는다.
                #   ⓑ **묶음 인용** — `(§1.4.2 · §1.4.6)` 은 규칙 ④ 로 한
                #      멤버만 맞으면 전체가 ok 다. 나머지 멤버는 안 재는 것이다.
                # 둘 다 실패로 만들면 오탐이 되므로(그 규칙들은 오탐을 낮추려
                # 넣은 것이다) **통과로 두되 덮임에서 뺀다.** 덮임은 「이 장의
                # 재번호를 잡을 수 있는가」의 척도이고, 이 둘은 잡지 못한다.
                weak = (len(owners) >= WEAK_OWNERS_MIN
                        or not all(any(p == tgt and is_ancestor_or_self(mm, k)
                                       for p, k in owners) for mm in members))
                if weak:
                    r["ok_weak"] += 1
                else:
                    r["ok"] += 1
                    tr = str(tgt.relative_to(root))
                    r["cover"][tr] = r["cover"].get(tr, 0) + 1
            elif not owners:
                r["soft"] += 1        # 의역/요약 — 대상은 못 재지만 R6 이 수를 잠근다
                if hard_zone:
                    r["soft_hard"].append((rel, line_no, num, q))
            else:
                r["wrong"].append(
                    (rel, line_no, "·".join(members), q,
                     ", ".join(f"{p.name} §{k}" for p, k in owners[:4])))
    return r


def axis2b(root: Path, g: Guide, files) -> dict:
    """`@sec:` 도 `§` 도 없는 맨 번호 — 「4.2.2 함정이 못박듯」 형태.

    **블록 종류만** 잰다: 「N.M 함정」이라 적었으면 §N.M 안에 `#함정(` 이
    있어야 한다. 「규범」·「해설」은 보통명사로도 쓰여 정밀도가 낮으므로 세지
    않는다 (§6.7 — 덮는 범위를 이름에 적는다).
    """
    r = {"checked": 0, "bad": [], "sites": []}
    for src, text in files:
        rel = str(src.relative_to(root))
        if not (rel.startswith("docs/wt64v1-architecture-guide/")
                or rel.startswith(("rtl/", "proofs/"))):
            continue
        for m in BARE2_RE.finditer(text):
            pre = text[max(0, m.start() - 40): m.start()]
            if re.search(r"@sec:[a-z0-9-]+\s*$", pre):
                continue                      # 축 0 이 본다
            if re.search(r"(v|V|버전|version|ISA-|D-|F-|B\.|E\.|§)\s*$", pre):
                continue
            mk = BLOCK_WORD_RE.match(text[m.end(): m.end() + 40])
            if not mk:
                continue
            num = m.group(1)
            tgt = g.chap_files.get(num.split(".")[0])
            if tgt is None or num not in g.secmaps.get(tgt, {}):
                continue                      # 실재는 축 2 가 본다
            r["checked"] += 1
            r["sites"].append((rel, text[: m.start()].count("\n") + 1, num))
            a, b = g.secmaps[tgt][num]
            body = "\n".join(g.contents[tgt][a - 1:b - 1])
            if "#함정(" not in body:
                line_no = text[: m.start()].count("\n") + 1
                kinds = [k for k in ("#규범(", "#해설(", "#함정(") if k in body]
                r["bad"].append((rel, line_no, num,
                                 ", ".join(kinds) or "(블록 없음)"))
    return r


# ---------------------------------------------------------------------------
# 래칫 판정
# ---------------------------------------------------------------------------
def ratchet(name: str, actual: dict[str, int], allowed: dict[str, int],
            fails: list[str]) -> None:
    """파일별 표 래칫 — 늘어나면 실패, 줄면 표를 같이 내리라고 말한다."""
    for f in sorted(set(actual) | set(allowed)):
        got, cap = actual.get(f, 0), allowed.get(f, 0)
        if got > cap:
            fails.append(f"{name}: {f} — {got}건 (상한 {cap}). "
                         f"래칫 초과. 고치거나, 올린다면 그 편집이 리뷰 대상이다")
        elif got < cap:
            fails.append(f"{name}: {f} — {got}건인데 상한이 {cap} 이다. "
                         f"**상한을 함께 내려라** (항목 제거는 래칫 상한도 같이 내린다)")


# ---------------------------------------------------------------------------
# --drift — 축 1 의 이력 대조
# ---------------------------------------------------------------------------
def drift(root: Path) -> int:
    print(f"{TAG} --drift — 축 1 이력 대조 (`git blame` · 따옴표 불필요)")
    a1 = axis1(root)
    # 좌표가 실재하는 것만 대상
    targets: list[tuple[str, int, str, int, int]] = []
    for src, ln, res, a in a1["ok"]:
        targets.append((src, ln, res, a, a))
    for t in a1["stale"]:
        targets.append((t[0], t[1], t[2], t[3], t[3]))
    for t in a1["soft"]:
        targets.append((t[0], t[1], t[2], t[3], t[3]))
    for src, ln, res, _hz in a1["unmeasured"]:
        targets.append((src, ln, res, 0, 0))
    # 좌표 범위를 다시 뽑는다 (unmeasured 는 a 를 안 들고 있다)
    todo: list[tuple[str, int, str, int, int]] = []
    for src, ln, res, *_ in [(t[0], t[1], t[2]) for t in targets]:
        pass
    del todo

    # blame — 발신 파일별로 한 번
    blame: dict[str, dict[int, str]] = {}
    srcs = sorted({t[0] for t in targets})
    for s in srcs:
        out = subprocess.run(["git", "blame", "--line-porcelain", "-M", "--", s],
                             cwd=root, capture_output=True, text=True).stdout
        cur = 0
        mp: dict[int, str] = {}
        for line in out.splitlines():
            mm = re.match(r"^([0-9a-f]{40}) \d+ (\d+)", line)
            if mm:
                cur = int(mm.group(2))
                mp[cur] = mm.group(1)
        blame[s] = mp

    # ── 공허 게이트 방지 ── shallow clone 에서는 blame 이 전 줄을 한 커밋으로
    # 돌려준다. 그러면 옛 문면이 없어 이 축은 조용히 통과한다. 통과가 아니라
    # 실패로 인쇄한다.
    commits = {c for mp in blame.values() for c in mp.values()}
    depth = subprocess.run(["git", "rev-list", "--count", "HEAD"],
                           cwd=root, capture_output=True, text=True).stdout.strip()
    if len(commits) < 5 or (depth.isdigit() and int(depth) < 20):
        print(f"  ⛔ **공허** — blame 이 돌려준 커밋 {len(commits)}종 / 이력 깊이 "
              f"{depth}. shallow clone 에서 이 축은 아무것도 재지 못한다.",
              file=sys.stderr)
        print("     `git fetch --unshallow` 또는 CI 의 `fetch-depth: 0` 이 필요하다.",
              file=sys.stderr)
        return 1

    show: dict[tuple[str, str], list[str] | None] = {}

    def old(commit: str, path: str) -> list[str] | None:
        k = (commit, path)
        if k not in show:
            o = subprocess.run(["git", "show", f"{commit}:{path}"],
                               cwd=root, capture_output=True, text=True)
            show[k] = o.stdout.splitlines() if o.returncode == 0 else None
        return show[k]

    now: dict[str, list[str]] = {}

    def cur_lines(p: str) -> list[str]:
        if p not in now:
            now[p] = (root / p).read_text(encoding="utf-8", errors="replace").splitlines()
        return now[p]

    # 좌표를 다시 훑어 (a,b) 를 얻는다 — axis1 이 버린 정보가 있어서다
    cites: list[tuple[str, int, str, int, int]] = []
    files = list(iter_repo_files(root))
    tracked = {str(p.relative_to(root)) for p, _ in files}
    for src, text in files:
        src_rel = str(src.relative_to(root))
        for m in LINECITE_RE.finditer(text):
            tgt, a = m.group(1), int(m.group(2))
            b = int(m.group(3)) if m.group(3) else a
            if tgt.rsplit("/", 1)[-1] in AX1_OUT_OF_TREE:
                continue
            res = resolve_target(root, src_rel, tgt, tracked)
            if res is None:
                continue
            tl = cur_lines(res)
            if a < 1 or b > len(tl) or b < a:
                continue
            cites.append((src_rel, text[: m.start()].count("\n") + 1, res, a, b))

    stats = {"UNCHANGED": 0, "DRIFTED": 0, "NO-BLAME": 0, "TARGET-NEW": 0, "OLD-OOR": 0}
    drifted: list[tuple] = []
    for src_rel, ln, res, a, b in cites:
        c = blame.get(src_rel, {}).get(ln) or blame.setdefault(
            src_rel,
            {int(mm.group(2)): mm.group(1) for mm in
             (re.match(r"^([0-9a-f]{40}) \d+ (\d+)", x) for x in
              subprocess.run(["git", "blame", "--line-porcelain", "-M", "--", src_rel],
                             cwd=root, capture_output=True, text=True).stdout.splitlines())
             if mm}).get(ln)
        if not c:
            stats["NO-BLAME"] += 1
            continue
        o = old(c, res)
        if o is None:
            stats["TARGET-NEW"] += 1
            continue
        if b > len(o):
            stats["OLD-OOR"] += 1
            continue
        ov = norm("\n".join(o[a - 1:b]))
        nv = norm("\n".join(cur_lines(res)[a - 1:b]))
        if ov == nv:
            stats["UNCHANGED"] += 1
            continue
        stats["DRIFTED"] += 1
        found = None
        if ov.strip() and len(ov) >= 8:
            # 옛 내용이 **시작하는 줄**을 정확히 구한다 — 창을 미끄러뜨리면
            # 창 시작줄과 내용 시작줄이 달라 Δ 가 몇 줄 어긋난다.
            flat, posmap = norm_index(cur_lines(res))
            hits = start_lines(flat, posmap, ov)
            if hits:
                found = min(hits, key=lambda s: abs(s - a))
        drifted.append((src_rel, ln, res, a, b, found))

    print(f"  대상 {len(cites)}건 — " + " · ".join(f"{k} {v}" for k, v in stats.items()))
    canon = [d for d in drifted if d[2].startswith("docs/wt64v1-architecture-guide/")]
    print(f"  DRIFTED {len(drifted)}건 (기계 재조준 가능 "
          f"{sum(1 for d in drifted if d[5])}건) · 그중 **정본 대상** {len(canon)}건")
    for d in canon[:40]:
        print(f"    {d[0]}:{d[1]} → {d[2]}:{d[3]}"
              + (f"-{d[4]}" if d[4] != d[3] else "")
              + (f"   실제 자리 {d[5]} (Δ{d[5]-d[3]:+d})" if d[5] else "   (옛 내용 소멸)"))
    print("\n  ※ 이 축이 재는 것은 「좌표가 가리키던 내용이 바뀌었다」이지 "
          "「인용이 옳았는가」가 아니다 —\n"
          "     태어날 때부터 틀린 좌표는 UNCHANGED 로 조용히 통과한다.")
    return 0


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
def _by_file(rows) -> dict[str, int]:
    d: dict[str, int] = {}
    for row in rows:
        d[row[0]] = d.get(row[0], 0) + 1
    return d


def run(root: Path, quiet: bool = False,
        rat: Ratchet | None = DEFAULT_RATCHET) -> tuple[int, dict]:
    """래칫은 **기본으로 켜져 있다.** 끄려면 `rat=None` 을 명시해야 한다.

    기본을 `None` 으로 두었더니 「호출부에서 인자 하나를 빠뜨리면 게이트가
    통째로 공허해진다」는 형태가 됐다 — 그 한 줄이 사라져도 `make lint` 는
    rc=0 이고 자기시험은 자기 래칫을 따로 쓰므로 아무도 울지 않는다.
    """
    g = Guide(root)
    files = list(iter_scan_files(root))
    a0 = axis0(root, g, files)
    a1 = axis1(root)
    a2 = axis2(root, g, files)
    a2b = axis2b(root, g, files)

    fails: list[str] = []
    if rat is not None:
        ratchet("R1 좌표 실재(파일 없음)", _by_file(a1["missing"]),
                rat.missing_max, fails)
        if len(a1["range"]) > rat.range_max:
            for s, l, t, n in a1["range"]:
                fails.append(f"R1 좌표 범위 초과: {s}:{l} — `{t}` 인데 그 파일은 {n}행")
        ratchet("R3 축1 대상 대조(낡음)", _by_file(a1["stale"]),
                rat.stale_max, fails)
        ratchet("R4 축2 대상 대조(엉뚱한 절)", _by_file(a2["wrong"]),
                rat.wrong_max, fails)
        ratchet("R4′ 축2 대상 대조(비-hard 발신 — 정본 절을 정본 번호로 부른 인용)",
                _by_file(a2["wrong_out"]), rat.wrong_out_max, fails)
        ratchet("R4b 블록 종류(함정)", _by_file(a2b["bad"]), rat.kind_max, fails)
        # R5 — 파일별. 스칼라 상한은 위반 자리를 지목하지 못했고 하강에
        # 침묵했다 (위 상수 주석 ①②).
        ratchet("R5 축1 미계수(hard 구역 — 좌표에 따옴표 없음)",
                _by_file(a1["unmeasured_hard"]), rat.ax1_unmeasured_max, fails)
        ratchet("R5 축2 미계수(hard 구역 — `§N.M` 에 따옴표 없음)",
                _by_file(a2["unmeasured_hard"]), rat.ax2_unmeasured_max, fails)
        ratchet("R6 축1 의역(hard 구역 — 따옴표가 대상에 축자로 없다)",
                _by_file(a1["soft_hard"]), rat.ax1_soft_max, fails)
        ratchet("R6 축2 의역(hard 구역 — 따옴표가 정본 어디에도 없다)",
                _by_file(a2["soft_hard"]), rat.ax2_soft_max, fails)
        for f, floor in sorted(rat.ax1_cover_floor.items()):
            got = a1["cover_curated"].get(f, 0)
            if got < floor:
                fails.append(
                    f"덮임 하한(축 1 · curated 이상 발신): {f} — 대조 가능한 정확 "
                    f"인용 {got}건 (하한 {floor}). 상한만으로는 「인용을 안 쓰면 "
                    f"통과」가 된다")
        for f, floor in sorted(rat.ax2_cover_floor.items()):
            got = a2["cover"].get(f, 0)
            if got < floor:
                fails.append(
                    f"덮임 하한(축 2 · hard 발신): {f} — 반증력 있는 절 대조 "
                    f"{got}건 (하한 {floor}). 이 장의 재번호를 잡을 증거가 그만큼 "
                    f"줄었다")

    hard = a0["hard"] + a2["nonexist_hard"]
    for s, l, r_, a_, act, q in a1["stale"]:
        if r_.startswith(_G):
            hard.append(f"{s}:{l} — `{r_}:{a_}` 가 인용한 「{q[:30]}」는 그 줄에 없다. "
                        f"실제 자리는 **{act}** 다 (Δ{act - a_:+d})" if act else
                        f"{s}:{l} — `{r_}:{a_}` 가 인용한 「{q[:30]}」는 그 줄에 없다")
    for s, l, num, q, owners in a2["wrong"] + a2["wrong_out"]:
        hard.append(f"{s}:{l} — `§{num}` 이 인용한 「{q[:34]}」는 그 절에 없다. "
                    f"실제 자리는 **{owners}**")
    for s, l, num, kinds in a2b["bad"]:
        hard.append(f"{s}:{l} — 「{num} 함정」이라 적었는데 §{num} 에 `#함정(` 이 없다 "
                    f"(있는 것: {kinds})")

    rc = 1 if (hard or fails) else 0
    if quiet:
        return rc, {"a0": a0, "a1": a1, "a2": a2, "a2b": a2b,
                    "hard": hard, "fails": fails}

    soft = a0["soft"] + a2["nonexist_soft"]
    if soft:
        print(f"  · 축자 대조 보류 {len(soft)}건 (요약 인용으로 보인다 — 실패 아님):")
        for t in soft[:6]:
            print(f"      {t}")
        if len(soft) > 6:
            print(f"      … 외 {len(soft)-6}건")

    if hard or fails:
        print(f"{TAG}: 실패", file=sys.stderr)
        for h in hard:
            print(f"  ❌ {h}", file=sys.stderr)
        for f in fails:
            print(f"  ❌ {f}", file=sys.stderr)
        print(
            f"\n  — 좌표는 문서를 고칠 때마다 움직인다. 인용할 때 번호를 짐작하지 말고\n"
            f"    대상 파일의 `==`/`===` 를 세어 확인하라 (이 검사가 그것을 대신 센다).",
            file=sys.stderr,
        )
        return 1, {}

    ux1 = len(a1["unmeasured"])
    unf, unc = a1["untracked"]
    floors1 = rat.ax1_cover_floor if rat else AX1_COVER_FLOOR
    floors2 = rat.ax2_cover_floor if rat else AX2_COVER_FLOOR
    print(
        f"{TAG}: OK — 「따옴표를 동반한 인용의 **대상** 대조」 세 축\n"
        f"  축 0 `@sec:`     인용 {a0['checked']}건 실재 · 따옴표 대조 {a0['quoted']}건\n"
        f"  축 1 `파일:줄`   인용 {a1['total']}건 (정의역 밖 {a1['outoftree']}건) — "
        f"좌표 실재 확인, 대상 대조 **{len(a1['ok'])}건**\n"
        f"  축 2 `§N.M`      인용 {a2['checked']}건 실재 — 대상 대조 "
        f"**{a2['ok']}건** (hard 구역 = 정본·rtl·proofs)\n"
        f"                   + 비-hard 발신 대상 대조 **{a2['ok_out']}건** "
        f"(W6 이 밟은 부류 — 자기 번호 체계가 없는 문서의 정본 인용)\n"
        f"  축 2b 「N.M 함정」 블록 종류 {a2b['checked']}건 대조"
    )
    print(
        f"  ── **안 잰다** (통과가 아니다 — §6.6.5) ──\n"
        f"     축 1 따옴표 없음 {ux1}건 · 의역으로 보임 {len(a1['soft'])}건\n"
        f"     축 2 따옴표 없음 {a2['unmeasured']}건 · 결속 불가 {a2['ambig']}건 · "
        f"묶음 종속 {a2['group']}건 · 의역 {a2['soft']}건\n"
        f"     축 2 **반증력 없는 대조** {a2['ok_weak']}건 — 보통명사 인용"
        f"(소유 절 {WEAK_OWNERS_MIN}개 이상) 또는 묶음의 일부만 맞은 것.\n"
        f"        통과로 두되 **덮임에서 뺀다** — 어느 절 번호로 바꿔도 통과하므로\n"
        f"        재번호를 잡지 못한다\n"
        f"     축 2 정의역 밖 — 비정본 자기 번호 {a2['selfnum']}건 · "
        f"형제 문서 인용 {a2['crossdoc']}건 · 비-hard 발신 따옴표 없음 "
        f"{a2['outofdomain']}건 · 그 구역 의역 {a2['soft_out']}건\n"
        f"     축 1 정의역 밖 — **미추적 파일** {unf}개 / 좌표 {unc}건 "
        f"(정의역은 `git ls-files`, 즉 인덱스다)"
    )

    def _cover_block(title: str, got: dict, floors: dict, note: str) -> None:
        txt = " · ".join(f"{Path(f).name} {got.get(f, 0)}/{fl}"
                         for f, fl in sorted(floors.items())) or "(등재 없음)"
        print(f"  ── {title} ── ({note})\n     {txt}")
        zero = [f for f in sorted(floors) if got.get(f, 0) == 0]
        if zero:
            print(f"     ⚠ **증거 0 인 장 {len(zero)}개** — "
                  f"{', '.join(Path(f).name for f in zero)}. "
                  f"이 장들에 대한 「파손 0」은 무증거다")

    _cover_block("축 1 덮임 (`파일:줄` 대조 가능 인용 수) 실측/하한",
                 a1["cover_curated"], floors1,
                 "하한은 **curated 이상 발신만** 센다 — volatile(`.claude-memos` 등) "
                 "발신은 하한의 볼모가 되면 안 된다")
    vol = {f: a1["cover"].get(f, 0) - a1["cover_curated"].get(f, 0)
           for f in floors1}
    print("     · volatile 발신 덮임(**하한 밖 — 인쇄만**): "
          + (" · ".join(f"{Path(f).name} {n}" for f, n in sorted(vol.items()) if n)
             or "(없음)"))
    _cover_block("축 2 덮임 (`§N.M` 반증력 있는 절 대조 수) 실측/하한",
                 a2["cover"], floors2,
                 "발신이 정의상 전부 hard 구역이라 하한이 그대로 선다")
    print("  ※ `--drift`(이력 축)는 이 실행에서 **돌지 않았다** — 약 12초가 "
          "걸리고 전체 이력을 요구하며,\n"
          "     shallow clone 에서는 통과가 아니라 공허가 된다. "
          "(이 실행 자체는 약 1초, `--self-test` 는 약 6.5초다.)")
    return 0, {}


# ---------------------------------------------------------------------------
# --self-test — 음성 시험. **기준 문면 통과를 먼저 확인한다.**
#
# W2 가 세운 형태: 기준이 이미 깨져 있으면 모든 변이가 엉뚱한 이유로 울어
# 자기시험이 조용히 초록이 된다.
# ---------------------------------------------------------------------------
# 픽스처는 **인용하는 층과 인용되는 층을 둘 다** 담아야 한다. 처음에 정본과
# `rtl/formal/tla` 만 복사했더니 기준 문면의 **축 1 OK 가 0** 이었고, 축 1
# 변이 둘이 「잡지 못함」이 아니라 「잴 것이 없음」으로 조용히 실패했다.
# 자기시험이 스스로 공허해지는 정확한 형태다.
FIXTURE_DIRS = [
    "docs/wt64v1-architecture-guide",
    "rtl/formal/tla",
    "rtl/sv/assert",
]
_FIX_IGNORE = shutil.ignore_patterns("*.bin", "*.vcd", "*.fst", "*.log",
                                     "__pycache__", "sim_build", "*.pdf")


def _fixture(td: Path, extra: list[str]) -> Path:
    """정본 + 형식 모델 + **실제로 축 1 대조가 성립하는 발신 파일들.**

    `extra` 는 실 트리 실행이 돌려준 자리에서 뽑는다 — 손으로 적으면 문면이
    옮겨갔을 때 픽스처가 조용히 「잴 것 없음」이 된다.
    """
    base = td / "repo"
    for d in FIXTURE_DIRS:
        src = REPO / d
        if src.exists():
            shutil.copytree(src, base / d, ignore=_FIX_IGNORE)
    for f in sorted(set(extra)):
        src = REPO / f
        if src.exists() and not (base / f).exists():
            (base / f).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, base / f)
    return base


def calibrate(d: dict) -> Ratchet:
    """픽스처 기준선의 **실측치**를 그대로 래칫으로 만든다.

    실 트리 상수표는 부분 사본에 맞지 않는다(대상 부재 46건 등). 그래서
    자기시험은 오래도록 `check_ratchet=False` 로 돌았고, 그 결과 **래칫 집행
    코드 전체가 음성 시험의 정의역 밖**이었다 — 통째로 지워도 두 게이트가
    다 통과했다. 재보정한 래칫으로 돌리면 그 코드가 정의역 안으로 들어온다.

    덮임 하한을 실측치 **그대로**(1 이 아니라) 잠그는 이유: 자기시험에서는
    「감소가 정상인 편집」이 없다. 변이 하나가 덮임을 줄이면 그것은 곧
    회귀이므로, 하한을 실측치로 두어야 ⑪ 이 뜻을 갖는다.
    """
    a1, a2, a2b = d["a1"], d["a2"], d["a2b"]
    return Ratchet(
        missing_max=_by_file(a1["missing"]),
        range_max=len(a1["range"]),
        stale_max=_by_file(a1["stale"]),
        wrong_max=_by_file(a2["wrong"]),
        wrong_out_max=_by_file(a2["wrong_out"]),
        kind_max=_by_file(a2b["bad"]),
        ax1_unmeasured_max=_by_file(a1["unmeasured_hard"]),
        ax2_unmeasured_max=_by_file(a2["unmeasured_hard"]),
        ax1_soft_max=_by_file(a1["soft_hard"]),
        ax2_soft_max=_by_file(a2["soft_hard"]),
        ax1_cover_floor=dict(a1["cover_curated"]),
        ax2_cover_floor=dict(a2["cover"]),
    )


def _counts(root: Path, rat: Ratchet) -> dict:
    rc, d = run(root, quiet=True, rat=rat)
    a1, a2, a2b = d["a1"], d["a2"], d["a2b"]
    c = {
        "rc": rc,
        "ax1_ok": len(a1["ok"]), "ax1_stale": len(a1["stale"]),
        "ax1_range": len(a1["range"]), "ax1_missing": len(a1["missing"]),
        "ax2_ok": a2["ok"], "ax2_wrong": len(a2["wrong"]),
        "ax2b_bad": len(a2b["bad"]),
        "hard": len(d["hard"]),
        "fails": list(d["fails"]),
    }
    # **결함 총수** — `hard` 만 보면 래칫으로만 잡는 부류(좌표 실재)의 변이가
    # 「잡지 못함」으로 보인다. 검출 판정은 이 수로 한다.
    #
    # `ax1_missing` 은 **뺀다**: 자기시험 픽스처는 저장소의 부분 사본이라
    # 대상 파일이 없는 인용이 정상적으로 생긴다. 넣으면 기준 문면이 늘
    # 「깨져 있다」가 되어 자기시험이 시작도 못 한다 (실측 46건).
    c["defects"] = c["hard"] + c["ax1_range"]
    # 래칫 위반은 별도 축이다 — `defects` 는 문면 결함, 이것은 **표 위반**.
    c["nfails"] = len(c["fails"])
    return c


def _insert_lines(p: Path, at: int, n: int = 40) -> None:
    L = p.read_text(encoding="utf-8").splitlines(keepends=True)
    p.write_text("".join(L[:at] + ["// wt-selftest 삽입\n"] * n + L[at:]),
                 encoding="utf-8")


def self_test() -> int:
    print(f"{TAG} --self-test — 음성 시험")
    ok = True
    rows: list[tuple[str, str, bool]] = []
    _, dreal = run(REPO, quiet=True, rat=None)
    # 픽스처는 **잴 것을 담아야 한다.** 축 1 대조가 성립하는 발신 파일에 더해
    # 비-hard 발신 축 2 대조(W6 부류)의 발신도 넣는다 — 넣지 않으면 ⑬ 이
    # 「못 잡음」이 아니라 「잴 것 없음」이 된다.
    carriers = ([s[0] for s in dreal["a1"]["ok"]]
                + [s[0] for s in dreal["a2"]["ok_out_sites"]])
    with tempfile.TemporaryDirectory(prefix="wt-secrefs-") as td:
        base = _fixture(Path(td), carriers)

        # ── ⓪ 기준 문면 확인 — 이것이 **먼저**다 (W2 형태) ──
        # 기준이 이미 깨져 있으면 모든 변이가 엉뚱한 이유로 울고, 자기시험은
        # 조용히 초록이 된다. 그리고 「잴 것이 있는가」도 함께 본다 — 픽스처가
        # 대조 가능한 인용을 0건 담으면 변이는 「못 잡음」이 아니라 「잴 것
        # 없음」이 되고, 그것이 자기시험 자신의 공허다.
        _, d0 = run(base, quiet=True, rat=None)
        cal = calibrate(d0)          # ← 이 래칫으로 이후 **전부**를 돌린다
        b = _counts(base, cal)
        if b["defects"] != 0:
            print(f"  ⛔ 기준 문면이 이미 깨져 있다 (결함 {b['defects']}건) — 자기시험 중단")
            for h in d0["hard"][:5]:
                print(f"      {h}")
            return 1
        if b["nfails"] != 0:
            print(f"  ⛔ 재보정한 래칫이 기준 문면에서 이미 운다 — 보정이 틀렸다")
            for f in b["fails"][:5]:
                print(f"      {f}")
            return 1
        if b["ax1_ok"] < 5 or b["ax2_ok"] < 5:
            print(f"  ⛔ 픽스처에 대조 가능한 인용이 거의 없다 "
                  f"(축1 {b['ax1_ok']} · 축2 {b['ax2_ok']}) — 변이가 뜻을 갖지 못한다")
            return 1
        print(f"  ⓪ 기준 문면 통과 ✓ — 축1 대조 {b['ax1_ok']}건 · "
              f"축2 대조 {b['ax2_ok']}건 · 축0 대조 {len(d0['a0']['sites'])}건 · 결함 0\n"
              f"     (부분 사본이라 대상 부재 {b['ax1_missing']}건은 정상 — "
              f"이 축은 실 트리에서만 뜻이 있다)\n"
              f"     래칫은 **픽스처 기준선에서 재보정**했다 — 실 트리 상수표는 "
              f"부분 사본에 맞지 않고,\n"
              f"     그래서 오래도록 래칫 집행 코드 전체가 이 시험의 정의역 밖이었다 "
              f"(§6.7)")

        def measure(label: str, expect: str, key: str | None = "defects",
                    rule=None, names: str | None = None) -> dict:
            """변이 하나를 재고 **잡았는가**를 판정한다.

            `rule` 은 래칫 위반 메시지의 접두어다. 결함 수(`key`)로만 판정하면
            래칫으로만 잡는 부류(미계수·의역·덮임)가 이 시험의 정의역 밖에
            남는다 — 그것이 §6.3.2 가드 삭제 실험을 통과하지 못한 원인이었다.
            """
            nonlocal ok
            a = _counts(base, cal)
            delta = {k: a[k] - b[k] for k in a
                     if k not in ("rc", "fails")}
            caught = (a[key] > b[key]) if key else True
            rules = (rule,) if isinstance(rule, str) else tuple(rule or ())
            hit = [f for f in a["fails"] if f.startswith(rules)] if rules else []
            for one_rule in rules:
                # **규칙마다 따로 확인한다.** 한 변이가 여러 래칫을 울릴 때
                # 「어느 하나가 울었다」로 판정하면 나머지가 조용히 정의역
                # 밖으로 빠진다 — 실측으로 축 2 덮임 하한이 그 상태였다
                # (통째로 지워도 자기시험이 초록이었다).
                if not any(f.startswith(one_rule) for f in a["fails"]):
                    caught = False
            if names:
                # **위반 자리를 지목하는가** — 스칼라 상한 시절의 R5 는 방금 생긴
                # 자리가 아니라 스캔 순서 앞 12건을 인쇄했다. 건드린 적 없는
                # 파일의 오류를 보여 주는 게이트는 곧 꺼진다(F-52).
                caught = caught and any(names in h for h in hit)
            note = ", ".join(f"{k} {v:+d}" for k, v in delta.items() if v) or "변화 없음"
            for one_rule in rules:
                h = next((f for f in a["fails"] if f.startswith(one_rule)), None)
                note += f"\n        래칫 `{one_rule}` — " + (
                    h[:160] if h else "**울지 않았다**")
            rows.append((label, f"{expect} → {note}", caught))
            if not caught:
                ok = False
            return a

        # ── 변이는 **기준 실행이 돌려준 실제 자리**에서 고른다 ──
        # 문자열을 손으로 박으면 문면이 바뀔 때 변이가 조용히 무효가 된다
        # (아무것도 치환되지 않고 「변화 없음」 = 잡지 못함으로 보인다).
        ax1_sites = [s for s in d0["a1"]["ok"]
                     if "01-isa-asm.typ" in s[2]]
        ax2b_sites = d0["a2b"]["sites"]

        # ① 축 2 — 실재하는 **엉뚱한 절**로 개악 (W6 이 실측한 부류)
        p = base / "rtl/formal/tla/Payload.tla"
        orig = p.read_text(encoding="utf-8")
        needle = "§4.3 규범 1(「태그가 재조립의 키다」)"
        assert needle in orig, "변이 ① 의 대상 문면이 사라졌다 — 변이를 갱신하라"
        p.write_text(orig.replace(needle, needle.replace("§4.3", "§4.5")),
                     encoding="utf-8")
        measure("① 축2 — `§4.3` 인용을 실재하는 엉뚱한 절 `§4.5` 로",
                "WRONG-TARGET 검출", rule="R4 축2 대상 대조")
        p.write_text(orig, encoding="utf-8")

        # ⑩ 축 2 — **따옴표를 한 글자 의역**한다. §4.3 은 그대로 두고 인용문만
        #    흐린다. 이것이 ① 의 우회로였다: `wrong` 이 아니라 `soft` 로 떨어져
        #    **rc=0 이 됐다.** R6 이 그 우회로를 막는다.
        blur = needle.replace("재조립의 키다", "재조립의 열쇠다")
        assert blur != needle
        p.write_text(orig.replace(needle, blur), encoding="utf-8")
        measure("⑩ 축2 — 인용문을 한 글자 의역 (「키다」→「열쇠다」, 절 번호는 그대로)",
                "의역 상한(R6) **그리고** 축 2 덮임 하한 — 둘 다 울어야 한다. "
                "의역은 대상 대조를 통째로 빠져나가는 길이었고, 빠져나가면 "
                "그 장의 증거가 하나 줄어든다",
                key=None, rule=("R6 축2 의역", "덮임 하한(축 2"))
        p.write_text(orig, encoding="utf-8")

        # ② 축 1 — **덮임이 있는 장**에 줄을 밀어 넣는다 (재번호 아님, 순수 이동)
        assert ax1_sites, "변이 ② 의 대상(1장을 겨냥한 대조 가능 인용)이 없다"
        tgt = base / ax1_sites[0][2]
        tgt_rel = ax1_sites[0][2]
        orig_t = tgt.read_text(encoding="utf-8")
        at = min(s[3] for s in ax1_sites) - 1
        _insert_lines(tgt, max(0, at))
        a_ins = measure(f"② 축1 — 1장 {at}행에 40줄 삽입 "
                        f"(그 장을 겨냥한 대조 가능 인용 {len(ax1_sites)}건)",
                        "STALE 검출", rule="R3 축1 대상 대조")
        tgt.write_text(orig_t, encoding="utf-8")

        # ②′ **이 시험 자신의 검출력**을 래칫에 건다 (§6.6.5 「대상 오인」).
        #    ② 가 10건을 잡든 1건을 잡든 그동안 「음성 시험 통과」가 똑같이
        #    인쇄됐다 — 픽스처의 증거가 90% 사라져도 조용히 초록이었다.
        #    ⇒ 검출력의 하한을 **덮임 하한 표**에 건다. 그 표는 리뷰를 거쳐야
        #       내려가므로, 증거의 소실이 표를 건드리지 않고는 통과하지 못한다.
        pw = a_ins["ax1_stale"] - b["ax1_stale"]
        need = cal.ax1_cover_floor.get(tgt_rel, 0)
        rows.append((f"②′ ② 의 검출력 — STALE {pw}건 (하한 {need} = 덮임 하한 표의 "
                     f"{Path(tgt_rel).name} 칸)",
                     "검출력이 하한 아래로 내려가면 이 시험이 **공허**하다",
                     pw >= need and pw > 0))
        if not (pw >= need and pw > 0):
            ok = False

        # ③ 축 1 — 좌표를 파일 밖으로
        src3, ln3, res3, a3 = ax1_sites[0]
        p3 = base / src3
        orig3 = p3.read_text(encoding="utf-8")
        L3 = orig3.splitlines(keepends=True)
        L3[ln3 - 1] = re.sub(r":%d\b" % a3, ":999999", L3[ln3 - 1], count=1)
        p3.write_text("".join(L3), encoding="utf-8")
        measure(f"③ 축1 — `{Path(res3).name}:{a3}` 를 `:999999` 로 (범위 초과)",
                "OUT-OF-RANGE 검출", rule="R1 좌표 범위 초과")
        p3.write_text(orig3, encoding="utf-8")

        # ④ 축 2b — 「N.M 함정」의 절 번호를 함정 없는 절로
        gb = Guide(base)
        no_trap = next(
            (k for p_, sm in gb.secmaps.items() for k, (a_, b_) in sorted(sm.items())
             if k.count(".") == 1 and chapter_number(p_) == "4"
             and "#함정(" not in "".join(gb.contents[p_][a_ - 1:b_ - 1])),
            None)
        if ax2b_sites and no_trap:
            src4, ln4, num4 = ax2b_sites[0]
            p4 = base / src4
            orig4 = p4.read_text(encoding="utf-8")
            L4 = orig4.splitlines(keepends=True)
            L4[ln4 - 1] = L4[ln4 - 1].replace(num4 + " 함정", no_trap + " 함정", 1)
            assert L4[ln4 - 1] != orig4.splitlines(keepends=True)[ln4 - 1], \
                "변이 ④ 가 아무것도 치환하지 못했다"
            p4.write_text("".join(L4), encoding="utf-8")
            measure(f"④ 축2b — 「{num4} 함정」을 「{no_trap} 함정」으로 "
                    f"(§{no_trap} 에 `#함정(` 없음)", "블록 종류 불일치 검출",
                    rule="R4b 블록 종류")
            p4.write_text(orig4, encoding="utf-8")
        else:
            # **생략은 통과가 아니다.** 이 분기가 `True` 를 기록하던 동안
            # 축 2b 의 정의역이 0 이 되는 회귀(§6.7 이 이름한 바로 그 부류)에서
            # 자기시험이 조용히 초록이 됐다 — 안 돈 시험을 `✓` 로 인쇄한 것이다.
            rows.append(("④ 축2b", "픽스처에 「N.M 함정」 인용 0건 — **이 변이는 "
                                   "돌지 않았다**. 축 2b 의 정의역이 비었다는 뜻이고 "
                                   "그것은 통과가 아니다", False))
            ok = False

        # ⑥ 축 1 — 좌표의 **파일명**을 없는 것으로 (대상 부재)
        p6 = base / src3
        orig6 = p6.read_text(encoding="utf-8")
        L6 = orig6.splitlines(keepends=True)
        L6[ln3 - 1] = L6[ln3 - 1].replace(Path(res3).name,
                                          "wt-selftest-nonexistent.typ", 1)
        p6.write_text("".join(L6), encoding="utf-8")
        measure(f"⑥ 축1 — 대상 파일명을 없는 이름으로 (대상 부재)",
                "MISSING-FILE 검출", key="ax1_missing",
                rule="R1 좌표 실재")
        p6.write_text(orig6, encoding="utf-8")

        # ── 축 0 변이 둘 — **오늘 가장 큰 축인데 음성 시험이 하나도 없었다** ──
        # 축 0 의 hard 보고를 통째로 지워도 두 게이트가 다 통과했다.
        a0_sites = d0["a0"]["sites"]
        assert a0_sites, "축 0 의 대조 자리가 픽스처에 없다 — 변이가 뜻을 갖지 못한다"
        s0 = a0_sites[0]
        rel0, ln0, lab0, num0, tgt0, needle0 = s0
        p7 = base / rel0
        orig7 = p7.read_text(encoding="utf-8")
        L7 = orig7.splitlines(keepends=True)
        bogus = num0.split(".")[0] + ".99"
        L7[ln0 - 1] = L7[ln0 - 1].replace(f"@{lab0} {num0}", f"@{lab0} {bogus}", 1)
        assert L7[ln0 - 1] != orig7.splitlines(keepends=True)[ln0 - 1], \
            "변이 ⑦ 이 아무것도 치환하지 못했다"
        p7.write_text("".join(L7), encoding="utf-8")
        measure(f"⑦ 축0 — `@{lab0} {num0}` 을 실재하지 않는 `{bogus}` 로",
                "절 실재 위반 검출")
        p7.write_text(orig7, encoding="utf-8")

        # ⑧ 축 0 — 실재하는 **엉뚱한 절**로. 재번호가 만드는 형태다.
        gb2 = Guide(base)
        sib = next((k for k in sorted(gb2.secmaps.get(tgt0, {}))
                    if k != num0 and k.startswith(num0.split(".")[0] + ".")
                    and needle0 not in gb2._bodies(tgt0).get(k, "")), None)
        assert sib, "변이 ⑧ 의 대체 절을 찾지 못했다"
        L8 = orig7.splitlines(keepends=True)
        L8[ln0 - 1] = L8[ln0 - 1].replace(f"@{lab0} {num0}", f"@{lab0} {sib}", 1)
        p7.write_text("".join(L8), encoding="utf-8")
        measure(f"⑧ 축0 — `@{lab0} {num0}` 을 실재하는 엉뚱한 절 `{sib}` 로 "
                f"(인용문은 그대로)", "WRONG-TARGET 검출")
        p7.write_text(orig7, encoding="utf-8")

        # ⑨ R5 — hard 구역에 **따옴표 없는** 절 인용 하나를 더한다.
        #    스칼라 상한 시절에는 이 변이가 「스캔 순서 앞 12건」을 인쇄했다.
        p9 = base / "rtl/formal/tla/Walk.tla"
        orig9 = p9.read_text(encoding="utf-8")
        sec9 = next(iter(sorted(gb2.secmaps.get(gb2.chap_files.get("1"), {}))))
        p9.write_text(orig9 + f"\n(* 자기시험 — §{sec9} 를 따옴표 없이 인용 *)\n",
                      encoding="utf-8")
        measure(f"⑨ R5 — `Walk.tla` 에 따옴표 없는 `§{sec9}` 인용 1건 추가",
                "미계수 상한 초과 검출 — **그 파일을 지목하는가**",
                key=None, rule="R5 축2 미계수", names="Walk.tla")
        p9.write_text(orig9, encoding="utf-8")

        # ⑨′ R5 의 **축 1 쪽**. 같은 규칙이 두 축에 따로 살아서 한쪽만 시험하면
        #     다른 쪽이 조용히 정의역 밖에 남는다 (실측으로 그 상태였다).
        tgt9 = str(gb2.chap_files["1"].relative_to(base))
        p9.write_text(orig9 + f"\n(* 자기시험 — {tgt9}:10 을 따옴표 없이 인용 *)\n",
                      encoding="utf-8")
        measure(f"⑨′ R5 — `Walk.tla` 에 따옴표 없는 좌표 `…01-isa-asm.typ:10` 추가",
                "미계수(축 1) 상한 초과 검출 — **그 파일을 지목하는가**",
                key=None, rule="R5 축1 미계수", names="Walk.tla")
        p9.write_text(orig9, encoding="utf-8")

        # ⑩′ R6 의 **축 1 쪽**. 좌표 옆에 따옴표를 달되 **대상에 축자로 없는**
        #     문면을 적는다. 이것이 축 1 에서 「대상 대조를 빠져나가는 길」이고,
        #     ⑩ 이 축 2 에서 막은 것과 같은 부류다.
        #     오늘 hard 구역 발신의 축 1 대조는 0건이라 기존 자리를 흐리는
        #     방식으로는 이 규칙을 시험할 수 없다 — 그래서 자리를 만든다.
        p9.write_text(orig9 + f"\n(* 자기시험 — {tgt9}:10 「이 문면은 정본 어디에도 "
                              f"축자로 존재하지 않는 자기시험 문장이다」 *)\n",
                      encoding="utf-8")
        measure("⑩′ R6 — `Walk.tla` 에 좌표 + **대상에 없는** 따옴표 1건 추가",
                "의역(축 1) 상한 초과 검출", key=None,
                rule="R6 축1 의역", names="Walk.tla")
        p9.write_text(orig9, encoding="utf-8")

        # ⑪ 덮임 하한 — curated 발신의 대조 가능 인용을 하나 **지운다**.
        #    (따옴표만 깨서 「안 잰다」로 떨어뜨린다 — 좌표는 그대로 둔다.)
        one = next((f for f, n in sorted(cal.ax1_cover_floor.items()) if n == 1),
                   None)
        site11 = next((s for s in d0["a1"]["ok"]
                       if s[2] == one and sender_zone(s[0]) != "volatile"), None)
        assert one and site11, "변이 ⑪ 의 대상(덮임 1 인 curated 인용)이 없다"
        p11 = base / site11[0]
        orig11 = p11.read_text(encoding="utf-8")
        L11 = orig11.splitlines(keepends=True)
        L11[site11[1] - 1] = L11[site11[1] - 1].replace("「", "〔", 1).replace("」", "〕", 1)
        p11.write_text("".join(L11), encoding="utf-8")
        measure(f"⑪ 덮임 하한 — `{Path(one).name}` 을 겨냥한 유일한 curated 인용의 "
                f"따옴표를 깬다", "덮임 1→0 검출", key=None, rule="덮임 하한(축 1",
                names=Path(one).name)
        p11.write_text(orig11, encoding="utf-8")

        # ⑤ **덮임 구멍의 실증** — 같은 변이를 덮임 0 인 장에 건다.
        #    이 시험은 「잡히면 성공」이 아니라 **잡히지 않는 것을 인쇄**한다.
        #    상한만 두면 「인용을 안 쓰면 통과」가 성립한다는 증거가 이것이다.
        hole = [f for f, floor in sorted(cal.ax1_cover_floor.items())
                if floor == 0 and d0["a1"]["cover"].get(f, 0) == 0]
        if hole:
            ph = base / hole[0]
            if ph.exists():
                orig5 = ph.read_text(encoding="utf-8")
                _insert_lines(ph, 100)
                a5 = _counts(base, cal)
                got = (a5["defects"] - b["defects"]) + (a5["nfails"] - b["nfails"])
                ph.write_text(orig5, encoding="utf-8")
                rows.append((f"⑤ 축1 — 덮임 0 인 장({Path(hole[0]).name}) 100행에 "
                             f"40줄 삽입",
                             f"검출 **{got}건**. 0 이면 그 장에 대한 「파손 0」은 "
                             f"**무증거**다 — ② 와의 대비가 덮임 하한의 근거",
                             True))

        # ⑬ **W6 그 자체** — 비-hard 발신이 정본 절을 정본 번호로 부르는 인용의
        #    대상이 재번호로 바뀌는 변이. 인용이 가리키는 절 **바로 앞**에 절을
        #    하나 삽입하면 그 번호가 빈 절로 옮겨 간다. 2026-08-30 이전에는 이
        #    부류가 통째로 대조 대상 밖이라 이 변이가 아무것도 움직이지 않았다.
        #    **자기 번호 체계를 가진 발신을 우선 고른다** — 그 자리가 W6 그
        #    자체이고, `selfnum` 예외가 죽으면 이 변이가 곧바로 뜻을 잃는다.
        outs = d0["a2"]["ok_out_sites"]
        w6 = [s for s in outs if s[4]]
        rows.append((f"⑬′ `selfnum` 예외의 생존 — 자기 번호 체계를 가진 문서의 "
                     f"정본 인용 대조 {len(w6)}건",
                     "0 이면 예외가 죽었고 **W6 이 밟은 부류가 통째로 정의역 "
                     "밖**이다 (그 상태가 2026-08-30 이전이었다)", bool(w6)))
        if not w6:
            ok = False
        s13 = next(iter(w6 or outs), None)
        assert s13, "변이 ⑬ 의 대상(비-hard 발신 축 2 대조)이 픽스처에 없다"
        rel13, ln13, num13, tgt13, _sn13 = s13
        p13 = base / tgt13
        orig13 = p13.read_text(encoding="utf-8")
        sm13 = Guide(base).secmaps[p13]
        at13 = sm13[num13][0] - 1
        p13.write_text("".join(orig13.splitlines(keepends=True)[:at13]
                               + ["== 자기시험이 삽입한 절\n", "\n"]
                               + orig13.splitlines(keepends=True)[at13:]),
                       encoding="utf-8")
        measure(f"⑬ W6 부류 — `{rel13}` 의 `§{num13}` 이 가리키는 절 앞에 "
                f"절 하나 삽입 (번호가 빈 절로 옮겨 간다)",
                "WRONG-TARGET 검출 (비-hard 발신)",
                rule="R4′ 축2 대상 대조")
        p13.write_text(orig13, encoding="utf-8")

        # ⑫ **W6 이 실제로 밟은 자리의 재현** — 이 검사가 태어난 동기다.
        #    on-wire 절 삽입으로 §3.11 이 형식 속성에서 원격 표면으로 바뀌었을 때
        #    그 부류 6건이 「파손 0」인 채 틀려 있었다. 그 자리를 그대로 재현한다.
        #    이 시험도 「잡히면 성공」이 아니라 **잡히지 않는 것을 인쇄**한다 —
        #    오늘 저장소의 `§3.11` 인용 2건은 전부 `.claude-memos/`(정의역 밖)에
        #    살고, 3장 뒤쪽을 겨냥한 줄 좌표 인용은 0건이다.
        ch3 = gb2.chap_files.get("3")
        if ch3 is not None:
            p12 = base / ch3.relative_to(base)
            orig12 = p12.read_text(encoding="utf-8")
            L12 = orig12.splitlines(keepends=True)
            tail_at = max(i for i, l in enumerate(L12) if l.startswith("== "))
            p12.write_text("".join(L12[:tail_at]
                                   + ["== 자기시험이 삽입한 절\n", "\n"]
                                   + L12[tail_at:]), encoding="utf-8")
            a12 = _counts(base, cal)
            g12 = (a12["defects"] - b["defects"]) + (a12["nfails"] - b["nfails"])
            p12.write_text(orig12, encoding="utf-8")
            rows.append((f"⑫ W6 재현 — 3장 마지막 절 앞에 절 하나 삽입 "
                         f"(§3.N 이하가 전부 한 칸씩 밀린다)",
                         f"검출 **{g12}건**. 0 이면 W6 이 밟은 그 자리는 "
                         f"**오늘도 무증거**다 — 그 부류의 인용이 정의역 밖"
                         f"(`.claude-memos/`)에만 살기 때문이고, 축 2 덮임 표가 "
                         f"그 사실을 장별로 인쇄한다", True))

    print("\n  변이 시험")
    for label, note, caught in rows:
        print(f"  {'✓' if caught else '✗'} {label}\n        {note}")
    print("\n음성 시험 " + ("통과" if ok else "**불통과** — 잡지 못한 변이가 있다"))
    return 0 if ok else 1


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--drift", action="store_true")
    ap.add_argument("--root", default=str(REPO))
    args = ap.parse_args()
    if args.self_test:
        return self_test()
    if args.drift:
        return drift(Path(args.root))
    rc, _ = run(Path(args.root), rat=DEFAULT_RATCHET)
    return rc


if __name__ == "__main__":
    sys.exit(main())
