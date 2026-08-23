---
name: wavetensor-origin
description: "프로젝트 이름의 기원 — \"WaveScalar ISA 를 가속기용으로 개량하면?\" 이라는 질문에서 출발"
metadata: 
  node_type: memory
  type: project
  originSessionId: e7f99d7a-a6eb-46be-b7eb-fd78237e02a7
  modified: 2026-08-23T04:52:28.022Z
---

WaveTensor 라는 이름은 프로젝트의 출발 질문에서 왔다 (사용자 설명, 2026-08-23): **"WaveScalar ISA 를 CPU 가 아니라 가속기에 활용할 수 있도록 개량하면 어떨까?"** — WaveScalar(Swanson et al., UW) + Tensor(가속기 워크로드).

이 계보가 설계에 이미 남긴 흔적: 태그의 wave 32b 필드, 정본 §4 의 Wave-Ordered Memory 절(개념 지목, 현행 미구현), "wave" 라는 실행 단위 어휘 전반.

설계 판단 시 이 기원을 렌즈로 쓸 것 — 특히 **패브릭 용량 초과 프로그램의 처리**(WaveScalar 의 WaveCache 는 하드웨어 측 동적 가상화, WT64v1 현행은 능력 부재 → 호스트 분해로 반대편 극단). 조사 보고서: `docs/research/wavescalar-capacity.md` (2026-08-23 착수). [[wt64v1-rtl-reimplementation]]
