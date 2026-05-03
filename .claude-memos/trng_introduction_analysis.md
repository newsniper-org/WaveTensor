<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors -->

# Truly-Random Number Generation (TRNG) Register: 도입 여부 및 위치 분석

작성일: 2026-05-03
컨텍스트: 16-PE Pod (XCAU25P) timing closure 완료 후 (Pod LUT 35%, WNS +2.54 ns @ 100 MHz). 추가 기능 여유 large.

## 결론 요약

**도입 권장**: HIU 내부에 단일 TRNG 엔트로피 소스 + Pod-wide 분배 채널. 이유는 ① 이미 HIU에 ChaCha20 KDF 인프라가 있어 자연스러운 conditioning 경로를 제공하고, ② TRNG는 비용 대비 활용가치가 높은 데에 비해 라이센스/엔트로피 추출 회로의 복제는 의미가 없으며, ③ HW-direct EINSUM 데이터플로우 모델과 결이 맞기 때문이다.

비도입 시: 현재 디자인은 정확한 결정론(deterministic)이라 nonce/seed 재사용 취약점이 발생할 수 있는 보안 워크로드를 수행할 수 없으며, 모델 dropout/sampling류 stochastic 연산은 SW에서 host가 사전 생성한 random tape를 입력으로 받아야 한다.

## 도입 시 활용 use-case

1. **HIU의 ChaCha20 KDF rekey** — 현재 `chacha_key`/`chacha_nonce`는 외부 input으로 정적. 주기적 rekey 또는 매 transaction unique nonce가 필요한 시나리오에서 외부 의존을 제거.
2. **Sampling-style dataflow ops** — Dropout (random mask), 가우시안 노이즈 주입, stochastic rounding (특히 4-bit/8-bit 정밀도 cast), reservoir sampling. WaveScalar 토큰 모델과 자연스럽게 결합 (랜덤 token 생성).
3. **Side-channel/fault-injection mitigation** — Random delays, dummy ops 삽입, masked arithmetic의 fresh masks. ChaCha20-기반 deterministic PRNG로 부족한 fault-attack 시나리오에 대응.
4. **Test/diagnostic** — Self-test pattern generation (PRBS 대체). 합성 시 disable 가능하면 코스트 0.
5. **ID/coordinate uniqueness** — 추후 멀티-Pod 시나리오에서 chip-level UID (PUF의 대체).

## TRNG 후보 구조 (UltraScale+ FPGA)

| # | 구조 | LUT/FF | 엔트로피율 | 특이점 |
|---|---|---:|---|---|
| (a) | **Free-running 링 오실레이터(RO) 다발 + jitter sampling** | ~30 LUT × N stages | 10-100 Mbps | 가장 표준적. `(* keep = "true" *)` + `(* dont_touch = "true" *)`로 Vivado가 RO 합성을 유지하도록 강제 필요. AMD UltraScale+ 합성기는 inverter loop을 자연스럽게 합성. |
| (b) | **Cross-coupled latch metastability** (Vasyltsov-style TERO) | ~50 LUT | 1-10 Mbps | 진정한 metastable 설계 — placement constraint(`LOC`/`BEL`) 필수. 작업량 큼. |
| (c) | **DSP/CARRY 카오스 시스템** (chaos-from-overflow) | ~100 LUT + 1 DSP | 1 Mbps | Logistic map 등. 결정론과 분리하기 어려워 NIST SP800-90B 통과 검증 까다로움. |
| (d) | **PUF + 후처리** (TERO-PUF, RO-PUF) | ~200-500 LUT | 한 번 측정 후 stable | 엄밀하게는 TRNG보다 ID 생성기. 본 메모 범위에서는 (a)/(b)와 보완재. |

**추천**: (a) RO-기반 + von Neumann debiasing + ChaCha20 conditioning. 검증된 패턴(Xilinx XAPP 1314 류)을 따른다. RO 갯수는 일단 8-bit 폭으로 시작 (3 RO × debiased = 1 bit/cycle 수준).

엔트로피 추출 후처리:
- **De-bias**: von Neumann (01→1, 10→0, 00/11→discard) 또는 XOR tree.
- **Health check**: NIST SP800-90B repetition count test (RCT) + adaptive proportion test (APT). 위반 시 `trng_unhealthy` 플래그.
- **Conditioning**: HIU의 기존 ChaCha20 코어 재사용. 64-bit 엔트로피 풀 → ChaCha20(key=fresh, nonce=monotonic) → 64-bit output stream.

## 어디에 두어야 하는가

### 비교 후보

