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
# 사용: 컨테이너 안에서 저장소 루트를 cwd 로 두고 실행.
#   SBY_OUT  산출물 디렉터리 (기본 /sbyout)
#   LOG      결과 로그 (기본 표준출력)

set -u
SBY_OUT="${SBY_OUT:-/sbyout}"
LOG="${LOG:-/dev/stdout}"

mkdir -p "$SBY_OUT"
fail=0; hollow=0; broken=0; total=0

for f in rtl/formal/sby/*/*.sby; do
  total=$((total + 1))
  name=$(basename "$f" .sby)
  dir=$(basename "$(dirname "$f")")
  prefix="$SBY_OUT/$dir-$name"

  rm -rf "$prefix" "$prefix"_*
  if sby -f --prefix "$prefix" "$f" > "/tmp/log-$dir-$name" 2>&1; then
    # 합성 모델에서 assert/cover 셀을 센다. 작은따옴표 안이라 `$` 는 리터럴 —
    # 이 줄이 이 파일의 전부이고, 여기 말고 다른 층에 정규식을 두지 않는다.
    models=$(ls "$prefix"*/model/design_prep.il 2>/dev/null)
    if [ -z "$models" ]; then
      # 모델 파일 자체가 없다 — 셀이 0 인 것이 아니라 *세지 못한* 것이다.
      echo "$dir/$name UNCOUNTED (design_prep.il 없음 — 게이트 결함이지 대상 결함이 아니다)" >> "$LOG"
      broken=$((broken + 1))
      continue
    fi
    n=$(cat $models | grep -c 'cell \$assert\|cell \$cover')
    if [ "$n" -eq 0 ]; then
      echo "$dir/$name HOLLOW (단언 0개 — 통과가 아무것도 보증하지 않는다)" >> "$LOG"
      hollow=$((hollow + 1))
    else
      echo "$dir/$name PASS ($n)" >> "$LOG"
    fi
  else
    echo "$dir/$name FAIL (로그: /tmp/log-$dir-$name)" >> "$LOG"
    fail=$((fail + 1))
  fi
done

echo "SWEEP-DONE total=$total fail=$fail hollow=$hollow uncounted=$broken" >> "$LOG"
[ $((fail + hollow + broken)) -eq 0 ]
