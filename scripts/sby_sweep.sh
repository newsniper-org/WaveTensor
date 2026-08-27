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

    tcells="$tcells${tcells:+ }$t:$mode:$a:$c:$ca:$ce"
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
  rnames=""; unames=""
  for s in "$prefix"*/PASS "$prefix"*/FAIL; do
    [ -f "$s" ] || continue
    rnames="$rnames $(awk '/^ *reached cover statement /{print $4}' "$s")"
    unames="$unames $(awk '/unreached cover statement /{print $4}' "$s")"
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
