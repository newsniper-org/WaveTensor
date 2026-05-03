<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors -->

# WaveTensor 프로젝트

## 1. Project Goal
Implement a hybrid dataflow AI accelerator based on the attached research proposal PDF ("AI 가속기 아키텍처 연구 제안.pdf").
Target: AMD/Xilinx FPGA, pure Verilog RTL (no HLS), 2-Pod scale (512 PEs) prototype.

## 2. 2026년 4월 29일까지의 진행상황
* HIU (Host Interface Unit): Universal IOMMU + Zero-Copy DMA + 보안 강화(constant-time, XChaCha20 masking, partitioned TLB, flush-on-context-switch) 완전 구현 완료. cocotb 테스트 1/1 PASS.
* ISA (Instruction Set Architecture): **80-bit 고정 포맷에서 IPv6 확장-헤더 패턴의 TLV 가변 길이 포맷으로 전면 리팩터링 완료.** 32-bit base header + 최대 4개의 32-bit-aligned extension header 체인. 단일 cycle 조합 디코더. 자세한 명세는 §8 참조.
* 두 번째 피연산자 경로 정상화: `input_payload_b`(64-bit) + `input_payload_b_valid` 포트 추가. MATMUL/TENSOR_ADD/EINSUM이 더 이상 16-bit imm_offset을 squeeze하지 않음.
* EINSUM 8 패턴 완전 구현: `i->`(sum), `ii->`(trace), `ij->ji`(transpose), `ij,jk->ik`(matmul), `ij,ij->ij`(hadamard), `i,j->ij`(outer), `ijk->ij`(partial-sum), `ii->i`(diagonal). 미지원 패턴은 `error_flag`로 명시적 trap.
* error_flag 분류 체계 완성: chain 불일치, bh_len 불일치, reserved 비트 위반, 미지원 opcode, 필수/금지 EH 위반, IMM/OPREF XOR 위반, F_HAS_OPB without b_valid, opref src_kind 미지원, divide-by-zero, MATMUL dim 불일치.
* 기존 잠재 버그 동시 정리: TAG_WIDTH 64↔80 폭 불일치, output_port wire-write lint 에러, `0x000001` Python-syntax-in-Verilog literal.
* Shape ops 추가 (opcode 0x20..0x25): SQUEEZE / UNSQUEEZE / VIEW / PERMUTE / BROADCAST / REDUCE_AXIS. Metadata-only 케이스(SQUEEZE/UNSQUEEZE/VIEW)는 PE 1 cycle에 tag rewrite로 처리; 단순 데이터 이동(2×2 transpose, 1D reduce sum/max/min)도 PE-local; 그 외는 새 `lower_required` 신호로 컴파일러 lowering 경로에 위임.
* EINSUM 시그너처 2종 추가: `i,i->` (DOT), `ij,j->i` (MAT_VEC). 미지원 패턴은 이제 `error_flag` 대신 `lower_required`로 분리 (구조적 오류 vs. SW lowering 필요의 의미 구분).
* 테스트: 5개 모듈 회귀 75/75 PASS — HIU 1/1, ISA_Decoder 48/48 (legacy + EINSUM 10 패턴 + 6 shape op + 9 negative + encoder self-check), Tensor_ALU 1/1, SIMD_ALU 9/9, ALU_Extended 16/16.
* SIMD_ALU.v 합성 안전성 강화: imm_offset 64-bit 명시적 zero-extend, 단일-라이터 staging 제거(read-after-write 1-cycle bug 수정), DIV/REM-by-zero 보호 + `div_zero_flag` 출력, 명시적 MUL truncation 문서화.
* ALU_Extended.v 함수 채움 + 정합화: floor/round/ceil/euclid_norm/conjugate 모듈 내부 정의, Cfloat32 mul을 signed 32-bit 곱셈으로 재작성, unary opcode(0x40~0x44) vs. precision_mode 경로의 명시적 우선순위 arbitration.
* **단계 1-1 어셈블러 완성** (`asm/wavetensor_asm.py`): low-level / high-level 두 계층 정의, 6-stage lowering pipeline (parse → alias_pass → default_pass → macro_pass → legality_pass → encode_pass), encode_instr() 비트 단위 일치 검증. 자세한 명세는 §9 참조.
* **단계 1-1 후속 — Top_Core.v** 통합: HIU + ISA_Decoder 구조적 배선, 5/5 cocotb 테스트 PASS.
* **임의 EINSUM lowering** (어셈블러 macro_pass 확장): HW-direct 10 패턴은 통과; 외 매trix-style은 PERMUTE → VIEW → EINSUM(matmul) → VIEW → PERMUTE로 자동 분해. `.shape` 디렉티브로 라벨 사이즈 명시. trace/broadcast는 명확한 진단으로 거부.
* **PE.v / Cluster.v / Pod.v** 계층 구축:
  * `PE.v`: ISA_Decoder 얇은 래퍼, OPREF 필드 노출
  * `Cluster.v`: PE_ROWS×PE_COLS ∈ {(2,2),(2,4),(4,2),(4,4)}, default (2,2) — 4 PEs. 토큰을 tag.port_context_id[3:0]에 따라 target PE로 라우팅, 출력 OR-merge.
  * `Pod.v`: CLUSTER_ROWS×CLUSTER_COLS ∈ 같은 set, default (2,2) — 4 Clusters. tag.port_context_id[7:4]로 Cluster 선택. 두 레벨이 독립.
  * 두 레벨 모두 elaboration-time `$fatal`로 비허용 geometry 거부.
