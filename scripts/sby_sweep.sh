#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
#
# 후-formal 전수 스윕 — 컨테이너 *안*에서 실행된다.
#
# ## 왜 스크립트로 뺐는가
#
# 셀 수 세기의 정규식이 `cell $assert` 를 매치해야 하는데, 그 `$` 가
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
# `sh scripts/sby_sweep.sh` 만 하고 정규식은 여기 한 곳에만 산다.
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
# 스텁은 `--prefix` 를 받아 `<prefix>_<task>/{status,model/design_prep.il}`
# 과 `<prefix>_cover/PASS` 를 갈래별로 만들고 종료 코드만 달리한다.
# 「셀이 0」과 「모델 파일이 없다」를 갈라 만드는 것이 시험의 요점이다.

set -u
SBY_OUT="${SBY_OUT:-/sbyout}"
LOG="${LOG:-/dev/stdout}"
LINT="scripts/lint_postformal.py"

mkdir -p "$SBY_OUT"
fail=0; hollow=0; broken=0; total=0
TOOL=$(sby --version 2>/dev/null | head -1)

# 증거 기록 — 서식·해시·[files] 파싱은 전부 lint_postformal 이 한다.
emit() {
  python3 "$LINT" --emit-evidence "$1" \
    --verdict "$2" --tasks "$3" \
    --assert-cells "$4" --cover-cells "$5" \
    --cover-reached "$6" --cover-unreached "$7" \
    --tool "$TOOL" >> "$LOG" 2>&1
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

  # 합성 모델에서 assert/cover 셀을 센다. 작은따옴표 안이라 `$` 는 리터럴 —
  # 이 두 줄이 이 파일의 전부이고, 여기 말고 다른 층에 정규식을 두지 않는다.
  #
  # 태스크마다 model/ 이 따로 생기므로 **합이 아니라 최댓값**을 쓴다. 합은
  # 같은 셀을 태스크 수만큼 겹쳐 세어 「몇 개를 재는가」라는 물음에 답하지
  # 못한다. 공허 판정(0 인가)에는 둘 다 같지만 증거로는 최댓값이 옳다.
  acell=0; ccell=0; nmodel=0
  for m in "$prefix"*/model/design_prep.il; do
    [ -f "$m" ] || continue
    nmodel=$((nmodel + 1))
    a=$(grep -c 'cell \$assert' "$m")
    c=$(grep -c 'cell \$cover' "$m")
    [ "$a" -gt "$acell" ] && acell=$a
    [ "$c" -gt "$ccell" ] && ccell=$c
  done

  # cover 증인 도달 수 — sby 의 완전 요약은 로그가 아니라 PASS/FAIL 파일에
  # 있다 (로그는 「and N further traces」로 잘라 인쇄한다). 「unreached」가
  # 「reached」의 부분 문자열이므로 앞의 공백을 요구해 갈라 센다.
  #
  # 매치 없는 글로브를 `cat` 에 넘기지 않고 파일마다 도는 이유: 셸에 따라
  # 매치 없는 글로브가 리터럴로 남기도(POSIX) 명령 전체를 실패시키기도 한다.
  # 후자면 도달 수가 조용히 0 이 되고, 그것은 **또 하나의 「측정하지 못했다를
  # 0이었다로 보고」**다. 셸 방언에 판정을 맡기지 않는다.
  reached=0; unreach=0
  for s in "$prefix"*/PASS "$prefix"*/FAIL; do
    [ -f "$s" ] || continue
    reached=$((reached + $(grep -c '^ *reached cover statement' "$s")))
    unreach=$((unreach + $(grep -c 'unreached cover statement' "$s")))
  done

  if [ "$rc" = ERROR ]; then
    echo "$dir/$name ERROR (엔진이 상태 없이 죽었다 rc=$sbyrc — 게이트·환경 결함이지 대상 결함이 아니다. 단독 재실행: sh scripts/sby_sweep.sh $f)" >> "$LOG"
    broken=$((broken + 1))
    emit "$f" ERROR "$tasks" "$acell" "$ccell" "$reached" "$unreach"
  elif [ "$rc" = FAIL ]; then
    echo "$dir/$name FAIL (로그: /tmp/log-$dir-$name)" >> "$LOG"
    fail=$((fail + 1))
    emit "$f" FAIL "$tasks" "$acell" "$ccell" "$reached" "$unreach"
  elif [ "$nmodel" -eq 0 ]; then
    # 모델 파일 자체가 없다 — 셀이 0 인 것이 아니라 *세지 못한* 것이다.
    echo "$dir/$name UNCOUNTED (design_prep.il 없음 — 게이트 결함이지 대상 결함이 아니다)" >> "$LOG"
    broken=$((broken + 1))
    emit "$f" UNCOUNTED "$tasks" 0 0 "$reached" "$unreach"
  elif [ $((acell + ccell)) -eq 0 ]; then
    echo "$dir/$name HOLLOW (단언 0개 — 통과가 아무것도 보증하지 않는다)" >> "$LOG"
    hollow=$((hollow + 1))
    emit "$f" HOLLOW "$tasks" 0 0 "$reached" "$unreach"
  else
    echo "$dir/$name PASS (assert $acell · cover $ccell · 증인 $reached 도달/$unreach 미도달)" >> "$LOG"
    emit "$f" PASS "$tasks" "$acell" "$ccell" "$reached" "$unreach"
  fi
done

echo "SWEEP-DONE total=$total fail=$fail hollow=$hollow uncounted=$broken" >> "$LOG"
[ $((fail + hollow + broken)) -eq 0 ]