| 위치 | 장점 | 단점 |
|---|---|---|
| **PE_Core 내부** (each L-PE) | 분산 → bandwidth 높음, dataflow op과 가까움 | LUT 비용 16배 (stripping 정신과 정면충돌). RO들의 metastability가 PE_Core 합성에 악영향. PE_Core의 stripping 파라미터(`MUL_OPS_SUPPORTED` 등)와 같은 정책으로 다루면 어색함. |
| **Cluster 내부** (each Cluster) | 4× 분산 — bandwidth 충분. ChaCha20 conditioning은 클러스터별로 가능 | 4× LUT 비용 + 4× ChaCha20 인스턴스 → 자원 낭비. M-UNIT/DIV-UNIT처럼 dedicated unit 패턴이 가능하나 share rate가 낮을 듯 (RNG 요청은 EINSUM/MUL만큼 흔하지 않음). |
| **Pod-top** (1×) | 자원 효율. Pod-wide nonce uniqueness 보장 | Pod 내 모든 PE가 단일 reader bandwidth로 직렬화. 하지만 8-bit/cycle = 800 Mbps @ 100 MHz는 dropout/nonce용으로 충분. |
| **HIU 내부** (1×) | ChaCha20 KDF와 동일 모듈에 있어 conditioning 경로 자명. HIU는 이미 보안/신뢰의 root임 (TLB, IOMMU, partition_id 등) — 신뢰 컴퓨팅 베이스에 자연스럽게 포함됨. | HIU가 메모리/보안 책임으로 비대해짐. 다만 현재 HIU는 LUT 1.9 K로 매우 가볍기에 +500 LUT는 무시 가능. |

### 추천: **HIU 내부 + Pod-wide 분배 채널**

이유:
1. **신뢰 경계 일치** — TRNG는 보안 primitive. HIU는 이미 partition_id, ChaCha20 nonce, IOMMU shadow region 등을 책임지는 trusted module이므로 TRNG도 같은 boundary에 두는 것이 정합적이다.
2. **conditioning 경로 재사용** — HIU의 ChaCha20 코어를 raw → conditioned 변환에 그대로 활용. 별도 인스턴스 불필요.
3. **자원 단일화** — RO + 후처리 합쳐 ~500 LUT 1회 비용, Pod-wide 6.25 LUT/PE 분담 효과.
4. **API 정합** — 기존 ISA에 `LD_RNG` 또는 OPERAND_REF.src_kind=2 (RNG source)를 추가하면, 데이터플로우 토큰이 자연스럽게 random 페이로드를 받음. Cluster의 bank routing이 (M-UNIT bank, DIV-UNIT bank, RNG bank)을 동등하게 다룰 수 있다.
5. **검증 비용 효율** — NIST SP800-90B 검증은 단일 인스턴스에서만 수행하면 됨.

분배 채널 옵션:
- **Pull-by-instruction**: 새 opcode `0x06 RNG_RD`. PE가 명령어로 random 64-bit을 요청 → HIU가 응답. 한 cycle에 하나의 PE만 RNG 사용 가능 — bandwidth 충분.
- **OPREF.src_kind=2**: 모든 binary op에서 B 피연산자를 RNG에서 가져올 수 있음. dropout 등 stochastic dataflow에 자연스러움. 권장.

### 도입 비용 (추정)

| 컴포넌트 | LUT | FF | 비고 |
|---|---:|---:|---|
| 8× RO + sampling | 250 | 16 | placement constraint XDC 추가 |
| von Neumann debias + health check | 80 | 32 | NIST SP800-90B RCT/APT |
| ChaCha20 conditioning (HIU 기존 재사용) | 0 | 0 | 인터페이스 wire만 추가 |
| Pod-wide 분배 라우팅 (broadcast bus) | ~50 | 0 | 8-bit + valid handshake |
| **합계** | **~380 LUT** | **~50 FF** | Pod 49.6 K LUT의 0.8% |

XCAU25P 141 K LUT 한도 대비 무시 가능. timing 영향 최소 (RO는 비동기 sampler 후 CDC).

## 위험 요소

| # | 위험 | 대응 |
|---|---|---|
| R1 | Vivado가 RO를 inverter chain으로 합성하면서 timing 분석에서 false-path 처리 누락 | XDC에 `set_false_path -through [get_pins ro_*]` 명시. `(* dont_touch = "true" *)`로 합성 최적화 차단. |
| R2 | RO의 환경(전압/온도) 의존성 — 엔트로피 부족 | health check (RCT/APT)로 런타임 감지. 부족 시 `trng_unhealthy` 플래그 + ChaCha20을 deterministic-counter 모드로 fallback. |
| R3 | NIST 인증 필요 시 SP800-90A/B 컴플라이언스 추가 검증 부담 | 인증 필수가 아닌 경우 skip. 필요한 경우 외부 lab 인증 또는 entropy estimator (Markov, predictor)를 H/W 또는 SW로 추가. |
| R4 | 보안 워크로드(SCA mitigation)에서 fresh mask가 RNG bandwidth를 초과 | conditioned ChaCha20 stream은 cycle당 64 bit 가능 → 16 PE × 1 fresh mask/cycle 충당 가능. |
| R5 | TRNG가 enable disabled일 때 dropout/sampling op은 deterministic fallback 필요 | `RNG_OPS_SUPPORTED` 파라미터로 Vivado가 DCE 가능하게 strip. instr 수신 시 `lower_required` 발사. |