* **OPERAND_REF NoC routing** (`src_kind=1`): ISA_Decoder가 `src_kind=0`(직접 payload_b) / `src_kind=1`(NoC source) 모두 통과 (≥2만 error). Cluster의 bank 메커니즘이 `bank[noc_route]`(= 해당 PE의 직전 출력)을 target PE의 `in_b_payload`에 주입. **Topology-independence 유지**: binary는 물리 좌표를 모르고 logical bank ID만 명시.
* 테스트: 9개 모듈 + 어셈블러 회귀 **167/167 PASS** — assembler 58 (+6 dim_ovr legality), HIU 1, ISA_Decoder 56 (+4 dim_ovr 동작), Tensor_ALU 1, SIMD_ALU 9, ALU_Extended 16, Top_Core 5, PE 4, Cluster 10, Pod 7.
* PRECISION EH `dim_override` 완성: `F_DIM_OVR` (flags bit 0) 사용 시 PRECISION EH의 `dim` 필드가 tag의 `dimension_sizes`를 모든 실행 경로 + forwarded_tag에 반영. `F_PRECISION_OVR`/`F_DIM_OVR` 둘 다 PRECISION EH 누락 시 error_flag (legality 검사 — `prec_flag_without_eh`).

## 3. 이론 요약
* WaveScalar 데이터플로우 모델: 토큰(tag + payload) 기반 비순차 실행. Wave-Ordered Memory로 메모리 순서 보장.
* NoC 기반 CGRA: Folded Torus 토폴로지로 텐서 All-Reduce / Multicast 지원.
* Universal IOMMU: DMA Zero-Copy + side-channel 방지 (constant-time, XChaCha20 masking).
* EINSUM: hyper_parameter로 subscript 패턴 처리 → MATMUL, tensor contraction, sum 등 범용 지원.
* Precision & Dimension: tag로 이동하여 런타임 동적 처리 가능.

## 4. 참고문헌/자료
* `.claude-assets/AI 가속기 아키텍처 연구 제안.md`
* Swanson, S., Michelson, K., Schwerin, A., & Oskin, M. (2003). "WaveScalar." Proceedings of the 36th Annual IEEE/ACM International Symposium on Microarchitecture (MICRO-36), pp. 291-302. https://doi.org/10.1109/MICRO.2003.1253203
* University of Washington WaveScalar Project. "WaveScalar Architecture Overview." https://wavescalar.cs.washington.edu/
* Jouppi, N. P., et al. (2017). "In-Datacenter Performance Analysis of a Tensor Processing Unit." ISCA '17.
* Chen, T., et al. (2018). "TVM: An Automated End-to-End Optimizing Compiler for Deep Learning." OSDI '18.
* "Dataflow Architectures with SIMD Extensions", IEEE Transactions on Parallel and Distributed Systems, Vol. 15, No. 5, 2004.

