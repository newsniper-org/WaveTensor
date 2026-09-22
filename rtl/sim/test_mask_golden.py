# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""test_mask_golden.py — SEC-1 주소 마스킹의 golden 정확 대조 (MaskUnit 단독).

DUT 는 `rtl/generated/MaskUnit.sv` — 합성 형상 그대로다. MMIO 는 이 형상에
없다 (그것은 `Wt64Top` 의 `0xE80`–`0xEC0` 구역이다); 여기서는 소박한 워드
기입 포트를 직접 때린다.

═══════════════════════════════════════════════════════════════════════════
## 대조식 — 한 줄로 닫힌다
═══════════════════════════════════════════════════════════════════════════

`XlateStore.scala:60-70` 「val PAGE_W = 12」 가 `PA_W=44` · `PAGE_W=12` · `FRAME_W=32` 를 정하고,
E.9 3항(마스크는 페이지 프레임 부분에만)에 따라 적용 슬라이스가
`mask64[PAGE_W+FRAME_W-1 : PAGE_W]` = `mask64[43:12]` 다.

`MaskUnit.scala:528-534` 「rFrame := io.req.frame ^ maskFrame(io.req.part)」:
    when(io.en) { rValid := io.req.valid
                  rFrame := io.req.frame ^ maskFrame(io.req.part) }

⇒  io_rsp_frame  ==  io_req_frame ^ (mask64 >> 12) & 0xFFFFFFFF

