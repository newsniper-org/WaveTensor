---
name: ric3-fork-review
description: rIC3 fork(~/ric3-fork stage4) 도입 검토 결과 2026-09-25 — 도입한다면 fork 397bccb 가 upstream 보다 낫지만 이유는 Stage 2~4 가 아니라 인증서 세그폴트 회피; 도입 자체는 급하지 않음
metadata:
  node_type: memory
  type: project
  originSessionId: e7f99d7a-a6eb-46be-b7eb-fd78237e02a7
  modified: 2026-09-25T07:33:45.711Z
---

2026-09-25 사용자 요청으로 `~/ric3-fork` `stage4`(397bccb) 대 upstream gipsyh/rIC3 를 실측 검토. 저장소 무편집.

**결론:** 도입한다면 fork stage4(또는 v1.5.2 릴리스). 이유는 fork 가 7149d56 에 고정돼 upstream master(b6fe22c)의 `--cert`/`--cex` 세그폴트를 피한다는 것 — Stage 2~4 는 우리 워크로드에 무효:
- Riemann(카운터 가속)은 lemma 주입일 뿐이고 기본 빌드 no-op. HiuMask w16(z3 5시간 웨지)은 upstream·stage4·riemann 모두 0.02 s — 웨지는 smtbmc z3 문제였지 IC3 난도가 아니었다.
- Lebesgue 는 liveness 전용(우리 live 태스크 0). Stage 4 SIMD/GPU/포트폴리오는 CLI 에 결선 안 됨.

**Why 급하지 않은가:** 웨지 두 건은 이미 abc bmc3/pdr · btormc 로 해소. 순이득은 prove 속도 + **certifaiger 독립 인증서**(stage4 로 engine·HiuMask 둘 다 check passed) — 「재실행만이 검증이다」를 강화한다.

**How to apply (도입 시 조건):** 핀 = 커밋 sha + 서브모듈 8개 sha 소스 tarball 보관본 + b2sum (stage4 는 롤링 브랜치 — [[rolling-asset-pin-trap]]) · sby v0.66 의 `aiger rIC3` 글루가 v1.4.1 이전 CLI 문법이라 shim/패치를 우리가 소유 · 반례 재생은 `aigsmt z3` 명시(yices 없음) · 증거용 실행은 `ic3` 단일 엔진 명시(포트폴리오 기본값) · bmc 는 `--cex` 에서 panic → 2단 호출 · certifaiger 는 호스트 docker 호출이라 게이트 경로 재설계 필요 · 변이 반례 완주를 태스크마다 재측정([[solver-blindness-trap]]). GPL-3.0 외부 도구 — vendor/licenses 등재.
미측정: walk_decode · cover 직접 통합(sby 미지원) · upstream 세그폴트 원인.