## 5. 구성 요소

### 5-1) PE (Processing Element) – 가장 작은 실행 단위
* 역할: 하나의 WaveScalar 토큰을 받아 tag를 해석하고, opcode에 따라 연산을 수행한 뒤 새로운 토큰을 출력하는 기본 연산 유닛.
* 구성:
    * ISA_Decoder 모듈 (opcode 해독 + dimension size 검사 + error_flag 처리)
    * ALU (Bit-Fusion + SIMD 지원, ADD/SUB/MUL/DIV/REM/DIVREM/MATMUL/EINSUM/FLOOR/ROUND/CEIL/EUCLID_NORM/CONJUGATE/BITS-ORD-REVERSE 등)
    * ZERO 레지스터 (항상 0x0), ONE 레지스터 (항상 0x1)
    * 로컬 레지스터 파일 (payload 저장용)
    * 입력/출력 포트 버퍼 (input_port_mask, output_port 처리)
* tag 처리: input_tag[79:0]에서 Wave Number, Thread ID, Port/Context ID, Precision Mode, Dimension size를 추출하여 연산 결정.
* payload: tag의 Dimension size와 Precision Mode에 따라 크기가 동적으로 결정됨 (예: dimension size=0b01010101이면 2×2×2×2 텐서, float64이면 512-bit payload).
* 에러 처리: MUL/DIV/REM/DIVREM에서 두 번째 입력이 single-element가 아니면, ADD/SUB에서 size 불일치 시 error_flag=1 → output_valid=0, memory_req=0.

### 5-2) Cluster (4×4 PE 배열) – 중간 계층
* 역할: 4×4 = 16개의 PE를 하나의 타일로 묶어 로컬 데이터 공유와 간단한 In-Network Computing 수행.
* 구성:
    * 16개 PE
    * Cluster 내부 NoC (Folded Torus의 작은 버전, multicast 지원)
    * 공유 레지스터 파일 (PE 간 빠른 데이터 교환)
    * Cluster Controller (PE 간 동기화, WAVE-ADVANCE 전파)

* 특징: PE 간 STEER/MERGE 연산이 Cluster 내부에서 빠르게 처리됨.
* EINSUM/MATMUL 같은 텐서 연산이 Cluster 단위에서 병렬 실행 가능.

### 5-3) Pod (256 PE = 16 Cluster) – 대형 타일
* 역할: 16개의 Cluster를 모아 256 PE 규모의 독립 실행 단위.
* 구성:
    * 16개 Cluster
    * Pod 내부 NoC (Folded Torus 전체 토폴로지 적용)
    * Pod-level In-Network Reduce (All-Reduce, Sum, Max 등 하드웨어 지원)
    * Pod Memory (로컬 메모리 버퍼, Wave-Ordered Memory 시퀀스 관리)
    * Pod Controller (Cluster 간 WAVE-ADVANCE, error_flag 전파)
* 특징: 2 Pods (512 PE) 프로토타이핑 스케일에서 사용.
* CXL-independent Zero-Copy는 HIU를 통해 Pod 단위로 연결.

### 5-4) Global Grid (전체 시스템) – 최상위 계층
* 역할: 여러 Pod를 연결하여 전체 가속기를 구성.
* 구성:
    * 여러 Pod (현재 프로토타이핑은 2 Pods)
    * Global NoC (Folded Torus 전체)
    * Global Router (hardware multicast, in-network reduce)
    * Host Interface (HIU + Universal IOMMU)
* 특징: Global Grid는 FPGA에서 합성 가능한 수준으로 제한.

### 5-5) 전체 계층 구조 요약 (그림 설명 대신 텍스트)
* PE (1개) → Cluster (4×4 PE = 16개) → Pod (16 Cluster = 256 PE) → Global Grid (여러 Pod)
* 모든 계층에서 tag가 흐르며, ISA_Decoder는 PE 내부에서만 동작합니다.
* HIU는 Global Grid의 Host Interface로만 존재합니다.

