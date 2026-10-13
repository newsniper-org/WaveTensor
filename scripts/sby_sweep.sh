#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
#
# 후-formal 전수 스윕 — 컨테이너 *안*에서 실행된다.
#
# ## 왜 스크립트로 뺐는가
#
# 셀 수 세기의 정규식이 `cell $cover` 를 매치해야 하는데, 그 `$` 가
# Makefile → 호스트 셸 → podman 인자 → 컨테이너 셸 네 층을 지나며 매번
# 다르게 해석된다. 2026-08-25 에 이 이스케이프를 **두 번 틀렸고 두 번 다
# 전 태스크가 HOLLOW 로 오탐**됐다:
#   · 첫째 — 산출물이 컨테이너 /tmp 에 있는데 세는 쪽이 호스트였다 (16 중 14)
#   · 둘째 — 큰따옴표 안의 `\$` 가 셸에 먹혀 정규식에 줄 끝 앵커만 남았다 (전건)
#
# 두 번 다 게이트가 「측정하지 못했다」를 「측정했더니 0이었다」로 보고했다.
# 그 둘을 구분하지 못하는 것이 결함의 알맹이다 — 전자는 게이트를 고쳐야 하고
# 후자는 대상을 고쳐야 하는데, 같은 낱말로 보고하면 엉뚱한 것을 고치러 간다.
# 그래서 이 스크립트는 **셀을 셀 수 없는 경우를 HOLLOW 와 다른 낱말로 낸다.**
#
# 인용 층을 하나로 줄이는 것이 이 파일의 존재 이유다 — 호출자는
# `sh scripts/sby_sweep.sh` 만 하고 셸 정규식은 여기 한 곳에만 산다.
#
# ## assert 계수는 이제 여기서 세지 않는다 (2026-08-27 — 4차 파도)
#
# `lint_tautology.py --count` 가 센다. 그쪽은 상수 접힘을 재려고 어차피
# `cell $assert` 를 전수로 훑어야 하고, **간접 상수 결속을 따라가므로 grep 두
# 줄로 끝나지 않는다** (실측: 이 저장소의 모델에 모듈 수준 상수 결속 434건).
# 같은 셀을 두 파서가 세면 「같은 사실에 두 기계가 다른 수를 인쇄한다」가 되고,
# 그것이 3차가 닫은 형태다. 그래서 assert 계수와 상수 계수는 **한 호출에서
# 함께** 받는다. 부수 이득: 그 파서는 python 이라 셸 인용 층이 아예 없다.
#
# `--count` 를 부르지 못하면 `-1` 을 적는다 — **미계수**다. 0 을 적으면
# 「접힘이 없다」로 읽히고, 그것이 이 파일이 존재하는 이유가 된 오탐의 형태다.
#
# cover 셀은 그쪽이 세지 않으므로 여기 grep 이 그대로 남는다.
#
# ## 증거를 남긴다 (2026-08-26 — 후-formal 2차 파도)
#
# notes-vacuity-detection.md 의 세 층 표에서 이 스크립트는 **실행 층**이다:
# 「실제로 재고 증거를 남긴다」. 지금까지 남긴 것은 표준출력 한 줄뿐이라
# 정적 층(`lint_postformal`)이 읽을 것이 없었고, 그래서 lint 는 앵커의
# 실재성만 재면서 그것을 「덮임」으로 계수했다.
#
# 이제 태스크마다 `<태스크>.evidence.json` 을 쓴다:
#   판정 · assert/cover 셀 수 · cover 증인 도달/미도달 · `[files]` 각 입력의
#   sha256 · 그 .sby 자신의 sha256 · 앵커 목록 · 도구 판 · 시각.
#
# **셈은 여기서, 서식과 해시는 lint_postformal 에서.** 증거를 쓰는 코드와
# 읽는 코드가 같은 파일에 살아야 두 층이 서로 다른 것을 보는 일이 없다 —
# 위 두 오탐의 뿌리가 정확히 「판정 로직이 여러 층에 흩어져 각 층이 조금씩
# 다르게 해석했다」였다. `[files]` 파서도 같은 이유로 lint 쪽 한 벌만 쓴다.
#
# ## 증인 0 은 여기서 판정하지 않는다 (2026-08-26 — 3차 파도의 판단)
#
# 「cover 증인이 0 인 태스크는 통과가 아니다」가 3차 파도에 섰다 (공허의 넷째
# 결 — `lint_postformal._NO_WITNESS` 를 보라). 그 판정을 **이 스크립트에
# 새 낱말로 넣지 않았다.** 근거:
#
#   · 이 스크립트의 낱말(PASS·FAIL·HOLLOW·UNCOUNTED)은 「이번 실행에서
#     관측한 것」이고, 증인 0 은 관측이 아니라 **규율의 적용**이다. 예외
#     허용목록과 래칫이 따라붙으므로 판정 상태가 lint 쪽에만 있다.
#   · HOLLOW 를 여기와 lint 양쪽에 둔 것은 이미 이중이고, 그때는 실행 층이
#     즉시 크게 실패해야 한다는 이유가 있었다. 증인 0 은 그렇지 않다 —
#     `make rtl-postformal` 이 스윕 직후 `lint_postformal --require-fresh` 를
#     부르므로 **같은 실행 안에서 잡힌다.** 낱말을 늘리면 판정 로직이 다시
#     두 층에 흩어지고, 그것이 2026-08-25 두 오탐의 뿌리였다.
#
# 이 스크립트가 하는 일은 그대로다: cover 셀 수와 도달/미도달을 **세어서
# 증거에 적는다.** 세는 것과 판정하는 것을 가르는 것이 이 파일의 규율이다.
#
# ## 4차 파도가 더 세는 것 (2026-08-27)
#
# 같은 규율 아래 넷을 더 센다. 전부 **세기**이지 판정이 아니다:
#
#   · **태스크별** assert/cover 셀 수 + 모드. 최댓값 한 쌍으로는 「어느 태스크가
#     재고 있는가」에 답하지 못한다 — 실측으로 `contracts` 는 bmc·prove 가
#     assert 50 이고 cover 는 assert 0/cover 42 다. prove 만 부착이 깨져도
#     최댓값 50 이 남아 HOLLOW 가 안 뜬다. 모드는 `design_prep.ys` 의
#     `chformal` 줄에서 읽는다 (`-assert -remove` ⇒ cover 모드) — 태스크 *이름*
#     에서 추측하지 않는다. `deep` 은 이름이 cover 가 아니지만 assert 모드다.
#   · **상수 접힘** const_a/const_en0 — `lint_tautology --count` 에서.
#   · **증인 이름** — 계수 위조를 이름 위조로 승격한다. 계수는 이름에서
#     유도한다(따로 세지 않는다). `step N` 은 **적지 않는다**: 솔버 선택에
#     좌우되어 재실행마다 흔들리고, 그러면 diff 가 매번 전면 변경이 되어
#     아무도 안 읽는다 — 증거를 커밋한 이유가 무효화된다.
#   · **yosys 배너** — 셀을 센 주체의 판. 절대 기준과 대조할 상대는 없고
#     (yosys 는 Arch 스냅샷에서 오고 ARG 로 핀되지 않는다) 증거끼리의 일치만
#     잰다. 좁혀 재기가 규율이고 컨테이너는 재빌드되므로 이 표류는 실제로
#     일어난다.
#
# ## 엔진 처분 파도가 더 세는 것 (2026-08-28)
#
#   · **선-flatten 감사 모델의 const_a** (`design_preflatten.il` 이 있는
#     태스크만 — 7째 칸 `const_a_authored`). 저작-항진과 병합-상수를 가르는
#     유일한 측정이고, 갈라치기·판정은 lint 몫이다 (`lint_tautology` 의
#     `_CONST_BY_MERGE` 머리 주석이 정본).
#
# ## btor 증인 갈래 (2026-08-29 — cover 엔진 증강 파도)
#
# sby 의 btor 엔진(btormc)은 cover PASS 요약에 「cover trace: …vcd」만 적고
# smtbmc 의 「reached cover statement <이름>」 줄을 내지 않는다 — 실측
# (walk_decode: PASS 요약이 궤적 22줄뿐, 이름 0). FAIL 요약은 더 나쁘다:
# btor 엔진은 속성별 status 를 설계 DB 에 갱신하지 않아 도달했던 증인까지
# **전부 unreached 절에 인쇄된다** — 실측 기록. 그러므로 btor 태스크의 요약
# 파일에서 이름 줄을 읽으면 PASS 는 「증인 0」 오탐, FAIL 은 「전부 미도달」
# 위증이 된다. 도달 귀속은 셋에서 유도한다:
#
#   · **이름** — model/design_btor.btor 의 bad 심볼. 파일 등장 순서가 곧
#     btormc 의 속성 인덱스 0.. 이다 (실측: props.w1…w22, 소스 좌표 동반).
#   · **도달** — engine_N/logfile.txt 의 「[btor>mc] bad state property <i>
#     reachable at bound k = <k> SATISFIABLE」 줄의 인덱스. btormc 는 도달한
#     속성을 이후 bound 에서 skip 하므로 인덱스는 원래 중복되지 않지만
#     dedup 을 겸한다. 어느 engine_N 인지는 요약의 「engine_N (btor …)
#     returned …」 줄에서 읽는다 — 태스크 이름으로 추측하지 않는다.
#   · **미도달** — (전 bad 심볼) − (도달). FAIL 요약의 unreached 절은 위
#     관측대로 위증이라 읽지 않는다.
#
# PASS 요약에서는 「cover trace:」 줄 수와 로그 도달 수를 교차 대조한다 —
# sby 는 도달 증인마다 궤적 하나를 재생하므로(btorsim) 어긋나면 귀속을 믿을
# 수 없다. 귀속이 성립하지 않는 경우(btor 모델·엔진 로그 부재 · 이름 없는
# bad 심볼 · 교차 불일치)는 **도달 0 이 아니라 UNCOUNTED** 다 — 「세지
# 못했다」와 「0 이었다」를 가르는 이 파일의 규율 그대로다. smtbmc·abc
# 요약은 엔진 판별 매치가 비어 종전 갈래를 바이트 그대로 지난다.
#
# ## 실패해도 증거를 남긴다
#
# FAIL·HOLLOW·UNCOUNTED 도 그대로 기록한다. 「실패를 기록하지 않는 게이트」는
# 다음 사람에게 미측정과 구별되지 않는 상태를 물려준다. lint 는 그 세 판정을
# **하드 실패**로 읽는다 — 증거가 스스로 결함을 보고하는데 통과시킬 이유가 없다.
#
# 사용: 컨테이너 안에서 저장소 루트를 cwd 로 두고 실행.
#   sh scripts/sby_sweep.sh                      전수
#   sh scripts/sby_sweep.sh rtl/formal/sby/A/b.sby …   좁혀서 (scripts/sby_impact.py
#                                                가 지목한 것만 다시 재고 증거 갱신)
#   SBY_OUT  산출물 디렉터리 (기본 /sbyout)
#   LOG      결과 로그 (기본 표준출력)
#
# ## 네 갈래의 음성 시험 — 솔버 없이
#
# PASS·HOLLOW·FAIL·UNCOUNTED 네 갈래가 실제로 그 낱말을 내는지는 스텁 `sby`
# 하나로 확인한다 (2026-08-26 실측: 네 갈래 전부 그 낱말을 냈고, lint 가
# 뒤의 셋을 각각 다른 문면으로 하드 실패시켰다):
#
#   PATH=<스텁 디렉터리>:$PATH SBY_OUT=/tmp/stub/out LOG=/tmp/stub/log \
#     sh scripts/sby_sweep.sh rtl/formal/sby/<Dir>/<name>.sby
#
# 스텁은 `--prefix` 를 받아 `<prefix>_<task>/{status,model/design_prep.il,
# model/design_prep.ys}` 와 `<prefix>_cover/PASS` 를 갈래별로 만들고 종료
# 코드만 달리한다. 「셀이 0」과 「모델 파일이 없다」를 갈라 만드는 것이 시험의
# 요점이고, 4차 파도는 거기에 세 갈래를 더한다:
#   · `design_prep.ys` 를 빼면 모드가 UNKNOWN 이 되고 lint 가 그렇게 인쇄한다
#     (「모드를 읽지 못했다」 — 「cover 모드였다」가 아니다)
#   · `lint_tautology.py` 를 PATH 밖에 두면 계수가 -1 이 되고 스윕이
#     **UNCOUNTED** 를 낸다. 0 이 아니다 — 「접힘이 없다」와 「세는 쪽이
#     죽었다」를 가르는 것이 이 파일의 규율 그 자체다
#   · 태스크 하나의 `status` 만 빼면 tasks 문자열이 조용히 짧아진다. 스윕은
#     그것을 모르지만 lint 가 `.sby` 의 `[tasks]` 로 재유도해 잡는다