## TRNG 레지스터의 권장 크기

TRNG 레지스터는 단일 폭이 아니라 **계층적 구조**를 가진다. 각 계층마다 결정 기준이 다르므로 분리해서 sizing.

| 레지스터 | 폭 | 결정 기준 |
|---|---:|---|
| **ISA-visible output (token payload)** | **64-bit** | WaveTensor 토큰 payload 폭과 일치 (`ADDR_WIDTH=64`). PE에 1 token당 1 random word를 공급할 수 있어 dataflow 모델이 자연스러움. 더 좁으면 stochastic op이 cross-token concat을 강요받고, 더 넓으면 토큰 단위가 깨짐. |
| **ChaCha20 keystream block** | **512-bit** | ChaCha20 spec이 1 block = 16 × 32-bit. 그대로 register로 보유하고 64-bit씩 8회 drain. 1회 ChaCha20 호출 비용이 8 token에 amortize됨. 내부 SRAM-style FF array. |
| **Raw entropy pool (pre-conditioning)** | **256-bit** | NIST SP800-90A의 instantiate seed length 권장값. ChaCha20 key (256-bit)를 직접 채우는 데에 정확히 fit. RO 샘플을 von Neumann debias 후 shift-in으로 누적. |
| **RO sample window (health check)** | **16-bit per RO** | SP800-90B Repetition Count Test (RCT, threshold ~10) + Adaptive Proportion Test (APT, window 512). 16-bit shift 레지스터는 RCT에 충분, APT는 별도 9-bit counter로 보강. |
| **ChaCha20 nonce counter** | **64-bit** (monotonic) + **32-bit** (block ctr) | ChaCha20 spec의 96-bit nonce + 32-bit counter. nonce 64-bit가 reuse되지 않도록 monotonic. wrap 시 reseed. |
| **Reseed period counter** | **24-bit** | 매 ~16 M random output마다 raw pool에서 ChaCha20 key를 reseed. SP800-90A의 reseed limit (≤2⁴⁸ blocks)를 훨씬 보수적으로 잡음. |

### 합산 storage

| 항목 | bits |
|---|---:|
| Output register (single, ISA-visible) | 64 |
| ChaCha20 state (key+nonce+block) | 256 + 96 + 32 = 384 |
| ChaCha20 keystream buffer | 512 |
| Raw entropy pool | 256 |
| Health check shift / counters | 8 RO × 16 + APT counters ~ 200 |
| Reseed counter | 24 |
| **총합** | **~1,440 bits ≈ 180 bytes** |

FF 비용: ~1,440 FF. Pod 14,300 FF의 10%. LUT 비용은 health check + ChaCha20 round 로직 (HIU의 기존 ChaCha20 코어를 시간 다중화로 재사용하면 새 LUT 거의 0).

### 왜 이 크기인가 — 단일 답변 요약

- **ISA에서 보이는 폭**: **64-bit**. 토큰 payload 폭이 그대로 정답.
- **내부 풀**: **256-bit raw + 512-bit conditioned**. ChaCha20 spec과 SP800-90A seed length를 그대로 따른다.
- **다른 폭을 시도하지 말 것**: 32-bit는 dataflow와 어긋나고, 128-bit는 token bus를 두 cycle로 가리며, 1024-bit raw pool은 health check overhead만 늘어난다. 표준 값에서 벗어날 동기가 약하다.

## 권장 도입 순서

1. **Phase 1** (지금 추가하기 쉬운 것): HIU에 RO + von Neumann debias + 8-bit `rng_raw` 출력 wire 추가. health check는 stub. Pod-top까지 broadcast 라우팅.
2. **Phase 2**: ISA에 OPREF.src_kind=2 (RNG) 정의. Cluster의 bank routing에 RNG 채널 추가.
3. **Phase 3**: ChaCha20 conditioning 활성화 + health check 완성. SP800-90B compliance 검토.
4. **Phase 4** (옵션): 새 opcode `0x06 RNG_RD` 추가하거나 stochastic einsum (dropout/sampling subscript) 추가.

## 결론

**HIU에 단일 RO-based TRNG + ChaCha20 conditioning + Pod-wide 분배가 자원/신뢰/API 정합 측면에서 최적**이다. ~380 LUT (Pod의 0.8%) 비용으로 보안(nonce uniqueness, fresh masks), AI(dropout/stochastic rounding), 진단(BIST seed) 기능이 동시에 활성화된다. 현재 35% LUT 사용률 기준 헤드룸이 충분하므로 도입에 자원 제약은 없다.

도입을 보류할 합리적 사유는 ① 비결정성을 허용하지 않는 워크로드만 다룰 계획이거나, ② NIST SP800-90B 인증 부담이 우선순위 밖일 때다. 둘 다 해당이 아니라면 다음 사양 iteration에 포함시킬 것을 권장한다.