## 6. Overall Roadmap
* HIU + ISA_Decoder 완전 구현 (완료)
* Top_Core.v 생성 → HIU + ISA_Decoder + ALU 모듈들을 wire로 연결
* PE.v (ISA_Decoder + ALU wrapper)
* Cluster.v (4×4 PE + local NoC)
* Pod.v (16 Cluster + Pod NoC)
* Global Grid + NoC + FPGA synthesis (ALINX AXU3EGB V2.1 target)
* Full cocotb system-level test + Vivado synthesis / timing analysis

## 7. Current TODO
* **(I) Vivado synthesis 인프라** — **완료** (synth/ 디렉터리, TCL 스크립트, parse_reports.py, Makefile 타겟). XCZU3EG 디바이스 패밀리 미설치 → AMD installer 재실행 또는 device 추가 필요.
* **자원 폭증 이슈 발견 (smoke-test on Spartan 7 xc7s100)**: 16-PE Pod (2×2/2×2) = **494K LUT** + 160 DSP, WNS −214 ns @ 100MHz. ISA_Decoder 내부의 `matmul_func` (4×4×4 unrolled) 가 PE당 ~30K LUT 소비.
* **Mitigation (a) 적용 완료**: `matmul_func` 를 4×4×4 (64 muls + 48 adds) 에서 **고정 2×2 (8 muls + 4 adds)** 로 축소. 64-bit payload 자체가 4 요소 (2×2 max) 한계라 capability loss 0. MATMUL의 dim 검사도 `eff_dim_sizes == 0x05` only로 강화. 더 큰 matmul은 어셈블러 / Cluster-level dispatch로 분해. 회귀 167/167 PASS, 재합성 후 LUT 측정 예정.
* **FPGA synthesis 디바이스 패밀리 설치** — Vivado 2025.2에 Zynq UltraScale+ MPSoC 추가. 공식 AMD installer 재실행 권장.
* (V) PRECISION EH dim_override — **완료** (F_DIM_OVR 플래그, eff_dim_sizes 전 경로 반영, PRECISION EH 누락 시 error_flag).
* Cluster-level tile-PERMUTE / tile-RESHAPE / in-network REDUCE (현재는 PE-local fast-path만; 큰 텐서 분산은 향후).
* 임의 EINSUM lowering의 trace/broadcast 케이스 지원 (현재 matmul-style만).
* Pod-level operand bank (cross-Cluster NoC routing) — 현재 NoC routing은 intra-Cluster만.
* HIU의 multi-cycle DMA 응답을 ISA_Decoder의 LOAD에 loopback (현재는 한쪽 방향 only).

## 8. ISA — TLV (IPv6 EH-style) 가변 길이 포맷

### Base Header (32-bit, 항상 word 0)
```
[31:24] opcode      — 8-bit, 기존 opcode 그대로 (0x00..0x44)
[23:20] next_hdr    — 4-bit, 첫 EH 타입 (0x0=END)
[19:16] flags       — bit3=F_HAS_OPB, bit2=F_PRECISION_OVR,
                      bit1=F_MEM, bit0=F_DIM_OVR
[15: 8] reserved    — 0이어야 함
[ 7: 0] bh_len      — 전체 길이 (32-bit 워드 단위)
```

### EH 공통 헤더 (각 EH의 첫 16-bit)
```
[15:12] next_hdr    — 다음 EH 타입 (0x0=END)
[11: 8] type        — 이 EH의 타입
[ 7: 0] ext_len     — 이 EH의 길이 (워드 단위)
```

### EH 카탈로그
| Code | 이름        | Words | 본문 |
|------|-------------|-------|------|
| 0x0  | END         | —     | sentinel |
| 0x1  | PORT        | 1     | `[15:8]=output_port_id`, `[7:0]=input_port_mask_low8` |
| 0x2  | IMM16       | 1     | `[15:0]`=imm |
| 0x3  | IMM32       | 2     | word1[31:0]=imm32 |
| 0x4  | IMM64       | 3     | {word2,word1}=imm64 |
| 0x5  | MEM         | 2     | addr_mode/stride + word1=offset32 |
| 0x6  | SUBSCRIPT   | 2     | EINSUM 48-bit body (A/B/O 각각 16-bit) |
| 0x7  | OPERAND_REF | 1     | src_kind/port_id/noc_route. iter-1: src_kind=0 ⇒ payload_b |
| 0x8  | PRECISION   | 1     | precision_mode + dim_override |
| 0xF  | NOP_PAD     | 1     | 정렬용 무시 |