set -u
SBY_OUT="${SBY_OUT:-/sbyout}"
LOG="${LOG:-/dev/stdout}"
LINT="scripts/lint_postformal.py"
TAUT="scripts/lint_tautology.py"

# ── yosys-abc 호환 셔김 (2026-08-28, walk_decode 엔진 처분 파도) ──────────
#
# sby 의 abc 엔진과 yosys-smtbmc 의 abc 백엔드는 실행 파일 이름을
# `yosys-abc` 로 하드코딩한다 (sby_core.py: os.getenv("ABC", …"yosys-abc") ·
# smtio.py: popen_vargs=['yosys-abc', …]). 이 컨테이너의 yosys 는 Arch
# 패키지라 yosys-abc 가 없고 독립 /usr/sbin/abc(Berkeley ABC 1.01)만 있다 —
# 실측. 이름만 잇는 것으로 끝나지 않는 비호환이 하나 더 있다: sby 는
# yosysHQ abc 전용 스위치를 전제로 `pdr` 에 `-v -l` 를 부가하는데
# (sby_engine_abc.py 실측), Berkeley pdr 에는 `-l` 이 없어 사용법만 인쇄하고
# UNKNOWN 이 된다 — 실측 (같은 모델·같은 pdr 가 `-l` 만 빼면 537초에
# Property proved). 그래서 셔김은 두 가지만 한다: 이름을 잇고, 인자 속
# `pdr -v -l` 을 `pdr -v` 로 좁혀 바꾼다 — 그 밖의 인자는 그대로 지난다.
#
# 진짜 yosys-abc 가 있으면 셔김을 만들지 않는다. 둘 다 없어도 만들지
# 않는다 — abc 엔진 태스크는 그때 「Engine terminated」(ERROR 갈래)로 죽고,
# 그것이 「엔진이 없는데 있다고 적는」 것보다 낫다 (없는 것을 있다고
# 보고하는 쪽이 늘 더 나쁜 오탐이다).
if ! command -v yosys-abc >/dev/null 2>&1 && command -v abc >/dev/null 2>&1; then
  _abcshim=$(mktemp -d)
  _abcreal=$(command -v abc)
  {
    printf '#!/bin/sh\n'
    printf 'n=$#; i=0\n'
    printf 'while [ $i -lt $n ]; do\n'
    printf '  a=$1; shift\n'
    printf '  case "$a" in *"pdr -v -l"*) a=$(printf "%%s" "$a" | sed "s/pdr -v -l/pdr -v/g");; esac\n'
    printf '  set -- "$@" "$a"\n'
    printf '  i=$((i+1))\n'
    printf 'done\n'
    printf 'exec %s "$@"\n' "$_abcreal"
  } > "$_abcshim/yosys-abc"
  chmod +x "$_abcshim/yosys-abc"
  PATH="$_abcshim:$PATH"; export PATH
