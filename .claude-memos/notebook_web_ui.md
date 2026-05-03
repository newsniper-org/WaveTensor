<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors -->

# Notebook 스타일 웹 UI — 설계 및 구현 검토

> **연관 메모**: [`remote_accelerator_access.md`](./remote_accelerator_access.md) — A/M/S/N 토폴로지와 가속기 lease 흐름. 본 메모의 "셀 실행 흐름" / "Lease panel" / "가속기 RPC" 부분은 그 메모에서 정의되는 daemon API 위에 얹힘.

## 목적

WaveTensor 가속기 사용자에게 Jupyter/Colab 같은 친숙한 환경을 제공:
- 코드 셀 작성 → 가속기로 실행 → 결과 시각화
- 모델 weight, 텐서 데이터를 노트북 안에서 명시적으로 다룸
- 가속기 점유 상태, 컴파일된 LL 코드, 실행 cycle 수 등 가시화

## 주요 사용자 시나리오

1. PyTorch 모델 작성 → WaveTensor 어셈블러로 lower → A 가속기에 발사 → 결과 표
2. 어셈블리 코드 직접 작성 → `assemble()` → 비트 결과 확인 → 가속기 발사
3. 합성 결과 (LUT/timing/power) 대시보드 표시
4. 다중 사용자가 가속기 자원 lease 큐 보면서 잡 발사

## 후보 아키텍처

### (1) Jupyter + custom kernel
- WaveTensor kernel → 어셈블러 + 가속기 RPC client 임베드
- 장점: Jupyter 생태계 (lab, hub, plotly, ipywidgets) 그대로
- 단점: kernel API 학습 곡선, IPython protocol 위에 가속기 lease 흐름을 얹기 까다로움
- 변형: 일반 Python kernel + `%wavetensor` magic command
   - `%%wt` 셀 안에서 어셈블리 작성 → 자동으로 assemble + 발사
   - magic 만 만들면 되니 가장 가벼움

### (2) 자체 노트북 웹앱 (React/Next.js + WS RPC)
- frontend: 셀 grid, monaco editor (VS Code 엔진), shape 시각화
- backend: FastAPI / Axum / 자체 Go server, WebSocket으로 실시간 상태
- 장점: 가속기 도메인 (LUT/cycle/lease) UI를 1급으로 다룸
- 단점: 처음부터 짜야 함, 큰 작업

### (3) Marimo (반응형 Python notebook)
- Marimo 는 셀 의존성 자동 추적 + reactive 실행 + 웹앱 export
- WaveTensor SDK 만 Python 패키지로 제공하면 Marimo 안에서 그대로 사용
- 장점: notebook + reactive UI 거의 무료
- 단점: 가속기-특화 UI (cycle 차트, lease queue) 는 별도 widget 필요

### (4) JupyterLab + lab extension
- Jupyter 위에 lab extension 으로 가속기 dashboard / lease panel 추가
- launcher 에 "Connect to A" 버튼, status bar 에 가속기 상태
- 장점: 사용자 친숙성 ↑, 확장 모델 명확
- 단점: TypeScript+React lab extension 작성 필요

### (4') JupyterLab + lab extension (TypeScript + Svelte 5.x)  *— 권장 변형*

(4) 의 파생형. UI 레이어를 React 대신 **Svelte 5 (Runes)** 로 작성.

#### 구조
```
extension/
├── src/
│   ├── index.ts              ← JupyterLab plugin entry, Lumino Widget
│   ├── widgets/SvelteWidget.ts  ← Lumino ↔ Svelte 라이프사이클 어댑터
│   └── ui/
│       ├── LeasePanel.svelte
│       ├── CycleCounter.svelte
│       ├── PEHeatmap.svelte
│       └── SynthDashboard.svelte
└── webpack.config.js (또는 vite)  ← @sveltejs/vite-plugin-svelte 설정
```

#### Lumino ↔ Svelte 어댑터 (요지)
```ts
import { Widget } from '@lumino/widgets';
import { mount, unmount } from 'svelte';
import LeasePanel from './ui/LeasePanel.svelte';

class LeaseWidget extends Widget {
  private app?: ReturnType<typeof mount>;
  protected onAfterAttach(): void {
    this.app = mount(LeasePanel, {
      target: this.node,
      props: { lease$: this.leaseStore /* svelte/store */ }
    });
  }
  protected onBeforeDetach(): void {
    if (this.app) unmount(this.app);
  }
}
```

JupyterLab 측 Lumino signal → Svelte writable/derived store로 어댑팅 → Svelte 5 runes (`$state`, `$derived`, `$effect`) 가 fine-grained 갱신.

#### 우리 use case 적합도 (왜 권장되는가)

| 가속기-특화 요소 | React vs. Svelte 5 |
|----------------|-----|
| Cycle counter (high-frequency tick) | Svelte 5 runes 가 컴파일-타임 reactivity → React 보다 적은 re-render, 부드러운 갱신 |
| PE heatmap (PE_ROWS×PE_COLS×CLUSTER_*) 64+ cell 색상 갱신 | Svelte 의 fine-grained 가 React VDOM diff 보다 효율 |
| Lease countdown timer | Svelte `$effect` + `setInterval` 한 줄 — React 의 useEffect 의존성 배열 boilerplate 없음 |
| Synth dashboard (정적 차트) | 두 framework 모두 비슷; uPlot/d3 wrap |
| 번들 크기 (브라우저 다운로드) | Svelte runtime ~5KB vs React+ReactDOM ~45KB → 큰 노트북 페이지에서 시작 latency↓ |

#### 트레이드오프