### Opcode별 EH 합법성
| Opcode | 필수 | 선택 | F_HAS_OPB |
|--------|------|------|-----------|
| 0x00 NOP | — | PORT | 0 |
| 0x01/02/03 WAVE-ADV/STEER/MERGE | PORT | PRECISION | 0 |
| 0x04/05 LOAD/STORE | PORT, MEM | PRECISION | 0 |
| 0x10..0x1D 산술 binary | PORT | IMM* XOR OPREF | 0 또는 1 |
| 0x17/0x1A SHIFT-L/ROTATE-R | PORT, IMM16 | — | 0 |
| 0x1B/0x1F LOG-NEG/BITS-REV | PORT | — | 0 |
| **0x20 SQUEEZE / 0x21 UNSQUEEZE / 0x22 VIEW / 0x23 PERMUTE / 0x24 BROADCAST / 0x25 REDUCE_AXIS** | **PORT, IMM16** | — | 0 |
| 0x30/0x31 MATMUL/TENSOR_ADD | PORT, OPREF | PRECISION | 1 |
| 0x32 EINSUM | PORT, SUBSCRIPT, OPREF | PRECISION | 1 |
| 0x40..0x44 단항 FP | PORT | PRECISION | 0 |

### Shape ops IMM16 인코딩
| Opcode | IMM16 의미 | 처리 위치 |
|--------|------------|-----------|
| 0x20 SQUEEZE | `[1:0]`=axis (제거할 size-1 차원) | PE / 1 cycle / tag-only |
| 0x21 UNSQUEEZE | `[1:0]`=axis (삽입 위치) | PE / 1 cycle / tag-only |
| 0x22 VIEW | `[7:0]`=new dim_sizes (총 요소수 동일해야 함) | PE / 1 cycle / tag-only |
| 0x23 PERMUTE | `[7:0]`=permutation (각 2-bit 슬롯 = 출력 axis가 가져올 입력 axis). 0x01 (2D transpose) + dim=0x05만 PE-local | PE-local 또는 lower_required |
| 0x24 BROADCAST | `[7:0]`=target dim_sizes | iter-1: 항상 lower_required |
| 0x25 REDUCE_AXIS | `[3:0]`=axis, `[7:4]`=op (0=SUM, 1=MAX, 2=MIN). axis=0 + dim=0x03만 PE-local | PE-local 또는 lower_required |

### EINSUM SUBSCRIPT 본문 (48-bit)
- `[47:32]` A axes (4 nibbles, 각 axis 라벨 0x0=absent / 0x1..0xC=a..l / 0xF=bcst)
- `[31:16]` B axes (동일 인코딩)
- `[15: 0]` O axes (동일 인코딩)

### 지원 EINSUM 패턴 (HW 직결)
| 패턴 | A | B | O |
|------|---|---|---|
| `i->` (sum) | a,0,0,0 | 0,0,0,0 | 0,0,0,0 |
| `ii->` (trace) | a,a,0,0 | 0,0,0,0 | 0,0,0,0 |
| `ij->ji` (transpose) | a,b,0,0 | 0,0,0,0 | b,a,0,0 |
| `ij,jk->ik` (matmul) | a,b,0,0 | b,c,0,0 | a,c,0,0 |
| `ij,ij->ij` (hadamard) | a,b,0,0 | a,b,0,0 | a,b,0,0 |
| `i,j->ij` (outer) | a,0,0,0 | b,0,0,0 | a,b,0,0 |
| `ijk->ij` (partial sum) | a,b,c,0 | 0,0,0,0 | a,b,0,0 |
| `ii->i` (diagonal) | a,a,0,0 | 0,0,0,0 | a,0,0,0 |
| `i,i->` (dot) | a,0,0,0 | a,0,0,0 | 0,0,0,0 |
| `ij,j->i` (mat-vec) | a,b,0,0 | b,0,0,0 | a,0,0,0 |

미지원 패턴 → `lower_required` (구조적 오류가 아니므로 error_flag와 분리). SW 런타임 / 컴파일러 lowering pass가 임의 einsum을 (MATMUL + PERMUTE + RESHAPE + BROADCAST + REDUCE) 그래프로 분해할 책임.