fi

mkdir -p "$SBY_OUT"
fail=0; hollow=0; broken=0; total=0
TOOL=$(sby --version 2>/dev/null | head -1)

# 증거 기록 — 서식·해시·[files] 파싱은 전부 lint_postformal 이 한다.
#
# 태스크별 계수와 증인 이름은 **인자 하나씩**으로 넘긴다. 반복 인자로 하면
# 셸에 배열이 없어 `eval` 이 들어오고, 그것이 정확히 이 파일이 없애러 온
# 인용 층이다. 공백 구분으로 충분하다 — 태스크 이름에도 증인 이름에도
# 공백이 없다 (증인 이름은 SV 식별자 경로다).
emit() {
  python3 "$LINT" --emit-evidence "$1" \
    --verdict "$2" --tasks "$3" --task-cells "$4" \
    --cover-reached-names "$5" --cover-unreached-names "$6" \
    --tool "$TOOL" --yosys "$7" >> "$LOG" 2>&1
}

[ "$#" -gt 0 ] || set -- rtl/formal/sby/*/*.sby

for f in "$@"; do
  total=$((total + 1))
  name=$(basename "$f" .sby)
  dir=$(basename "$(dirname "$f")")
  prefix="$SBY_OUT/$dir-$name"

  rm -rf "$prefix" "$prefix"_*

  # sby 의 종료 코드를 *갈라서* 받는다.
  #
  # 1 = 반례(대상의 결함) / 16 = 엔진이 상태 없이 죽음(게이트·환경의 결함).
  # 둘을 FAIL 한 낱말로 접으면 lint 가 「실패한 증명」으로 인쇄하고 독자는
  # 설계를 고치러 간다 — 2026-08-26 실측: z3 자원 경합으로 basecase 가
  # 「Unexpected EOF response from solver」로 죽었고 단독 재실행은 PASS 였다.
  # 「측정하지 못했다」와 「측정했더니 틀렸다」는 고칠 대상이 다르다.
  sby -f --prefix "$prefix" "$f" > "/tmp/log-$dir-$name" 2>&1
  sbyrc=$?
  if [ "$sbyrc" -eq 0 ]; then
    rc=PASS
  elif [ "$sbyrc" -ge 16 ]; then
    rc=ERROR
  else
    rc=FAIL
  fi

  # 태스크별 판정 — sby 는 태스크마다 status 파일을 남긴다.
  tasks=""
  for s in "$prefix"/status "$prefix"_*/status; do
    [ -f "$s" ] || continue
    t=$(basename "$(dirname "$s")")
    tasks="$tasks${tasks:+ }${t#"$dir-$name"_}:$(head -1 "$s" | cut -d' ' -f1)"
  done

  # ── 태스크별 계수 ────────────────────────────────────────────────────
  #
  # 태스크마다 model/ 이 따로 생긴다. 4차 파도 전까지는 **최댓값 한 쌍**만
  # 남겼고, 그것이 태스크 단위의 공허 1형(하네스 미부착)을 통째로 눈감았다.
  # 이제 태스크마다 한 줄씩 적고 최댓값은 lint 가 그 줄들에서 유도한다 —
  # 두 수가 각자 저장되면 어느 쪽이 참인지 물어야 하는 상태가 된다.
  #
  # `cell $cover` 의 작은따옴표 안 `$` 는 리터럴이다. assert 와 상수 계수는
  # lint_tautology 가 세고(위 머리 주석), 못 부르면 -1 = **미계수**다.
  tcells=""; acell=0; ccell=0; nmodel=0; nmiss=0
  for m in "$prefix"*/model/design_prep.il; do
    [ -f "$m" ] || continue
    nmodel=$((nmodel + 1))
    mdir=$(dirname "$m")
    t=$(basename "$(dirname "$mdir")")
    t=${t#"$dir-$name"}; t=${t#_}; [ -n "$t" ] || t=default

    # 모드는 합성 레시피에서 **읽는다** — 태스크 이름에서 추측하지 않는다.
    # `deep` 은 이름이 cover 가 아니지만 assert 모드다.
    mode=UNKNOWN
    if [ -f "$mdir/design_prep.ys" ]; then
      if grep -q 'chformal .*-assert -remove' "$mdir/design_prep.ys"; then
        mode=cover
      elif grep -q 'chformal .*-cover -remove' "$mdir/design_prep.ys"; then
        mode=assert
      fi
    fi

    c=$(grep -c 'cell \$cover' "$m")
    trip=$(python3 "$TAUT" --count "$m" 2>/dev/null | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d["assert_cells"],d["const_a"],d["const_en0"])' 2>/dev/null)
    [ -n "$trip" ] || trip="-1 -1 -1"
    a=${trip%% *}; rest=${trip#* }; ca=${rest%% *}; ce=${rest##* }
    [ "$a" -lt 0 ] && nmiss=$((nmiss + 1))

    # 선-flatten 감사 모델 — .sby 의 [script] 가 flatten *직전에*
    # `write_rtlil ../model/design_preflatten.il` 을 두는 태스크만 있다
    # (첫 실물: DecodeWalk/walk_decode — opt_merge 가 참조·RTL 의 동형 CRC
    # 콘을 물리 공유해 등가 단언이 상수로 접히는 태스크). 여기서 센 const_a
    # 가 「저작-항진」이고, design_prep.il 계수와의 차가 「병합-상수」다 —
    # 그 갈라치기는 lint 몫이고 여기는 **센다**. 파일이 있는데 세지 못하면
    # 그것은 0 이 아니라 미계수다 (이 파일의 규율 그대로).
    aa=""
    if [ -f "$mdir/design_preflatten.il" ]; then
      aa=$(python3 "$TAUT" --count "$mdir/design_preflatten.il" 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["const_a"])' 2>/dev/null)
      if [ -z "$aa" ]; then aa=-1; nmiss=$((nmiss + 1)); fi
    fi
    tcells="$tcells${tcells:+ }$t:$mode:$a:$c:$ca:$ce${aa:+:$aa}"
    [ "$a" -gt "$acell" ] && acell=$a
    [ "$c" -gt "$ccell" ] && ccell=$c
  done

  # 셀을 센 주체의 판. 첫 모델 하나면 된다 — 한 스윕 안에서는 같은 yosys 다.
  yo=""
  for m in "$prefix"*/model/design_prep.il; do
    [ -f "$m" ] || continue
    yo=$(sed -n '1s/^# Generated by Yosys \([^ ]*\) (git sha1 \([^,)]*\).*/Yosys \1 (git sha1 \2)/p' "$m")
    [ -n "$yo" ] || yo=$(head -1 "$m")
    break
  done

  # cover 증인 — sby 의 완전 요약은 로그가 아니라 PASS/FAIL 파일에 있다
  # (로그는 「and N further traces」로 잘라 인쇄한다). 「unreached」가
  # 「reached」의 부분 문자열이므로 앞의 공백을 요구해 갈라 센다.
  #
  # 매치 없는 글로브를 `cat` 에 넘기지 않고 파일마다 도는 이유: 셸에 따라
  # 매치 없는 글로브가 리터럴로 남기도(POSIX) 명령 전체를 실패시키기도 한다.
  # 후자면 도달 수가 조용히 0 이 되고, 그것은 **또 하나의 「측정하지 못했다를
  # 0이었다로 보고」**다. 셸 방언에 판정을 맡기지 않는다.
  #
  # **이름을 세고 계수는 이름에서 유도한다.** 따로 세면 두 수가 갈릴 자리가
  # 생기고, 그 자리는 이 저장소가 이미 두 번 밟았다.
  #
  # btor 엔진 태스크는 요약에 이름이 없다 — 갈래 전체가 머리 주석
  # 「btor 증인 갈래」에 있다. 판별은 요약 자신의 「engine_N (btor …)
  # returned …」 줄이다: smtbmc·abc 요약은 매치가 비어 종전 갈래를
  # 바이트 그대로 지난다.
  rnames=""; unames=""; wmiss=0
  for s in "$prefix"*/PASS "$prefix"*/FAIL; do
    [ -f "$s" ] || continue
    beng=$(awk '$1 ~ /^engine_[0-9]+$/ && index($2, "(btor") == 1 { print $1; exit }' "$s")
    if [ -z "$beng" ]; then
      rnames="$rnames $(awk '/^ *reached cover statement /{print $4}' "$s")"
      unames="$unames $(awk '/unreached cover statement /{print $4}' "$s")"
      continue
    fi
    # ── btor 갈래 — 이름은 bad 심볼, 도달은 엔진 로그, 미도달은 차집합 ──
    sdir=$(dirname "$s")
    # btor 갈래는 cover 태스크에서만 — bmc · prove 태스크의 bad 심볼은 단언이지 증인이 아니다.
    # (W3 2026-10-13 실측: XlateDoor/door.sby 의 bmc 가 btor btormc 라 단언 넷이 「미도달 증인」
    #  으로 실려 reached+unreached ≠ cover 셀 — lint_postformal 항등 · lint_witness_map 이 운다.)
    grep -qx 'mode cover' "$sdir/config.sby" 2>/dev/null || continue
    bt="$sdir/model/design_btor.btor"
    el="$sdir/$beng/logfile.txt"
    if [ ! -f "$bt" ] || [ ! -f "$el" ]; then
      # 귀속의 재료가 없다 — 「도달 0」이 아니라 「귀속하지 못했다」다.
      wmiss=$((wmiss + 1))
      continue
    fi
    if [ "$(awk '$2 == "bad" && (NF < 4 || $4 == ";") { n++ } END { print n + 0 }' "$bt")" -gt 0 ]; then
      # 이름 없는 bad 심볼 — 인덱스→이름 사상이 성립하지 않는다.
      wmiss=$((wmiss + 1))
      continue
    fi
    # bad 심볼을 파일 등장 순(= btormc 속성 인덱스)으로 적재하고, 로그의
    # 「reachable … SATISFIABLE」 인덱스를 이름으로 사상한다. UNSATISFIABLE
    # 은 $NF 전장 비교라 갈라진다 (「reached/unreached」 부분 문자열 함정과
    # 같은 결 — 접미 매치가 아니라 필드 등가로 센다).
    br=$(awk '
      NR == FNR { if ($2 == "bad") name[n++] = $4; next }
      $1 == "[btor>mc]" && $2 == "bad" && $3 == "state" && $4 == "property" &&
        $6 == "reachable" && $NF == "SATISFIABLE" && !($5 in hit) && $5 + 0 < n {
        hit[$5] = 1; print name[$5]
      }' "$bt" "$el")
    # `i` 명시 초기화 — 미초기화 awk 변수는 `in` 의 첨자로 "" 이지 "0" 이
    # 아니라서, 첫 bad(인덱스 0)가 hit 대조를 그냥 지나 미도달로 인쇄된다
    # (실장 중 실물 로그 건식 대조에서 실제로 밟았다).
    bu=$(awk '
      BEGIN { i = 0 }
      NR == FNR {
        if ($1 == "[btor>mc]" && $2 == "bad" && $3 == "state" && $4 == "property" &&
            $6 == "reachable" && $NF == "SATISFIABLE") hit[$5] = 1
        next
      }
      $2 == "bad" { if (!(i in hit)) print $4; i++ }' "$el" "$bt")
    case "$s" in */PASS)
      # PASS 는 도달 증인마다 궤적 하나를 재생한다 — 로그 귀속과 「cover
      # trace:」 줄 수를 교차 대조한다. 어긋난 귀속을 싣는 것보다 UNCOUNTED
      # 가 낫다. (FAIL 은 여기서 가르지 않는다 — 판정 사다리에서 FAIL 이
      # 먼저 서고, 로그 유도 이름은 그 증거에 그대로 실린다.)
      if [ "$(echo $br | wc -w)" -ne "$(grep -c '^cover trace: ' "$s")" ]; then
        wmiss=$((wmiss + 1))
        continue
      fi
    esac
    rnames="$rnames $br"
    unames="$unames $bu"
  done
  reached=$(echo $rnames | wc -w)
  unreach=$(echo $unames | wc -w)

  if [ "$rc" = ERROR ]; then
    echo "$dir/$name ERROR (엔진이 상태 없이 죽었다 rc=$sbyrc — 게이트·환경 결함이지 대상 결함이 아니다. 단독 재실행: sh scripts/sby_sweep.sh $f)" >> "$LOG"
    broken=$((broken + 1))
    emit "$f" ERROR "$tasks" "$tcells" "$rnames" "$unames" "$yo"
  elif [ "$rc" = FAIL ]; then
    echo "$dir/$name FAIL (로그: /tmp/log-$dir-$name)" >> "$LOG"
    fail=$((fail + 1))
    emit "$f" FAIL "$tasks" "$tcells" "$rnames" "$unames" "$yo"
  elif [ "$nmodel" -eq 0 ]; then
    # 모델 파일 자체가 없다 — 셀이 0 인 것이 아니라 *세지 못한* 것이다.
    echo "$dir/$name UNCOUNTED (design_prep.il 없음 — 게이트 결함이지 대상 결함이 아니다)" >> "$LOG"
    broken=$((broken + 1))
    emit "$f" UNCOUNTED "$tasks" "$tcells" "$rnames" "$unames" "$yo"
  elif [ "$nmiss" -gt 0 ]; then
    # 모델은 있는데 세는 쪽을 부르지 못했다 — 같은 부류의 게이트 결함이다.
    echo "$dir/$name UNCOUNTED (모델 $nmiss개를 $TAUT --count 로 세지 못했다 — 「접힘이 없다」가 아니라 「세는 쪽이 죽었다」다)" >> "$LOG"
    broken=$((broken + 1))
    emit "$f" UNCOUNTED "$tasks" "$tcells" "$rnames" "$unames" "$yo"
  elif [ "$wmiss" -gt 0 ]; then
    # btor 증인의 귀속이 성립하지 않았다 — 「도달 0」이 아니라 「귀속하지
    # 못했다」다. bad 심볼·엔진 로그·궤적 수가 맞물려야 이름이 선다
    # (머리 주석 「btor 증인 갈래」).
    echo "$dir/$name UNCOUNTED (btor 요약 $wmiss건의 증인 귀속 실패 — 「도달 0」이 아니라 「귀속하지 못했다」다)" >> "$LOG"
    broken=$((broken + 1))
    emit "$f" UNCOUNTED "$tasks" "$tcells" "$rnames" "$unames" "$yo"
  elif [ $((acell + ccell)) -eq 0 ]; then
    echo "$dir/$name HOLLOW (단언 0개 — 통과가 아무것도 보증하지 않는다)" >> "$LOG"
    hollow=$((hollow + 1))
    emit "$f" HOLLOW "$tasks" "$tcells" "$rnames" "$unames" "$yo"
  else
    echo "$dir/$name PASS (태스크 [$tcells] · assert≤$acell · cover≤$ccell · 증인 $reached 도달/$unreach 미도달 · $yo)" >> "$LOG"
    emit "$f" PASS "$tasks" "$tcells" "$rnames" "$unames" "$yo"
  fi
done

echo "SWEEP-DONE total=$total fail=$fail hollow=$hollow uncounted=$broken" >> "$LOG"
[ $((fail + hollow + broken)) -eq 0 ]