**장점 (위 표 외)**:
- TS 지원 성숙 (svelte-check, language server)
- HMR (vite + plugin-svelte) — 셀 panel 개발 사이클 빠름
- 컴파일러 framework 라 production 번들에 dead-code 거의 없음

**단점**:
- JupyterLab 공식 cookiecutter 는 React 전제. webpack config / package.json 직접 손댐
- 기존 lab extension 생태계에서 React 컴포넌트 import 시 interop 필요 (Lumino widget으로 wrap)
- "JupyterLab + Svelte" 사례가 드물어 troubleshooting 시 1차 자료 적음
- 팀 내 React 경험만 있으면 학습 곡선

#### 빌드 / 패키지 메모
- Svelte 5 (2024-Q4 stable) — Runes 활성화에 `<script>` 안 `let count = $state(0)` 패턴
- `@sveltejs/vite-plugin-svelte` 또는 `svelte-loader@5+` 사용
- TypeScript: `<script lang="ts">` + `svelte-check`
- JupyterLab 4.x 확장 매뉴얼: lab extension 의 webpack rule 에 `.svelte` 추가
- 스타일 격리: Svelte 의 `<style>` 자동 scoping → JupyterLab CSS 와 충돌 적음

#### 권장 채택 시점

(4) 의 자리를 (4') 로 채택 — Phase 2 권장안. (1)-magic 으로 prototype, (3) Marimo 로 베타, (4') 로 정식 UI.

특히 우리 가속기는 **고빈도 telemetry (cycle/PE/lease)** 가 핵심 시각화 대상이라 Svelte 5 의 fine-grained reactivity 가 맞음. 정적인 form-heavy UI 면 React 도 충분하지만, 우리는 그 케이스가 아님.

## 권장 — Phase 별

| 단계 | 권장 |
|------|------|
| Phase 0 (개발) | **(1)-magic 변형**: 보통 IPython kernel + `%%wt` magic. 1주 안에 prototype. |
| Phase 1 (베타) | **(3) Marimo** 또는 (1) full kernel. 사용자 협업/공유 가능. |
| Phase 2 (정식) | **(4') JupyterLab + TypeScript+Svelte 5 lab extension**. 또는 (2) 자체 웹앱 (자원 여력 있으면). |

(1)-magic 으로 시작 → 사용자 피드백 본 다음 (3)/(4')로 진화하는 흐름이 자연스러움.

## A/M/S/N 토폴로지에서의 배치

```
        +-- R (internet)
        |
   +----N----+
   |    |    |
   A    M    S
```

- **노트북 웹 서버 위치**: M에 배포 (사용자가 브라우저로 `http://M:8888` 접속).
  - M이 control-plane 역할을 이미 하므로 자연스러움
  - A는 가속기 daemon만, S는 weight/data 저장만 — 분업
- **사용자 접근 경로**: 사내 LAN이면 `http://M:8888` 직결.
  외부 접근이면 R 통해 reverse proxy / VPN.
- **셀 실행 흐름**:
  1. 사용자 브라우저 ↔ M (웹 서버, 노트북 상태/UI)
  2. M ↔ A (가속기 RPC; 토큰 발사 / 결과 회수)
  3. M ↔ S (weight/dataset fetch; 또는 A↔S 직접으로 우회 — `remote_accelerator_access.md` 참조)
- **인증**: 노트북 자체는 OAuth/JWT (organisation-내 SSO 연동 가능). 가속기 lease 토큰은 노트북 세션과 binding.

## 가속기-특화 UI 요소 후보

| 요소 | 용도 |
|------|------|
| 어셈블리 셀 (`%%wt`) | LL/HL 어셈블리 직접 작성 + 자동 assemble |
| Lower-to-LL 토글 | HL 셀 옆에 "stage 1~5 통과 후 LL" 미리보기 |
| Tag/Payload 시각화 | 80-bit tag 비트 필드 + 64-bit payload 16-bit 요소 격자 |
| Cycle counter | 마지막 실행의 cocotb 사이클 수 / 합성-기반 wall-time 추정 |
| Lease panel | 현재 가속기 점유 상태, 대기 큐, 만료 timer |
| Synth dashboard | LUT/FF/BRAM/DSP utilization, WNS 추이 그래프 |
| Topology view | PE 그리드 (PE_ROWS × PE_COLS × CLUSTER_ROWS × CLUSTER_COLS) 색깔 = 활성 PE |

## 기존 자산 활용

- **`asm/wavetensor_asm.py`** 의 `assemble()` / `lower_to_ll()` → 그대로 magic 안에서 호출
- **`test_isa_decoder.py`** 의 `make_tag()`, `pack16()` 헬퍼 → SDK 의 일부로 노출
- **`synth/parse_reports.py`** → synth dashboard 의 데이터 소스

## 미해결 / 추후 결정

- **다중 사용자 격리**: 노트북 세션 = 가속기 lease 단위? 또는 셀 단위?
- **셀 결과 영속화**: S에 저장? 노트북 내 inline?
- **재현성**: 노트북 + commit hash + 가속기 RTL 버전 + 합성 결과 → 한 set 로 묶어 archive
- **공유**: 노트북 export to static HTML / GitHub markdown
- **WebGPU / canvas**: PE 토폴로지 시각화에 직접 쓸지, 아니면 plotly/d3로 충분할지
- **VS Code Notebook integration**: jupyter 파일 (.ipynb) 호환 → VS Code 사용자도 같은 노트북 열기 가능

## 진입 트리거

- 보드 도착 + 첫 wall-clock 검증 후 — "이제 사용자가 만져볼 단계" 신호
- 또는 사용자께서 "노트북 UI 작업 진입" 명시
- 또는 외부 demo / 협업 일정 (학회/세미나 발표 등) 임박 시