### error_flag vs. lower_required 의미 분리
- `error_flag`: 구조적/논리적 오류 — chain 불일치, 미정의 EH, 필수 EH 누락, 데이터 손실 가능 (예: SQUEEZE non-1 axis, VIEW count mismatch), divide-by-zero 등. 명령은 폐기되어야 함.
- `lower_required`: 명령 자체는 valid이나 PE-local fast path가 없음. SW 런타임이 이 명령을 supported primitive 시퀀스로 lower하여 재발사하면 됨. EINSUM 미지원 패턴, PERMUTE 일반, BROADCAST, REDUCE_AXIS 비-fastpath 등.

### ISA_Decoder 인터페이스 (요약)
- `INSTR_WIDTH = 416-bit` (32-bit base + 4×96-bit EH 슬롯)
- `TAG_WIDTH = 80-bit` (wave_number/thread_id/port_context_id/precision_mode/dimension_sizes)
- 입력: `input_payload`(64), `input_payload_b`(64), `input_payload_b_valid`
- 출력: `output_payload`(64), `output_tag`(80), `output_valid`, `opcode_out`(8), `memory_req`, `mem_addr`(64), `error_flag`, `lower_required`

### Makefile (모듈별 회귀 실행)
```
make MOD=HIU            #  1 test
make MOD=ISA_Decoder    # 52 tests (어셈블러 e2e 포함)
make MOD=Tensor_ALU     #  1 test
make MOD=SIMD_ALU       #  9 tests
make MOD=ALU_Extended   # 16 tests
make MOD=Top_Core       #  5 tests (HIU + ISA_Decoder 통합)
make MOD=PE             #  4 tests (PE wrapper)
make MOD=Cluster        # 10 tests (4-PE grid + NoC routing)
make MOD=Pod            #  7 tests (4-Cluster grid)
python -m unittest asm.test_wavetensor_asm   # 어셈블러 단위 52 tests
```

## 9. 어셈블러 — High-Level / Low-Level / Machine Code

### 9-1. 두 계층의 정의

- **Low-Level (LL) 어셈블리**: 한 줄이 정확히 하나의 TLV 기계어 명령에 1:1 대응. 매크로 없음, 기본값 채움 없음, 모든 EH가 명시적.
- **High-Level (HL) 어셈블리**: LL의 strict superset. LL로 짠 모든 프로그램은 그대로 valid HL이며, HL은 추가로 다음을 제공:
  - `.alias name value` — 기호 상수 선언
  - `.default_port mask=N out=N` — PORT EH 자동 삽입
  - `.default_precision mode=N` — PRECISION EH 자동 + `prec` flag 자동
  - `RESHAPE .from N .to N` — VIEW로 lowering되는 매크로 (요소수 보존 검증 포함)

### 9-2. 6-Stage Lowering Pipeline

```
Stage 1   parse           text   → AST
Stage 2   alias_pass      AST    → AST    (.alias 해소)
Stage 3   default_pass    AST    → AST    (default_port/default_precision 채움)
Stage 4   macro_pass      AST    → AST    (RESHAPE 등 HL 매크로 확장)
Stage 5   legality_pass   AST    → AST    (ISA_Decoder.v와 동일한 EH 합법성 검사)
Stage 6   encode_pass     AST    → List[int]   (각 int = 416-bit 기계어 word)
```

각 stage는 순수 함수 (AST → AST)이며, 마지막 stage만 List[int] 반환. Pipeline 결과는 `test_isa_decoder.py:encode_instr(...)` 출력과 비트 단위 일치.

### 9-3. 니모닉 → opcode 매핑

| Mnemonic | Opcode | 의미 |
|----------|--------|------|
| `NOP`/`WADV`/`STEER`/`MERGE` | 0x00..0x03 | 제어 |
| `LD`/`ST` | 0x04, 0x05 | 메모리 |
| `ADD`/`SUB`/`MUL`/`DIV`/`REM`/`DIVREM` | 0x10/11/12/13/1C/1D | 산술 binary |
| `SHL`/`ROR`/`NEG`/`BITREV` | 0x17/1A/1B/1F | 비트/단항 |
| `SQZ`/`USQZ`/`VIEW`/`PERM`/`BCAST`/`RED` | 0x20..0x25 | shape ops |
| `MATMUL`/`TADD`/`EINSUM` | 0x30/31/32 | 텐서 |
| `FLOOR`/`ROUND`/`CEIL`/`ENORM`/`CONJ` | 0x40..0x44 | 단항 FP |

