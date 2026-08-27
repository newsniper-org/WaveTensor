# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""test_mask_golden.py — SEC-1 주소 마스킹의 golden 정확 대조 (MaskUnit 단독).

DUT 는 `rtl/generated/MaskUnit.sv` — 합성 형상 그대로다. MMIO 는 이 형상에
없다 (그것은 `Wt64Top` 의 `0xE80`–`0xEC0` 구역이다); 여기서는 소박한 워드
기입 포트를 직접 때린다.

═══════════════════════════════════════════════════════════════════════════
## 대조식 — 한 줄로 닫힌다
═══════════════════════════════════════════════════════════════════════════

`XlateStore.scala:60-70` 이 `PA_W=44` · `PAGE_W=12` · `FRAME_W=32` 를 정하고,
E.9 3항(마스크는 페이지 프레임 부분에만)에 따라 적용 슬라이스가
`mask64[PAGE_W+FRAME_W-1 : PAGE_W]` = `mask64[43:12]` 다.

`MaskUnit.scala:416-426`:
    when(io.en) { rValid := io.req.valid
                  rFrame := io.req.frame ^ maskFrame(io.req.part) }

⇒  io_rsp_frame  ==  io_req_frame ^ (mask64 >> 12) & 0xFFFFFFFF

RTL 은 64비트 마스크를 레지스터에 두지 않는다 (`MaskUnit.scala:219-226`).
`PH_FINAL`(:350-371)이 그 32비트만 상수 분해로 직접 만든다 — 생성물
`MaskUnit.sv:263-266` 에서 상수 셋(`12'h79b` · `20'h61707` · `12'h46e`)을
대조 확인했다. 이 사영은 **정보 손실이 없다** (벡터 전 라인에서
`(PHYS[43:12] ^ mask64[43:12]) == MASKED[43:12]` 성립 — 아래 회계가 매
실행 재확인한다).

═══════════════════════════════════════════════════════════════════════════
## 금지형 — 정본 §5.2.4 함정의 직접 이행
═══════════════════════════════════════════════════════════════════════════

「확산은 세어서 확인할 수 없다. `!=` 검사는 무의미하다 — **틀린 값도
다르다.**」 그 규율의 수신인이 이 파일이다 (`MaskUnit.scala:74-79` 가
명시한다). 이 파일에 다음은 **한 곳도 없다**:

    assert got != legacy          # 틀린 값도 다르다
    assert popcount(a ^ b) > k    # 확산 세기
    assert 0.4 < hamming/32 < 0.6 # 통계
    if got != exp: warn(...)      # 경고는 판정이 아니다

있는 것은 golden 이 낸 그 32비트와의 **등가 비교 하나**뿐이다.
`nonce_tail`·`key_word` 가족의 「회귀 검출기」 성격은 *그 벡터가 폐기
알고리즘을 골라내도록 golden 이 구성됐다*는 뜻이지 이 하네스가 통계를
잰다는 뜻이 아니다 — 검출은 golden 값과의 정확 비교가 한다.

fault 는 **`io_fault*` 실포트로만** 관측한다. 시뮬 전용 단언으로 fault 를
구현하지 않는다 — 합성 결과물에 그 검사가 없기 때문이다.

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
   (`MaskUnit.scala:336`), ROUNDS 는 Scala 상수(:123)로 SV 파라미터가 아니다.
   다중 블록 키스트림·축소 라운드 교차대조는 이 기계에 대상이 없다.
5. **재키잉↔flush 결합(E.9 4항)은 잴 수 없다** — flush 동반은 호스트 ABI
   의무(§3.10)로 명시 위임돼 있고 RTL 에 강제 배선이 없다. 이 파일이 재는
   것은 「옛/새 입력 혼합 금지」(compDirty → faultWrDuringRekey)뿐이다.