RTL 은 64비트 마스크를 레지스터에 두지 않는다 (`MaskUnit.scala:289-296` 「저장은 적용 비트만」).
`PH_FINAL`(`MaskUnit.scala:443` 「is(PH_FINAL) {」 이하)이 그 32비트만 상수 분해로 직접 만든다 — 생성물
`MaskUnit.sv:304-307` 「st_1[11 : 0] + 12'h46e」 에서 상수 셋(`12'h79b` · `20'h61707` · `12'h46e`)을
대조 확인했다. 이 사영은 **정보 손실이 없다** (벡터 전 라인에서
`(PHYS[43:12] ^ mask64[43:12]) == MASKED[43:12]` 성립 — 아래 회계가 매
실행 재확인한다).

═══════════════════════════════════════════════════════════════════════════
## 키·논스 저장의 범위 — 임대(파티션)마다 다르다
═══════════════════════════════════════════════════════════════════════════

정본 `05-security.typ:112` 「키의 범위 — 임대마다 다르다」 를 RTL 이 따라잡은
뒤(2026-09-20, ca3c496) 키 저장은 논스와 같이 **파티션별**이다. 이 하네스가
전제하는 계약 넷 (전부 현재 `MaskUnit.scala` 에서 실물 확인):

  · 키 기입 포트에 `io_keyWr_part` 가 있고 워드는 `key(part)(idx)` 에 앉는다
    (`MaskUnit.scala:489` 「key(io.keyWr.part)(io.keyWr.idx) := io.keyWr.data」).
  · 키 기입은 **그 파티션의** maskValid 만 떨어뜨린다
    (`MaskUnit.scala:494` 「maskValid(io.keyWr.part) := False」 — 정본
    `e-defined.typ:339` 「기입은 그 파티션의 마스크 유효를 즉시 떨어뜨린다」).
  · REKEY 는 `key(io.rekey.part)` 를 읽는다
    (`MaskUnit.scala:392` 「st(4 + i)  := key(io.rekey.part)(i).asUInt」).
  · 계산 중 기입이 `compDirty` 를 세우는 것은 기입 파티션이 계산 중 파티션
    (actPart)이거나 이번에 수락되는 REKEY 의 대상일 때뿐이다
    (`MaskUnit.scala:501-502` 「io.keyWr.part === actPart」) — 다른 파티션은
    E.9 4항 그대로 `e-defined.typ:1526` 「다른 파티션이 그 변경의 사정권 밖」.

제어면(저장 스코프 · 기입의 무효화 범위 · REKEY 유휴 수락)은 후-formal
`rtl/formal/sby/HiuMask/hiumask.sby` 가 이미 증명했다 (Mask.key_scoped_storage
· Mask.key_write_own_only · Mask.rekey_idle_only). **값**(SEC-1)은 형식이
아니라 golden 대조의 몫이고 그것이 이 파일이다 — 지향 시험 둘
(`key_scope_cross_partition_value` · `wr_other_partition_during_rekey_is_clean`)
이 그 계약을 값 수준에서 재고, golden 루프가 파티션을 골고루 돌며 저장이
파티션별인지를 매 라인 확인한다.

옛 계약(키 전역 1벌 · 키 기입이 전 파티션 무효화)을 전제한 채 남은 하네스는
part≠0 으로 값을 재는 시험 둘에서 죽었다 (2026-09-22 실측, HEAD ac63902):
`io_keyWr_part` 를 구동하지 않으면 Verilator 미구동 입력은 0 이라 모든 키가
파티션 0 에만 앉고, 다른 파티션은 리셋 값(전부 0) 키로 재키잉해 golden 과
어긋난다. part 0 에서만 값을 재던 여섯은 통과했다 — 「통과한 여섯」은 그
축을 재지 않았던 것이지 계약을 확인한 것이 아니다.

═══════════════════════════════════════════════════════════════════════════
## 금지형 — 정본 §5.2.4 함정의 직접 이행
═══════════════════════════════════════════════════════════════════════════

「확산은 세어서 확인할 수 없다. `!=` 검사는 무의미하다 — **틀린 값도
다르다.**」 그 규율의 수신인이 이 파일이다 (`MaskUnit.scala:125-130` 「확산 검사는 구현하지 않는다」
가 명시한다). 이 파일에 다음은 **한 곳도 없다**:

    assert got != legacy          # 틀린 값도 다르다
    assert popcount(a ^ b) > k    # 확산 세기
    assert 0.4 < hamming/32 < 0.6 # 통계
    if got != exp: warn(...)      # 경고는 판정이 아니다

있는 것은 golden 이 낸 그 32비트와의 **등가 비교 하나**뿐이다.
`nonce_tail`·`key_word` 가족의 「회귀 검출기」 성격은 *그 벡터가 폐기
알고리즘을 골라내도록 golden 이 구성됐다*는 뜻이지 이 하네스가 통계를
잰다는 뜻이 아니다 — 검출은 golden 값과의 정확 비교가 한다.

fault 는 **`io_fault*` 실포트로만** 관측한다. 시뮬 전용 단언으로 fault 를
구현하지 않는다 — 합성 결과물에 그 검사가 없기 때문이다. 그리고 fault 의
기대값도 등가로 잰다 — 「서야 할 때 1」만이 아니라 「서지 않아야 할 때 0」
도 단언이다 (golden 루프의 `faultNonceDup` 대조가 그 형태다).

═══════════════════════════════════════════════════════════════════════════
## 이 파일이 재지 못하는 마스킹 축 (정직 명기)
═══════════════════════════════════════════════════════════════════════════

1. **mask64 의 32비트가 존재하지 않는다** — `[63:44]`·`[11:0]` 은 RTL 에
   레지스터도 배선도 없다. golden `MASK`/`MASKED` 64비트 중 32비트는
   비교 불가가 아니라 **비교 대상 부재**다. 벡터당 판별력은 32비트다.
2. **`SUBKEY`·`BLOCK` 필드를 못 쓴다** — 부표준키·블록 16워드를 내는 포트가
   없다. `st_0..st_15` 가 생성 SV 에 이름으로 남지만 그것은 포트 계약이
   아니라 SpinalHDL 명명의 우연이므로 통과 기준으로 쓰지 않는다.
3. **80 라인 ≠ 80 자극점** — 사영 뒤 서로 다른 `maskFrame` 은 73/80,
   서로 다른 `(KEY,NONCE,frame)` 은 79/80 이다 (`pinned` 8줄이 같은 키·논스
   이고 그 중 두 줄은 페이지 오프셋만 다르다). 축소는 하네스 결함이 아니라
   사영의 필연이며, 아래 회계가 두 수를 매 실행 재계산해 인쇄한다.
4. **counter·rounds 를 못 흔든다** — counter 는 `st(12):=0` 고정
   (`MaskUnit.scala:429` 「st(12) := 0」), ROUNDS 는 Scala 상수(`MaskUnit.scala:185` 「val ROUNDS = 20」)로 SV 파라미터가 아니다.
   다중 블록 키스트림·축소 라운드 교차대조는 이 기계에 대상이 없다.
5. **재키잉↔flush 결합(E.9 4항)은 잴 수 없다** — flush 동반은 호스트 ABI
   의무(§3.10)로 명시 위임돼 있고 RTL 에 강제 배선이 없다. 이 파일이 재는
   것은 「옛/새 입력 혼합 금지」(compDirty → faultWrDuringRekey)와 그
   금지의 **범위**(같은 파티션만 — `wr_other_partition_during_rekey_is_clean`)
   · 그 **시점**(busy 사이클 전부, FINAL 사이클 포함 —
   `wr_same_partition_at_final_edge_is_loud`)뿐이다.
6. **`faultNonceDup` 의 사각지대는 RTL 계약 자체에 있다** —
   `maskValid` 가 서지 않은 파티션과의 논스 중복은 검사되지 않는다
   (`MaskUnit.scala:365-367` 「maskValid(q) && (U(q, partW bits) =/= io.rekey.part)」).
   하네스가 이것을 우회로 「해결」하지 않고 계약의 범위로 적는다. 키가 파티션별이 된 뒤로 golden 루프에서는 다른
   파티션의 `maskValid` 가 살아남으므로 dup 검사가 더는 공허하지 않다 —
   `pinned` 8줄(같은 키·논스)을 서로 다른 파티션에 앉히면 **실제로 선다**.
   그래서 루프가 하네스 쪽 모델(유효 파티션 → 논스)로 install 마다 기대값을
   계산해 `io_faultNonceDup` 과 등가 대조하고 해제한 뒤 다음 라인으로 간다
   (E.9 2항을 루프가 함께 잰다). 그 모델도 RTL 과 같은 사각지대를 갖는다 —
   미유효 파티션과의 중복은 기대값에도 없다. 그것을 재려면 계약이 먼저
   바뀌어야 한다.
7. **부채널·상수 시간성은 대상 밖** — 여기서 보는 것은 사이클 수 동일성뿐
   이다 (게이트 지연·전력·EM 아님).

(옛 8항 「FINAL 엣지의 같은-파티션 동시 기입 모서리는 재지 않는다」는 파도 D
(2026-09-22)에서 **이제 잰다** — `wr_same_partition_at_final_edge_is_loud`.
파도 D 이전 판(1666c7a)은 수락+42 엣지(FINAL 사이클)의 활성 파티션 기입에
유효만 떨어뜨리고 `faultWrDuringRekey` 가 침묵했다 — `dirtyAtFinal` 이
레지스터 `compDirty` 의 엣지 전 값(0)만 읽고 같은 엣지의 `compDirty := True`
는 다음 사이클에야 섰다. 지금은 FINAL 가지가 같은 사이클 항을 직접 본다 —
`MaskUnit.scala:473` 「val dirtyNow = compDirty || wrActNow」. 기존
`fault_wr_during_rekey` 는 수락 뒤 5엣지(HROUND)에서만 쓰므로 그 시험은 이
모서리에 침묵한다 — 시점 축은 새 지향 시험 하나가 유일한 그물이다.)
"""

import os
import re
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

# ── 사영 상수 — RTL 과 같은 출처에서만 온다 ────────────────────────────────
# 하네스가 12/32 를 자기 판단으로 적지 않는다. 값의 출처는 XlateStore.scala
# 60-70 이고, 여기서 어긋나면 대조식이 조용히 다른 슬라이스를 본다.
PAGE_W = 12
FRAME_W = 32
FRAME_MASK = (1 << FRAME_W) - 1

# ── 재키잉 지연 — **실측으로 못박은 상수. 끝점을 함께 적는다** ─────────────
#
# `MaskUnit.scala` 는 두 숫자를 말하고 **끝점을 적지 않는다**: 머리 주석
# `MaskUnit.scala:165` 「총 43사이클」 (수락 1 + 유도 20 + 재구성 1 + 본 라운드
# 20 + 최종 덧셈 1) 과 `MaskUnit.scala:328` 「어떤 입력이든 42사이클 동일」.
# 어느 쪽이 맞느냐가 아니라 **둘 다 맞고 끝점이 다르다** — 그 사실이 문면에
# 없어서 다음 사람이 하나를 오타로 읽는다. 아래 셋이 그 자리를 닫는다
# (전부 실측으로 확정):
#
#   TOTAL_INCLUSIVE  43  수락 엣지를 **포함**한 총 사이클 (= 「총 43사이클」의 43)
#   REKEY_TO_READY   42  수락 엣지 **이후** maskReady[part] 관측까지의 엣지 수
#   BUSY_HIGH        41  io_busy 가 1 로 관측되는 사이클 수 (FINAL 엣지에서
#                        phase→IDLE 이므로 관측 표본 하나가 빠진다)
TOTAL_INCLUSIVE = 43
REKEY_TO_READY = 42
BUSY_HIGH = 41

CLK_NS = 4
SETTLE_NS = 1  # 엣지 뒤 관측 시점 — 다음 엣지까지 3ns 여유

# 파티션 수 — `io_maskReady` 폭 (생성물 `[3:0]`). 모델과 루프의 `i % PARTS` 가
# 이 값을 쓴다.
PARTS = 4

VEC_PATH = Path(os.environ["WT_REPO"]) / "include" / "generated" / "xchacha_vectors.hex"

# `include/generated/xchacha_vec_contract.md` §1 — MSB-first 필드 폭.
FIELDS = [
    ("META", 32), ("KEY", 256), ("NONCE", 192), ("PHYS", 64),
    ("SUBKEY", 256), ("BLOCK", 512), ("MASK", 64), ("MASKED", 64),
]
LINE_BITS = sum(w for _, w in FIELDS)  # 1440
# 계약 §2 — 가족별 라인 수. 회계가 이 표와 어긋나면 FAIL 이다.
FAMILY_EXPECT = {0x00: 8, 0x01: 32, 0x02: 8, 0x03: 16, 0x04: 16}
FAMILY_NAME = {0x00: "pinned", 0x01: "rand", 0x02: "edge",
               0x03: "nonce_tail", 0x04: "key_word"}


def frame_of(x64: int) -> int:
    """mask64[43:12] 사영 — 적용 슬라이스."""
    return (x64 >> PAGE_W) & FRAME_MASK


def load_vectors():
    """벡터 파일을 읽고 **회계**한다.

    미완료를 통과로 읽지 않기 위해, 헤더가 선언한 `N_VEC` 와 실제 읽은 라인
    수·가족별 라인 수를 셋 다 대조한다. 하나라도 어긋나면 예외다.
    """
    declared = None
    lines = []
    for raw in VEC_PATH.read_text().splitlines():
        s = raw.strip()
        if not s:
            continue
        if s.startswith("//"):
            if "N_VEC" in s:
                declared = int(s.split("N_VEC")[1].strip().lstrip("=").strip())
            continue
        lines.append(s)
    if declared is None:
        raise RuntimeError(f"{VEC_PATH}: 헤더에 N_VEC 선언이 없다 — 회계 불가")
    if len(lines) != declared:
        raise RuntimeError(f"{VEC_PATH}: 라인 {len(lines)} ≠ 선언 N_VEC {declared}")

    recs = []
    for i, s in enumerate(lines):
        if len(s) * 4 != LINE_BITS:
            raise RuntimeError(f"라인 {i}: {len(s)*4} 비트 ≠ 계약 {LINE_BITS}")
        v = int(s, 16)
        rec, pos = {}, LINE_BITS
        for name, w in FIELDS:
            pos -= w
            rec[name] = (v >> pos) & ((1 << w) - 1)
        assert pos == 0
        rec["family"] = rec["META"] >> 24
        recs.append(rec)

    fam = {}
    for r in recs:
        fam[r["family"]] = fam.get(r["family"], 0) + 1
    if fam != FAMILY_EXPECT:
        raise RuntimeError(f"가족별 라인 수 {fam} ≠ 계약 §2 {FAMILY_EXPECT}")

    # 사영이 정보 손실 없는지 — 계약 §4 5항과 사영의 정합. 매 실행 재확인한다.
    for i, r in enumerate(recs):
        if r["MASKED"] != r["PHYS"] ^ r["MASK"]:
            raise RuntimeError(f"라인 {i}: MASKED ≠ PHYS ^ MASK — 벡터 파일 자기모순")
        if frame_of(r["MASKED"]) != (frame_of(r["PHYS"]) ^ frame_of(r["MASK"])):
            raise RuntimeError(f"라인 {i}: 사영이 XOR 와 교환되지 않는다")
    return recs


def pick_distinct(recs, *avoid):
    """사영 뒤 마스크가 `avoid` 의 어느 것과도 다른 **첫** 벡터를 찾아서 쓴다.

    색인으로 고르지 않는다 — `pinned` 8줄은 키·논스가 같아 사영 마스크가
    같다 (서로 다른 maskFrame 이 73/80 인 이유). 색인으로 집으면 「구성을
    갈았는데 값이 같다」가 공허하게 통과한다; `negative_control` 이 실제로
    그렇게 짰다가 걸린 관용구를 함수로 둔다. 없으면 예외 — 공허한 자극으로
    본시험에 들어가지 않는다. (이 「다르다」 는 판정이 아니라 **자극이
    비공허함**의 파이썬 쪽 확인이다 — DUT 값은 여기 없다.)
    """
    taken = {frame_of(a["MASK"]) for a in avoid}
    r = next((x for x in recs if frame_of(x["MASK"]) not in taken), None)
    if r is None:
        raise AssertionError(
            "사영 마스크가 서로 다른 벡터가 모자란다 — 구성 축 대조가 공허해진다")
    return r


# ═══════════════════════════════════════════════════════════════════════════
# DUT 구동 원시 연산
# ═══════════════════════════════════════════════════════════════════════════

# ⚠ 이 목록이 `boot()` 의 초기화 정의역이다. 포트가 늘었는데 여기 없으면
#   Verilator 미구동 입력은 0 으로 남고 — `io_keyWr_part` 가 정확히 그렇게
#   빠져 있었다 — 그 0 이 「파티션 0」이라는 뜻을 가진 채 시험이 조용히 다른
#   계약을 잰다. 그래서 `boot()` 가 생성물 머리의 입력 포트 집합과 이 목록을
#   **기계로** 대조한다 (누락·잉여 = FAIL) — 주석은 호출이 아니다.
INPUTS = [
    "io_keyWr_valid", "io_keyWr_part", "io_keyWr_idx", "io_keyWr_data",
    "io_nonceWr_valid", "io_nonceWr_part", "io_nonceWr_idx", "io_nonceWr_data",
    "io_rekey_valid", "io_rekey_part",
    "io_en", "io_req_valid", "io_req_part", "io_req_frame",
    "io_faultClearNoMask", "io_faultClearNonceDup", "io_faultClearWrRekey",
]


async def step(dut, n=1):
    """엣지 하나 + 관측 정착. 이 함수 뒤의 모든 읽기는 **엣지 이후** 값이다."""
    for _ in range(n):
        await RisingEdge(dut.clk)
        await Timer(SETTLE_NS, "ns")


GEN_SV = Path(os.environ["WT_REPO"]) / "rtl" / "generated" / "MaskUnit.sv"
_INPUT_PORT_RE = re.compile(r"^\s*input\s+wire\s*(?:\[[^\]]+\]\s*)?(\w+)\s*,?\s*$")


def generated_input_ports():
    """생성물 머리(첫 모듈의 포트 목록)에서 `input wire` 이름 집합을 뽑는다.

    `INPUTS` 의 정의역은 이 집합이다 — 손 목록이 아니라 생성물이 정한다.
    """
    names = set()
    for line in GEN_SV.read_text(encoding="utf-8").splitlines():
        m = _INPUT_PORT_RE.match(line)
        if m:
            names.add(m.group(1))
        elif line.strip() == ");" and names:
            break
    assert names, f"생성물에서 입력 포트를 하나도 못 읽었다: {GEN_SV}"
    return names


async def boot(dut):
    # 포트 정의역 대조 — `INPUTS` 가 생성물과 다르면 여기서 죽는다. 이것이
    # 없던 동안 `io_keyWr_part` 누락이 두 시험을 조용히 다른 계약으로 보냈다.
    ports = generated_input_ports() - {"clk", "reset"}
    assert ports == set(INPUTS), (
        f"INPUTS 가 생성물 입력 포트와 다르다 — 누락 {sorted(ports - set(INPUTS))} · "
        f"잉여 {sorted(set(INPUTS) - ports)}. 미구동 입력은 0 으로 남아 시험이 "
        "조용히 다른 계약을 잰다")
    for n in INPUTS:
        getattr(dut, n).value = 0
    cocotb.start_soon(Clock(dut.clk, CLK_NS, unit="ns").start())
    dut.reset.value = 1
    await step(dut, 3)
    dut.reset.value = 0
    await step(dut)
    # reset 후 전부 미준비 — 구성하지 않은 기계가 우연히 마스킹하지 않는다.
    assert int(dut.io_maskReady.value) == 0, (
        f"reset 후 maskReady={int(dut.io_maskReady.value):#x} ≠ 0 — "
        "미구성 기계가 마스킹 준비 상태로 나온다")


async def write_key_word(dut, part, idx, data):
    """키 워드 하나 기입 — 파티션 `part` 의 word `idx`."""
    dut.io_keyWr_valid.value = 1
    dut.io_keyWr_part.value = part
    dut.io_keyWr_idx.value = idx
    dut.io_keyWr_data.value = data
    await step(dut)
    dut.io_keyWr_valid.value = 0


async def write_key(dut, part, key256):
    """파티션 `part` 에 키 8워드 기입 (`MaskUnit.scala:231` 「word n = key[32n+31:32n]」).

    키 저장은 파티션별이다 — 기입은 **그 파티션의** maskValid 만 떨어뜨리고
    다른 파티션은 사정권 밖이다 (파일 머리 「키·논스 저장의 범위」).
    """
    for n in range(8):
        await write_key_word(dut, part, n, (key256 >> (32 * n)) & 0xFFFFFFFF)


async def write_nonce(dut, part, nonce192):
    """논스 6워드 기입. word i = NONCE[32i+31:32i]. idx 6·7 은 무시된다."""
    for i in range(6):
        dut.io_nonceWr_valid.value = 1
        dut.io_nonceWr_part.value = part
        dut.io_nonceWr_idx.value = i
        dut.io_nonceWr_data.value = (nonce192 >> (32 * i)) & 0xFFFFFFFF
        await step(dut)
    dut.io_nonceWr_valid.value = 0


async def write_nonce_word(dut, part, idx, data):
    """논스 워드 하나 기입 — 파티션 `part` 의 word `idx`. idx 6·7 은 RTL 이
    무시한다 (예약 오프셋 정책 — `MaskUnit.scala:238` 「6·7 기입은 무시한다」);
    음성 대조 자극으로 쓴다."""
    dut.io_nonceWr_valid.value = 1
    dut.io_nonceWr_part.value = part
    dut.io_nonceWr_idx.value = idx
    dut.io_nonceWr_data.value = data
    await step(dut)
    dut.io_nonceWr_valid.value = 0


async def clear_wr_rekey(dut):
    """`faultWrDuringRekey` sticky 를 해제선으로 내리고 **내려갔음을 확인**한다."""
    dut.io_faultClearWrRekey.value = 1
    await step(dut)
    dut.io_faultClearWrRekey.value = 0
    await step(dut)
    assert int(dut.io_faultWrDuringRekey.value) == 0, "해제선이 faultWrDuringRekey sticky 를 내리지 못했다"


async def rekey(dut, part, expect_accept=True):
    """재키잉 펄스. **`io_rekey_ready` 를 같은 엣지에서 확인한다.**

    `MaskUnit.scala:344` 「io.rekey.ready := !engineBusy」 이고 미수락은 무언
    드롭이 아니라 ready 하강으로 관측되는 것이 계약이다. ready 를 안 보고 쏘면
    **하네스가 스스로 조용한 드롭을 만든다.**
    """
    dut.io_rekey_valid.value = 1
    dut.io_rekey_part.value = part
    # `MaskUnit.sv:421` 「assign io_rekey_ready = (! engineBusy);」 는 레지스터만의
    # 함수라 방금 쓴 입력에 의존하지 않는다 — 델타 없이 지금 값이 이 엣지의 값이다.
    ready = int(dut.io_rekey_ready.value)
    assert ready == (1 if expect_accept else 0), (
        f"rekey(part={part}): io_rekey_ready={ready}, 기대 "
        f"{1 if expect_accept else 0} — 미수락은 ready 하강으로만 관측된다")
    await step(dut)
    dut.io_rekey_valid.value = 0


async def wait_mask_ready(dut, part, limit=200):
    """maskReady[part] 상승까지의 엣지 수. 상한 초과는 skip 이 아니라 FAIL."""
    for c in range(1, limit + 1):
        await step(dut)
        if (int(dut.io_maskReady.value) >> part) & 1:
            return c
    raise AssertionError(
        f"maskReady[{part}] 가 {limit} 엣지 안에 서지 않았다 — 미완료는 통과가 아니다")


async def wait_engine_idle(dut, limit=REKEY_TO_READY + 10):
    """`io_busy` 하강까지 기다린다. 상한 초과는 FAIL — 미완료는 통과가 아니다.

    `wait_mask_ready` 와 달리 **유효화를 전제하지 않는다** — compDirty 로
    미유효화된 재키잉의 끝을 보는 자리다.
    """
    for _ in range(limit):
        await step(dut)
        if not int(dut.io_busy.value):
            return
    raise AssertionError("엔진이 끝나지 않았다 — 미완료는 통과가 아니다")


async def translate(dut, part, frame):
    """요청 1박 → 다음 엣지의 응답. 경로 무관 고정 1사이클."""
    dut.io_en.value = 1
    dut.io_req_valid.value = 1
    dut.io_req_part.value = part
    dut.io_req_frame.value = frame
    await step(dut)
    dut.io_req_valid.value = 0
    valid = int(dut.io_rsp_valid.value)
    got = int(dut.io_rsp_frame.value)
    assert valid == 1, "io_rsp_valid 가 요청 다음 엣지에 서지 않았다 (고정 1사이클 계약)"
    return got


async def clear_nonce_dup(dut):
    """`faultNonceDup` sticky 를 해제선으로 내리고 **내려갔음을 확인**한다."""
    dut.io_faultClearNonceDup.value = 1
    await step(dut)
    dut.io_faultClearNonceDup.value = 0
    await step(dut)
    assert int(dut.io_faultNonceDup.value) == 0, "해제선이 faultNonceDup sticky 를 내리지 못했다"


async def install(dut, key256, nonce192, part):
    """한 파티션에 (키, 논스) 를 앉히고 마스크 준비까지 간다. 키도 논스도
    `part` 로 간다 — 저장이 파티션별이다.

    ⚠ 키·논스 기입과 rekey 펄스 사이에 **≥1 유휴 엣지**를 둔다. 같은 엣지면
      dirty 다 (`MaskUnit.scala:501-502` 「rekeyFire && io.keyWr.part === io.rekey.part」)
      — FINAL 에서 maskValid 가 서지 않고 `faultWrDuringRekey` 가 뜬다 — 하네스가 스스로 fault 를
      만드는 자리다.
    """
    await write_key(dut, part, key256)
    await write_nonce(dut, part, nonce192)
    await step(dut)  # 유휴 1엣지
    await rekey(dut, part)
    return await wait_mask_ready(dut, part)


# ═══════════════════════════════════════════════════════════════════════════
# 테스트
# ═══════════════════════════════════════════════════════════════════════════

@cocotb.test()
async def sec1_golden_exact(dut):
    """SEC-1 — 벡터 80 라인 전수, golden 과 **정확 비교**. 파티션은 `i % 4`.

    회계: 읽은 라인 · 실제로 비교한 수 · 가족별 수 셋 다 대조한다. 그리고
    사영 뒤 판별력(서로 다른 maskFrame 수 / 서로 다른 자극점 수)을 인쇄한다 —
    「80 라인이니 80 자극점」이라는 오독을 매 실행 차단한다.

    `faultNonceDup` 도 매 라인 **등가**로 잰다. 키가 파티션별이라 install
    이 다른 파티션의 maskValid 를 건드리지 않으므로, 같은 논스를 다른
    파티션에 앉히는 라인(`pinned` 8줄 · `key_word` 쌍의 뒤 줄 등)에서 RTL
    E.9 2항 검사가 실제로 선다. 하네스 쪽 모델은 「maskValid 가 선 파티션 →
    그 논스」이고 기대값은 RTL 술어와 같은 형태 — 재키잉 수락 시점에
    maskValid 가 선 **다른** 파티션과 논스 전폭 일치
    (`MaskUnit.scala:365-367` 「(nonceFlat(q) === reqNonce)」 — 앞 두 항이 전건).
    기대가 1 이면 해제해 내리고 다음 라인으로 간다 — sticky 를 침묵 속에
    두고 가지 않는다. 기대 계산이 RTL 과 어긋나면 그것이 발견이지 우회 대상이
    아니다.
    """
    recs = load_vectors()
    await boot(dut)

    compared = 0
    per_family = {}
    valid_nonce = {}     # 모델: maskValid 가 선 파티션 → 그 파티션의 논스
    dup_lines = []       # faultNonceDup 이 (기대대로) 선 라인 번호
    for i, r in enumerate(recs):
        part = i % PARTS  # 파티션도 골고루 — 사영·저장이 파티션별인지 함께 본다
        # install 의 키·논스 기입이 이 파티션의 maskValid 를 먼저 떨어뜨린다
        # (모델도 같은 순서로 지운다). 수락 시점의 전건은 **다른** 유효 파티션.
        valid_nonce.pop(part, None)
        exp_dup = 1 if any(q != part and n == r["NONCE"]
                           for q, n in valid_nonce.items()) else 0
        await install(dut, r["KEY"], r["NONCE"], part)
        valid_nonce[part] = r["NONCE"]  # wait_mask_ready 가 유효화를 확인했다

        got_dup = int(dut.io_faultNonceDup.value)
        assert got_dup == exp_dup, (
            "라인 %d (%s, part=%d): io_faultNonceDup=%d ≠ 기대 %d — 모델(유효 "
            "파티션→논스 %s) 과 RTL E.9 2항 검사가 어긋난다"
            % (i, FAMILY_NAME[r["family"]], part, got_dup, exp_dup,
               {q: "%048x" % n for q, n in valid_nonce.items() if q != part}))
        if exp_dup:
            dup_lines.append(i)
            await clear_nonce_dup(dut)

        req = frame_of(r["PHYS"])
        exp = frame_of(r["MASKED"])          # 파일이 실은 값에서 유도
        got = await translate(dut, part, req)

        # ← 등가 비교 하나. 그것뿐이다.
        assert got == exp, (
            "라인 %d (%s, part=%d): io_rsp_frame 0x%08X ≠ golden MASKED[43:12] "
            "0x%08X (mask64=0x%016X · mask64[43:12]=0x%08X · req_frame=0x%08X)"
            % (i, FAMILY_NAME[r["family"]], part, got, exp,
               r["MASK"], frame_of(r["MASK"]), req))
        compared += 1
        per_family[r["family"]] = per_family.get(r["family"], 0) + 1

    assert compared == len(recs), f"비교 {compared} ≠ 라인 {len(recs)}"
    assert per_family == FAMILY_EXPECT, f"가족별 비교 {per_family} ≠ {FAMILY_EXPECT}"
    # 루프가 끝난 자리에 침묵하는 fault 가 없다 — 셋 다 0 과 등가.
    faults = (int(dut.io_faultNoMask.value), int(dut.io_faultNonceDup.value),
              int(dut.io_faultWrDuringRekey.value))
    assert faults == (0, 0, 0), (
        f"golden 루프 뒤 sticky (noMask, nonceDup, wrDuringRekey)={faults} ≠ (0,0,0) — "
        "루프가 만든 fault 를 보지 않고 지나왔다")
    # dup 이 선 라인이 0 이면 E.9 2항 축은 루프에서 공허하다 — 그것은 벡터
    # 구성(pinned 8줄이 같은 논스)에 반하므로 FAIL 이지 「통과」가 아니다.
    assert dup_lines, "golden 루프에서 faultNonceDup 이 한 번도 서지 않았다 — E.9 2항 축이 공허하다"

    distinct_mask = len({frame_of(r["MASK"]) for r in recs})
    distinct_stim = len({(r["KEY"], r["NONCE"], frame_of(r["PHYS"])) for r in recs})
    dut._log.info(
        f"SEC-1: {compared} 라인 정확 비교 통과 · 가족 {per_family} · "
        f"사영 뒤 서로 다른 maskFrame {distinct_mask}/{len(recs)} · "
        f"서로 다른 자극점 {distinct_stim}/{len(recs)} "
        f"(축소는 사영의 필연 — 판별력은 64비트가 아니라 {FRAME_W}비트) · "
        f"faultNonceDup 등가 대조 {compared}건 중 기대 1 이 {len(dup_lines)}건 "
        f"(라인 {dup_lines})")


@cocotb.test()
async def negative_control_comparison_is_live(dut):
    """음성 대조 — 「0건 불일치」가 「비교가 죽었다」와 구별되는가.

    이것이 없으면 위 80건 통과는 「일치했다」와 「관측이 상수를 읽는다」를
    구별하지 못한다. 두 축을 **각각 하나씩만 흔들어** 보인다:
      (a) **요청만** 흔든다 — 프레임에 delta 를 걸면 응답이 정확히 delta 만큼
          움직인다 (XOR 투명성. 등가 비교 두 개이고 `!=` 가 아니다).
      (b) **구성만** 흔든다 — 요청 프레임을 바이트 고정한 채 키·논스를 다른
          벡터의 것으로 갈면 응답이 그 벡터의 golden 마스크와 정확히 같아진다.
          「DUT 가 구성을 무시하고 요청을 되돌려준다」를 끊는 자리다.

    ⚠ 여기에 `assert got != (틀린 기대값)` 을 두지 않는다. `got == exp` 를
      이미 단언한 뒤라면 그것은 **항진이라 결코 실패할 수 없고**, 실패할 수
      없는 단언을 「술어가 살아 있다」로 읽는 것이 이 저장소가 이름한 공허한
      초록 그 자체다. 술어의 생존은 (a)·(b) 가 실측으로 잰다.
    """
    recs = load_vectors()
    r = recs[0]
    await boot(dut)
    await install(dut, r["KEY"], r["NONCE"], 0)

    req = frame_of(r["PHYS"])
    exp = frame_of(r["MASKED"])
    got = await translate(dut, 0, req)
    assert got == exp, f"기준점 불일치 0x{got:08X} ≠ 0x{exp:08X}"

    delta = 0x0000_0001
    got2 = await translate(dut, 0, req ^ delta)
    assert got2 == exp ^ delta, (
        f"XOR 투명성 위반: req^{delta:#x} 의 응답 0x{got2:08X} ≠ "
        f"0x{exp ^ delta:08X} — 관측면이 요청을 따라 움직이지 않는다")

    # (b) 구성만 흔든다 — 요청은 바이트 고정. 움직여야 하는 것은 마스크뿐이다.
    # 색인으로 고르지 않는다 — recs[1] 을 집으면 이 대조가 공허해진다 (`pinned`
    # 8줄은 사영 마스크가 같다; 실제로 그렇게 짰다가 걸렸다). `pick_distinct`.
    r2 = pick_distinct(recs, r)
    await install(dut, r2["KEY"], r2["NONCE"], 0)
    exp_b = req ^ frame_of(r2["MASK"])          # 같은 요청, 다른 구성의 golden
    got_b = await translate(dut, 0, req)        # ← 요청은 위와 바이트 동일
    assert got_b == exp_b, (
        f"요청을 고정하고 키·논스만 갈았는데 응답이 그 구성의 golden 과 다르다: "
        f"0x{got_b:08X} ≠ 0x{exp_b:08X} — 마스킹이 구성을 경유하지 않는다")
    dut._log.info(
        f"음성 대조: (a) 요청만 흔듦 → 응답이 정확히 delta 만큼 이동 · "
        f"(b) 요청 고정·구성만 갈아 응답이 새 golden 과 정확 일치 "
        f"(0x{frame_of(r['MASK']):08X} → 0x{frame_of(r2['MASK']):08X}). "
        f"두 축 모두 등가 비교이고 항진 단언은 없다")


@cocotb.test()
async def fixed_latency_path_invariant(dut):
    """경로 무관 고정 사이클 — 두 끝점을 **따로** 재고 상수를 못박는다.

    `MaskUnit.scala` 는 43(「총 43사이클」)과 42(「어떤 입력이든 42사이클
    동일」)를 둘 다 말하고 끝점 차이를 적지 않는다. 여기서 그 모호함을 닫는다. 서로 크게 다른 입력 셋이 **같은 수**를
    내야 한다 (데이터 의존 분기 부재). 다르면 FAIL — 「대충 비슷하다」는
    판정이 아니다.
    """
    recs = load_vectors()
    probes = [recs[0], recs[40], recs[41], recs[79]]  # pinned · edge 둘 · key_word
    seen_ready, seen_busy = set(), set()

    await boot(dut)
    for r in probes:
        await write_key(dut, 0, r["KEY"])
        await write_nonce(dut, 0, r["NONCE"])
        await step(dut)
        await rekey(dut, 0)
        # busy 는 rekey 수락 엣지 직후부터 관측된다.
        busy_cycles = 0
        ready_cycles = 0
        for c in range(1, 201):
            await step(dut)
            if int(dut.io_busy.value):
                busy_cycles += 1
            if (int(dut.io_maskReady.value) >> 0) & 1:
                ready_cycles = c
                break
        assert ready_cycles, "maskReady 미상승 — 미완료는 통과가 아니다"
        seen_ready.add(ready_cycles)
        seen_busy.add(busy_cycles)

    dut._log.info(
        f"고정 지연 실측: rekey 수락 엣지 이후 maskReady 까지 {sorted(seen_ready)} 엣지 · "
        f"io_busy 상승 {sorted(seen_busy)} 사이클 (입력 {len(probes)}종)")
    assert len(seen_ready) == 1 and len(seen_busy) == 1, (
        f"입력에 따라 사이클이 갈렸다 — ready {sorted(seen_ready)} · "
        f"busy {sorted(seen_busy)}. 경로 무관 고정 사이클 계약 위반")
    ready_n, busy_n = seen_ready.pop(), seen_busy.pop()
    assert ready_n == REKEY_TO_READY, (
        f"rekey 수락 엣지 **이후** maskReady 까지 = {ready_n} 엣지, 못박은 상수 "
        f"{REKEY_TO_READY}. 상수를 고치려면 끝점을 함께 적어라")
    assert busy_n == BUSY_HIGH, (
        f"io_busy 상승 = {busy_n} 사이클, 못박은 상수 {BUSY_HIGH}")
    assert ready_n + 1 == TOTAL_INCLUSIVE, (
        f"수락 엣지 포함 총계 {ready_n + 1} ≠ {TOTAL_INCLUSIVE}")
    dut._log.info(
        f"고정 지연 확정: 수락 엣지 **포함** 총 {TOTAL_INCLUSIVE}사이클 = "
        f"머리 주석 「총 43사이클」의 43 · 수락 엣지 **제외** {ready_n}엣지 · "
        f"io_busy 상승 {busy_n}사이클 = 「어떤 입력이든 42사이클 동일」의 42. "
        "정본이 두 숫자를 끝점 없이 말한 자리를 이 셋이 닫는다")


@cocotb.test()
async def en_is_the_single_stall_source(dut):
    """`io_en=0` 이면 응답이 얼어붙는다 — SEC-2 상태열 균일의 관측 지점.

    `MaskUnit.scala:528` 「when(io.en)」 이 rValid/rFrame 갱신의 유일한
    관문이다. 얼어붙음은 **직전 값과의 정확 일치**로 확인한다. 파티션 2 에
    앉힌다 — part≠0 이라 키 저장이 파티션별인지도 이 값 하나가 함께 잰다.
    """
    recs = load_vectors()
    r = recs[1]
    await boot(dut)
    await install(dut, r["KEY"], r["NONCE"], 2)

    exp = frame_of(r["MASKED"])
    got = await translate(dut, 2, frame_of(r["PHYS"]))
    assert got == exp, f"기준점 불일치 (part=2) 0x{got:08X} ≠ golden 0x{exp:08X}"

    dut.io_en.value = 0
    dut.io_req_valid.value = 1
    dut.io_req_frame.value = 0xDEAD_BEEF
    for c in range(5):
        await step(dut)
        assert int(dut.io_rsp_frame.value) == got, (
            f"en=0 인데 rsp_frame 이 움직였다 (엣지 {c}): "
            f"0x{int(dut.io_rsp_frame.value):08X} ≠ 0x{got:08X}")
        assert int(dut.io_rsp_valid.value) == 1, "en=0 인데 rsp_valid 가 움직였다"
    dut.io_req_valid.value = 0
    dut.io_en.value = 1
    dut._log.info("en 정지원: 5엣지 동안 rsp 가 직전 값과 비트 동일")


@cocotb.test()
async def fault_no_mask(dut):
    """미준비 파티션 통과 → `io_faultNoMask` sticky. 해제선으로만 내려간다.

    reset 직후 전 파티션이 미준비이므로 요청 하나로 발화한다. XOR 는
    무조건 수행되고 지연은 준비 여부와 무관하다 — 판정이 경로·시간을 가르지
    않는 것이 §5.3 이고, 그것도 함께 본다.

    *미준비 = 항등* 은 **reset 직후에만** 참이다(마스크 레지스터가 0):
    기입으로 무효화된 파티션은 옛 `maskFrame`
    을 그대로 XOR 하고 `faultNoMask` 로만 관측된다(실측 2026-09-22). 이 시험은
    reset 경우만 잰다.
    """
    await boot(dut)
    assert int(dut.io_faultNoMask.value) == 0

    got = await translate(dut, 1, 0x1234_5678)
    assert got == 0x1234_5678, (
        f"미준비 마스크가 항등이 아니다: 0x{got:08X} — reset 값 0 마스크 계약 위반")
    assert int(dut.io_faultNoMask.value) == 1, (
        "미준비 파티션 통과인데 faultNoMask 가 서지 않았다 (loud-fault-never-silent)")

    # sticky — 해제 없이 여러 엣지 지나도 유지된다.
    dut.io_req_valid.value = 0
    await step(dut, 5)
    assert int(dut.io_faultNoMask.value) == 1, "sticky 가 저절로 내려갔다"

    dut.io_faultClearNoMask.value = 1
    await step(dut)
    dut.io_faultClearNoMask.value = 0
    await step(dut)
    assert int(dut.io_faultNoMask.value) == 0, "해제선이 sticky 를 내리지 못했다"
    dut._log.info("faultNoMask: 발화 · sticky 유지 · 명시 해제 확인")


@cocotb.test()
async def fault_wr_during_rekey(dut):
    """계산 중 **같은 파티션** 입력 기입 → 결과를 유효화하지 않는다 (E.9 4항 혼합 금지).

    `MaskUnit.scala:501-502` 「compDirty := True」 가 FINAL 에서 `maskValid` 를
    막고 `faultWrDuringRekey` 를 세운다. **두 관측이 모두 필요하다** — fault 만
    보면 「fault 는 떴는데 마스크는 유효」인 창을 못 잡는다.
    짝은 `wr_other_partition_during_rekey_is_clean` — 다른 파티션 기입은
    사정권 밖이라 유효화되고 fault 도 없다.
    """
    recs = load_vectors()
    r = recs[2]
    await boot(dut)
    await write_key(dut, 0, r["KEY"])
    await write_nonce(dut, 0, r["NONCE"])
    await step(dut)
    await rekey(dut, 0)

    # 계산 중(HROUND 어딘가)에 **같은 파티션**의 키 워드 하나를 덮어쓴다.
    await step(dut, 5)
    assert int(dut.io_busy.value) == 1, "기입 시점에 엔진이 가동 중이 아니다 — 자극이 계약 밖"
    await write_key_word(dut, 0, 3, 0xA5A5_A5A5)

    await wait_engine_idle(dut)
    assert (int(dut.io_maskReady.value) >> 0) & 1 == 0, (
        "혼합 입력 재키잉의 결과가 유효화됐다 — 옛 키 마스크를 쓰는 창이 열린다")
    assert int(dut.io_faultWrDuringRekey.value) == 1, (
        "혼합 입력인데 faultWrDuringRekey 가 서지 않았다")

    dut.io_faultClearWrRekey.value = 1
    await step(dut)
    dut.io_faultClearWrRekey.value = 0
    await step(dut)
    assert int(dut.io_faultWrDuringRekey.value) == 0
    dut._log.info("faultWrDuringRekey: 미유효화 + 발화 + 해제 확인")


@cocotb.test()
async def wr_other_partition_during_rekey_is_clean(dut):
    """계산 중 **다른 파티션** 기입 → 결과는 유효하고 fault 도 없다 (E.9 4항의 범위).

    `fault_wr_during_rekey` 의 짝. `compDirty` 의 파티션 한정
    (`MaskUnit.scala:501-502` 「engineBusy && io.keyWr.part === actPart」) 이
    없으면 — 기입이 파티션과 무관하게 가동 중이면 dirty 라면 — part 3 의 키
    워드 하나가 part 0 의 재키잉을 미유효화한다. 세 관측을 **모두** 등가로
    본다: maskReady 전폭이 정확히 part 0 하나 · faultWrDuringRekey == 0 ·
    part 0 translate 가 golden 과 일치 (혼합 마스크가 아니다 — E.9 4항,
    `e-defined.typ:1526` 「다른 파티션이 그 변경의 사정권 밖」).
    """
    recs = load_vectors()
    r = recs[5]
    await boot(dut)
    await write_key(dut, 0, r["KEY"])
    await write_nonce(dut, 0, r["NONCE"])
    await step(dut)
    await rekey(dut, 0)

    # 계산 중(HROUND 어딘가)에 **part 3** 의 키 워드 하나를 쓴다.
    await step(dut, 5)
    assert int(dut.io_busy.value) == 1, "기입 시점에 엔진이 가동 중이 아니다 — 자극이 계약 밖"
    await write_key_word(dut, 3, 3, 0xA5A5_A5A5)

    await wait_engine_idle(dut)
    ready = int(dut.io_maskReady.value)
    assert ready == 0b0001, (
        f"maskReady={ready:#06b} ≠ 0b0001 — part 0 재키잉이 다른 파티션 기입에 "
        "미유효화됐거나(bit0=0) part 3 이 재키잉 없이 유효해졌다(bit3=1)")
    assert int(dut.io_faultWrDuringRekey.value) == 0, (
        "다른 파티션 기입인데 faultWrDuringRekey 가 섰다 — compDirty 가 파티션 한정이 아니다")
    got = await translate(dut, 0, frame_of(r["PHYS"]))
    exp = frame_of(r["MASKED"])
    assert got == exp, (
        f"part 0 translate 0x{got:08X} ≠ golden 0x{exp:08X} — 다른 파티션 기입이 "
        "part 0 의 마스크에 섞였다")
    dut._log.info(
        "다른 파티션 기입 during rekey: maskReady=0b0001 · faultWrDuringRekey=0 · "
        "part 0 값 golden 일치 — 사정권 밖 확인")


@cocotb.test()
async def wr_same_partition_at_final_edge_is_loud(dut):
    """수락 엣지 기준 오프셋 N ≥ 1 의 **같은 파티션** 기입 — fault ⇔ 그 기입이
    busy 사이클에 실렸다 (FINAL 사이클 **포함**). 파도 D (2026-09-22) 의 지향
    시험. 수락 사이클 자체(N=0)의 같은-파티션 기입도 오염이지만 그때는 busy=0
    이라 이 쌍조건 밖이다 — 그 면은 후-formal engine.sby 의 f_dirty 갈래 (i)
    와 증인 W8 이 잰다(이 파일은 N=0 점을 두지 않는다 — 재지 않는 축).

    정본: `e-defined.typ:518` 「재키잉 중 입력 기입」 (FAULT_STATUS [13] — 시점
    예외 없음) · `e-defined.typ:1549` 「재계산 중(`0xEC0` `[8]`)」 — 「재키잉
    중」의 정의역은 장치 자신의 관측 busy=1 이다 · `e-defined.typ:1544` 「그 파티션 비트가 설 때까지 기다린다」
    — 호스트의 완료 관측. 파도 D 이전 판(1666c7a)은 수락+42 엣지(FINAL
    사이클)의 활성 파티션 기입에 유효만 떨어뜨리고 fault 가 침묵해 그 기다림이
    어떤 비트도 없이 무한이었다 — 수락+40·+41 은 fault 1 이라 같은 호스트
    행위가 1사이클 타이밍에 두 판정을 받았다. 지금은 FINAL 가지가 같은
    사이클 항을 직접 본다 (`MaskUnit.scala:473` 「val dirtyNow = compDirty || wrActNow」).

    사이클 표 (rekey() 가 수락 엣지 E0 를 소비한다): E0 수락 → E20 HEXTRACT →
    E21 CROUND → E41 뒤 phase=FINAL (busy=1 · ready=0) → E42 IDLE·유효화.
    오프셋 N 의 기입은 엣지 E_N 에 래치된다 — busy 는 기입 **직전** 표본이고
    io_busy 는 레지스터만의 함수라 그 표본이 정확하다
    (`MaskUnit.scala:342` 「private val engineBusy = phase =/= PH_IDLE」).
      N=40·41: compDirty 가 FINAL 사이클에 이미 1 — 파도 D 이전에도 fault.
      N=42:    FINAL 사이클 자체의 기입 — **파도 D 가 세운 자리** (wrActNow).
      N=43·44: 유휴 기입 — fault 0. 유효는 기입이 떨어뜨린 0 인데, 기입 **전**
               maskReady[p]==1 을 등가로 단언해 「FINAL 이 유효화한 적 없는」
               변이가 통과하지 못하게 한다.
    판정은 전부 등가다: fault == busy_seen · 기입 전 maskReady[p] == !busy_seen
    · 기입 뒤 maskReady[p] == 0 · 해제 뒤 fault == 0. busy_seen 자체도 상수
    표(N <= REKEY_TO_READY)와 등가라 지연 상수가 바뀌면 여기서 죽는다.
    논스 변형: N=42 idx=5 (fault 1) + 음성 대조 N=42 idx=6 (예약 오프셋 —
    RTL 이 무시한다: fault 0 · maskReady[p]==1). sticky 는 케이스마다 해제해
    0 을 확인한다 — 42 의 fault 가 43 으로 새어 등가 판정을 흐리지 않는다.
    타 파티션 대조: N=42 에 q≠p 키 기입 — 같은 사이클 항 wrActNow 도 활성
    파티션 한정이다(MaskEngine.dirty_scoped 의 FINAL 사이클 판): (busy_seen,
    fault, maskReady[p], maskReady[q]) == (1, 0, 1, 0) 이고 p 의 값은 golden.
    변이 실측(2026-09-22, 사본 생성물에서 wrActNow 의 파티션 비교를 뗀
    mutScope): 앞의 다섯 케이스와 논스 둘은 전부 통과하고 이 케이스만 죽는다
    — 이 케이스가 없던 동안 그 축은 오라클에 한 점도 없이 태어나 있었다.
    """
    recs = load_vectors()
    r = recs[6]
    p = 1

    async def one_case(label, n, do_write):
        # 매 케이스 새 재키잉 — 키·논스 기입(유효 하강) → 유휴 1엣지 → 수락 E0.
        await write_key(dut, p, r["KEY"])
        await write_nonce(dut, p, r["NONCE"])
        await step(dut)
        await rekey(dut, p)
        await step(dut, n - 1)                       # E_(n-1) 뒤
        busy_seen = int(dut.io_busy.value)
        exp_busy = 1 if n <= REKEY_TO_READY else 0
        assert busy_seen == exp_busy, (
            f"[{label}] 기입 직전 io_busy={busy_seen} ≠ 상수 표 {exp_busy} — "
            f"오프셋 {n} 이 busy 창({REKEY_TO_READY}) 과 어긋난다: 자극이 계약 밖")
        ready_before = (int(dut.io_maskReady.value) >> p) & 1
        assert ready_before == 1 - busy_seen, (
            f"[{label}] 기입 전 maskReady[{p}]={ready_before} ≠ {1 - busy_seen} — "
            "busy 중 유효(혼합 창) 또는 유휴인데 FINAL 이 유효화하지 않았다")
        await do_write()                             # E_n 에 래치
        await wait_engine_idle(dut)
        fault = int(dut.io_faultWrDuringRekey.value)
        ready_after = (int(dut.io_maskReady.value) >> p) & 1
        return busy_seen, fault, ready_after

    await boot(dut)
    table = []
    for n in (40, 41, 42, 43, 44):
        label = f"key N={n}"
        busy_seen, fault, ready_after = await one_case(
            label, n, lambda: write_key_word(dut, p, 3, 0xA5A5_A5A5))
        assert fault == busy_seen, (
            f"[{label}] io_faultWrDuringRekey={fault} ≠ busy_seen={busy_seen} — "
            "재키잉 중(busy=1) 기입인데 fault 가 침묵했거나, 유휴 기입에 fault 가 섰다 "
            "(판정이 시간을 갈랐다)")
        assert ready_after == 0, (
            f"[{label}] 기입 뒤 maskReady[{p}]={ready_after} ≠ 0 — 기입이 유효를 "
            "떨어뜨리지 않았다 (invalidate_beats_validate)")
        await clear_wr_rekey(dut)
        table.append((n, fault))
    assert table == [(40, 1), (41, 1), (42, 1), (43, 0), (44, 0)], (
        f"오프셋별 fault 표 {table} ≠ [(40,1),(41,1),(42,1),(43,0),(44,0)]")

    # 논스 변형 — N=42 idx=5: FINAL 사이클의 논스 기입도 같은 항이다.
    busy_seen, fault, ready_after = await one_case(
        "nonce N=42 idx=5", 42, lambda: write_nonce_word(dut, p, 5, 0x5A5A_5A5A))
    assert (busy_seen, fault, ready_after) == (1, 1, 0), (
        f"[nonce N=42 idx=5] (busy_seen, fault, ready_after)={(busy_seen, fault, ready_after)} "
        "≠ (1, 1, 0) — FINAL 사이클의 논스 기입이 키 기입과 동형이 아니다")
    await clear_wr_rekey(dut)

    # 음성 대조 — N=42 idx=6: 예약 오프셋은 RTL 이 무시한다 → 깨끗한 완료.
    busy_seen, fault, ready_after = await one_case(
        "nonce N=42 idx=6 (예약)", 42, lambda: write_nonce_word(dut, p, 6, 0x5A5A_5A5A))
    assert (busy_seen, fault, ready_after) == (1, 0, 1), (
        f"[nonce N=42 idx=6] (busy_seen, fault, ready_after)={(busy_seen, fault, ready_after)} "
        "≠ (1, 0, 1) — 예약 오프셋 기입이 무시되지 않았다(fault 또는 무효화)")

    # 타 파티션 대조 — N=42 에 q≠p 키 기입. FINAL 사이클의 같은-사이클 항
    # (wrActNow)도 활성 파티션 한정이다: p 의 완료는 깨끗하고(유효화·fault 0),
    # q 는 기입이 유효를 떨어뜨린 0 (설치한 적 없어 원래 0) 이며 p 의 값은 golden.
    q = 2
    busy_seen, fault, ready_after = await one_case(
        "key N=42 other part", 42, lambda: write_key_word(dut, q, 3, 0xA5A5_A5A5))
    ready_q = (int(dut.io_maskReady.value) >> q) & 1
    assert (busy_seen, fault, ready_after, ready_q) == (1, 0, 1, 0), (
        f"[key N=42 other part] (busy_seen, fault, ready[p], ready[q])="
        f"{(busy_seen, fault, ready_after, ready_q)} ≠ (1, 0, 1, 0) — FINAL 사이클의 "
        "타 파티션 기입이 활성 파티션의 완료를 더럽혔다(사정권 밖이어야 한다)")
    got = await translate(dut, p, frame_of(r["PHYS"]))
    assert got == frame_of(r["MASKED"]), (
        f"[key N=42 other part] part {p} 0x{got:08X} ≠ golden 0x{frame_of(r['MASKED']):08X}")

    faults = (int(dut.io_faultNoMask.value), int(dut.io_faultNonceDup.value),
              int(dut.io_faultWrDuringRekey.value))
    assert faults == (0, 0, 0), f"sticky (noMask, nonceDup, wrDuringRekey)={faults} ≠ (0,0,0)"
    dut._log.info(
        f"FINAL 엣지 동시 기입: 오프셋별 (N, fault) {table} — fault == 기입 직전 io_busy "
        "전 케이스 등가 · 기입 뒤 maskReady[p]==0 · 논스 idx=5 동형 · idx=6 예약 무시 "
        "(fault 0 · maskReady 1) · 타 파티션 N=42 기입은 사정권 밖 (1,0,1,0) + golden. "
        "판정은 전부 등가 비교")


@cocotb.test()
async def key_scope_cross_partition_value(dut):
    """키의 범위 — 임대(파티션)마다 다르다. 제어면 증명을 **값 수준**에서 잰다.

    정본 `05-security.typ:112` 「키의 범위 — 임대마다 다르다」. 후-formal
    (HiuMask: key_scoped_storage · key_write_own_only) 은 저장과 무효화 범위를
    제어면에서 증명했고, 여기는 그 결과가 **golden 값**으로 나타나는지를 본다:
      1. 키 A·논스 a 를 part 1, 키 B·논스 b 를 part 2 에 각각 자기 파티션으로
         install → 각 파티션 translate 가 자기 golden 과 일치. 논스가 다르므로
         faultNonceDup == 0 (등가).
      2. part 1 의 키만 C 로 다시 쓴다 (재키잉 없이) → maskReady 전폭이 정확히
         0b0100: part 1 만 무효 (`MaskUnit.scala:494` 「maskValid(io.keyWr.part) := False」),
         part 2 는 그대로 유효. part 2 translate 는 여전히 golden B.
      3. part 1 에 논스 c 를 쓰고 재키잉 → part 1 translate 가 golden C 와 일치,
         part 2 는 여전히 golden B, maskReady == 0b0110. 키 C 가 part 1 에만
         앉았다는 것을 값이 말한다 (part 2 에 샜으면 B 가 깨진다).
    벡터 A·B·C 는 사영 뒤 마스크가 서로 다른 것으로 **찾아서** 쓴다.
    """
    recs = load_vectors()
    ra = recs[0]
    rb = pick_distinct(recs, ra)
    rc = pick_distinct(recs, ra, rb)
    assert ra["NONCE"] != rb["NONCE"] and rb["NONCE"] != rc["NONCE"], (
        "골라 쓴 벡터의 논스가 같다 — faultNonceDup 이 값 대조를 흐린다. "
        "(이 `!=` 는 판정이 아니라 자극 선택의 파이썬 쪽 확인이다)")
    req_a, exp_a = frame_of(ra["PHYS"]), frame_of(ra["MASKED"])
    req_b, exp_b = frame_of(rb["PHYS"]), frame_of(rb["MASKED"])
    req_c, exp_c = frame_of(rc["PHYS"]), frame_of(rc["MASKED"])

    await boot(dut)
    # 1. 두 파티션에 각각 자기 키·논스.
    await install(dut, ra["KEY"], ra["NONCE"], 1)
    await install(dut, rb["KEY"], rb["NONCE"], 2)
    assert int(dut.io_faultNonceDup.value) == 0, "논스가 다른데 faultNonceDup 이 섰다"
    assert int(dut.io_maskReady.value) == 0b0110, (
        f"maskReady={int(dut.io_maskReady.value):#06b} ≠ 0b0110")
    got_a = await translate(dut, 1, req_a)
    assert got_a == exp_a, f"part 1 (키 A) 0x{got_a:08X} ≠ golden A 0x{exp_a:08X}"
    got_b = await translate(dut, 2, req_b)
    assert got_b == exp_b, f"part 2 (키 B) 0x{got_b:08X} ≠ golden B 0x{exp_b:08X}"

    # 2. part 1 의 키만 C 로 — 재키잉 없이. part 2 는 사정권 밖이어야 한다.
    await write_key(dut, 1, rc["KEY"])
    await step(dut)
    ready = int(dut.io_maskReady.value)
    assert ready == 0b0100, (
        f"part 1 키 기입 뒤 maskReady={ready:#06b} ≠ 0b0100 — "
        "part 1 이 무효화되지 않았거나(bit1=1) part 2 가 함께 무효화됐다(bit2=0)")
    got_b2 = await translate(dut, 2, req_b)
    assert got_b2 == exp_b, (
        f"part 1 키를 갈았는데 part 2 값이 변했다: 0x{got_b2:08X} ≠ golden B 0x{exp_b:08X}")

    # 3. part 1 을 (C, c) 로 재키잉 — 키 C 가 part 1 에만 앉았음을 값으로.
    await write_nonce(dut, 1, rc["NONCE"])
    await step(dut)
    await rekey(dut, 1)
    n = await wait_mask_ready(dut, 1)
    assert n == REKEY_TO_READY, f"재키잉 지연 {n} ≠ {REKEY_TO_READY}"
    assert int(dut.io_maskReady.value) == 0b0110, (
        f"maskReady={int(dut.io_maskReady.value):#06b} ≠ 0b0110")
    got_c = await translate(dut, 1, req_c)
    assert got_c == exp_c, f"part 1 (키 C) 0x{got_c:08X} ≠ golden C 0x{exp_c:08X}"
    got_b3 = await translate(dut, 2, req_b)
    assert got_b3 == exp_b, (
        f"part 1 재키잉 뒤 part 2 값이 변했다: 0x{got_b3:08X} ≠ golden B 0x{exp_b:08X}")
    faults = (int(dut.io_faultNoMask.value), int(dut.io_faultNonceDup.value),
              int(dut.io_faultWrDuringRekey.value))
    assert faults == (0, 0, 0), f"sticky (noMask, nonceDup, wrDuringRekey)={faults} ≠ (0,0,0)"
    dut._log.info(
        f"키 범위: part1=A(0x{exp_a:08X}) · part2=B(0x{exp_b:08X}) 각자 golden → "
        f"part1 키만 C 로 갈아 maskReady 0b0100 · part2 값 불변 → part1 재키잉 뒤 "
        f"C(0x{exp_c:08X}) · part2 여전히 B. 셋 다 등가 비교")


@cocotb.test()
async def fault_nonce_dup(dut):
    """논스 재사용 재키잉 → `io_faultNonceDup` (E.9 2항) — directed 최소형.

    golden 루프(`sec1_golden_exact`)도 매 라인 이 fault 를 등가로 재지만, 거기서
    는 키·논스·파티션이 벡터 순서로 얽혀 있다. 여기서는 전건 하나만 만든다 —
    part 0 유효, part 1 에 **같은 논스** (키는 part 1 에 다시 쓰지 않는다;
    쓰더라도 part 0 은 사정권 밖이라 전건은 살지만, 자극을 하나로 둔다).
    검사가 사이클을 가르지 않음(부채널)도 함께 본다.

    그리고 계약의 사각지대를 함께 적는다: `maskValid` 가 서지 않은 파티션과의
    논스 중복은 **검사되지 않는다** (`MaskUnit.scala:365-367` 「maskValid(q) &&」).
    그것은 하네스의 누락이 아니라 RTL 계약의 범위다 — 우회로 「해결」하지 않는다.
    """
    recs = load_vectors()
    r = recs[3]
    await boot(dut)

    await install(dut, r["KEY"], r["NONCE"], 0)   # part0 유효
    assert int(dut.io_faultNonceDup.value) == 0

    await write_nonce(dut, 1, r["NONCE"])
    await step(dut)
    await rekey(dut, 1)
    assert int(dut.io_faultNonceDup.value) == 1, (
        "유효한 타 파티션과 논스 전폭이 같은데 faultNonceDup 이 서지 않았다 — "
        "같은 키스트림 재사용이고 그것은 마스킹이 아니다")

    # 계산은 계속한다 — 판정이 경로·시간을 가르지 않는다 (처분은 호스트 몫).
    n = await wait_mask_ready(dut, 1)
    assert n == REKEY_TO_READY, (
        f"dup 이 사이클을 갈랐다: {n} ≠ {REKEY_TO_READY} — 판정이 시간을 가르면 "
        "부채널이다")

    await clear_nonce_dup(dut)
    dut._log.info(
        "faultNonceDup: 발화 + 사이클 불변 + 해제 확인. "
        "사각지대(미유효 파티션과의 중복)는 RTL 계약의 범위이지 이 하네스의 누락이 아니다")


@cocotb.test()
async def rekey_backpressure_is_loud(dut):
    """엔진 가동 중 재키잉은 **ready 하강으로 관측된다** — 무언 드롭이 아니다.

    조용한 드롭 금지의 이 유닛 쪽 이행. 가동 중 `io_rekey_ready` 가 0 이고,
    그 상태로 쏜 펄스가 다른 파티션을 유효화하지 않음을 함께 본다.
    """
    recs = load_vectors()
    r = recs[4]
    await boot(dut)
    await write_key(dut, 0, r["KEY"])
    await write_nonce(dut, 0, r["NONCE"])
    await write_nonce(dut, 3, r["NONCE"] ^ 0xFFFF)
    await step(dut)
    await rekey(dut, 0)

    await step(dut, 3)
    assert int(dut.io_busy.value) == 1
    # 가동 중 — ready 는 0 이어야 하고, 이 펄스는 수락되지 않아야 한다.
    await rekey(dut, 3, expect_accept=False)

    n = await wait_mask_ready(dut, 0)
    assert n <= REKEY_TO_READY, "첫 재키잉이 방해받았다"
    assert (int(dut.io_maskReady.value) >> 3) & 1 == 0, (
        "ready=0 에서 쏜 재키잉이 조용히 수락됐다 — 미수락은 ready 로만 관측되는 "
        "것이 계약이다")
    dut._log.info("재키잉 배압: ready 하강으로 관측 · 미수락 펄스가 효과 0")