플래그 토큰 (mnemonic 뒤): `opb` (F_HAS_OPB), `prec` (F_PRECISION_OVR), `mem_hint` (F_MEM), `dim_ovr` (F_DIM_OVR).

`prec` / `dim_ovr` 둘 다 PRECISION EH 필수 (어셈블러 legality 검사). PRECISION EH의 `mode` / `dim` 인자 중 사용한 것에 대응되는 플래그가 `default_pass`에 의해 자동 셋.

### 9-4. EH 디렉티브

| 디렉티브 | EH | 인자 형태 |
|---------|-----|---------|
| `.port` | PORT | `mask=N out=N` |
| `.imm16` / `.imm32` / `.imm64` | IMM* | 위치 인자 (값) |
| `.mem` | MEM | `offset=N [mode=N stride=N]` |
| `.subscript` | SUBSCRIPT | `A=i,j,... B=... O=...` (라벨은 알파벳 식별자) |
| `.opref` | OPERAND_REF | `[kind=N port=N route=N]` |
| `.precision` | PRECISION | `mode=N [dim=N]` |

서브스크립트 라벨은 **첫 등장 순서**로 1, 2, 3, ... 코드에 자동 매핑 (`ij,jk->ik` 와 `pq,qr->pr` 은 비트 동등). 최대 12개 distinct 라벨.

### 9-5. 예제 프로그램

```
# 기호 상수와 기본 포트 선언
.alias port_a 0x01
.default_port mask=port_a out=0

# LL 직접 작성
ADD .imm16 7

# HL: 매크로
RESHAPE .from 0x03 .to 0x05

# HL: HW-direct EINSUM (lower 없이 그대로 통과)
EINSUM opb .subscript A=i,j B=j,k O=i,k .opref
```

각 줄을 Python에서 다룰 때:
```python
from wavetensor_asm import assemble, lower_to_ll
machine_code = assemble(text)        # → List[int] (각 416-bit)
ll_text      = lower_to_ll(text)     # → str (Stage 5까지 lower된 LL)
```

## 10. Hierarchy — PE / Cluster / Pod

### Geometry parameters

| 모듈 | 격자 파라미터 | 허용 조합 | Default |
|------|-------------|-----------|---------|
| Cluster.v | `(PE_ROWS, PE_COLS)` | `{(2,2),(2,4),(4,2),(4,4)}` | `(2,2)` (= 4 PEs) |
| Pod.v | `(CLUSTER_ROWS, CLUSTER_COLS)` | 같은 set | `(2,2)` (= 4 Clusters) |

두 레벨이 **독립** — `4×4 PE/Cluster + 2×2 Cluster/Pod` (= 64 PE/Pod) 같은 비대칭 조합도 허용. 비허용 geometry는 elaboration-time `$fatal`.

### Tag-driven routing

| Tag bits | 의미 |
|----------|------|
| `port_context_id[2:0]` | PE 내부의 8-bit input_port_mask와 one-hot 매칭 (PE 0..7) |
| `port_context_id[3:0]` | Cluster 내 PE 인덱스 (Cluster.v `target_idx`) |
| `port_context_id[7:4]` | Pod 내 Cluster 인덱스 (Pod.v `cluster_idx`) |
| `port_context_id[15:8]` | reserved (Global Grid / 다중-Pod 라우팅용) |

**Topology-independence 보장**: 어떤 binary도 PE_X / PE_Y / CLUSTER_X / CLUSTER_Y 같은 물리 좌표를 명령어에 담지 않음. `port_context_id`만 명시하면 어떤 geometry에서도 동일하게 동작 (단, 인덱스가 grid 범위 내인 경우).

### Stage-21 NoC routing (OPERAND_REF.src_kind=1)