6. **`faultNonceDup` 의 사각지대는 RTL 계약 자체에 있다** —
   `maskValid` 가 서지 않은 파티션과의 논스 중복은 검사되지 않는다
   (`MaskUnit.scala:286-289`). 하네스가 이것을 우회로 「해결」하지 않고
   계약의 범위로 적는다. 그리고 아래 golden 루프는 매 벡터 키를 다시 쓰므로
   `maskValid` 가 전부 0 이라 dup 검사가 **공허하게 거짓**이다 — 그래서 dup
   축은 별도 directed 케이스(`fault_nonce_dup`)로만 선다.
7. **부채널·상수 시간성은 대상 밖** — 여기서 보는 것은 사이클 수 동일성뿐
   이다 (게이트 지연·전력·EM 아님).
"""

import os
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
# :103 「총 43사이클 (수락 1 + 유도 20 + 재구성 1 + 본 라운드 20 + 최종 덧셈
# 1)」, :258 「어떤 입력이든 42사이클 동일」. 어느 쪽이 맞느냐가 아니라 **둘
# 다 맞고 끝점이 다르다** — 그 사실이 문면에 없어서 다음 사람이 하나를 오타로
# 읽는다. 아래 셋이 그 자리를 닫는다 (전부 실측으로 확정):
#
#   TOTAL_INCLUSIVE  43  수락 엣지를 **포함**한 총 사이클 (= :103 의 43)
#   REKEY_TO_READY   42  수락 엣지 **이후** maskReady[part] 관측까지의 엣지 수
#   BUSY_HIGH        41  io_busy 가 1 로 관측되는 사이클 수 (FINAL 엣지에서
#                        phase→IDLE 이므로 관측 표본 하나가 빠진다)
TOTAL_INCLUSIVE = 43
REKEY_TO_READY = 42
BUSY_HIGH = 41

CLK_NS = 4
SETTLE_NS = 1  # 엣지 뒤 관측 시점 — 다음 엣지까지 3ns 여유

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


# ═══════════════════════════════════════════════════════════════════════════
# DUT 구동 원시 연산
# ═══════════════════════════════════════════════════════════════════════════

INPUTS = [
    "io_keyWr_valid", "io_keyWr_idx", "io_keyWr_data",
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


async def boot(dut):
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


async def write_key(dut, key256):
    """키 8워드 기입. word n = KEY[32n+31:32n] (`MaskUnit.scala:216`).

    ⚠ 키 기입은 **전 파티션**의 maskValid 를 떨어뜨린다 (`:387`).
    """
    for n in range(8):
        dut.io_keyWr_valid.value = 1
        dut.io_keyWr_idx.value = n
        dut.io_keyWr_data.value = (key256 >> (32 * n)) & 0xFFFFFFFF
        await step(dut)
    dut.io_keyWr_valid.value = 0


async def write_nonce(dut, part, nonce192):
    """논스 6워드 기입. word i = NONCE[32i+31:32i]. idx 6·7 은 무시된다."""
    for i in range(6):
        dut.io_nonceWr_valid.value = 1
        dut.io_nonceWr_part.value = part
        dut.io_nonceWr_idx.value = i
        dut.io_nonceWr_data.value = (nonce192 >> (32 * i)) & 0xFFFFFFFF
        await step(dut)
    dut.io_nonceWr_valid.value = 0


async def rekey(dut, part, expect_accept=True):
    """재키잉 펄스. **`io_rekey_ready` 를 같은 엣지에서 확인한다.**

    `ready = !busy` (`MaskUnit.scala:274`) 이고 미수락은 무언 드롭이 아니라
    ready 하강으로 관측되는 것이 계약이다. ready 를 안 보고 쏘면 **하네스가
    스스로 조용한 드롭을 만든다.**
    """
    dut.io_rekey_valid.value = 1
    dut.io_rekey_part.value = part
    # `io_rekey_ready = !engineBusy` (`MaskUnit.sv:348`) 는 레지스터만의 함수라
    # 방금 쓴 입력에 의존하지 않는다 — 델타 없이 지금 값이 이 엣지의 값이다.
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


async def install(dut, key256, nonce192, part):
    """한 파티션에 (키, 논스) 를 앉히고 마스크 준비까지 간다.

    ⚠ 키·논스 기입과 rekey 펄스 사이에 **≥1 유휴 엣지**를 둔다. 같은 엣지면
      `compDirty := True` (`MaskUnit.scala:392`) 라 FINAL 에서 maskValid 가
      서지 않고 `faultWrDuringRekey` 가 뜬다 — 하네스가 스스로 fault 를 만드는
      자리다.
    """
    await write_key(dut, key256)
    await write_nonce(dut, part, nonce192)
    await step(dut)  # 유휴 1엣지
    await rekey(dut, part)
    return await wait_mask_ready(dut, part)


# ═══════════════════════════════════════════════════════════════════════════
# 테스트
# ═══════════════════════════════════════════════════════════════════════════

@cocotb.test()
async def sec1_golden_exact(dut):
    """SEC-1 — 벡터 80 라인 전수, golden 과 **정확 비교**.

    회계: 읽은 라인 · 실제로 비교한 수 · 가족별 수 셋 다 대조한다. 그리고
    사영 뒤 판별력(서로 다른 maskFrame 수 / 서로 다른 자극점 수)을 인쇄한다 —
    「80 라인이니 80 자극점」이라는 오독을 매 실행 차단한다.
    """
    recs = load_vectors()
    await boot(dut)

    compared = 0
    per_family = {}
    for i, r in enumerate(recs):
        part = i % 4  # 파티션도 골고루 — 사영·저장이 파티션별인지 함께 본다
        await install(dut, r["KEY"], r["NONCE"], part)

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

    distinct_mask = len({frame_of(r["MASK"]) for r in recs})
    distinct_stim = len({(r["KEY"], r["NONCE"], frame_of(r["PHYS"])) for r in recs})
    dut._log.info(
        f"SEC-1: {compared} 라인 정확 비교 통과 · 가족 {per_family} · "
        f"사영 뒤 서로 다른 maskFrame {distinct_mask}/{len(recs)} · "
        f"서로 다른 자극점 {distinct_stim}/{len(recs)} "
        f"(축소는 사영의 필연 — 판별력은 64비트가 아니라 {FRAME_W}비트)")


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
    # 색인으로 고르지 않는다 — `pinned` 8줄은 키·논스가 같아 **사영 마스크가
    # 같다** (그래서 서로 다른 maskFrame 이 73/80 이다). recs[1] 을 집으면 이
    # 대조가 공허해진다; 실제로 그렇게 짰다가 아래 단언에 걸렸다. 사영 뒤
    # 실제로 다른 첫 벡터를 **찾아서** 쓴다.
    r2 = next((x for x in recs if frame_of(x["MASK"]) != frame_of(r["MASK"])), None)
    assert r2 is not None, (
        "사영 마스크가 전부 같다 — 구성 축 음성 대조가 공허해진다. "
        "(이 `!=` 는 판정이 아니라 **자극이 비공허함**의 파이썬 쪽 확인이다)")
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

    `MaskUnit.scala` 는 43(:103)과 42(:258)를 둘 다 말하고 끝점 차이를 적지
    않는다. 여기서 그 모호함을 닫는다. 서로 크게 다른 입력 셋이 **같은 수**를
    내야 한다 (데이터 의존 분기 부재). 다르면 FAIL — 「대충 비슷하다」는
    판정이 아니다.
    """
    recs = load_vectors()
    probes = [recs[0], recs[40], recs[41], recs[79]]  # pinned · edge 둘 · key_word
    seen_ready, seen_busy = set(), set()

    await boot(dut)
    for r in probes:
        await write_key(dut, r["KEY"])
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
        f"머리 주석 :103 의 43 · 수락 엣지 **제외** {ready_n}엣지 · "
        f"io_busy 상승 {busy_n}사이클 = :258 의 42. "
        "정본이 두 숫자를 끝점 없이 말한 자리를 이 셋이 닫는다")


