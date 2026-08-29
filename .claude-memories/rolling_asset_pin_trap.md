---
name: rolling-asset-pin-trap
description: 버전 태그가 롤링 CI 산출물이면 「버전 핀」은 핀이 아니다 — TLA v1.8.0 실측. 캐시가 그 실패를 삼켜 이미지와 Dockerfile 이 다른 도구를 말했다
metadata: 
  node_type: memory
  type: feedback
  originSessionId: e7f99d7a-a6eb-46be-b7eb-fd78237e02a7
  modified: 2026-08-29T07:08:41.050Z
---

`.devcontainer/Dockerfile` 이 TLA+ 를 `TLA_VERSION=1.8.0` + 해시로 핀해 왔는데, **`v1.8.0` 은
릴리스가 아니라 롤링 pre-release** 다. 상류 README 축자: 「every commit to the master branch is
built & uploaded to the 1.8.0 Clarke pre-release」. GitHub API 도 `prerelease=true` 로 답한다.
즉 그 자산은 master 커밋마다 같은 태그에 덮어써진다 — **버전으로 보이는 것이 실은 CI 산출물이었다.**

2026-08-29 실측으로 드러난 실제 상태: 커밋된 핀(`4b2313f3…`)은 **더는 받을 수 없었다.**
정본 Dockerfile 은 from-scratch 빌드 불가였고, 작업 이미지 안의 jar 는 다른 바이트(`644f4331…`)였다 —
**이미지와 Dockerfile 이 서로 다른 도구를 말하고 있었다.** 파생 빌드가 캐시 층을 재사용해
그 실패를 삼키고 있어서 아무도 몰랐다.

**Why:** 해시 핀은 「받은 것이 그것인가」를 재지만 「그것을 아직 받을 수 있는가」는 재지 않는다.
그리고 캐시가 있으면 후자의 실패가 조용히 지연된다 — 정본 §6.6 이 「어떤 도구의 어느 버전으로
쟀는지 답할 수 없는 검증은 검증이 아니다」라고 적은 자리에서, 답이 두 개가 되어 있었다.

**How to apply:**
1. **핀을 걸기 전에 그 태그가 릴리스인지 확인하라** — GitHub 은 `prerelease` 플래그로 답한다.
   상류 README 를 읽어라. 색인 하나가 비었다고 부재로 단정하지도 마라: Maven Central release
   색인이 0건이어도 상류는 **스냅샷 저장소**에 올리고 있었다(내가 이 오류를 범해 원장에 거짓을
   적었고, 사용자 지적으로 되돌렸다).
2. **해시 말고 자기보고도 핀하라.** TLA 층은 이제 해시(바이트) + `TLA_TLC_BUILD`/`TLA_TLC_REV`
   (그 바이트가 스스로 무엇이라 말하는지)를 둘 다 잰다 — 해시만 갈아 끼우는 기계적 재핀이 죽는다.
3. **도구는 「기동한다」가 아니라 「일한다」로 재라.** Maven 얇은 jar 는 `tlc` 무인수 호출에
   버전을 인쇄하고 깨끗이 끝났고 SANY 도 전 모듈을 파싱했다 — **깨진 것은 실제 모델 검사뿐**이었다
   (번들 의존 gson·javax.mail 부재로 374 run 전량 `NoClassDefFoundError`). 그래서 이미지 빌드에
   진짜 모델 하나를 검사하는 스모크를 넣었고 양방향으로 실측했다.
4. **주기적 재핀을 전제하라.** 이번 수리는 시계를 되감았을 뿐 멈추지 않았다 — 다음 master 푸시와
   함께 다시 죽는다. 재핀은 도구 버전 변경과 같은 급의 결정이므로 별도 커밋 + 이력 기록.
5. 같은 부류 구멍이 남아 있다: `ALA_SNAPSHOT`·`COCOTB_VERSION`·`WITH_SBY` 는 양방향 대조 밖이고,
   `SBY_COMMIT` 은 devcontainer.json 에 아예 없으며, base 이미지는 다이제스트로 안 묶여 있다.