- `src_kind=0`: 직접 `input_payload_b` 사용 (외부 driver)
- `src_kind=1`: Cluster의 `bank[noc_route[3:0]]`(= 해당 PE의 마지막 등록 출력)을 `input_payload_b`로 라우팅
- `src_kind≥2`: reserved → `error_flag`

Cluster 단위에서만 노출됨; Pod-level cross-cluster bank routing은 미구현 (TODO).

## 11. FPGA Synthesis (Vivado)

### 인프라 (`synth/`)

```
synth/
├── scripts/
│   ├── common.tcl       — shared procedures, source list, geometry
│   ├── synth_pod.tcl    — out-of-context synth_design
│   └── impl_pod.tcl     — opt + place + route from synth checkpoint
├── constraints/
│   └── pod.xdc          — clock 100 MHz, false_path on async rst
├── reports/             — generated (gitignored)
├── checkpoints/         — generated (gitignored)
└── parse_reports.py     — pretty-print key metrics
```

### 사용

```bash
# Default: 16-PE Pod (2×2/2×2) on XCZU3EG
make synth-pod                    # synth_design
make impl-pod                     # opt + place + route
make synth-report                 # 요약 출력

# Geometry / 타겟 변경
make synth-pod PE_ROWS=4 PE_COLS=4 PART=xczu7ev-ffvc1156-2-e

# 정리
make synth-clean
```

### 환경 요구

- **Vivado 2025.2** at `/opt/Xilinx/2025.2/Vivado/bin/vivado` (`VIVADO=` 변수로 override)
- **디바이스 패밀리**: 현재 AUR 설치본은 Spartan 7만 포함. **Zynq UltraScale+ MPSoC 추가 설치 필요** (공식 AMD installer 재실행 또는 GUI의 *Help → Add Devices*).

### 1차 smoke-test 결과 (xc7s100, 임시)

**16-PE Pod (default 2×2/2×2 geometry)**:
- LUT: **494,232** (xc7s100 한계 64K 의 7.7×, XCZU3EG 154K 의 3.2× 초과)
- FF: 3,328
- DSP: 160
- WNS @ 100MHz: **−214.767 ns** (1024 endpoints failing)
- 합성 시간: ~7분, timing analysis: ~22분

### 자원 폭증의 원인 (분석)

`ISA_Decoder.v::matmul_func` 가 4×4 16-bit MATMUL을 fully unrolled로 합성 → **64 muls + 48 adds** 의 거대 조합 트리. PE당 ~30K LUT 소비. 16 PEs × 30K = **~480K LUT** 의 대부분이 matmul.

추가 요인:
- 416-bit instruction 버스가 모든 PE에 broadcast (라우팅 LUT)
- 80-bit tag, 64-bit dual payload
- ChaCha20 / TLB 등은 본 합성에 미포함 (Pod만 OOC, HIU 별도)

### 아키텍처 mitigation 후보 (결정 대기)

| 옵션 | 효과 | 단점 |
|------|------|------|
| (a) HW-direct matmul을 2×2로 축소, 4×4는 SW lowering | PE당 LUT ~5× 감소 (~6K) | 어셈블러 macro_pass 확장 필요 |
| (b) matmul 파이프라인화 (multi-cycle) | LUT 65% 감소, latency ↑ | RTL 재설계 필요 |
| (c) PE 이질화 — "logic PE" + "matmul PE" | 평균 LUT ↓, geometry 결정 복잡 | Cluster 라우팅 변경 |
| (d) Cluster당 1개 공유 MATMUL 유닛 | PE는 simple, Cluster 한 곳에 matmul | dataflow 모델 변형 |
| (e) 더 큰 FPGA로 변경 (ZCU104 504K) | 즉시 합성 가능 | 보드 비용 ↑, 연구 제안 spec과 거리 |

(a)+(b) 조합이 **WaveScalar 본질 (작은 PE 다수)** 에 가장 부합. (a) 단독으로도 ~6K LUT/PE → 16-PE Pod = 96K LUT → XCZU3EG 154K의 62% → fits with timing 여유.

타이밍 closure에 대해서는 critical path가 ISA_Decoder 출력 register이므로, EH chain walk + matmul → output_payload 경로에 1-stage 파이프라인 (매 사이클 결과를 latch하는 식) 도입이 필요할 가능성.