@cocotb.test()
async def en_is_the_single_stall_source(dut):
    """`io_en=0` 이면 응답이 얼어붙는다 — SEC-2 상태열 균일의 관측 지점.

    `MaskUnit.scala:416` 의 `when(io.en)` 이 rValid/rFrame 갱신의 유일한
    관문이다. 얼어붙음은 **직전 값과의 정확 일치**로 확인한다.
    """
    recs = load_vectors()
    r = recs[1]
    await boot(dut)
    await install(dut, r["KEY"], r["NONCE"], 2)

    exp = frame_of(r["MASKED"])
    got = await translate(dut, 2, frame_of(r["PHYS"]))
    assert got == exp

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
    무조건 수행되고(미준비면 마스크 0 = 항등) 지연은 준비 여부와 무관하다 —
    판정이 경로·시간을 가르지 않는 것이 §5.3 이고, 그것도 함께 본다.
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
    """계산 중 입력 기입 → 결과를 유효화하지 않는다 (E.9 4항 혼합 금지).

    `compDirty` (`MaskUnit.scala:392`) 가 FINAL 에서 `maskValid` 를 막고
    `faultWrDuringRekey` 를 세운다. **두 관측이 모두 필요하다** — fault 만
    보면 「fault 는 떴는데 마스크는 유효」인 창을 못 잡는다.
    """
    recs = load_vectors()
    r = recs[2]
    await boot(dut)
    await write_key(dut, r["KEY"])
    await write_nonce(dut, 0, r["NONCE"])
    await step(dut)
    await rekey(dut, 0)

    # 계산 중(HROUND 어딘가)에 키 워드 하나를 덮어쓴다.
    await step(dut, 5)
    dut.io_keyWr_valid.value = 1
    dut.io_keyWr_idx.value = 3
    dut.io_keyWr_data.value = 0xA5A5_A5A5
    await step(dut)
    dut.io_keyWr_valid.value = 0

    for _ in range(REKEY_TO_READY + 10):
        await step(dut)
        if not int(dut.io_busy.value):
            break
    assert int(dut.io_busy.value) == 0, "엔진이 끝나지 않았다 — 미완료는 통과가 아니다"
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
async def fault_nonce_dup(dut):
    """같은 키 아래 논스 재사용 재키잉 → `io_faultNonceDup` (E.9 2항).

    ⚠ 이 축은 **directed 로만 선다.** 위 golden 루프는 매 벡터 키를 다시 쓰고
      키 기입이 전 파티션 maskValid 를 떨어뜨리므로, 그 루프에서 dup 검사는
      공허하게 거짓이다 (`MaskUnit.scala:286-289` 의 `maskValid(q) && …`).
      여기서만 「유효한 타 파티션」 전건을 실제로 만든다.

    그리고 계약의 사각지대를 함께 적는다: `maskValid` 가 서지 않은 파티션과의
    논스 중복은 **검사되지 않는다.** 그것은 하네스의 누락이 아니라 RTL 계약의
    범위다 — 우회로 「해결」하지 않는다.
    """
    recs = load_vectors()
    r = recs[3]
    await boot(dut)

    await install(dut, r["KEY"], r["NONCE"], 0)   # part0 유효
    assert int(dut.io_faultNonceDup.value) == 0

    # part1 에 **같은 논스** — 키는 다시 쓰지 않는다 (쓰면 part0 이 무효가 되어
    # 전건이 사라진다).
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

    dut.io_faultClearNonceDup.value = 1
    await step(dut)
    dut.io_faultClearNonceDup.value = 0
    await step(dut)
    assert int(dut.io_faultNonceDup.value) == 0
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
    await write_key(dut, r["KEY"])
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
