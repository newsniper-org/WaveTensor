// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// Wt64Top — WT64v1 재구현의 top-level 조립.
//
// 착지한 유닛 전부를 한 지붕 아래 인스턴스하고, 보고서(promote)가 확정한
// 경계 계약대로 배선한다. 이 파일은 **조립**이다 — 판정·상태·fault 의 원천은
// 전부 하위 유닛에 있고, 여기서 새로 만드는 상태는 MMIO 표면의 창 레지스터
// (E.9 MASK_PART)와 이 표면의 거절 sticky 하나(cfgSurfBadWrite)뿐이다. 스테이징은
// 자기 컴포넌트가 든다 — E.12 소거 태그는 `AbortStaging`(2026-08-25 결정 A),
// 변환 항목의 LO 스테이징은 `XlateStaging`(파도 3, 2026-09-26). 둘 다 잴 수 있는
// 경계를 요구했기 때문이며, 근거는 각 클래스의 스칼라독이 소유한다.
//
// ## 인스턴스 지도 (XlateStore 는 HiuPipeline 이 품는다 — §3.2 조회 단계의 몸)
//
//   디코드   DecodeWalk → OperandDecode → { RouteJudge · Reassembly 개방 ·
//            MemOrderGate 제시 }
//   HIU      HiuPipeline(XlateStore 내장) ↔ OwnershipTable(E.7 승인 조회) ·
//            MmioConfig(사상표) → RouteJudge(viewWr/bankWr 구동 규약)
//   패브릭   SharedUnit → FabricMerge(lane 0) → Reassembly 조각 접수 →
//            (완성 인도) → CompletionUnit 완료 링 · ResultBank(물리 슬롯)
//   보안     MaskUnit(마스킹) · StepSequencer(fp32 실행)
//   호스트   CompletionUnit(E.5/E.6/E.11) + MMIO 디코드(아래)
//
// ## MMIO 디코드 — 호스트 ABI 결정 2 의 구역 지도 (2026-08-25, 4 KiB 블록)
//
// 배정 원칙과 구역별 근거는 companion `object Wt64Top` 의 스칼라독이 소유한다
// (상수와 근거를 한 자리에 둔다 — 표만 두 곳에 적으면 드리프트 표면이다).
// 여기는 *무엇이 배선됐고 무엇이 배선되지 않았는가*만 적는다:
//
//   0x000–0x11F  기존 배정 — 워드를 두지 않는다: 쓰기 거절 + [6] · 읽기 0 (§3.10 합의 전의 처분 — 판정 T3)
//   0x120–0x1FF  예약 — 기존 배정이 늘어날 자리 (§3.7)
//   0x200–0x2FF  OwnershipTable (E.7)                              — 배선
//   0x300–0x37F  CompletionUnit (E.5 완료 방향 · E.6 · E.11)       — 배선
//   0x380–0x3FF  명령 링 (E.5 명령 방향)                           — **미배선** (표 워드 쓰기 거절 + [6] · 읽기 0 — 판정 T1-i)
//   0x400–0x7FF  MmioConfig — LNID 소유 표 (§3.7.1)                — 배선
//   0x800–0xBFF  MmioConfig — LBID 사상표 (§3.7.1)                 — 배선
//   0xC00–0xDFF  변환 항목 표면 — 형상 비노출 (E.1.2 · E.3)      — 배선 (XlateStaging)
//   0xE00–0xE7F  변환 저장소 제어 — flush · 미적중 관측 (§3.6.3)   — 배선 (관측 값 = hiu 스냅샷, 파도 4)
//   0xE80–0xEFF  마스킹 — 키 · 논스 · 재키잉 · 논스 중복 캡처 (E.9)  — 배선 (`0xEC4` 캡처 읽기·쓰기 거절은 파일 끝 dupArea)
//   0xF00–0xF3F  step 프로그램 적재 (@fabric 2.5)                  — 배선
//   0xF40–0xF7F  재조립 문맥 소거 (E.12)                           — 배선
//   0xF80–0xFBF  장치 전역 fault · 능력 부재 (§3.8)                — 배선
//   0xFC0–0xFFF  장치 식별 — HIU_SHAPE (`0xFF8`) · HIU_ABI_VERSION (`0xFFC`) — 부분 (RO 쓰기 거절 + [6] · `0xFF8` 은 형상 읽기(파일 끝 identArea) · `0xFFC` 읽기는 합의 전 0 — 판정 T1-ii)
//   그 밖        예약 — 정렬 쓰기 무시 · 읽기 0 (§3.7). 비정렬 쓰기는 페이지 전역 거절 + [6] (판정 T2)
//
// **「미배선」은 「예약」이 아니다.** 예약 오프셋은 *표에 없는* 오프셋이고,
// 위의 미배선 구역은 표에 *있는데* 소비자 회로가 아직 없는 것이다. 읽기는
// 예약과 같은 0 을 돌려주지만 쓰기는 거절 + [6] 이다(파일 끝 pageArea) — 코드에서도 구별된다 —
// 구역마다 이름 있는 상수와 `UNWIRED` 주석이 있고, 디코더가 그 구역을
// *열거한다* (`selUnwired`). 다음 사람이 「예약인가 미배선인가」를 물었을 때
// 답이 코드에 있어야 한다. 등재: rtl/README.md 「자리는 있고 회로는 없다」 ·
// 정본 §3.9 — 미측정은 통과가 아니다 (§6.7 원칙 5).
//
// ## 장치 전역 fault 표면 — 이 파도가 배선했다 (§3.8 · HIU-6)
//
// 앞 파도는 구역 *경계*만 새 맵으로 옮기고 (`0x300`–`0x3FF` → `0x300`–`0x37F`)
// 완료 구역 *안쪽*과 fault 표면을 옛 배치로 남겼다 — 파일 배정 밖이었기
// 때문이며 rtl/README.md 에 정직하게 등재됐다. 이 파도가 그 어긋남을 닫는다:
//
//   · 완료 구역 안쪽은 `host/CompletionUnit.scala` 가 정본 E.1.2 로 옮겼다.
//     가장 위험했던 자리는 `+0x04` 다 — 정본은 CQ_BASE_HI(RW)인데 옛 RTL 은
//     CQ_HEAD(RW)여서, 정본을 따른 드라이버가 링 기저 상위 워드를 쓰면 완료
//     링의 *소비 색인이 조용히 덮였다.* 예약이면 무해했을 자리가 유효한 RW
//     기입으로 상태를 망가뜨리는 형태다. 옛 오프셋을 비우는 것이 수리다.
//   · fault 는 `0xF80`–`0xF90` 다섯 워드로 나왔다. 정의 축은 이제 스물이고(`[19]`
//     비소유 프레임 접근은 3.10 v1.0 묶음이 `[4]` 에서 원인별로 갈랐다) 그중 열여덟이
//     *합성 가능한 sticky 비트*로 존재한다 (§3.8 만족) — 없던 것은 호스트 대면 표면,
//     HIU-6 의 「명시적 해제」 경로였고 이제 `0xF84` W1C 가 그 경로다. `[17]` 엔트로피와
//     `[18]` 명령 디스크립터 둘만 원천 미착지라 상수 0 이며, rtl/README.md 가 행으로 든다.
//
// 해제 경로가 둘이 된 축(기존 `io.faultClear.*` IO + MMIO W1C)은 **논리합**
// 이다 — 어느 쪽도 다른 쪽을 무효화하지 않는다. StickyFault 규약(발화가 해제를
// 이긴다)이 모듈 안에 있으므로 해제 원천이 늘어도 「해제로 fault 를 삼키는
// 창」은 생기지 않는다. IO 해제선 없이 MMIO 로만 해제되는 축은 여섯이다 —
// 완료 유닛 둘(cqOverflow · cqBadWrite) · 소유권 표의 거절된 기입(ownBadWrite) ·
// step 능력 부재(fpCapAbsent) · EH 사슬 능력 부재(ehCapAbsent, 2026-09-21 CAP_STATUS
// 파도) · 비소유 프레임 접근(hiuOwn `[19]`, 3.10 v1.0 묶음) — 정본이 정한 해제 표면이
// 그것이기 때문이며, 없는 경로를 새로 만들지 않는다.
//
// ## 잠정 배선 (TODO — 몰래 고치지 않고 여기 전부 적는다)
//
//   · Reassembly.wr → ResultBank.write 는 **미배선**이다. LBID → 물리 슬롯
//     사상(§3.7.1 — MmioConfig lbidMem 이 정본)이 조회 포트를 아직 내지
//     않는다. 기입 면은 관측 IO 로 수출한다.
//   · OPREF B 토큰의 RouteJudge 제시는 미배선 — tokIn 은 사이클당 하나다.
//   · MemOrderGate 슬롯 결속(io.mem.slotSel)·순서 토큰 구성(cfgPreds)은
//     외부 입력이다 — 토큰 채널의 명령 필드 배정을 정본이 아직 안 했다
//     (§4.4.3). down/complete 는 메모리 파이프 미착지로 IO 수출.
//   · E.11 여섯 카운트 중 ⑥ tokens 만 **부분**이다 — MemOrderGate 점유는
//     cfgPreds 가 약속했으나 미완료인 토큰의 popcount 이고, 발행됐으나
//     구성 표가 더는 참조하지 않는 토큰의 관측(발행 관측)은 상류(발행
//     경로) 미착지다. 나머지 다섯(pipe·pending·output·ownSlots·contexts)은
//     해당 유닛 점유 포트 실물이다 — DRAIN_ALLZERO 는 그 다섯 축의 드레인
//     완주 **증거**이고, tokens 축만 하한으로 읽는다 (0 이 필요조건이지
//     충분조건은 아니다).
//   · SharedUnit 요청(dispatch 방향)·FabricMerge lane 1..N-1(PE 산출)·
//     ResultBank 세 포트·StepSequencer 요청/피연산자는 상류 유닛 미착지로
//     IO 수출이다.
//
// ## 태그 사이드밴드 — 확정 (호스트 ABI 결정 4, 2026-08-25)
//
// 명령 제시(io.instr)는 태그를 *사이드밴드*로 동반한다: 명령 워드열과 태그가
// 같은 beat 에 나란히 오고, 태그는 독립 valid 를 갖지 않는다 — 명령 valid
// 하나가 둘을 함께 유효화한다. E.10 이 조각 머리에 내린 처분(「도착의
// 원자성」)의 재사용이며, 「이 태그가 어느 명령의 것인가」라는 대응 계약을
// *구조로* 없앤다.
//
// 정본이 이미 닫은 갈래 둘이 나머지 후보를 배제한다: §1.1 정의가 태그를
// 「명령어 인코딩의 일부가 *아니라*」고 적어 **명령 스트림 워드** 갈래를
// 배제하고, E.10 규범 1항이 같은 질문(머리와 몸의 동반)에 답과 이유까지 적어
// **채널 분리**를 배제한다. 실질 경쟁자였던 「문맥 핸들 등록」의 기각 근거는
// 절약의 부재다 — 태그 80b 중 32b 가 wave 번호라 wave 마다 바뀌므로 태그는
// 상각되는 문맥이 아니다. 절약할 것이 없는 자리에 ABI 표면 셋(등록 MMIO ·
// 핸들 재사용 규약 · 태그↔핸들 표)을 새로 만드는 거래이고, §3.7.1 해설이
// 직접 이름 붙인 나쁜 거래다 — 「계약을 늘리지 않고 해결되는 것을 계약으로
// 푸는 것」.
//
// **사이드밴드가 나르는 태그는 *통째*다 — 워드 표면이 아니다.** E.5.4 규범 3항이
// 그렇게 정한다: 명령 디스크립터는 *호스트 메모리 쪽 형태*이고 사이드밴드는 *장치
// 안쪽 제시 형태*이며, 둘을 잇는 것은 「1 디스크립터 = 1 명령 + 그 태그」다. 워드
// 직렬화(E.5.1 세 워드)는 32비트 워드 표면 — 완료 디스크립터 · 명령 디스크립터 ·
// E.12 소거 스테이징 — 에만 걸리고, 이 포트는 그 셋 중 어느 것도 아니다.
//
// 그래서 `io.instr.tag` 는 `Types.Tag` 번들 그대로다. 이 파도가 한때 이 자리를
// 다섯 워드 포트로 바꿨다가 되돌렸다 — 정본이 확정한 직렬화가 다섯이 아니라 셋
// 이었고, 무엇보다 *사이드밴드는 직렬화의 대상이 아니었다*. 번들 포트에는 예약
// 여백이 아예 없으므로 「검사받지 않고 통과하는 비트」(§5.7)도 생기지 않는다 —
// 여백은 워드 표면에만 있고 그 표면의 처분은 방향이 정한다 (E.5.1 4항).
//
// 80b 팩킹 순서는 여전히 미확정이며 이 파일은 그것을 알 필요가 없다 — 태그
// 슬라이스가 한 곳도 없기 때문이다 (§1.4.4).
//
// ## GUARD-MAP — 정식 줄 하나 (Mask 넷째 가드) + 접점 서술 (접점 불릿은 lint 비파싱)
//
// GUARD-MAP: Mask.rekey_explicit_target -> 재키잉 대상은 수락된 MASK_REKEY(0xEBC)
//   기입의 [7:0] 그 자체다 — maskArea 가 rekey.part 를 partField 에서만 떼고, 창
//   (maskPart · MASK_PART 0xEA0)은 그 식에 들지 않는다. 후-formal 은 조립층
//   rtl/formal/sby/Wt64Top/assembly.sby 가 mask 의 rekey 핀을 창과 독립인 오라클로
//   잰다. 엔진이 그 파티션의 저장을 읽는 절반은 hiumask.sby 의 key_scoped_storage 다.
//   · Route.view_sync (정식 줄: RouteJudge) — MmioConfig.viewWr/bankWr 를 RouteJudge
//     에 사이 레지스터 없이 직결했다 — 기입 사이클 즉시 반영이라는 그 줄의 전제.
//   · Platform.owner_check (정식 줄: HiuPipeline) — io.owner.devOwned 의 원천을
//     OwnershipTable.query 로 조합 0사이클 직결했다 — 승인(D11)의 전제.
//   · Fabric.bp_relief (정식 ENV 줄: FabricMerge — 불변) — Reassembly.deliver 를
//     완료 링에 배압 보존으로 이었다 (deliver.ready = comp.ready).
//   · Decode.stall_uniform (정식 줄: HiuPipeline) — MaskUnit 의 io.en 에 파이프
//     advance(= hiu.req.ready)를 그대로 물렸다 — 정지 원천 무관 s4 동행.
//   · Isolation.no_early_forward (정식 줄: HiuPipeline) — hiu.io.mask 를 MaskUnit
//     하나에만 직결했다 (req 를 다른 소비자에 내지 않고 rsp 를 밖에서 구동하지 않는다).
//   다섯 접점의 핀 결선 등식도 같은 assembly.sby 가 잰다 (조립 절반 — 정식 앵커는 괄호 안).
package wt64.top

import spinal.core._
import spinal.lib._
import wt64._
import wt64.decode.{DecodeWalk, OperandDecode}
import wt64.route.{RouteJudge, RouteTok}
import wt64.payload.Reassembly
import wt64.memorder.{MemOrderGate, MemOrderGateParams}
import wt64.hiu.{HiuPipeline, MmioConfig, OwnershipTable, XlatePerm, XlateStore}
import wt64.host.CapStatusWord
import wt64.fabric.{FabricMerge, ProducePort, ResultBank, ResultBeat, SharedUnit, SharedUnitParams}
import wt64.mask.MaskUnit
import wt64.fp.{StepSeqParams, StepSequencer}
import wt64.host.CompletionUnit

/** 4 KiB 구성 페이지의 구역·워드 배정 — 호스트 ABI 결정 2 (2026-08-25).
  *
  * ## 배정 원칙 — 결과 표 이전에 규칙이 있다
  *
  * 아래 상수는 이 넷을 적용한 *결과*다. 확장은 표를 흉내 내는 것이 아니라
  * 넷을 다시 적용해서 만든다.
  *
  *  1. **2의 거듭제곱 크기와 자기 정렬** — 모든 기능 구역은 크기가 2^k 이고
  *     시작 오프셋이 그 크기로 정렬된다. 그러면 구역 판정이 주소의 상위
  *     *접두 비교 하나*로 끝난다 — 하한·상한 두 번의 크기 비교가 사라진다.
  *     `Region.require` 가 이 규칙을 elaborate 시점에 강제하고, `prefix`/
  *     `loBit` 이 그 접두 비교의 재료다. 이 파일에 범위 비교(`>= A && < B`)는
  *     한 곳도 없다 — 비교기 개수가 곧 면적이고, 무엇보다 범위 비교는
  *     *경계를 틀리게 적을 자리*를 구역마다 하나씩 만든다.
  *  2. **기능별 clustering** — 한 유닛이 소유하는 표면은 한 구역에 모은다.
  *     옛 `0xC00` 잠정 배정은 마스킹·step 적재·문맥 소거·재조립 진단 넷을
  *     한 256 B 블록에 섞어 이 규칙을 어겼다 (소비 유닛이 MaskUnit ·
  *     StepSequencer · Reassembly 셋인데 디코드는 하나였다). 이번 이동이
  *     그것을 셋으로 가른다.
  *  3. **큰 것부터 앉힌다** — 최대 항목(변환 항목 창 512 B)이 자기 정렬을
  *     만족하는 자리를 먼저 잡는다. 남은 공간에서 그 자리는 `0xC00` 하나뿐
  *     이었고, 그래서 마스킹이 그 자리를 비켜 `0xE80` 으로 갔다.
  *  4. **페이지 끝은 움직이지 않는 자리다** — 앞 구역이 아무리 늘어나도
  *     페이지 마지막 워드는 밀리지 않는다. 드라이버가 *가장 먼저* 읽는
  *     레지스터(ABI 판, `0xFFC`)를 그곳에 둔다.
  *
  * 규칙 1이 적용되지 않는 유일한 자리는 `0x000`~`0x11F` 다 — 288 B 는 2의
  * 거듭제곱이 아니다. 예외가 아니라 *물려받은 것*이며 (§3.10), 그것을 감싸는
  * 512 B 블록 `0x000`~`0x1FF` 은 정렬돼 있어 상위 구역 디코드는 접두 비교로
  * 닫힌다. 그래서 이 객체는 그 구역에 `Region` 을 두지 않는다 — 합의 전 처분(쓰기 거절)은 접두 비교 둘(`0x000`~`0x0FF` · `0x100`~`0x11F`)로 잡는다 (파일 끝 pageArea).
  *
  * ## 「예약」과 「미배선」은 다르다 — 이 상수들이 그 구별의 실물이다
  *
  * §3.7 예약 *오프셋* 정책(쓰기 무시 · 읽기 0)은 **표에 없는 오프셋**의
  * 처분이다. 아래 상수가 이름한 오프셋은 표에 *있다* — 다만 소비자 회로가
  * 아직 없어 읽기는 같은 0 을 돌려주고 쓰기는 거절 + [6] 이다 (판정 T1). 미배선 표면도 상수로 이름을
  * 갖고 `UNWIRED` 로 표시하는 이유가 그것이다: 다음 사람이 「예약인가
  * 미배선인가」를 물었을 때 답이 코드에 있어야 한다.
  *
  * ## 워드 안의 예약 *비트*는 엄격이다 (결정 A 와 같은 형태)
  *
  * 예약 *오프셋*의 관대 정책을 워드 *안*으로 옮겨 적지 않는다. 아래
  * `*_RSV` 마스크가 선 워드의 기입은 거절 + loud sticky fault 다 —
  * `hiu/MmioConfig.scala` 머리의 「엔트리 내부 예약 비트」 절과 같은 논거
  * (방향 축: 호스트가 써 넣고 장치가 해석하는 「받아들이는 쪽」)이고,
  * 마스크를 *적재 마스크의 여집합으로 유도*하는 형태까지 같다.
  */
object Wt64Top {
  /** 기능 구역 하나 — 배정 원칙 규칙 1을 elaborate 시점에 강제한다.
    *
    * @param base 시작 바이트 오프셋 (4 KiB 페이지 안)
    * @param size 바이트 크기 — 2의 거듭제곱이어야 하고 base 가 그 크기로
    *             정렬돼 있어야 한다. 어기면 구역 판정이 접두 비교로 닫히지
    *             않는다 (= 범위 비교 두 개가 살아난다).
    */
  case class Region(base: Int, size: Int, name: String) {
    require(isPow2(size), s"구역 「$name」 크기 $size — 규칙 1 위반 (2의 거듭제곱이 아니다)")
    require(base % size == 0, s"구역 「$name」 base 0x${base.toHexString} — 규칙 1 위반 (자기 정렬 아님)")
    require(base >= 0 && base + size <= 0x1000, s"구역 「$name」 이 4 KiB 페이지 밖이다")
    /** 접두 비교의 최하위 비트 — addr(11 downto loBit) === prefix 하나로 끝난다. */
    def loBit:  Int = log2Up(size)
    def prefix: Int = base >> loBit
    /** 구역 안 워드 색인의 최상위 비트 (바이트 오프셋 [loBit-1:2]). */
    def wordHi: Int = loBit - 1
  }

  // ═══ 구역 지도 ═══════════════════════════════════════════════════════
  // 배선된 구역 — 소비자 회로가 실재한다.
  val R_OWN   = Region(0x200, 0x100, "페이지 소유권 표 (E.7)")
  val R_CQ    = Region(0x300, 0x080, "완료 방향 — 완료 링·통지·드레인 (E.5·E.6·E.11)")
  val R_LNID  = Region(0x400, 0x400, "LNID 소유 표 (§3.7.1)")
  val R_LBID  = Region(0x800, 0x400, "LBID 사상표 (§3.7.1)")
  val R_XENT  = Region(0xC00, 0x200, "변환 항목 표면 — 형상 비노출, 파티션 기저 4 (E.1.2·E.3)")
  val R_XCTL  = Region(0xE00, 0x080, "변환 저장소 제어 — flush·미적중 (§3.6.3·E.3)")
  val R_MASK  = Region(0xE80, 0x080, "마스킹 — 키·논스·재키잉 (E.9)")
  val R_FP    = Region(0xF00, 0x040, "step 프로그램 적재 (@fabric 2.5)")
  val R_ABORT = Region(0xF40, 0x040, "재조립 문맥 소거 (E.12)")
  val R_FAULT = Region(0xF80, 0x040, "장치 전역 fault · 능력 부재 (§3.8)")

  // UNWIRED — 자리는 배정됐고 소비자 회로가 없다 (R_XCTL 의 관측 워드 셋도 — Xctl).
  // 부재 사유는 rtl/README.md 「자리는 있고 회로는 없다」 표가 행마다 소유한다.
  val R_SQ    = Region(0x380, 0x080, "명령 방향 — 명령 링 (E.5)")
  val R_IDENT = Region(0xFC0, 0x040, "장치 식별 (§3.7 측정 트랙)") // 부분 — `0xFF8` HIU_SHAPE 읽기만 배선 (파일 끝 identArea)

  /** 드리프트 방지 — 구역 base 는 소유 모듈의 상수와 같은 값이어야 한다.
    * 두 곳이 따로 표류하면 디코더는 A 를 고르고 모듈은 B 를 해석한다. */
  require(R_OWN.prefix == OwnershipTable.REGION, "R_OWN 이 OwnershipTable.REGION 과 어긋난다")
  require(R_LNID.base == MmioConfig.LNID_TBL_BASE, "R_LNID 가 MmioConfig 와 어긋난다")
  require(R_LBID.base == MmioConfig.LBID_TBL_BASE, "R_LBID 가 MmioConfig 와 어긋난다")

  // ═══ 배선된 구역의 워드 — 구역 안 바이트 오프셋 ══════════════════════
  //
  // 마스킹 (R_MASK, 0xE80) — 옛 0xC00 지역의 워드 색인 0..16 을 그대로
  // 옮겼다. 상대 배치가 같아 이동은 base 하나의 변경이다.
  val M_KEY0       = 0x00 // ~0x1C  WO  E.9 1항 — 키 8워드. 읽기 0 (되읽지 않는다, §5.8)
  /** MASK_PART — 구 MASK_NONCE_PART 를 넓힌 것(정본 7fa5f2e,
    * e-defined.typ:344·351 7항). 키·논스 두 기입 모두의 대상 파티션을
    * *함께* 정하는 창이다 — authority(재키잉 지목)는 이 창이 아니라 MASK_REKEY 기입 하나(같은 7항). */
  val M_MASK_PART  = 0x20 //        RW  키·논스 기입 대상 파티션 선택
  val M_NONCE0     = 0x24 // ~0x38  WO  E.9 2항 — 선택 파티션의 논스 6워드
  val M_REKEY      = 0x3C //        WO  E.9 4항 — 기입이 발화
  val M_STATUS     = 0x40 //        RO  [7:0] maskReady · [8] busy · [9] rekey ready
  val M_DUP_CAPTURE = 0x44 //       RO  [7:0] p · [15:8] 같은 논스의 다른 유효 파티션 비트맵 · [16] = [12] — MaskUnit.dupCapture (파일 끝 dupArea)
  val M_KEY_WORDS   = 8
  val M_NONCE_WORDS = 6

  // step 프로그램 적재 (R_FP, 0xF00)
  val F_PROG   = 0x00 // WO  [31:24] slot · [23:16] idx · [15:0] step
  val F_BIND   = 0x04 // WO  [31] en · [30:24] 예약(엄격) · [23:16] slot · [15:0] key
  val F_STATUS = 0x08 // RO  [0] loadReady · [1] busy

  // 재조립 문맥 소거 (R_ABORT, 0xF40)
  val A_TAG0       = 0x00 // WO  태그 wave 32b (스테이징)
  val A_TAG1       = 0x04 // WO  [31:28] 에포크 · [27] poison · [26] trace · [25:16] 예약 · [15:0] LNID (스테이징 · [27:16] 엄격)
  val A_TAG2       = 0x08 // WO  [15:8] precision · [7:0] dim · [31:16] 예약(엄격)
  val A_FIRE       = 0x0C // WO  [0]=1 기입 = 소거 발화 · [31:1] 예약(엄격)
  val A_COUNT      = 0x10 // RO  소거 카운트 (E.12 2항 회계)
  val A_INCOMPLETE = 0x14 // RO  미완 재조립 문맥 수 (진단)
  /** ABORT_ARM — 무장 마스크 RO 관측면 (정본 E.12.1 4항 · §5.8 상태 표면
    * 부류). 비트 $i$ 가 `0xF40`+4$i$ 스테이징 워드의 무장이다 · `[31:3]` RO
    * 예약 = 0 · reset 값 0. 구역 `0xF40`+`0x18` = `0xF58` 이며 구역 64 B 안의
    * 일곱째 워드다 — 구역을 늘리지 않고 여유가 흡수한 증설이다.
    * *태그 값은 내지 않는다* — 스테이징 워드를 WO 로 둔 결정과 같은 이유다
    * (E.1.1 WO 규범 · §5.8 관측면 최소화). */
  val A_ARM        = 0x18 // RO  [2:0] 무장 마스크 · [31:3] RO 예약 = 0

  // ═══ 워드 안의 예약 비트 — 엄격 (비0 기입은 거절 + loud fault) ════════
  // 적재 마스크의 *여집합으로 유도*한다 — 두 상수가 따로 표류할 자리를
  // 없앤다 (MmioConfig.LNID_RSV_MASK 선례).
  private def rsv(loadMask: Long): Long = (~loadMask) & 0xFFFFFFFFL
  /** 파티션 선택 필드는 8b 고정이다 — 형상의 함수가 아니다 (INV-T1: MASK_STATUS
    * 의 `[7:0]` 파티션 필드와 같은 처분). 그래서 예약은 `[31:8]` 이다. */
  val PART_FIELD_W       = 8
  val M_MASK_PART_RSV    = rsv(0x000000FFL) // [31:8]
  val M_REKEY_RSV        = rsv(0x000000FFL) // [31:8]
  /** ABORT_TAG2 의 예약 = `[31:16]` — *태그 워드 코덱*에서 끌어온다 (세 워드가 E.5.1 직렬화의 원본이라 여백의 자리도 그 코덱이
    * 정본이다 — 같은 값을 두 곳에 적으면 어느 쪽이 정본인지 답할 수 없다). 처분이 *엄격*인 것은 받아들이는 쪽이라서다 (E.5.1 4항). */
  val A_TAG2_RSV         = rsv((1L << Types.Tag.TAG2_RSV_LO) - 1) // [31:16]
  /** ABORT_TAG1 의 거절 = `[27:16]` poison·trace·예약 — 처분은 셋 다 같다 (E.1.2 `0xF44` · E.12 6항). 필드 자리는 태그 워드 코덱(`Types.Tag` TAG1 필드 마스크 — E.5.1 재배분)에서 끌어온다: 이 표면이 거절하는 *필드의 조합*만 여기서 짓는다 (명령 디스크립터는 trace 를 거절하지 않는다 — 조합은 표면의 몫). */
  val A_TAG1_RSV         = Types.Tag.TAG1_POISON_MASK | Types.Tag.TAG1_TRACE_MASK | Types.Tag.TAG1_RSV_MASK; require(A_TAG1_RSV == 0x0FFF0000L, "ABORT_TAG1 거절 마스크가 정본 E.1.2 0xF44 [27:16] 과 다르다 — 코덱의 TAG1 필드 자리가 움직였다") // [27:16]
  val A_FIRE_RSV         = rsv(0x00000001L) // [31:1]
  val F_BIND_RSV         = rsv(0x80FFFFFFL) // [30:24]
  /** FAULT_CLEAR 의 예약 = `[31:20]`. 비트 *수*를 `Fault.N_BITS` 에서 끌어와
    * 마스크를 유도한다 — 축이 하나 늘 때 고칠 자리가 상수 하나여야 한다
    * (두 곳에 적으면 그 순간부터 어느 쪽이 정본인지 답할 수 없다). E.5.4 가 `[18]` 을,
    * 3.10 v1.0 묶음이 `[19]` 를 새로 만들었을 때 실제로 이 한 상수(`N_BITS`)만 움직였다. */
  val FLT_CLEAR_RSV      = rsv((1L << Fault.N_BITS) - 1)     // [31:20]
  /** CAP_CLEAR 의 예약 = `[31:4]` (정본 E.1.2 CAP_CLEAR 행). 같은 유도 —
    * `Fault.N_CAP_BITS` 가 값의 단일 출처이고, 워드 컴포넌트(`CapStatusWord`)가
    * 스스로 유도한 마스크와 같은지는 조립이 elaborate 시점 `require` 로
    * 못박는다 (아래 `capWord`). */
  val CAP_CLEAR_RSV      = rsv((1L << Fault.N_CAP_BITS) - 1) // [31:4]

  /** 장치 전역 fault (R_FAULT) — 구역 안 바이트 오프셋. **배선됨.**
    *
    * fault 는 특정 유닛의 표면이 아니라 *장치 전역*이므로 자기 구역을 갖는다
    * (E.1 구역별 근거). 스무 축 중 열여덟의 sticky 비트는 하위 유닛(또는 이
    * 조립)이 든다 — §3.8 「합성 가능한 sticky 비트」는 만족이었다 —
    * 없던 것은 *호스트 대면 표면*이었다. `STATUS` 가 그 관측면이고 `CLEAR`
    * 가 HIU-6 이 요구하는 명시적 해제다. 관측·해제의 비트 배치가 같아
    * 드라이버는 읽은 워드를 그대로 되쓰면 자기가 본 것만 지운다.
    *
    * `[17]` 엔트로피와 `[18]` 명령 디스크립터 둘만 원천이 재구현에 미착지라
    * 상수 0 이다 (엔트로피원 유닛 · 명령 링 소비자) — 그 사실은
    * rtl/README.md 「자리는 있고 회로는 없다」가 행으로 든다. 비트가 *없는*
    * 것이 아니라 *세울 원천이* 없다. */
  object Fault {
    val STATUS  = 0x00 // RO  sticky 비트맵 (아래 비트 배정)
    val CLEAR   = 0x04 // WO  STATUS 와 같은 비트 배치의 W1C
    val SUMMARY = 0x08 // RO  [0] STATUS 의 논리합 (§5.6 1항 — 개별 노출을 대체하지 않는다)
    val CAP_STATUS = 0x0C // RO  [0] 재조립 슬롯 · [1] step 미상주 · [2] EH 사슬 · [3] 연산 미지원 — *fault 가 아니다*
    val CAP_CLEAR  = 0x10 // WO  CAP_STATUS 와 같은 배치의 W1C

    // FAULT_STATUS 비트 배정 — 원천별로 가른다 (접지 않는다, §5.6 3항).
    // 이 순서는 호스트 드라이버와 공유되는 순간 ABI 다 (§3.10 합의 입력).
    val B_DECODE_WALK  = 0  // 명령 걷기 malformation
    val B_OPERAND      = 1  // 피연산자 디코드 malformation
    val B_ROUTE        = 2  // route — 미사상 논리 ID
    val B_REASM        = 3  // 재조립
    val B_XLATE_PERM   = 4  // 변환 자격 거부 — 권한 비트가 그 접근을 허용하지 않음 (비소유는 [19])
    val B_CFG_DUP      = 5  // 구성 — 소유 서로소 위반 (D2)
    val B_CFG_BADWRITE = 6  // 구성 — 거절된 구성 기입 (넷 + 다섯을 접는다)
    val B_OWN_COLLIDE  = 7  // 페이지 소유권 표 충돌
    val B_FABRIC_BP    = 8  // 병합 배압 무시
    val B_SHARED_BP    = 9  // 공유 유닛 배압 무시
    val B_BANK_WRITE   = 10 // 비소유 결과 슬롯 기입
    val B_MASK_NOMASK  = 11 // 미준비 마스크 통과
    val B_MASK_NONCE   = 12 // 논스 재사용 재키잉
    val B_MASK_REKEY   = 13 // 재키잉 중 입력 기입
    val B_FP_BP        = 14 // step sequencer 배압 무시
    val B_FP_BADPROG   = 15 // step 프로그램 불량
    val B_RING_OVF     = 16 // 링 오버플로
    val B_ENTROPY      = 17 // 엔트로피원 건강성 검사 실패 (유닛 자체가 미착지)
    /** 명령 디스크립터 malformation — E.5.4 가 만든 새 원천 (모르는 kind ·
      * 예약 비0 · 부적법한 길이). 명령 링 소비자가 미착지라 세울 원천이
      * 없다 — `[17]` 엔트로피와 같은 부류이며 상수 0 이다. 비트를 비워 두는
      * 것과 비트가 없는 것은 다른 사실이므로 자리를 잡아 둔다. */
    val B_CMD_DESC     = 18
    val B_OWN_FRAME    = 19 // 비소유 프레임 접근 — 자격이 허용된 장치 접근이 장치 소유가 아닌 프레임에 닿음 (HiuPipeline faultOwn · 3.10 v1.0 묶음이 [4] 에서 갈랐다)
    val N_BITS = 20 // 정의된 fault 비트 수 — `[31:20]` 은 RO 예약 = 0 (정본 E.1.2)
    // 미적중 통지(XCTL STATUS [1])와 능력 부재(CAP_STATUS)는 이 워드에
    // 들지 않는다 — 오류가 아니기 때문이다 (E.3 · §1.6.2).

    // CAP_STATUS/CAP_CLEAR 비트 배정 — *fault 가 아니다* (§1.6.2). 바이너리는
    // 옳고 이 기계가 지금 못 하는 것이며 상위 계층이 조회·수리·해제·재시도한다.
    // 축은 「고칠 동작」으로 가른다 (정본 E.1.2 규범) — 넷은 서로 접지 않는다.
    // 워드의 *행위*(축별 sticky · W1C · 예약 엄격 · 발화가 해제를 이긴다)는
    // host/CapStatusWord 가 들고, 어느 사건이 어느 축인가는 이 상수들과 그
    // 결선(`io.fault.*` 수출 자리)이 든다.
    val C_REASM_SLOT     = 0 // 재조립 슬롯 능력 부재 — sticky 는 Reassembly 안 (워드는 pass-through)
    val C_FP_PROG        = 1 // step 프로그램 미상주 — sticky 는 CapStatusWord
    val C_EH_CHAIN       = 2 // EH 사슬 용량 — sticky 는 CapStatusWord, set 은 DecodeWalk 종결 (oValid 한정)
    val C_OP_UNSUPPORTED = 3 // 연산 미지원 — 원천 0건, 상수 0 (rtl/README.md 「자리는 있고 회로는 없다」)
    /** 정의된 능력 부재 비트 수 — `[31:4]` 는 RO 예약 = 0 (정본 E.1.2). */
    val N_CAP_BITS       = 4
  }

  // ═══ 변환 저장소 두 구역 · UNWIRED 구역의 워드 ═════════════════════════
  //
  // 값을 여기 적는 이유: 「예약이라 이름이 없다」와 「이름은 있는데 회로가
  // 없다」는 다른 사실이고, 뒤의 것은 다음 사람이 배선할 때 자리를 다시
  // 정하지 않게 한다. Xent · Xctl 은 파도 3 이 XlateStaging 으로 배선했고
  // (Xctl 의 관측 세 워드는 값만 UNWIRED), Sq · Ident 는 회로에 닿지 않는다.

  /** 명령 링 (R_SQ) — 구역 안 바이트 오프셋. 완료 방향과 *같은 상대 오프셋*
    * 이라 드라이버가 한 구조체를 base 만 바꿔 두 링에 쓴다 (구역 간 거리
    * 정확히 `0x80`). UNWIRED: 명령 방향 실물 0건 — 이 기계에서 일의 원천은
    * top 의 `io.instr` 외부 제시이고 링에서 디스크립터를 꺼내는 경로가 없다. */
  object Sq {
    val BASE_LO = 0x00 // RW
    val BASE_HI = 0x04 // RW  LO 스테이징 · HI 커밋 발화
    val SIZE    = 0x08 // RW  [4:0] log2(엔트리 수) — E.5 1항이 검사 없이 구조로 성립
    val HEAD    = 0x0C // RO  *장치* 갱신 (완료 링과 방향이 뒤집힌다)
    val TAIL    = 0x10 // RW  *호스트* 갱신
  }

  /** 변환 항목 표면 (R_XENT) — 형상 비노출 (3.10 v1.0 묶음 · W3): 파티션 기저 = `0xC00` + (p ≪ 7)
    * (`addr[8:7]` = 파티션) · 기저 안 워드 `addr[6:2]`. 호스트는 (VPN, 프레임, 권한)만 쓰고 칸은
    * 장치가 정한다 — 색인이 주소에 없다. XlateStaging 이 판정하고 조립이 VPN 을 XlateStore.idxOf/
    * tagOf 로 갈라 install 로 잇는다. 최상위 IO `io.install` 은 은퇴했다 (authority 하나). */
  object Xent {
    val PART_LO = 7    // addr[8:7] = 파티션 기저
    val VPN     = 0x00 // WO  [31:0] 가상 페이지 번호 — 스테이징, 파티션 래치
    val FRAME   = 0x04 // WO  [31:0] 물리 프레임 — 스테이징 (래치 기저에서만)
    val COMMIT  = 0x08 // WO  [31] V · [30:28] R·W·X · [27:0] 예약(엄격) — 커밋 발화
    val VPN_HI  = 0x0C // WO  [31:0] 예약(엄격) — 0 만 수락 · FRAME 유효를 내린다
    val RSV_LO  = 0x10 // +0x10..+0x7C 예약-엄격 28 워드 — 쓰기 거절 + [6] · 읽기 0
  }

  /** 변환 저장소 제어 (R_XCTL) — 구역 안 바이트 오프셋. **배선 (파도 3 · 4)**: FLUSH
    * 발화와 MISS_CLEAR 해제는 XlateStaging 이 판정하고(최상위 IO `io.flush` 은
    * 은퇴), 세 RO 워드의 쓰기는 거절 + [6] 이다. 관측 *값*은 파도 4 가 배선했다
    * — hiu 의 정지 게이트 스냅샷(missStall·missPart·missVpn) · sticky (xlateArea 끝). */
  object Xctl {
    val FLUSH        = 0x00 // WO  [7:0] 파티션 — 기입이 곧 발화 · [31:8] 예약(엄격)
    val STATUS       = 0x04 // RO  [0] 미적중 정지 · [1] 미적중 sticky · [15:8] 파티션
    val MISS_VPN_LO  = 0x08 // RO
    val MISS_VPN_HI  = 0x0C // RO
    val MISS_CLEAR   = 0x10 // WO  [0] 에 1 기입 = sticky 해제 (정지는 안 풀린다)
  }

  /** 장치 식별 (R_IDENT) — 구역 안 바이트 오프셋. `0xFFC` = 페이지 마지막 워드 (규칙 4). **부분**: RO 쓰기는 거절 + [6] (파일 끝 pageArea · E.1.1). `0xFFC` 읽기 값은 합의 전 0 이고 판 0 은
    * 물려받은 `0x000`–`0x11F` 에 어떤 레이아웃도 약속하지 않는다 (판정 T1-ii — §3.10 합의 전의
    * 처분). 비0 판 값과 필드 분할은 합의가 정한다 — 여기서 임의로 박지 않는다. `0xFF8` 은 형상 읽기다 (파일 끝 identArea). */
  object Ident {
    val HIU_SHAPE   = 0x38 // RO  `0xFF8` — [7:0] 실재 파티션 수 · [23:8] 파티션당 저장 칸 수(개수) · [31:24] 0 — 값은 형상 cfg 한 곳
    val ABI_VERSION = 0x3C // RO  `0xFFC` — [31:0] 호스트 ABI 판
    val PRE_AGREEMENT = 0  // 합의 전 판 값 — resvRd 경로의 0 이 곧 이 값이다 (pageArea 의 require)
  }
  require(R_IDENT.base + Ident.ABI_VERSION == 0xFFC, "ABI 판이 페이지 마지막 워드가 아니다 (규칙 4)")
}

/** 재조립 문맥 소거의 *호스트 대면 절반* — 태그 스테이징 + 무장 규율 + 발화
  * (정본 E.12.1 「무장 비트 다섯 항」 · 2026-08-25 결정 A).
  *
  * ## 왜 별 Component 인가
  *
  * 이 로직은 조립(Wt64Top) 안의 한 Area 로 있어도 전기적으로 같다. 별
  * Component 로 세운 이유는 *측정*이다. 결정 A 의 요점이 「부분 기입 무효과」와
  * 「stale staging 부재」를 ABI 의무에서 **기계가 강제하는 속성**으로 옮기는
  * 것인데, 잴 수 없는 속성은 절반만 옮긴 것이다. 후-formal 이 태스크를 걸려면
  * `prep -top` 이 짚을 이름이 있어야 하고, 9500줄짜리 조립 전체를 k-귀납에
  * 올리는 것은 이 속성을 재는 값에 비해 터무니없는 비용이다. 경계가 이름을
  * 가지면 하네스는 스무 줄이다.
  *
  * ## 무장 규율 (정본 E.12.1 다섯 항)
  *
  *  1. *워드별 무장 비트* — 태그 세 워드의 *수락된* 기입이 각각 자기 무장
  *     비트를 세운다. 재기입은 값을 덮되 비트는 선 채다. 거절된 기입은
  *     무장을 세우지 않는다 — 효과 없는 기입이 승인만 남기면 그것이 곧
  *     부분 기입의 승격이다 (E.12.1 1항).
  *  2. *발화는 셋이 모두 선 상태에서만 유효*하다. 무장 미완 발화는 **무시**다 —
  *     E.12 3항(없는 태그 기입은 무시, 오류 아님)과 같은 처분이며 fault 도
  *     아니고 소거 카운트도 올리지 않는다.
  *  3. *발화 워드 기입은 성립·불성립 무관하게 무장 비트를 전부 내린다* (잔류
  *     소진). stale staging 이 구조로 사라진다 — 「어제 반쯤 실어 둔 태그가
  *     오늘의 발화에 실린다」가 표현 불가다.
  *  4. *무장 마스크는 RO 상태 워드*로 나간다 — `0xF58` ABORT_ARM
  *     (§5.8 상태 표면 부류 · 드레인 정의역은 아니다).
  *  5. *무장은 태그 값을 검사하지 않는다* — 「세 워드가 다 왔는가」만 본다.
  *     어느 태그가 스테이징돼 있는지는 관측면에 내지 않는다. *워드의 적법성은 무장보다 앞선다* — 예약·poison·trace 비0 기입은 거절이고 무장을 세우지 않는다 (E.12.1 5항 · 1항).
  *
  * E.7 이 「전이는 한 번의 쓰기로 완결된다」로 얻은 원자성을 태그 80b 는 가질
  * 수 없다 — 32b 워드에 안 들어간다. 스테이징+발화가 그 대체이고, 무장 규율이
  * 그 대체를 *관행에서 계약으로* 올린다. 이것은 현행의 **엄격한 축소**다:
  * 올바른 호스트 시퀀스(세 워드 기입 후 발화)는 글자 그대로 동작한다.
  *
  * ## 「성립·불성립 무관」의 경계 — 거절된 기입은 기입이 아니다
  *
  * 무장을 내리는 것은 *수락된* 발화 워드 기입이다. 예약 비트 비0 인 발화 기입은
  * E.1.1 엄격 정책의 *거절 + loud fault* 이고, 이 저장소의 반복 규율은 「거절된
  * 기입은 레지스터를 한 비트도 움직이지 않는다」(TAG2 스테이징·FAULT_CLEAR 와
  * 같은 처분)다. 거절이 무장을 내리면 호스트는 자기 오타 하나로 세 워드를 다시
  * 실어야 하고, 그것은 「거절 = 무동작」이라는 표면 전체의 계약과 어긋난다.
  * ⇒ 수락된 발화 기입(값이 0 이어도)은 무장을 내린다. 거절된 것은 아무것도
  * 하지 않는다. E.12.1 3항의 「성립·불성립」은 *소거의 성립*을 가리키고, 기입
  * 자체의 수락/거절 축은 같은 절 1항이 스테이징 쪽에 이미 그은 것을 대칭으로
  * 옮긴 것이다 — 두 축을 한 낱말로 읽으면 1항과 3항이 서로를 부정한다.
  *
  * 상위 디코더가 구역 선택·정렬·방향을 이미 가른 뒤의 워드 스트로브만 받는다 —
  * 이 컴포넌트는 「어느 워드에 무엇을 썼는가」만 안다.
  */
class AbortStaging extends Component {
  import Wt64Top.{A_FIRE_RSV, A_TAG1_RSV, A_TAG2_RSV}

  /** TAG2 의 *정의 비트* 폭 (16) — 예약 `[31:16]` 은 저장하지 않는다. */
  private val T2_DEF_W = Types.Tag.TAG2_RSV_LO

  val io = new Bundle {
    /** 이 구역의 정렬된 기입 스트로브 (구역 선택·정렬은 상위가 이미 가렸다). */
    val wr      = in port Bool()
    val selTag0 = in port Bool()
    val selTag1 = in port Bool()
    val selTag2 = in port Bool()
    val selFire = in port Bool()
    val wdata   = in port Bits(32 bits)

    /** 거절된 구성 기입 — 워드 안 예약 비트 비0 (E.1.1 엄격 · FAULT `[6]`).
      * *무장 미완 발화는 여기 들지 않는다* — 그것은 거절이 아니라 무시다. */
    val badWrite = out port Bool()

    /** 무장 마스크 RO 관측면 — `[0]` TAG0 · `[1]` TAG1 · `[2]` TAG2
      * (결정 A 4항 · §5.8 상태 표면 부류). */
    val armed = out port Bits(3 bits)

    /** 소거 발화 — 의미론 스트로브. 무장 완비 + 발화 워드 `[0]`=1 + 수락된
      * 기입일 때만 선다. */
    val fire = out port Bool()
    val tag  = out port Types.Tag()
  }

  // 워드 안 예약 판정 — 마스크 상수는 companion 이 소유한다 (두 곳에 적으면 어느 쪽이 정본인지 답할 수 없다).
  private val tag1RsvBad = (io.wdata & B(A_TAG1_RSV, 32 bits)) =/= 0 // poison·trace·예약 — E.12 6항
  private val tag2RsvBad = (io.wdata & B(A_TAG2_RSV, 32 bits)) =/= 0
  private val fireRsvBad = (io.wdata & B(A_FIRE_RSV, 32 bits)) =/= 0

  /** 수락된 워드 기입 — 거절은 기입이 아니다 (위 스칼라독의 경계). */
  private val okTag0 = io.wr && io.selTag0
  private val okTag1 = io.wr && io.selTag1 && !tag1RsvBad
  private val okTag2 = io.wr && io.selTag2 && !tag2RsvBad
  private val okFire = io.wr && io.selFire && !fireRsvBad

  // 스테이징은 *정의 비트만* 든다 — TAG2 예약 `[31:16]` 은 엄격 거절이라
  // 저장할 값이 없고, 그럼에도 저장하면 §5.7 해설이 경계한 「무시되는 비트가
  // 어딘가에 저장되면」의 그 저장이 이 레지스터가 된다.
  val tag0 = Reg(Bits(32 bits)) init 0
  val tag1 = Reg(Bits(32 bits)) init 0
  val tag2 = Reg(Bits(T2_DEF_W bits)) init 0

  /** 무장 비트 — 워드마다 하나 (결정 A 1항). */
  val armed = RegInit(B(0, 3 bits))

  when(okTag0) { tag0 := io.wdata;                            armed(0) := True }
  when(okTag1) { tag1 := io.wdata;                            armed(1) := True }
  when(okTag2) { tag2 := io.wdata(T2_DEF_W - 1 downto 0);     armed(2) := True }
  // 잔류 소진 (결정 A 3항) — 발화 워드의 *수락된* 기입은 성립·불성립 무관하게
  // 셋을 전부 내린다. 마지막 대입이라 위 셋과 다투지 않지만, 애초에 한 접근은
  // 한 워드에만 닿으므로 겹칠 수 없다 (배타 디코드).
  when(okFire) { armed := 0 }

  private val abWords = Vec(tag0, tag1, B(0, 32 - T2_DEF_W bits) ## tag2)

  // 이중 방어 — 발화 시점에 스테이징의 예약 여백을 *같은 함수로* 다시 본다.
  // 기입 시점 거절이 이미 막고 있어 이 갈래는 도달 불가이며, 그것이 요점이다:
  // 스테이징 경로가 훗날 하나 더 생겨도 발화가 그것을 통과시키지 않는다.
  private val stagedRsvBad = Types.Tag.reservedNonZero(abWords) || (tag1 & B(A_TAG1_RSV, 32 bits)) =/= 0 // poison·trace 는 예약이 아니라 표면 마스크 (위 A_TAG1_RSV)

  // 발화 조건 (결정 A 2항) — 무장 완비가 연언에 들어간다. armed 는 *레지스터
  // 값*이므로 「앞선 사이클들의 기입」을 본다: 같은 사이클에 워드 하나를 쓰면서
  // 발화하는 것은 애초에 불가능하고(한 접근 한 워드), 무장이 그 사실을 상태로
  // 든다. 미완 발화는 무시 — badWrite 에도 들지 않는다.
  io.fire  := okFire && io.wdata(0) && armed.andR && !stagedRsvBad
  io.tag   := Types.Tag.fromWords(abWords)
  io.armed := armed
  io.badWrite := (io.wr && io.selTag1 && tag1RsvBad) || (io.wr && io.selTag2 && tag2RsvBad) || (io.wr && io.selFire && fireRsvBad)
}

/** WT64v1 top-level 조립.
  *
  * @param cfg      형상 파라미터 — Wt64Config 한 곳 정의 (승격 3건 반영:
  *                 ownEntries · cqDepth · stepProgDepth)
  * @param ehSlots  EH 슬롯 상한 — DecodeWalk·OperandDecode 는 같은 값으로
  *                 인스턴스돼야 한다 (OperandDecode 계약)
  * @param nCtxs    재조립 문맥 풀 크기 (Reassembly 승격 후보)
  * @param bodyW    조각 본문 폭 — 데이터 경로 형상 (§2.3.1 이 재구현 폭을
  *                 측정 후 결정으로 미룬다 — GenFabricMerge 와 같은 자리값)
  * @param memSlots MemOrderGate 동시 관리 슬롯 수
  */
class Wt64Top(
    val cfg:      Wt64Config = Wt64Config(),
    val ehSlots:  Int        = 4,
    val nCtxs:    Int        = 4,
    val bodyW:    Int        = 64,
    val memSlots: Int        = 4,
) extends Component {
  import XlateStore.{FRAME_W, VPN_W}
  import Wt64Top._ // 구역·워드 배정 — companion 스칼라독이 근거를 소유한다

  private val partW = log2Up(cfg.xlateParts)
  private val idxW  = log2Up(cfg.xlateIdx)
  // (xTagW — 옛 HI [27:0] 태그 폭 등식은 W3 에서 사라졌다: 분할은 XlateStore.idxOf/tagOf 한 정의)
  private val slotW = log2Up(cfg.slotCap) max 1

  // 파티션 필드는 8b 고정이다 (MASK_STATUS `[7:0]` maskReady · MASK_NONCE_PART ·
  // MASK_REKEY). 형상이 그 값 공간을 넘으면 워드 배치 합의부터 다시다 —
  // 조용히 자르지 않는다.
  require(cfg.xlateParts <= (1 << PART_FIELD_W),
    s"파티션 필드 ${PART_FIELD_W}b 초과 형상 — 마스킹 구역 워드 배치 합의부터 다시")
  require(cfg.xlateParts <= 8, "MASK_STATUS `[7:0]` 배치는 파티션 8 이하")

  /** MemOrderGate 불투명 기술자 폭 — 태그(통째) ‖ MEM 본문(addr_mode 4 ·
    * stride 12 · 오프셋 32, §1.3.2). 태그는 여기서도 불투명하다 —
    * MemOrderGate 는 해석하지 않고 나른다 (wave/addr_not_gating 의 전제). */
  private val mogReqW = Types.Tag.BUNDLE_W + 4 + 12 + 32 // 번들 70b — 예약 10b 는 번들에 없다 (Common.scala)

  // ═══ 인스턴스 — 15유닛 (XlateStore 는 HiuPipeline 내장 = 조립 14 + 1 · 문 xstg 는 파일 끝) ═══
  val walk   = new DecodeWalk(ehSlots)
  val od     = new OperandDecode(ehSlots)
  val rj     = new RouteJudge(cfg)
  val reasm  = new Reassembly(cfg, nCtxs, bodyW)
  val mog    = MemOrderGate(MemOrderGateParams(nSlots = memSlots, reqW = mogReqW))
  val hiu    = new HiuPipeline(cfg) // XlateStore 를 품는다 (§3.2 3단계)
  val own    = OwnershipTable(cfg, cfg.ownEntries) // 승격 반영 — 형상은 Wt64Config 한 곳
  val cfgBlk = MmioConfig(cfg)
  val merge  = FabricMerge(cfg, HardType(ResultBeat(bodyW)))
  /** 병합 지점 페이로드 폭 — SharedUnit 완료가 lane 0 으로 흐르기 위한 폭. */
  private val beatW = widthOf(merge.io.consumer.payload)
  val shared = new SharedUnit(SharedUnitParams(reqWidth = beatW))
  val bank   = new ResultBank(cfg, dataW = bodyW)
  val mask   = MaskUnit(cfg)
  val fps    = StepSequencer(StepSeqParams(progDepth = cfg.stepProgDepth)) // 승격 반영
  val cq     = new CompletionUnit(cfg.cqDepth) // 승격 반영
  /** E.12 소거의 호스트 대면 절반 — 태그 스테이징 + 무장 규율 + 발화 (결정 A).
    * 유일하게 *이 파일이 정의하는* 컴포넌트다 (다른 것은 자기 파일에 산다 — xstg 포함) —
    * MMIO 표면의 절반이라 조립의 소관이고, 잴 수 있게 이름을 준 것뿐이다. */
  val stg    = new AbortStaging
  /** 능력 부재 관측 워드 CAP_STATUS/CAP_CLEAR 의 *행위* — 축별 sticky · 수락
    * W1C · 예약 엄격 (2026-09-21 파도, 정본 1126a38 축 둘→넷). 축 수는 ABI
    * (`Fault.N_CAP_BITS`) 한 곳에서 흐르고, 컴포넌트가 스스로 유도한 예약
    * 마스크가 companion 의 `CAP_CLEAR_RSV` 와 같은지를 아래 require 가
    * 못박는다 — 출처가 하나여야 두 값이 따로 표류하지 않는다. */
  val capWord = CapStatusWord(nBits = Fault.N_CAP_BITS)
  require(capWord.rsvMask == CAP_CLEAR_RSV,
    f"CAP_CLEAR 예약 마스크 불일치 — 컴포넌트 0x${capWord.rsvMask}%08X vs companion 0x${CAP_CLEAR_RSV}%08X")

  // ═══ IO ══════════════════════════════════════════════════════════════
  val io = new Bundle {
    // ── 명령 제시 — 태그는 사이드밴드 (머리 주석 「태그 사이드밴드」) ────
    //    valid 하나가 words 와 tag 를 *함께* 유효화한다 — 태그에 독립 valid 를
    //    주지 않는 것이 「도착의 원자성」의 이행이다 (E.10 1항 재사용).
    //    태그는 *통째*로 온다 — 사이드밴드는 워드 표면이 아니므로 E.5.1 세 워드
    //    직렬화의 대상이 아니다 (E.5.4 규범 3항).
    val instr = new Bundle {
      val valid = in port Bool()
      val words = in(Vec(Bits(32 bits), walk.maxWords))
      val tag   = in(Types.Tag())
    }

    // ── 디코드 관측면 — 2차 소비자(EINSUM·즉치 소비 등) 미착지로 수출 ────
    val dec = new Bundle {
      val valid         = out port Bool()
      val malformed     = out port Bool()
      val capAbsent     = out port Bool()
      val execValid     = out port Bool()
      val portPresent   = out port Bool()
      val portDest      = out port UInt(Isa.LNID_W bits)
      val imm16Present  = out port Bool()
      val imm16         = out port Bits(16 bits)
      val imm32Present  = out port Bool()
      val imm32         = out port Bits(32 bits)
      val imm64Present  = out port Bool()
      val imm64         = out port Bits(64 bits)
      val memPresent    = out port Bool()
      val subValid      = out(Vec(Bool(), ehSlots))
      val subO          = out(Vec(Bits(16 bits), ehSlots))
      val subA          = out(Vec(Bits(16 bits), ehSlots))
      val subB          = out(Vec(Bits(16 bits), ehSlots))
      val subCount      = out port UInt(log2Up(ehSlots + 1) bits)
      /** OPREF A 존재 관측 — 값(lbid·srcKind)은 진입점 토큰이 소비한다. */
      val oprefAValid   = out port Bool()
      val oprefBValid   = out port Bool()
      val oprefBLbid    = out port UInt(Isa.LBID_W bits)
      val oprefBSrcKind = out port UInt(RouteJudge.SRC_KIND_W bits)
      val precPresent   = out port Bool()
      val precMode      = out port Bits(8 bits)
      val precDim       = out port Bits(8 bits)
      /** ACCTGT 조각열 선언 총개수 T (§1.4.7 · W4) — 관측 수출뿐, 기계 안
        * 소비자 없음 (Reassembly 사이드밴드와의 결선은 파도 밖 — B.5). */
      val acctgtTotal   = out port UInt(8 bits)
    }

    // ── 배달 범위 진입점 — 통과 토큰·발화 관측 (하류 배달 지점 미착지) ───
    val route = new Bundle {
      val tokOut    = master(Flow(RouteTok()))
      val faultFire = out port Bool()
    }

    // ── 재조립 — 개방 처분 관측 + 기입 면 수출 (LBID→슬롯 사상 미착지) ───
    val reasmOpenGranted = out port Bool()
    val reasmWr = new Bundle {
      val valid = out port Bool()
      val base  = out port UInt(Isa.LBID_W bits)
      val off   = out port UInt(log2Up(cfg.slotCap) bits)
      val body  = out port Bits(bodyW bits)
    }
    /** 구간 무효화 수출 — 소거가 회계뿐 아니라 구간 데이터까지 비운다는 계약
      * (결정 B). 한 beat = `base` 구간 전체(slotCap 칸) 무효화이며, 이행은
      * 슬롯 소유자의 의무다. 기입 면과 *다른 면*인 이유는 Reassembly 의
      * `io.clr` 스칼라독이 소유한다 (원자성 · 기입 면 무간섭 · 이행의 자연형).
      * ⚠ 이 verb 와 그 완결 시점은 정본 미규정 — rtl/README.md 등재. */
    val reasmClr = new Bundle {
      val valid = out port Bool()
      val base  = out port UInt(Isa.LBID_W bits)
    }

    // ── 순서 토큰 게이트 — 구성·완료·하류는 외부 (§4.4.3 필드 배정 미확정) ─
    val mem = new Bundle {
      val cfgPreds   = in(Vec(Bits(memSlots - 1 bits), memSlots))
      val epochClear = in port Bool()
      val complete   = in port Bits(memSlots bits)
      /** 잠정 — 디코드된 MEM 연산이 앉을 슬롯의 외부 결속 (TODO: 토큰
        * 채널이 명령 필드에 배정되면 상류(디코드)가 이 자리를 대체한다). */
      val slotSel  = in port UInt(log2Up(memSlots) bits)
      val upReady  = out port Bits(memSlots bits)
      val down     = Vec(master(Stream(Bits(mogReqW bits))), memSlots)
      val token    = out port Bits(memSlots bits)
      val gateOpen = out port Bits(memSlots bits)
    }

    // ── HIU 요청 경로 — 요청 원천(메모리 파이프) 미착지로 외부 제시 ──────
    val hiuReq = new Bundle {
      val valid = in port Bool()
      val ready = out port Bool()
      val part  = in port UInt(partW bits)
      val vpn   = in port UInt(VPN_W bits)
      val write = in port Bool()
    }
    val hiuHold = in port Bool()
    // ── 은퇴 (파도 3, 2026-09-26): io.install · io.flush ─────────────────
    //    항목 설치와 파티션 flush 의 원천은 이제 MMIO 문 하나다 — `0xC00`
    //    항목 표면(VPN · FRAME · COMMIT) · `0xE00` XLATE_FLUSH (파일 끝 xlateArea · XlateStaging).
    //    남겨 두면 설치 authority 가 둘이 된다: install 은 다필드 트랜잭션이라
    //    faultClear 식 논리합으로 합칠 수 없고, ready 없는 IO flush 가 MMIO
    //    flush 와 한 사이클에 겹치면 XlateStore 의 단일 flush 포트가 하나를
    //    조용히 잃으며, 스테이징과 V 규약을 우회하는 옆문이 된다. 채움 주체는
    //    호스트이고 호스트의 문은 MMIO 다 (E.3). 모델 XlateSurface.tla 도 이 문을
    //    유일한 원천으로 가정한다. 이 주석은 삭제한 선언과 줄 수가 같다 — 아래
    //    선언들의 줄 좌표(와 SpinalHDL 줄번호 이름)를 밀지 않기 위해서다.
    //
    //
    //
    val hostRsp = new Bundle {
      val valid = in port Bool()
      val frame = in port UInt(FRAME_W bits)
      val perm  = in(XlatePerm())
    }
    /** 승인 방출 관측 — frame 은 io.phys 가 나른다 (마스킹된 값 하나뿐). */
    val hiuRsp = new Bundle {
      val valid    = out port Bool()
      val granted  = out port Bool()
      val part     = out port UInt(partW bits)
      val write    = out port Bool()
      val fromFill = out port Bool()
      val perm     = out(XlatePerm())
    }
    /** 물리 프레임 방출 — 승인된 요청의 **마스킹된** 프레임 (E.9 — 마스킹
      * 단은 파이프 안 s4 다. 장치 밖으로 나가는 물리 프레임은 이것 하나). */
    val phys = new Bundle {
      val valid = out port Bool()
      val frame = out port UInt(FRAME_W bits)
    }

    // ── 패브릭 — lane 1..N-1 생산자(PE 산출)·dispatch 요청은 미착지 ──────
    val push = Vec(slave(ProducePort(HardType(ResultBeat(bodyW)))), cfg.nPoints - 1)
    val sharedReq = new Bundle {
      val valid   = in port Bool()
      val payload = in port Bits(beatW bits)
      val ready   = out port Bool()
    }
    /** lane 0(SharedUnit 완료)의 stall 관측 — 완료는 되물릴 수 없으므로
      * stall 은 §2.6 4항의 위반 표현(shove → loud fault)으로만 남는다. */
    val sharedPushStall = out port Bool()

    // ── 결과 뱅크 — 사상 착지 전 외부 포트 (TODO: Reassembly.wr 결선) ────
    val bank = new Bundle {
      val acqValid   = in port Bool()
      val acqSlot    = in port UInt(slotW bits)
      val acqProd    = in port UInt(4 bits)
      val acqGranted = out port Bool()
      val wrValid    = in port Bool()
      val wrSlot     = in port UInt(slotW bits)
      val wrProd     = in port UInt(4 bits)
      val wrData     = in port Bits(bodyW bits)
      val rdSlot     = in port UInt(slotW bits)
      val rdData     = out port Bits(bodyW bits)
      val rdOwned    = out port Bool()
    }

    // ── fp32 step sequencer — dispatch·피연산자 인출 경로 미착지 ─────────
    val fp = new Bundle {
      val reqValid  = in port Bool()
      val opKind    = in port Bits(8 bits)
      val precision = in port Bits(Isa.PRECISION_W bits)
      val a         = in port Bits(fps.p.dataW bits)
      val b         = in port Bits(fps.p.dataW bits)
      val c         = in port Bits(fps.p.dataW bits)
      val reqReady  = out port Bool()
      val done      = out port Bool()
      val execValid = out port Bool()
      val capAbsent = out port Bool()
      val progMal   = out port Bool()
      val result    = out port Bits(fps.p.dataW bits)
    }

    // ── MMIO — 4 KiB 구성 블록 (버스 프로토콜 어댑터는 이 밖) ────────────
    val mmio = new Bundle {
      val addr    = in port UInt(12 bits)
      val wstrobe = in port Bool()
      val wdata   = in port Bits(32 bits)
      val rstrobe = in port Bool()
      val rdata   = out port Bits(32 bits)
      val rvalid  = out port Bool()
      val ready   = out port Bool()
    }

    /** 완료 통지 인터럽트 (E.6 — opt-in 가속, reset 마스크). */
    val irq = out port Bool()

    // ── sticky fault 관측면 — 원천별로 가른다 (§5.6 — 여기서 접지 않는다) ─
    val fault = new Bundle {
      val decodeWalk    = out port Bool()
      val operandDecode = out port Bool()
      val route         = out port Bool()
      val reasm         = out port Bool()
      val reasmCap      = out port Bool() // 능력 부재 — fault 채널과 분리 (§1.6.2)
      val hiuPerm       = out port Bool() // FAULT_STATUS `[4]` — 자격 거부만 (HiuPipeline permViol)
      val hiuOwn        = out port Bool() // FAULT_STATUS `[19]` — 자격 허용 ∧ 비소유 프레임 접근 (HiuPipeline faultOwn). IO 해제선 없음 — 0xF84 [19] 하나
      val hiuMiss       = out port Bool() // 미적중 통지 — fault 아님 (§3.8)
      val cfgDupOwner   = out port Bool()
      val cfgBadWrite   = out port Bool()
      /** 이 조립이 직접 디코드하는 구성 표면(마스킹·step·소거·변환 문·식별)의 거절된 기입.
        * 새 맵의 FAULT_STATUS `[6]`「구성 — 거절된 구성 기입」과 같은 자리이며
        * cfgBadWrite 와 같은 부류다 — 두 신호를 여기서 접지 않는 이유는 원천 모듈이 다르고
        * (MmioConfig 는 자기 sticky 를 자기가 든다) top 이 하위 유닛의 sticky 를 대신 들 수
        * 없기 때문이다. 호스트 대면 표면(`0xF80[6]`)에서는 한 비트로 합류한다 (faultWords — 폴딩 지점). */
      val cfgSurfBadWrite = out port Bool()
      val fpCfgBadWrite = out port Bool() // FP_BIND(0xF04) [30:24] 예약 거절 — 수락(loadReady) 게이트된 별도 sticky (D1 (b) · 파일 끝 fpBindArea). 원천별 수출은 조립 cover 의 절단 무관 증인 콘 판별(④)을 지키려는 측정 구조다 — 기능은 [6] 한 비트 · 해제는 0xF84[6] 하나
      val xlateCfgBadWrite = out port Bool() // 0xC00 COMMIT 의 데이터 사유 거절(FRAME 유효 없는 V=1 · [27:0] 비0) — 수락(installSlotFree) 게이트된 별도 sticky (DP-15 · 파일 끝 xlateArea). fpCfgBadWrite 와 같은 측정 구조 — 기능은 [6] 한 비트 · 해제는 0xF84[6] 하나
      val ownCollide    = out port Bool()
      /** 소유권 구역의 거절된 구성 기입 — RO 오프셋(`0x204` OWN_STATUS) 쓰기. FAULT_STATUS `[6]`
        * 합류 (cqBadWrite 와 같은 부류). 전이 인코딩이 데이터 비트에서 오프셋으로 옮겨 가면서 `0x204`
        * 가 RW→RO 가 됐고, 앞판 드라이버의 이양 기입이 *조용히 사라지지 않게* 하는 자리다. */
      val ownBadWrite   = out port Bool()
      val fabricBp      = out port Bool()
      val sharedBp      = out port Bool()
      val bankWrite     = out port Bool()
      val maskNoMask    = out port Bool()
      val maskNonceDup  = out port Bool()
      val maskWrRekey   = out port Bool()
      val fpBp          = out port Bool()
      val fpBadProg     = out port Bool()
      val fpCapAbsent   = out port Bool() // 능력 부재 sticky — fault 아님 (§1.6.2)
      /** EH 사슬 용량 능력 부재 sticky — CAP_STATUS `[2]` (2026-09-21 파도).
        * fpCapAbsent 와 같은 등급 — fault 아님, FAULT_STATUS·SUMMARY 어느
        * 쪽에도 들지 않는다. 원천은 DecodeWalk 의 종결 등급이고 set 은
        * `oValid` 로 유효 한정한다: `io.dec.capAbsent` 는 유효 한정 없는 등급
        * 레벨, 이 sticky 는 oValid 로 한정 — 쓰레기 헤더 사이클에 둘이
        * 갈리는 것은 설계다. IO 해제선 없음 — CAP_CLEAR `[2]` W1C 로만. */
      val ehCapAbsent   = out port Bool()
      val cqOverflow    = out port Bool() // FAULT_STATUS `[16]`
      val cqBadWrite    = out port Bool() // 완료 구역의 거절된 구성 기입 — `[6]` 합류
    }
    /** 명시적 해제 — 신호별.
      *
      * 이 IO 선들은 장치 전역 fault 표면(`0xF84` W1C)이 서기 *전*의 해제
      * 경로였고, 표면이 선 지금은 둘의 **논리합**이 각 유닛의 clear 다 —
      * 어느 쪽도 다른 쪽을 무효화하지 않는다. fault 표면 파도 이후에 난 축 다섯
      * (`cqOverflow` · `cqBadWrite` · `fpCapAbsent` · `ehCapAbsent` · `hiuOwn` `[19]`)은 여기
      * 선이 없다: 정본이 정한 해제 표면이 MMIO 이고, 없는 경로를 새로 만들지 않는다. */
    val faultClear = new Bundle {
      val decodeWalk    = in port Bool()
      val operandDecode = in port Bool()
      val route         = in port Bool()
      val reasm         = in port Bool()
      val reasmCap      = in port Bool()
      val hiuPerm       = in port Bool()
      val hiuMiss       = in port Bool()
      val cfgDupOwner   = in port Bool()
      val cfgBadWrite   = in port Bool()
      val cfgSurfBadWrite = in port Bool()
      val ownCollide    = in port Bool()
      val fabricBp      = in port Bool()
      val sharedBp      = in port Bool()
      val bankWrite     = in port Bool()
      val maskNoMask    = in port Bool()
      val maskNonceDup  = in port Bool()
      val maskWrRekey   = in port Bool()
      val fpBp          = in port Bool()
      val fpBadProg     = in port Bool()
    }
  }

  // ═══ 장치 전역 fault 표면의 해제 펄스 — 선언만 여기 ═══════════════════
  //
  // `0xF84` W1C 가 내는 비트별 해제 펄스다. **선언과 구동을 가른 이유**는
  // 순서 하나뿐이다: 하위 유닛 결선이 이 파일에서 MMIO 디코드보다 앞에 있고,
  // 디코드는 `selFault`·`mmioAligned` 를 필요로 한다. 구동은 아래
  // `faultArea` 하나이며 (전 비트 한 곳에서 대입) 그 외 어디서도 대입하지
  // 않는다 — 해제 원천이 흩어지면 「무엇이 이 fault 를 내렸는가」에 답할 수
  // 없다 (§3.8 · §2.6 함정: 다른 동작이 fault 를 함께 내리는 것 금지).
  //
  // 형태는 *수락 사이클 하나 + 비트 선택*이다 — 비트마다 신호를 미리 만들면
  // 소비자 없는 축(`[17]` 엔트로피 — 원천 유닛 미착지)이 죽은 배선으로 남고,
  // 그것은 lint 가 잡아내는 종류의 「자리는 있는데 회로가 없다」이다. 함수로
  // 두면 *참조된 비트만* 회로가 되며, 참조되지 않았다는 사실이 곧 미배선의
  // 증거다 (비트 배치 자체는 companion 의 `Fault` 상수가 전수로 든다 — ABI 는
  // 회로 유무와 무관하게 확정돼 있다).
  //
  // `0xF90` CAP_CLEAR 는 여기 없다 — 그 수락과 축별 W1C 펄스(`capWord.io.clrAcc`)
  // 는 워드 컴포넌트가 내고, 상류에 sticky 를 둔 축 0 의 해제만 그 펄스를
  // 받아 Reassembly 로 나른다 (아래 reasm 결선).
  private val fltClrAccept = Bool() // `0xF84` 수락 (예약 비트 검사 통과)
  private def fclr(bit: Int): Bool = fltClrAccept && io.mmio.wdata(bit)

  // ═══ 디코드 사슬 — DecodeWalk → OperandDecode (방출면 1:1) ═══════════
  walk.io.iValid      := io.instr.valid
  walk.io.iInstr      := io.instr.words
  walk.io.iFaultClear := io.faultClear.decodeWalk || fclr(Fault.B_DECODE_WALK)

  od.io.iValid       := walk.io.oValid
  od.io.iMalformed   := walk.io.oMalformed
  od.io.iCapAbsent   := walk.io.oCapAbsent
  od.io.iExecValid   := walk.io.oExecValid
  od.io.iInstr       := walk.io.oInstr
  od.io.iSlotPresent := walk.io.oSlotPresent
  od.io.iSlotCode    := walk.io.oSlotCode
  od.io.iSlotOff     := walk.io.oSlotOff
  od.io.iFaultClear  := io.faultClear.operandDecode || fclr(Fault.B_OPERAND)

  /** 태그 사이드밴드 정렬 — DecodeWalk 방출 단(1 레지스터)과 같은 지연.
    * 태그는 통째로 나른다 — 슬라이스 없음 (§1.4.4 · E.5.4 규범 3항). */
  private val tagQ = RegNext(io.instr.tag)

  // 디코드 관측면 수출
  io.dec.valid         := od.io.oValid
  io.dec.malformed     := od.io.oMalformed
  io.dec.capAbsent     := od.io.oCapAbsent
  io.dec.execValid     := od.io.oExecValid
  io.dec.portPresent   := od.io.oPortPresent
  io.dec.portDest      := od.io.oPortDest
  io.dec.imm16Present  := od.io.oImm16Present
  io.dec.imm16         := od.io.oImm16
  io.dec.imm32Present  := od.io.oImm32Present
  io.dec.imm32         := od.io.oImm32
  io.dec.imm64Present  := od.io.oImm64Present
  io.dec.imm64         := od.io.oImm64
  io.dec.memPresent    := od.io.oMemPresent
  io.dec.subValid      := od.io.oSubValid
  io.dec.subO          := od.io.oSubO
  io.dec.subA          := od.io.oSubA
  io.dec.subB          := od.io.oSubB
  io.dec.subCount      := od.io.oSubCount
  io.dec.oprefAValid   := od.io.oOprefAValid
  io.dec.oprefBValid   := od.io.oOprefBValid
  io.dec.oprefBLbid    := od.io.oOprefBLbid
  io.dec.oprefBSrcKind := od.io.oOprefBSrcKind
  io.dec.precPresent   := od.io.oPrecPresent
  io.dec.precMode      := od.io.oPrecMode
  io.dec.precDim       := od.io.oPrecDim
  io.dec.acctgtTotal   := od.io.oAcctgtTotal

  // ═══ 배달 범위 진입점 — 실행 유효 명령의 토큰 제시 ═══════════════════
  // OPREF 부재 명령은 srcKind = 0(직접, 게이트 산출 0)이라 LBID 축(ISA-8)에
  // 불참하고 LNID 축만 판정받는다 — 게이트 산출 0 이 여기서 의미와 맞물린다.
  // TODO: OPREF B 의 토큰 제시는 미배선 (tokIn 은 사이클당 하나 — 제시
  // 직렬화는 후속. 그때까지 B 참조의 LBID 축 판정이 비어 있다).
  rj.io.tokIn.valid           := od.io.oExecValid
  rj.io.tokIn.payload.tag     := tagQ
  rj.io.tokIn.payload.lbid    := od.io.oOprefALbid
  rj.io.tokIn.payload.srcKind := od.io.oOprefASrcKind
  rj.io.viewWr     := cfgBlk.io.viewWr // Route.view_sync 직결 — 사이 단 없음
  rj.io.bankWr     := cfgBlk.io.bankWr
  rj.io.faultClear := io.faultClear.route || fclr(Fault.B_ROUTE)
  io.route.tokOut << rj.io.tokOut
  io.route.faultFire := rj.io.faultFire

  // ═══ 재조립 — 개방(D8)·조각 접수·인도·소거 ═══════════════════════════
  // 개방 = 디코드의 ACCTGT 결속 (§4.3 태그→구간 결속 — malformed 는 여기
  // 못 온다: oReasmBind 는 실행 유효 게이트를 지난 것만 발화한다).
  reasm.io.open.valid  := od.io.oReasmBind.valid
  reasm.io.open.tag    := tagQ
  reasm.io.open.base   := od.io.oReasmBind.payload
  io.reasmOpenGranted  := reasm.io.open.granted

  // 조각 = 병합 지점 소비자 (E.10 — 조각 머리는 자기 조각과 같은 beat).
  // Reassembly 는 모든 조각을 도착 사이클에 처분하므로 ready 상수 True 가
  // 곧 그 계약의 배선이다 — 병합 지점에 배압이 걸릴 일이 없다.
  reasm.io.frag.valid := merge.io.consumer.valid
  reasm.io.frag.head  := merge.io.consumer.payload.head
  reasm.io.frag.body  := merge.io.consumer.payload.body
  merge.io.consumer.ready := True

  // 기입 면 수출 — LBID→물리 슬롯 사상 미착지 (머리 주석 TODO 1항).
  io.reasmWr.valid := reasm.io.wr.valid
  io.reasmWr.base  := reasm.io.wr.base
  io.reasmWr.off   := reasm.io.wr.off
  io.reasmWr.body  := reasm.io.wr.body
  // 구간 무효화 수출 — 소거와 같은 사이클 (결정 B). 기입 면과 같은 소유자에게
  // 간다: 「어느 구간을 비우는가」의 좌표계가 io.reasmWr.base 와 같은 LBID 다.
  io.reasmClr.valid := reasm.io.clr.valid
  io.reasmClr.base  := reasm.io.clr.base

  reasm.io.faultClear     := io.faultClear.reasm    || fclr(Fault.B_REASM)
  // 능력 부재는 fault 가 아니므로 해제도 CAP_CLEAR(`0xF90`) 쪽이다 (§1.6.2).
  // 축 0 의 sticky 는 Reassembly 안(capBit)에 살고 워드 컴포넌트는 레벨을
  // 통과시킨다 — 수락된 W1C 펄스 clrAcc(0) 가 여기로 와서 그 sticky 를 내린다.
  // sticky 는 한 곳에만 산다 (CapStatusWord 머리 「이중 sticky 레이스」).
  reasm.io.capAbsentClear := io.faultClear.reasmCap || capWord.io.clrAcc(Fault.C_REASM_SLOT)

  // ═══ 순서 토큰 게이트 — 디코드 MEM 제시 + 외부 구성 (§4.4.3 잠정) ═════
  for (i <- 0 until memSlots) {
    mog.io.cfgPreds(i)   := io.mem.cfgPreds(i)
    // 제시 — MEM EH 를 나른 실행 유효 명령 하나가 슬롯 하나다. 슬롯 결속은
    // 외부 입력(잠정 — io.mem.slotSel 주석). 기술자는 불투명: 태그 통째 ‖
    // MEM 본문. upReady 하강 중의 제시 유실 관측은 upReady 수출이 진다.
    mog.io.up(i).valid   := od.io.oMemPresent && io.mem.slotSel === i
    mog.io.up(i).payload := tagQ.asBits ## od.io.oMemAddrMode ## od.io.oMemStride ## od.io.oMemOffset
    io.mem.upReady(i)    := mog.io.up(i).ready
    io.mem.down(i) << mog.io.down(i)
  }
  mog.io.epochClear := io.mem.epochClear
  mog.io.complete   := io.mem.complete
  io.mem.token      := mog.io.token
  io.mem.gateOpen   := mog.io.gateOpen

  // ═══ HIU — 요청 파이프 ↔ 소유권 표(E.7) ↔ 마스킹 단 ══════════════════
  hiu.io.req.valid := io.hiuReq.valid
  hiu.io.req.part  := io.hiuReq.part
  hiu.io.req.vpn   := io.hiuReq.vpn
  hiu.io.req.write := io.hiuReq.write
  io.hiuReq.ready  := hiu.io.req.ready
  hiu.io.hold      := io.hiuHold

  // 승인 조회 직결 (D11) — OwnershipTable 의 조합 0사이클 계약이 전제다.
  own.io.query.frame    := hiu.io.owner.frame
  hiu.io.owner.devOwned := own.io.query.devOwned

  // hiu.io.install · hiu.io.flush 는 파일 끝 xlateArea 가 구동한다 — 원천은
  // XlateStaging 하나다 (최상위 IO 은퇴, 위 io 번들의 은퇴 주석). 결선이
  // 파일 끝인 이유: 문의 컴포넌트·형상 require·ready 덮어쓰기를 한 자리에
  // 모으고, 이 위의 줄 좌표를 밀지 않는다. 이 주석은 삭제한 결선과 줄 수가
  // 같다.
  //
  //
  //
  //
  hiu.io.hostRsp.valid := io.hostRsp.valid
  hiu.io.hostRsp.frame := io.hostRsp.frame
  hiu.io.hostRsp.perm  := io.hostRsp.perm
  hiu.io.faultClear    := io.faultClear.hiuPerm || fclr(Fault.B_XLATE_PERM)
  hiu.faultOwnClear    := fclr(Fault.B_OWN_FRAME) // [19] — IO 해제선 없음 (io.faultClear 주석 규율). hiu.io.missClear 는 xlateArea 가 구동한다 (IO 해제선 ∨ 0xE10 MISS_CLEAR 수락)

  // 마스킹 단 (s4) — HiuPipeline io.mask 왕복의 반대편이 MaskUnit 이다.
  // 결선 계약(HiuPipeline io.mask 주석) 그대로: req↔rsp 직결, io.en 에
  // advance(= req.ready) — 정지 원천이 무엇이든 파이프와 마스킹 단이 함께
  // 선다 (stall_uniform). io.mask 는 MaskUnit 외에 결선하지 않는다.
  mask.io.en        := hiu.io.req.ready
  mask.io.req.valid := hiu.io.mask.req.valid
  mask.io.req.part  := hiu.io.mask.req.part
  mask.io.req.frame := hiu.io.mask.req.frame
  hiu.io.mask.rsp.valid := mask.io.rsp.valid
  hiu.io.mask.rsp.frame := mask.io.rsp.frame

  // 물리 프레임 방출 — 승인 방출에서 직접. 마스킹이 s4(승인 앞)에서 이미
  // 끝났으므로 rsp.frame 이 곧 마스킹된 프레임이고, 미승인 값 축은 0 이다
  // (approve_gates_value — granted 게이트는 그 관측의 명시화다).
  io.phys.valid := hiu.io.rsp.valid && hiu.io.rsp.granted
  io.phys.frame := hiu.io.rsp.frame

  io.hiuRsp.valid    := hiu.io.rsp.valid
  io.hiuRsp.granted  := hiu.io.rsp.granted
  io.hiuRsp.part     := hiu.io.rsp.part
  io.hiuRsp.write    := hiu.io.rsp.write
  io.hiuRsp.fromFill := hiu.io.rsp.fromFill
  io.hiuRsp.perm     := hiu.io.rsp.perm

  // ═══ 패브릭 — SharedUnit 완료 → 병합 lane 0 → (소비자) 재조립 ═════════
  shared.io.req.valid   := io.sharedReq.valid
  shared.io.req.payload := io.sharedReq.payload
  io.sharedReq.ready    := shared.io.req.ready
  shared.io.faultClear  := io.faultClear.sharedBp || fclr(Fault.B_SHARED_BP)

  // lane 0 — 완료는 파이프 끝의 되물릴 수 없는 사건이라 스트로브 그대로다.
  // stall 무시가 물리적으로 가능한 그 경계(§2.6 4항)이며 위반은 merge 의
  // shove → loud fault 가 받는다. stall 은 관측면으로 수출한다.
  merge.io.push(0).strb := shared.io.rsp.valid
  merge.io.push(0).result.assignFromBits(shared.io.rsp.payload)
  io.sharedPushStall := merge.io.push(0).stall

  // lane 1..N-1 — PE 산출 미착지: 외부 생산자 포트로 낸다.
  for (i <- 1 until cfg.nPoints) {
    merge.io.push(i).strb   := io.push(i - 1).strb
    merge.io.push(i).result := io.push(i - 1).result
    io.push(i - 1).stall    := merge.io.push(i).stall
  }
  merge.io.faultClear := io.faultClear.fabricBp || fclr(Fault.B_FABRIC_BP)

  // ═══ 결과 뱅크 — 외부 포트 (TODO: LBID 사상 착지 후 Reassembly.wr 결선) ═
  bank.io.acquire.valid := io.bank.acqValid
  bank.io.acquire.slot  := io.bank.acqSlot
  bank.io.acquire.prod  := io.bank.acqProd
  io.bank.acqGranted    := bank.io.acquire.granted
  bank.io.write.valid   := io.bank.wrValid
  bank.io.write.slot    := io.bank.wrSlot
  bank.io.write.prod    := io.bank.wrProd
  bank.io.write.data    := io.bank.wrData
  bank.io.read.slot     := io.bank.rdSlot
  io.bank.rdData        := bank.io.read.data
  io.bank.rdOwned       := bank.io.read.owned
  bank.io.faultClear    := io.faultClear.bankWrite || fclr(Fault.B_BANK_WRITE)

  // ═══ fp32 step sequencer — 요청은 외부 (dispatch 표 미착지) ═══════════
  fps.io.req.valid     := io.fp.reqValid
  fps.io.req.opKind    := io.fp.opKind
  fps.io.req.precision := io.fp.precision
  fps.io.req.a         := io.fp.a
  fps.io.req.b         := io.fp.b
  fps.io.req.c         := io.fp.c
  io.fp.reqReady       := fps.io.req.ready
  io.fp.done           := fps.io.oDone
  io.fp.execValid      := fps.io.oExecValid
  io.fp.capAbsent      := fps.io.oCapAbsent
  io.fp.progMal        := fps.io.oProgMal
  io.fp.result         := fps.io.oResult
  fps.io.faultClearBp      := io.faultClear.fpBp      || fclr(Fault.B_FP_BP)
  fps.io.faultClearBadProg := io.faultClear.fpBadProg || fclr(Fault.B_FP_BADPROG)

  // ═══ 완료 유닛 — 인도 → 완료 링 (E.5) + E.11 집계 ════════════════════
  // 인도 = 완료 통지 (E.6 1항 — 링 삽입이 유일한 통지 수단).
  //
  // **디스크립터 조립은 더는 이 파일에 없다.** 앞판은 여기서 12 B 를 비트로
  // 팩킹해 256b 포트에 실었고, 그 한 줄이 (i) 정본이 정한 적 없는 태그 80b
  // 팩킹 순서를 굳히고 (ii) 「32 B 중 12 B 만 유의미」를 코드 밖 사실로 남겼다.
  // 이제 top 은 인도 페이로드의 *이름*을 그대로 넘기고, 워드 정렬 + kind 배치와
  // 32 B 전량 기입은 E.5 를 소유한 유닛이 진다 (host/CompletionUnit.scala 의
  // 「완료 디스크립터」 절 · `HostDesc.completion`).
  //
  // 배압 보존: 링 가득 → comp.ready 하강 → 인도 대기 (Fabric.bp_relief 접점).
  cq.io.comp.valid := reasm.io.deliver.valid
  cq.io.comp.tag   := reasm.io.deliver.payload.tag
  cq.io.comp.base  := reasm.io.deliver.payload.base
  cq.io.comp.total := reasm.io.deliver.payload.total
  reasm.io.deliver.ready := cq.io.comp.ready

  // E.11 여섯 카운트 — §3.7 정의역 순서. 전부 해당 유닛의 점유 관측 포트
  // 실물이다 (①~⑤ 정확값 · ⑥ tokens 만 부분 — 머리 주석 TODO 4항.
  // DRAIN_ALLZERO 는 이제 ①~⑤ 축의 드레인 완주 증거다):
  cq.io.drain.pipe     := hiu.io.occupancy.resized    // ① s1..s6 유효 popcount
  cq.io.drain.pending  := shared.io.occupancy.resized // ② 보류 큐 + 본체 busy
  cq.io.drain.output   := merge.io.occupancy.resized  // ③ lane cnt 합 (병합 중 beat 포함 — capture_atomic)
  cq.io.drain.ownSlots := bank.io.occupancy.resized   // ④ ownerValid popcount
  cq.io.drain.contexts := reasm.io.occupancy.resized  // ⑤ active 총계 (인도 대기 포함)
  // ⑥ 부분 — cfgPreds 약속·미완료 토큰만. 발행 관측 착지까지 하한 (TODO).
  cq.io.drain.tokens   := mog.io.occupancy.resized

  io.irq := cq.io.irq

  // ═══ MMIO 디코드 — 구역 지도 (companion object Wt64Top) ══════════════
  //
  // 구역 판정은 **상수 접두 비교 하나**다 (배정 원칙 규칙 1). 범위 비교는
  // 한 곳도 만들지 않는다 — 비교기 개수가 곧 면적이고, 범위 비교는 경계를
  // 틀리게 적을 자리를 구역마다 하나씩 만든다.
  private val mmioAligned = io.mmio.addr(1 downto 0) === 0
  private def sel(r: Region): Bool = io.mmio.addr(11 downto r.loBit) === r.prefix
  /** 구역 안 워드 색인 — 바이트 오프셋 [loBit-1:2]. */
  private def word(r: Region): UInt = io.mmio.addr(r.wordHi downto 2)

  // ── 배선된 구역 ──────────────────────────────────────────────────────
  private val selOwn   = sel(R_OWN)
  private val selCq    = sel(R_CQ)    // 0x300–0x37F — 0x3FF 에서 좁혔다 (머리 주석)
  private val selCfg   = sel(R_LNID) || sel(R_LBID)
  private val selMask  = sel(R_MASK)
  private val selFp    = sel(R_FP)
  private val selAbort = sel(R_ABORT)
  private val selFault = sel(R_FAULT) // 장치 전역 fault — 이 파도가 배선했다

  // ── UNWIRED 구역 둘 + 변환 저장소 두 구역 ─────────────────────────────
  //
  // selSq 는 소비 회로를 구동하지 않고 selIdent 는 0xFF8 형상 읽기 하나만 구동하지만(파일 끝 identArea) *디코더가 구역을 열거한다*는
  // 사실 자체가 산출물이다: 「예약이라 이름이 없다」와 「이름은 있는데 회로가
  // 없다」가 코드에서 구별된다. 처분은 읽기 0 · 표 워드 쓰기 거절 + [6](파일 끝 pageArea — 판정 T1)이고,
  // 그것은 *소비자가 없어서*이지 표에 없어서가 아니다. 변환 두 구역은 파도 3.
  private val selSq    = sel(R_SQ)    // 명령 링 — 명령 방향 실물 0건
  private val selXent  = sel(R_XENT)  // 변환 항목 표면 — XlateStaging (파일 끝 xlateArea)
  private val selXctl  = sel(R_XCTL)  // 변환 저장소 제어 — XlateStaging (관측 값은 xlateArea 끝)
  private val selIdent = sel(R_IDENT) // HIU_ABI_VERSION — 판 번호가 §3.10 대기 · HIU_SHAPE(0xFF8) 읽기만 배선 (파일 끝 identArea)
  private val selUnwired = selSq || selIdent

  // 영역별 스트로브 게이트 — 한 접근은 정확히 한 블록에 닿는다.
  own.io.addr    := io.mmio.addr
  own.io.wdata   := io.mmio.wdata
  own.io.wstrobe := io.mmio.wstrobe && selOwn
  own.io.rstrobe := io.mmio.rstrobe && selOwn
  own.io.faultClearCollide := io.faultClear.ownCollide || fclr(Fault.B_OWN_COLLIDE)
  // 소유권 구역의 거절된 구성 기입 (RO 오프셋 OWN_STATUS 쓰기 — E.1.1). 완료
  // 유닛의 같은 부류와 마찬가지로 해제 표면은 MMIO `0xF84[6]` 하나이고
  // 전용 IO 선은 새로 만들지 않는다 (io.faultClear 주석의 규율).
  own.io.faultClearBadWrite := fclr(Fault.B_CFG_BADWRITE)

  cq.io.addr    := io.mmio.addr(7 downto 0)
  cq.io.wdata   := io.mmio.wdata
  cq.io.wstrobe := io.mmio.wstrobe && selCq
  cq.io.rstrobe := io.mmio.rstrobe && selCq
  // 완료 유닛의 두 sticky 는 자기 구역이 아니라 *장치 전역 fault 표면*이
  // 해제한다 (정본 E.1.2 — 링 오버플로는 `0xF80[16]`). 옛 착지는 완료 구역
  // 안에 자기 FAULT/FAULT_CLEAR 두 워드를 갖고 있었고, 그 자리가 새 맵에서는
  // 미정의 오프셋과 IRQ_STATUS 다 — 두 워드를 지우는 것이 이동의 안전 논거다.
  cq.io.faultClearOverflow := fclr(Fault.B_RING_OVF)
  cq.io.faultClearBadWrite := fclr(Fault.B_CFG_BADWRITE)

  cfgBlk.io.addr    := io.mmio.addr
  cfgBlk.io.wdata   := io.mmio.wdata
  cfgBlk.io.wstrobe := io.mmio.wstrobe && selCfg
  cfgBlk.io.rstrobe := io.mmio.rstrobe && selCfg
  cfgBlk.io.faultClearDup := io.faultClear.cfgDupOwner || fclr(Fault.B_CFG_DUP)
  cfgBlk.io.faultClearBad := io.faultClear.cfgBadWrite || fclr(Fault.B_CFG_BADWRITE)

  // ── 거절된 구성 기입 — 이 조립이 직접 디코드하는 표면의 발화선 ────────
  //
  // 처분의 축은 *방향*이다 — §3.7.1 함정의 축이고, 부록 E.1.1 이 그것을
  // 「이름표를 먼저 찾지 말고 방향을 먼저 물어라」로 적었다. 그 축을 이
  // 표면에 대면 갈래가 넷 나온다:
  //
  //   · 워드 안의 예약 *비트* 비0 기입 → **거절 + loud fault.** 결정 A
  //     (df49b24) 와 같은 형태·같은 논거다 — 호스트가 써 넣고 장치가 해석
  //     하는 「받아들이는 쪽」이므로 관대함은 검사받지 않는 비트를 남긴다.
  //     되돌림 비대칭도 그대로다: 엄격→관대는 무해하고 관대→엄격은 편도다.
  //   · RO 오프셋의 *쓰기* → **거절 + loud fault.** 쓰기는 장치가 받아들이는
  //     쪽이고, 조용히 무시하면 드라이버는 자기 쓰기가 먹혔다고 믿는다.
  //   · WO 오프셋의 *읽기* → 0 반환, fault 없음. 읽기는 장치가 *돌려주는*
  //     쪽이라 관대함이 하위 호환을 만들고, 무엇보다 WO 로 둔 이유 자체가
  //     그 값을 상태 표면에 싣지 않기 위해서다 (E.9 키 — 되읽기를 주면 그
  //     결정이 무효가 된다, §5.8). 아래 읽기 경로가 WO 워드를 *덮지 않는
  //     것*이 그 이행이다.
  //   · 구역 안의 미정의 *정렬* 워드 · 비정렬 읽기 → §3.7 예약 *오프셋* 정책
  //     그대로: 쓰기 무시 · 읽기 0 · fault 없음. 비정렬 쓰기 · 물려받은 구간 · 명령 링 표 워드 · 0xFFC 쓰기는 파일 끝 pageArea (판정 T1–T3 → 거절 + [6]).
  //
  // 형상 밖 파티션 값(`>= cfg.xlateParts`)도 거절이다. 필드가 8b 고정이라
  // 없는 파티션이 표현 가능하고, 조용히 자르면 파티션 4 를 재키잉하려던
  // 호스트가 파티션 0 의 키를 갈아 버린다. MmioConfig 의 「없는 지점 등록
  // 거절」(pointBad)과 같은 형태이며 같은 부류의 sticky 로 접힌다.
  private val surfBadWr = False

  // ── 마스킹 구역 (0xE80) — E.9 키 · 논스 · 재키잉 ──────────────────────
  //
  // 옛 `0xC00` 지역의 워드 색인 0..16 을 base 만 바꿔 옮겼다 (상대 배치
  // 불변). 이 구역이 마스킹 *하나*의 것이라는 사실이 규칙 2 의 이행이다 —
  // 옛 배정은 소비 유닛 셋을 한 디코드에 섞고 있었다.
  private val maskArea = new Area {
    val wordOff = word(R_MASK)
    val wr = io.mmio.wstrobe && selMask && mmioAligned
    val rd = io.mmio.rstrobe && !io.mmio.wstrobe && selMask && mmioAligned

    // 워드 처분 — 상수와의 등가/구간 비교. 오프셋 숫자를 여기 다시 적지
    // 않는다 (companion 의 상수가 유일한 출처다).
    val isKey       = wordOff < M_KEY_WORDS                                      // WO
    val isMaskPart  = wordOff === M_MASK_PART / 4                                // RW
    val isNonce     = wordOff >= M_NONCE0 / 4 &&
                      wordOff <= (M_NONCE0 / 4 + M_NONCE_WORDS - 1)              // WO
    val isRekey     = wordOff === M_REKEY / 4                                    // WO
    val isStatus    = wordOff === M_STATUS / 4                                   // RO

    /** 파티션 필드 — 8b 고정, 형상의 함수가 아니다 (INV-T1 정합). 합법 값
      * 검사는 폭이 아니라 *기입 시점 거절*로 선다 (MmioConfig 선례). */
    val partField = io.mmio.wdata(PART_FIELD_W - 1 downto 0).asUInt
    val partBad   = XlateStaging.partBad(partField, cfg.xlateParts) // 한 정의 —
                    // XLATE_FLUSH(XlateStaging) 도 같은 함수를 부른다 (파티션을 받는 표면 셋)

    // MASK_PART(0xEA0) — 키·논스 두 기입 모두의 대상 파티션 창 (정본
    // 7fa5f2e, e-defined.typ:344·351 7항 — 구 MASK_NONCE_PART 를 넓힌 것).
    val maskPart = Reg(UInt(partW bits)) init 0
    val mpWr     = wr && isMaskPart
    val mpRsvBad = (io.mmio.wdata & B(M_MASK_PART_RSV, 32 bits)) =/= 0
    val mpReject = mpWr && (mpRsvBad || partBad)
    // 거절된 기입은 레지스터를 움직이지 않는다 — 그래서 되읽기가 언제나
    // 「마지막으로 수락된 값」이고 호스트가 쓴 값과 항등이다 (정규화 없음).
    when(mpWr && !mpRsvBad && !partBad) { maskPart := partField.resized }

    // E.9 1항 키 기입 — 워드 0..7. 예약 비트 없음 (32b 전폭이 키 워드다).
    // 창(maskPart)이 가리키는 파티션의 슬롯에 앉는다 — 키도 논스와 같은
    // 창을 거친다(정본 7fa5f2e "임대별 키의 인코딩 — 창이지 평면 배열이
    // 아니다"). authority(재키잉 지목)는 이 창이 아니라 MASK_REKEY 기입
    // 하나다 — 아래 rekey.part 는 이 레지스터를 참조하지 않는다.
    mask.io.keyWr.valid := wr && isKey
    mask.io.keyWr.part  := maskPart
    mask.io.keyWr.idx   := wordOff(log2Up(M_KEY_WORDS) - 1 downto 0)
    mask.io.keyWr.data  := io.mmio.wdata

    // E.9 2항 논스 — 같은 창(maskPart) + 워드 기입.
    mask.io.nonceWr.valid := wr && isNonce
    mask.io.nonceWr.part  := maskPart
    // 논스 워드 색인 — 구역 워드 9..14 의 하위 3비트가 001..110 이라
    // (하위 3비트 − 1) 이 곧 논스 워드 0..5 다. 전폭 감산 뒤 절단(미사용
    // 상위 비트)을 만들지 않는 폭 정합 산술.
    mask.io.nonceWr.idx   := wordOff(2 downto 0) - 1
    mask.io.nonceWr.data  := io.mmio.wdata

    // E.9 4항 재키잉 — 기입이 발화. 엔진이 유휴가 아니면 수락되지 않고
    // MASK_STATUS `[9]` 로 관측된다 (무언 드롭 아님 — MaskUnit 계약).
    // flush 동반·드레인 순서는 호스트 ABI 의무다 (§3.10).
    val rkWr     = wr && isRekey
    val rkRsvBad = (io.mmio.wdata & B(M_REKEY_RSV, 32 bits)) =/= 0
    val rkReject = rkWr && (rkRsvBad || partBad)
    mask.io.rekey.valid := rkWr && !rkRsvBad && !partBad
    mask.io.rekey.part  := partField.resized

    // 상태 워드 (RO). 파티션 필드는 8b 고정 — 형상이 그 안에 든다 (require).
    val maskStat = Bits(32 bits)
    maskStat := 0
    maskStat(cfg.xlateParts - 1 downto 0) := mask.io.maskReady
    maskStat(8) := mask.io.busy
    maskStat(9) := mask.io.rekey.ready

    // 거절 — 예약 비트 · 형상 밖 파티션 · RO 오프셋 쓰기.
    when(mpReject || rkReject || (wr && isStatus)) { surfBadWr := True }

    // 읽기 — WO 워드(키·논스·재키잉)는 여기 없다: 읽기 0 이 그 결정의
    // 이행이다 (되읽기를 주면 §5.8 관측면 최소화가 무효가 된다).
    val readValue = Bits(32 bits)
    readValue := 0
    when(isMaskPart) { readValue := maskPart.asBits.resize(32) }
    when(isStatus)   { readValue := maskStat }
  }

  // ── step 프로그램 적재 구역 (0xF00) — @fabric 2.5 ─────────────────────
  //
  // HIU 표면이 아니라 *패브릭 실행 자원*의 적재면이므로 마스킹·소거와 구역을
  // 나눈다 — 드레인 규약 아래 재적재되는 주체가 다르다 (§3.7).
  private val fpArea = new Area {
    val wordOff = word(R_FP)
    val wr = io.mmio.wstrobe && selFp && mmioAligned
    val rd = io.mmio.rstrobe && !io.mmio.wstrobe && selFp && mmioAligned

    val isProg   = wordOff === F_PROG / 4   // WO
    val isBind   = wordOff === F_BIND / 4   // WO
    val isStatus = wordOff === F_STATUS / 4 // RO

    // 용량 밖 슬롯·색인과 step 워드의 예약 비트는 StepSequencer 가 자기
    // 계약으로 거절하고 faultBadProg (새 맵 FAULT_STATUS `[15]`) 로 크게
    // 알린다 — 여기서 두 번 검사하지 않는다. 검사가 두 곳에 있으면 둘이
    // 갈리고, 그때 어느 쪽이 정본인지 답할 수 없다.
    fps.io.progWr.valid := wr && isProg
    fps.io.progWr.slot  := io.mmio.wdata(31 downto 24).asUInt
    fps.io.progWr.idx   := io.mmio.wdata(23 downto 16).asUInt
    fps.io.progWr.step  := io.mmio.wdata(15 downto 0)

    // FP_BIND `[30:24]` 은 예약 — 엄격이다 (슬롯 필드가 8b 인데 en 비트가
    // `[31]` 이라 그 사이가 비었다. 그 자리를 관대하게 두면 슬롯 폭을
    // 넓히는 날 옛 드라이버의 쓰레기가 조용히 의미가 된다).
    val bindRsvBad = (io.mmio.wdata & B(F_BIND_RSV, 32 bits)) =/= 0
    fps.io.bindWr.valid := wr && isBind && !bindRsvBad
    fps.io.bindWr.key   := io.mmio.wdata(15 downto 0)
    fps.io.bindWr.en    := io.mmio.wdata(31)
    fps.io.bindWr.slot  := io.mmio.wdata(23 downto 16).asUInt

    when(wr && isStatus) { surfBadWr := True } // FP_BIND 예약 거절은 파일 끝 fpBindArea — 수락(loadReady) 게이트 (D1 (b))

    val fpStat = Bits(32 bits)
    fpStat := 0
    fpStat(0) := fps.io.loadReady
    fpStat(1) := fps.io.oBusy

    val readValue = Bits(32 bits)
    readValue := 0
    when(isStatus) { readValue := fpStat }
  }

  // ── 재조립 문맥 소거 구역 (0xF40) — E.12 ──────────────────────────────
  //
  // step 적재와 이웃하지만 구역을 가른다: 소거는 *드레인 완주를 위한 처분*
  // 이고 적재는 *구성*이라 호스트가 부르는 시점이 다르다.
  //
  // 태그 스테이징 3워드 + 발화 1워드인 이유: 태그 80b 는 32b 버스 한 번에
  // 실리지 않는다 — E.7 이 「한 워드 전이」로 얻은 원자성을 여기서는 명시적
  // 발화 워드가 대신한다 (부분 기입 상태는 발화 전엔 효과가 없다). 그
  // 「효과가 없다」는 2026-08-25 결정 A 로 *무장 규율*이 되어 관행에서 계약으로
  // 올라갔고, 무장 마스크 RO 워드(`0xF58`)가 그 계약의 관측면이다.
  // 무장 규율(결정 A)의 실물은 `AbortStaging` 이 든다 — 그 스칼라독이 네 항의
  // 근거를 소유한다. 이 Area 는 워드 디코드와 배선만 한다: 스테이징 레지스터·
  // 무장 비트·발화 조건이 조립에 흩어져 있으면 「부분 기입 무효과」를 잴 자리가
  // 조립 전체가 된다.
  private val abortArea = new Area {
    val wordOff = word(R_ABORT)
    val wr = io.mmio.wstrobe && selAbort && mmioAligned
    val rd = io.mmio.rstrobe && !io.mmio.wstrobe && selAbort && mmioAligned

    val isTag0 = wordOff === A_TAG0 / 4 // WO  스테이징 (무장 [0])
    val isTag1 = wordOff === A_TAG1 / 4 // WO  스테이징 (무장 [1] · [27:16] 엄격 — E.12 6항)
    val isTag2 = wordOff === A_TAG2 / 4 // WO  스테이징 (무장 [2] · 예약 [31:16] 엄격)
    val isFire = wordOff === A_FIRE / 4 // WO  발화     (무장 완비 요구 · 예약 [31:1] 엄격)
    val isCnt   = wordOff === A_COUNT / 4      // RO
    val isInc   = wordOff === A_INCOMPLETE / 4 // RO
    val isArm   = wordOff === A_ARM / 4        // RO  무장 마스크 (E.12.1 4항)

    stg.io.wr      := wr
    stg.io.selTag0 := isTag0
    stg.io.selTag1 := isTag1
    stg.io.selTag2 := isTag2
    stg.io.selFire := isFire
    stg.io.wdata   := io.mmio.wdata

    reasm.io.abort.valid := stg.io.fire
    reasm.io.abort.tag   := stg.io.tag

    // 거절된 구성 기입 둘: 워드 안 예약 비0 (AbortStaging 이 판정) · RO 오프셋
    // 쓰기 (여기서 판정 — 그 세 워드는 이 Area 의 것이다). *무장 미완 발화는
    // 여기 들지 않는다* — 무시는 거절이 아니다 (결정 A 2항 · E.12 3항).
    when(stg.io.badWrite || (wr && (isCnt || isInc || isArm))) { surfBadWr := True }

    val readValue = Bits(32 bits)
    readValue := 0
    when(isCnt)   { readValue := reasm.io.abortCount.asBits.resize(32) }
    when(isInc)   { readValue := reasm.io.incomplete.asBits.resize(32) }
    when(isArm)   { readValue := stg.io.armed.resize(32) }
  }

  // ── 장치 전역 fault 구역 (0xF80) — §3.8 · @sec:security 5.6 · 5.8 ─────
  //
  // fault 는 특정 유닛의 표면이 아니라 *장치 전역*이라 자기 구역을 갖는다.
  // fault 축 스물 중 열여덟은 하위 유닛이 드는 비트의 *배치*일 뿐이다(`[19]` 도 원천은
  // HiuPipeline faultOwn) — §3.8 의 「합성 가능한 sticky 비트」는 이 표면 이전에 이미
  // 만족이었고, 없던 것은 HIU-6 의 해제 경로였다. 능력 부재 워드의 sticky
  // `[1]`·`[2]`·`[3]` 은 `capWord`(host/CapStatusWord)가 든다 — 이 구역이
  // 직접 만드는 상태는 없다.
  //
  // 관측(STATUS)과 해제(CLEAR)의 비트 배치가 같다: 드라이버가 읽은 워드를
  // 그대로 되쓰면 *자기가 본 것만* 지운다. 그 사이에 새로 선 fault 는 1 을
  // 쓰지 않았으므로 살아남고, 같은 사이클에 서면 StickyFault 규약이 발화를
  // 이기게 한다 — 어느 쪽으로도 해제가 fault 를 삼키지 않는다.
  private val faultArea = new Area {
    val wordOff = word(R_FAULT)
    val wr = io.mmio.wstrobe && selFault && mmioAligned
    val rd = io.mmio.rstrobe && !io.mmio.wstrobe && selFault && mmioAligned

    val isStatus  = wordOff === Fault.STATUS / 4     // RO
    val isClear   = wordOff === Fault.CLEAR / 4      // WO  W1C
    val isSummary = wordOff === Fault.SUMMARY / 4    // RO
    val isCapSt   = wordOff === Fault.CAP_STATUS / 4 // RO
    val isCapClr  = wordOff === Fault.CAP_CLEAR / 4  // WO  W1C

    val clrRsvBad = (io.mmio.wdata & B(FLT_CLEAR_RSV, 32 bits)) =/= 0

    // 거절된 기입은 *한 비트도* 내리지 않는다 — 반쯤 수락이 없다 (E.9 논스
    // 파티션 스테이징과 같은 처분).
    val doClr = wr && isClear && !clrRsvBad

    // 해제 수락 — 여기 한 곳에서 구동한다 (선언은 위쪽, 근거는 그 주석).
    // 원천이 흩어지면 「무엇이 이 fault 를 내렸는가」에 답할 수 없다.
    fltClrAccept := doClr

    // CAP_CLEAR(`0xF90`) — 예약 판정·수락·축별 W1C 는 워드 컴포넌트의 것이다.
    // 여기는 정렬된 워드 스트로브만 넘긴다 (AbortStaging 과 같은 분업 —
    // 「어느 워드에 무엇을 썼는가」만 안다).
    capWord.io.wr    := wr && isCapClr
    capWord.io.wdata := io.mmio.wdata

    // 거절 — RO 오프셋 쓰기 · 예약 비트 비0 (E.1.1 엄격 · E.1.2 해설의
    // 「RO 오프셋 쓰기」). 자기 거절이 자기 워드(`[6]`)를 세우는 것은 순환이
    // 아니라 정의다 — 거절된 구성 기입의 관측면이 그 비트다. CAP_CLEAR 의
    // 예약 위반은 컴포넌트가 `rsvBad` 로 돌려준다 — 능력 부재의 오류가
    // 아니라 *구성 기입*의 오류이므로 같은 `[6]` 에 합류한다.
    when((wr && (isStatus || isSummary || isCapSt)) ||
         (wr && isClear && clrRsvBad) ||
         capWord.io.rsvBad) { surfBadWr := True }
  }

  // ═══ sticky fault 관측면 — 원천별 수출 (여기서 접지 않는다, §5.6) ═════
  io.fault.decodeWalk    := walk.io.oFault
  io.fault.operandDecode := od.io.oFault
  io.fault.route         := rj.io.fault
  io.fault.reasm         := reasm.io.fault
  io.fault.reasmCap      := reasm.io.capAbsent
  io.fault.hiuPerm       := hiu.io.faultPerm
  io.fault.hiuOwn        := hiu.faultOwn // [19] — 원인별 수출 (자격 거부 [4] 와 배타)
  io.fault.hiuMiss       := hiu.io.missNotice
  io.fault.cfgDupOwner   := cfgBlk.io.faultDupOwner
  io.fault.cfgBadWrite   := cfgBlk.io.faultBadWrite
  // 이 조립이 직접 디코드하는 구성 표면의 거절 — 세운다 / 명시적 해제 외엔 내리지 않는다
  // (StickyFault 규약: 해제와 발화가 같은 사이클이면 발화가 이긴다). 호스트 대면 표면은 `0xF80[6]`
  // 이고, 이제 배선됐다 — 해제는 `0xF84[6]` 이며 같은 비트가 MmioConfig·완료 유닛의 같은 부류도 내린다.
  io.fault.cfgSurfBadWrite :=
    StickyFault(surfBadWr, io.faultClear.cfgSurfBadWrite || fclr(Fault.B_CFG_BADWRITE))
  io.fault.ownCollide    := own.io.faultCollide
  io.fault.ownBadWrite   := own.io.faultBadWrite
  io.fault.fabricBp      := merge.io.fault
  io.fault.sharedBp      := shared.io.faultBpViolation
  io.fault.bankWrite     := bank.io.fault
  io.fault.maskNoMask    := mask.io.faultNoMask
  io.fault.maskNonceDup  := mask.io.faultNonceDup
  io.fault.maskWrRekey   := mask.io.faultWrDuringRekey
  io.fault.fpBp          := fps.io.faultBpViolation
  io.fault.fpBadProg     := fps.io.faultBadProg
  io.fault.cqOverflow    := cq.io.faultOverflow
  io.fault.cqBadWrite    := cq.io.faultBadWrite
  // ── 능력 부재 워드 — 축별 결선 (어느 사건이 어느 축인가는 여기가 든다) ──
  //
  // 워드의 *행위*(sticky · W1C · 예약 엄격 · 발화가 해제를 이긴다)는 `capWord`
  // 가 들고, 이 결선은 정본 E.1.2 표의 *배정*이다. 넷 중 어느 축도 다른 축의
  // 신호를 보지 않는다 — 접지 않는다.
  private val capSet = Vec(Bool(), Fault.N_CAP_BITS)
  /** `[0]` 재조립 슬롯 — pass-through. sticky 는 Reassembly 안(capBit)에 살고
    * 해제는 위 reasm.io.capAbsentClear 로 간다 (clrAcc(0) 가 그 펄스다). 워드
    * 컴포넌트에서도 sticky 로 들면 이중 sticky 라 해제 사이클에 상류 레벨이
    * 아직 1 이어서 발화가 이겨 영영 안 내려간다 — 그래서 레벨 통과다. */
  capSet(Fault.C_REASM_SLOT) := reasm.io.capAbsent
  /** `[1]` step 프로그램 미상주 — StepSequencer 의 `oCapAbsent` 는 종결 사이클
    * 1펄스라 관측면이 놓칠 수 있다. 정본 E.1.2 가 「능력 부재도 관측이 sticky
    * 여야 재시도 주체가 놓치지 않는다」고 정했으므로 그 sticky 를 워드
    * 컴포넌트가 든다 — 원천 모듈이 sticky 를 갖지 않는 축이다. **fault 가
    * 아니다** (§1.6.2): FAULT_STATUS 에도 FAULT_SUMMARY 에도 들지 않고
    * CAP_STATUS `[1]` 로만 나간다. */
  capSet(Fault.C_FP_PROG) := fps.io.oCapAbsent
  /** `[2]` EH 사슬 용량 — DecodeWalk 의 종결 등급 `oCapAbsent` 는 명령 첫
    * 워드의 선언 길이만 보고 iValid 와 무관하게 계산된다 (rCapa). 그래서 set 은
    * `oValid` 로 **유효 한정**한다 — 쓰레기 헤더로 `[2]` 가 서면 안 된다.
    * `io.dec.capAbsent` 는 유효 한정 없는 등급 레벨이고 이 sticky 는 oValid
    * 로 한정된다 — 쓰레기 헤더 사이클에 둘이 갈리는 것은 설계다. */
  capSet(Fault.C_EH_CHAIN) := walk.io.oValid && walk.io.oCapAbsent
  /** `[3]` 연산 미지원 — 세울 원천이 0건이다 (지원 여부를 판정하는 회로가
    * 재구현에 없다). 자리는 ABI 이고 상수 0 — rtl/README.md 「자리는 있고
    * 회로는 없다」 표가 행으로 든다. 컴포넌트의 sticky 는 일반 계약이라 남고,
    * set 이 False 라 그 비트는 서지 않는다. 원천이 서는 날 바뀌는 것은 이
    * 한 줄이다. */
  capSet(Fault.C_OP_UNSUPPORTED) := False
  capWord.io.set := capSet.asBits

  io.fault.fpCapAbsent   := capWord.io.word(Fault.C_FP_PROG)
  io.fault.ehCapAbsent   := capWord.io.word(Fault.C_EH_CHAIN)


  // ── 장치 전역 fault 의 읽기 워드 — 위 수출이 확정된 뒤에 조립한다 ──────
  //
  // 원천 대입(`io.fault.*`)과 워드 조립을 붙여 두는 이유: 비트 배정이 ABI 라
  // (§3.10) 「어느 신호가 몇 번 비트인가」를 한 화면에서 검산할 수 있어야 한다.
  private val faultWords = new Area {
    /** FAULT_STATUS (`0xF80`) — sticky 비트맵. `[31:20]` RO 예약 = 0. */
    val status = Bits(32 bits)
    status := 0
    status(Fault.B_DECODE_WALK) := io.fault.decodeWalk
    status(Fault.B_OPERAND)     := io.fault.operandDecode
    status(Fault.B_ROUTE)       := io.fault.route
    status(Fault.B_REASM)       := io.fault.reasm
    status(Fault.B_XLATE_PERM)  := io.fault.hiuPerm
    status(Fault.B_CFG_DUP)     := io.fault.cfgDupOwner
    // `[6]` 이 넷 + 다섯을 접는다 (E.1.2 해설). *여섯* 원천(MmioConfig · 이
    // 조립이 직접 디코드하는 표면 · FP_BIND 예약 거절(D1 (b)) · COMMIT 데이터 사유 거절(DP-15 — 둘 다 수락 게이트) · 완료 유닛 · 소유권 표)의 같은 부류가
    // *여기서* 한 비트로 합류한다 — 수리 주체가 드라이버 하나이고 고칠
    // 동작이 같다(자기가 방금 쓴 워드를 고쳐 다시 쓴다). 폴딩 지점을 명시
    // 하라는 §5.6 3항의 이행이며, 관측면 상류에서는 접지 않았다.
    status(Fault.B_CFG_BADWRITE) := io.fault.cfgBadWrite ||
                                    io.fault.cfgSurfBadWrite || io.fault.cqBadWrite ||
                                    io.fault.ownBadWrite || io.fault.fpCfgBadWrite || io.fault.xlateCfgBadWrite
    status(Fault.B_OWN_COLLIDE) := io.fault.ownCollide
    status(Fault.B_FABRIC_BP)   := io.fault.fabricBp
    status(Fault.B_SHARED_BP)   := io.fault.sharedBp
    status(Fault.B_BANK_WRITE)  := io.fault.bankWrite
    status(Fault.B_MASK_NOMASK) := io.fault.maskNoMask
    status(Fault.B_MASK_NONCE)  := io.fault.maskNonceDup
    status(Fault.B_MASK_REKEY)  := io.fault.maskWrRekey
    status(Fault.B_FP_BP)       := io.fault.fpBp
    status(Fault.B_FP_BADPROG)  := io.fault.fpBadProg
    status(Fault.B_RING_OVF)    := io.fault.cqOverflow
    // `[17]` 엔트로피 — 자리는 ABI 로 확정됐고 *세울 원천이* 없다 (엔트로피원
    // 유닛이 재구현에 미착지). 상수 0 이며 rtl/README.md 가 행으로 등재한다.
    // 비트를 비워 두는 것과 비트가 없는 것은 다른 사실이다.
    status(Fault.B_ENTROPY)     := False
    // `[18]` 명령 디스크립터 malformation — E.5.4 가 만든 새 원천이고 세울
    // 주체(명령 링 소비자)가 이 저장소에 없다. `[17]` 과 같은 부류·같은 처분:
    // 상수 0 이며 rtl/README.md 가 행으로 등재한다.
    status(Fault.B_CMD_DESC)    := False
    status(Fault.B_OWN_FRAME)   := io.fault.hiuOwn // `[19]` 비소유 프레임 접근 — 3.10 v1.0 묶음이 `[4]` 에서 원인별로 갈랐다 (HiuPipeline faultOwn)
    /** FAULT_SUMMARY (`0xF88`) — `[0]` 논리합. @sec:security 5.6 1항의 「종합
      * 오류 신호」이며 개별 노출을 *대체하지 않고 덧붙인다* — 폴딩이 진단
      * 정보를 버리는 거래가 되지 않는 유일한 형태다. 예약 비트가 0 이라
      * 워드 전체의 논리합이 곧 정의 비트 스물의 논리합이다. */
    val summary = Bits(32 bits)
    summary := 0
    summary(0) := status.orR

    /** CAP_STATUS (`0xF8C`) — *fault 가 아니다* (§1.6.2). 바이너리는 옳고 이
      * 기계가 지금 못 하는 것이며, FAULT_STATUS·FAULT_SUMMARY 어느 쪽에도
      * 들지 않는다. 위 `status` 에 이 네 비트가 없다는 사실이 그 이행이다.
      * 워드 자체는 컴포넌트가 낸다 — `[31:4]` = 0 도 그쪽이 든다. */
    val capStatus = Bits(32 bits)
    capStatus := capWord.io.word

    // WO 워드(CLEAR · CAP_CLEAR)는 아래에 없다 — 읽기 0 이 그 처분이다.
    val readValue = Bits(32 bits)
    readValue := 0
    when(faultArea.isStatus)  { readValue := status }
    when(faultArea.isSummary) { readValue := summary }
    when(faultArea.isCapSt)   { readValue := capStatus }
  }

  // ── ready — 영역별 (구성 검사·초기화 소거 중에는 그 블록이 낮춘다) ────
  io.mmio.ready := True
  when(selOwn) { io.mmio.ready := own.io.ready }
  when(selCq)  { io.mmio.ready := cq.io.ready }
  when(selCfg) { io.mmio.ready := cfgBlk.io.ready }
  // step 적재 두 워드의 *정렬 쓰기*만 선택자 표 초기화 소거를 기다린다 (StepSequencer 계약) — 읽기·비정렬은 기다리지 않는다 (D1 (b)).
  when(fpArea.wr && (fpArea.isProg || fpArea.isBind)) {
    io.mmio.ready := fps.io.loadReady
  }

  // ── 읽기 응답 병합 — 스트로브가 배타라 rvalid 도 배타다 ───────────────
  //
  // 이 조립이 직접 응답하는 네 구역(마스킹·step·소거·fault)은 하위 블록들과
  // 같은 1사이클 규약이다: 수락 다음 사이클에 rdata 유효.
  private val mapRd    = maskArea.rd || fpArea.rd || abortArea.rd || faultArea.rd
  private val mapRdReg = Reg(Bits(32 bits)) init 0
  private val mapRv    = RegNext(mapRd, False)
  when(mapRd) {
    mapRdReg := 0
    when(selMask)  { mapRdReg := maskArea.readValue }
    when(selFp)    { mapRdReg := fpArea.readValue }
    when(selAbort) { mapRdReg := abortArea.readValue }
    when(selFault) { mapRdReg := faultWords.readValue }
  }

  /** 표에 *없는* 오프셋 — §3.7 예약 오프셋 정책 (쓰기 무시 · 읽기 0). 물려받은 0x000–0x11F 도 여기 든다 — 읽기 0 · 쓰기는 pageArea 가 거절. */
  private val resvOffset = !(selOwn || selCq || selCfg || selXent || selXctl ||
    selMask || selFp || selAbort || selFault || selUnwired)

  // 예약 오프셋 · **미배선 구역** · 변환 두 구역의 읽기 · 네 구역의 비정렬 접근 —
  // 전부 읽기 0 이고 rvalid 는 돌려준다 (응답 없는 읽기는 버스 행 멈춤이다).
  // 한 식에 접지 않고 열거해 두는 이유: 전기적으로 같아도 *사실*이 다르다.
  // `selUnwired` 는 표에 있는 오프셋이고 (Sq·Ident) 소비자 회로만 없다 (Ident 의 0xFF8 은 rvalid 만 여기, 값은 identArea 끝이 덮는다). 변환 두
  // 구역은 WO 워드의 읽기 0(E.1.1) · 관측 세 워드의 rvalid 다 (값은 xlateArea 끝이 덮는다).
  private val resvRd = io.mmio.rstrobe && !io.mmio.wstrobe &&
    (resvOffset || selUnwired || selXent || selXctl ||
     ((selMask || selFp || selAbort || selFault) && !mmioAligned))
  private val resvRv = RegNext(resvRd, False)

  io.mmio.rvalid := own.io.rvalid || cq.io.rvalid || cfgBlk.io.rvalid || mapRv || resvRv
  io.mmio.rdata := 0
  when(own.io.rvalid)    { io.mmio.rdata := own.io.rdata }
  when(cq.io.rvalid)     { io.mmio.rdata := cq.io.rdata }
  when(cfgBlk.io.rvalid) { io.mmio.rdata := cfgBlk.io.rdata }
  when(mapRv)            { io.mmio.rdata := mapRdReg }

  mask.io.faultClearNoMask   := io.faultClear.maskNoMask   || fclr(Fault.B_MASK_NOMASK)
  mask.io.faultClearNonceDup := io.faultClear.maskNonceDup || fclr(Fault.B_MASK_NONCE)
  mask.io.faultClearWrRekey  := io.faultClear.maskWrRekey  || fclr(Fault.B_MASK_REKEY)

  // ═══ 변환 저장소의 MMIO 문 — 0xC00 형상 비노출 항목 표면 · 0xE00 저장소 제어 (파도 3 · W3) ═══
  //
  // 정본 3.9 · E.1.3 이 「내부만」으로 적던 두 행을 닫는 자리다 — 항목 설치 논리와 flush 논리는
  // XlateStore 에 있고, 없던 것이 호스트 쪽 문이다. 3.10 v1.0 묶음 RTL 파도 W3 (2026-10-13)가
  // 문을 형상 비노출 표면으로 바꿨다 — 호스트는 파티션 기저마다 VPN · FRAME · COMMIT 을 쓰고
  // 칸은 장치가 정한다. 선-formal 계약은 rtl/formal/tla/XlateSurface.tla 이고 그 가드 스물아홉의
  // RTL 주장(GUARD-MAP)은 XlateStaging.scala(스물넷) · XlateStore.scala 끝(넷) · 이 Area 아래
  // (commit_replaces_vpn 하나)에 있다. 이 Area 는 구역 선택 · 정렬 · VPN 분할 결선 · 정지 처분 ·
  // 데이터 사유 sticky 만 한다.
  //
  // 파일 *끝*에 둔 이유 셋: (1) 위쪽 줄 좌표를 한 줄도 밀지 않는다 (2) io.mmio.ready
  // 덮어쓰기가 위 영역별 ready when 들보다 *뒤*여야 한다 (마지막 대입이 이긴다)
  // (3) 컴포넌트 인스턴스를 이것을 부르는 결선과 같은 자리에 둔다 (Scala 본문
  // 초기화 순서 — 위쪽에서 참조하면 elaborate 가 NullPointerException 으로 죽는다).
  //
  // ## VPN 분할 — 한 정의 (DP-1 · DP-3 갈래 A″)
  //
  // 문은 VPN 32b 를 내고 여기서 XlateStore.idxOf/tagOf 로 칸 색인 · 태그를 가른다. 조회
  // (XlateStore 의 reqIdx · reqTag)가 *같은 함수*를 부르므로 같은 (파티션, VPN) 은 늘 같은 칸으로
  // 가서 덮이고(결과 (a) — 두 칸 동시 유효가 구조로 없다), V=0 COMMIT 은 그 칸의 유효를 내린다
  // (결과 (b)). 대기 중에는 XlateStore 의 fillShadow 가 그 칸의 옛 판을 가린다.
  //
  // ## 하류 거부의 처분 — 버스 정지 (D-2 · 정본 COMMIT 행의 하류 정지 규범)
  //
  // XlateStore 의 install.ready 는 그 파티션 채움 슬롯이 차 있으면 내려간다. 그때 COMMIT 워드
  // 기입의 mmio ready 를 그 슬롯 여유(installSlotFree)로 낮춰 *같은 기입*을 잡아 둔다 —
  //   03-hiu.typ:1133 「수락 중에는 ready 가 내려가 있으므로 중간 상태는 관측되지」
  // 정지는 주소 · 스테이징 상태로 적법한 COMMIT(xstg.io.needReady)에만 걸린다. 주소 · 상태
  // 사유의 거절은 기다리지 않는다(needReady = 0 — 거절선 badWrite 의 콘에 하류 상태가 없다).
  // 데이터 사유(FRAME 유효 없는 V=1 · [27:0] 비0)는 정지를 받고 수락 사이클에 거절된다
  // (xstg.io.badData — 아래 원천별 sticky). 정지는 유계다 — 정지된 COMMIT 이 버스를 잡고 있어
  // 새 설치가 오지 않는 동안 XlateStore 의 commitFire(= fillPend.orR)가 매 사이클 한 파티션씩
  // 비우므로 xlateParts 사이클 안에 풀린다(DP-21). D1(수락되지 않은 기입의 효과) 재발을 막는
  // 조건 넷: ① 커밋 · 데이터 거절은 needReady ∧ installReady(= 그 사이클의 ready — 둘 다
  // slotFree)로만, 주소 · 상태 거절은 needReady 가 아닌(ready = 1) 쓰기로만 ② ready 는
  // 주소 · 스트로브 · 상태만의 함수(wdata 비의존 — *구조로도*: needReady 콘에 wdata 가 없고 ready
  // 값은 hiu.installSlotFree 다 — scripts/lint_ready_cone.py 가 상주 검사) ③ 읽기는 ready 를
  // 낮추지 않는다(wstrobe 가 전건) ④ flush · MISS_CLEAR 발화는 io.mmio.ready 를 참조하지 않는다
  // — install.ready 는 flush.valid 를 조합으로 본다(flushSamePart). 배타가 깨지면 설치가 조용히
  // 버려진다 — 하네스 a_xonehot.
  val xstg = new XlateStaging(cfg.xlateParts)
  val xlateArea = new Area { // 공개 — 참조자가 없는 Area 는 private 이면 unused 로 컴파일이 멈춘다
    // 형상 — 창(512 B)이 거는 상한은 파티션 기저 넷(addr[8:7]) 하나다. 파티션당 칸 수 · 색인
    // 함수는 형상이고 표면에 없다 — 조용히 창 밖으로 넘치는 형상은 금지다 —
    //   e-defined.typ:803 「조용히 창 밖으로 넘치는 형상은 금지다」
    require(cfg.xlateParts <= 4,
      s"변환 항목 창(addr[8:7] 파티션 기저) 밖 형상 — 파티션 ${cfg.xlateParts}. 창을 넓히는 정본 개정이 선행한다")
    require(FRAME_W == XlateStaging.FRAME_W,
      s"XLATE_ENTRY_FRAME [31:0] 프레임 폭 ${XlateStaging.FRAME_W} ≠ FRAME_W $FRAME_W")
    require(VPN_W == XlateStaging.VPN_W,
      s"XLATE_ENTRY_VPN [31:0] VPN 폭 ${XlateStaging.VPN_W} ≠ VPN_W $VPN_W (VA 44b · 4 KiB 페이지)")

    val wrEnt    = io.mmio.wstrobe && selXent && mmioAligned
    val wrCtl    = io.mmio.wstrobe && selXctl && mmioAligned
    val isCommit = io.mmio.addr(Xent.PART_LO - 1 downto 2) === Xent.COMMIT / 4 // 기저 안 워드 addr[6:2] = COMMIT

    xstg.io.wrEnt        := wrEnt
    xstg.io.wrCtl        := wrCtl
    xstg.io.woff         := io.mmio.addr(R_XENT.wordHi downto 2) // addr[8:2]
    xstg.io.wdata        := io.mmio.wdata
    xstg.io.installReady := hiu.installSlotFree // 아래 ready 덮어쓰기와 같은 신호 (조건 ①)

    // 설치 — part 는 valid 와 무관하게 그 기입의 기저다 (install.ready 가 그 파티션을 본다).
    // 칸 색인 · 태그는 조회와 같은 함수로 VPN 에서 가른다 (commit_replaces_vpn — 아래 GUARD-MAP).
    hiu.io.install.valid := xstg.io.commit.valid
    hiu.io.install.part  := xstg.io.commit.part.resized
    hiu.io.install.idx   := XlateStore.idxOf(xstg.io.commit.vpn, idxW)
    hiu.io.install.tag   := XlateStore.tagOf(xstg.io.commit.vpn, idxW)
    hiu.io.install.frame := xstg.io.commit.frame.resized
    hiu.io.install.perm  := xstg.io.commit.perm
    hiu.io.install.v     := xstg.io.commit.v

    // flush · 미적중 해제 — 버스 ready 와 무관하다 (조건 ④).
    hiu.io.flush.valid := xstg.io.flush.valid
    hiu.io.flush.part  := xstg.io.flush.part.resized
    // 해제 원천 둘의 논리합 — IO 해제선과 0xE10 수락 [0]. 정지는 풀지 않는다 —
    // e-defined.typ:329 「*정지 자체는 이것으로 풀리지 않는다*」 (XlateStaging 에 그 배선이 없다).
    hiu.io.missClear := io.faultClear.hiuMiss || xstg.io.missClr

    // 거절 — 주소 · 상태 사유(없는 기저 · 예약-엄격 워드 · 짝 불일치 · 비0 VPN_HI) · FLUSH 예약/
    // 없는 파티션 · MISS_CLEAR 예약 · RO 세 워드 쓰기. 전부 FAULT_STATUS [6] 합류다.
    when(xstg.io.badWrite) { surfBadWr := True }
    // 데이터 사유 거절 — 수락(installSlotFree) 게이트된 원천별 sticky (DP-15). surfBadWr 에 매지
    // 않는 이유는 fpBindArea 와 같다: 조립 sticky 의 콘에 절단 핀(hiu installSlotFree)이 들면 조립
    // cover 의 절단 무관 증인 판별이 운다. 기능은 같다 — [6] 한 비트로 합류하고 해제는 0xF84[6] 하나다.
    io.fault.xlateCfgBadWrite := StickyFault(xstg.io.badData, fclr(Fault.B_CFG_BADWRITE))

    // 하류 거부 = 버스 정지. 주소 · 상태로 적법한 COMMIT 워드의 *정렬된 쓰기*만 (조건 ②③).
    // isCommit 은 needReady 의 부분식이지만 이 식이 COMMIT 워드임을 코드에서 읽히게 둔다.
    when(wrEnt && isCommit && xstg.io.needReady) { io.mmio.ready := hiu.installSlotFree }

    // ── 미적중 관측 값 — 0xE04 XLATE_STATUS · 0xE08/0xE0C XLATE_MISS_VPN (파도 4 · 판정 E04 (A)) ──
    // 선-formal rtl/formal/tla/XlateObs.tla (GUARD-MAP: 파이프라인 쪽 셋은 HiuPipeline.scala 끝,
    // 포장·읽기 쪽 셋은 이 파일 끝). 값의 뜻 — 정지 게이트 스냅샷 · 정지가 없으면 0 · 찢김
    // 없음 — 은 hiu 가 진다 (missStall · missPart · missVpn). 이 조립은 워드로 포장만 한다:
    //   STATUS = [0] missStall · [1] 미적중 sticky(io.missNotice) · [15:8] missPart(0 확장) · 나머지 0
    //   VPN_LO = missVpn[31:0] · VPN_HI = missVpn 의 32b 위 (VA 44b 형상은 VPN 32b 라 상수 0)
    // 읽기 수락 사이클에 잡아 다음 사이클에 낸다 (MmioConfig 포트 계약 「수락 다음 사이클에
    // rdata 유효」). rvalid 는 위 resvRv 그대로다(resvRd 가 selXctl 읽기를 이미 센다) —
    // 여기는 rdata 만 *마지막 대입*으로 덮는다. 정렬된 selXctl 읽기 전부가 이 경로다:
    // 표의 세 RO 워드 밖(WO 워드 · 표에 없는 워드)은 mux 기본값 0. 워드 색인은 addr[6:2]
    // 5b 전폭 — 0xE24 같은 별칭이 0xE04 로 읽히지 않는다. 읽기는 아무것도 해제하지 않는다:
    // 이 경로는 hiu 의 어떤 입력(missClear · install · flush)에도 닿지 않는다 (obs_read_pure).
    // 이 구역의 읽기 ready 는 1 이다(위 덮어쓰기는 COMMIT 쓰기만) — 수락 = rstrobe.
    val obsRd   = io.mmio.rstrobe && !io.mmio.wstrobe && selXctl && mmioAligned
    val obsWord = io.mmio.addr(6 downto 2)
    val obsStatus = B(0, 16 bits) ## hiu.missPart.resize(8).asBits ## B(0, 6 bits) ##
                    hiu.io.missNotice.asBits ## hiu.missStall.asBits
    val obsVpnLo = hiu.missVpn.resize(32).asBits
    val obsVpnHi = (if (VPN_W > 32) (hiu.missVpn >> 32).resize(32).asBits else B(0, 32 bits))
    val obsValue = Bits(32 bits)
    obsValue := obsWord.mux(
      (Xctl.STATUS >> 2)      -> obsStatus,
      (Xctl.MISS_VPN_LO >> 2) -> obsVpnLo,
      (Xctl.MISS_VPN_HI >> 2) -> obsVpnHi,
      default                 -> B(0, 32 bits))
    val obsReg = RegNextWhen(obsValue, obsRd) init (B(0, 32 bits))
    val obsRv  = RegNext(obsRd) init (False)
    when(obsRv) { io.mmio.rdata := obsReg }
  }

  // ═══ 페이지 처분 — 합의 전 · 소비 회로 없는 워드 · 비정렬 쓰기 (파도 4 페이지 통합) ═══
  //
  // 선-formal 계약은 rtl/formal/tla/MmioPage.tla 이고 그 가드 아홉의 RTL 주장(GUARD-MAP)은
  // 파일 맨 끝에 있다. 이 Area 는 정본 f229c8b 판정 넷의 조립 몫을 surfBadWr → FAULT_STATUS
  // [6] 로 잇는다 — T3 (d) 물려받은 0x000–0x11F · T1-i (β) 명령 링의 표 워드 다섯(RW 넷 +
  // RO SQ_HEAD) · T1-ii 0xFFC 쓰기 · T2 (a) 비정렬 쓰기. 넷 다 ready = 1 인 쓰기라(own · cq ·
  // cfg 밖 · FP 정지는 정렬 쓰기뿐 · 변환 정지는 정렬 COMMIT 뿐) 수락 = 스트로브이고 거절선의
  // 콘에 절단 핀이 없다 — 조립 cover 의 절단 무관 증인 판별(④)이 그것을 기계로 확인한다.
  // 읽기 경로는 바꾸지 않는다: 네 부류의 읽기는 이미 resvRd 의 0 이다 (0xFFC 는 합의 전
  // 값 0 — Ident.PRE_AGREEMENT). 파일 *끝*에 둔 이유는 xlateArea 와 같다 — 위쪽 줄 좌표
  // (when_Wt64Top_lNNNN)를 밀지 않는다.
  val pageArea = new Area { // 공개 — 참조자가 없는 Area 는 private 이면 unused 로 컴파일이 멈춘다
    // T3 (d) — 이 장치는 물려받은 구간에 워드를 두지 않는다. 접두 비교 둘(0x000–0x0FF ·
    // 0x100–0x11F)로 잡는다 — 범위 비교 0 (배정 원칙 규칙 1 의 정신). 정렬 여부 무관.
    val selLeg = io.mmio.addr(11 downto 8) === 0 || io.mmio.addr(11 downto 5) === (0x100 >> 5)
    val legWr  = io.mmio.wstrobe && selLeg
    // T1-i (β) — 소비 회로가 없는 RW 워드(SQ_BASE_LO/HI · SQ_SIZE · SQ_TAIL)의 쓰기는 거절 +
    // [6]. SQ_HEAD(0x38C)는 RO 라 E.1.1 이 이미 거절을 정했다. 완료 링 base 둘(0x300 · 0x304)은
    // CompletionUnit 이 진다. 표에 없는 0x394–0x3FC 는 예약 정책(정렬 쓰기 무시) 그대로다.
    val sqWord = word(R_SQ)
    val isSqRw = sqWord === Sq.BASE_LO / 4 || sqWord === Sq.BASE_HI / 4 ||
                 sqWord === Sq.SIZE / 4 || sqWord === Sq.TAIL / 4
    val isSqRo = sqWord === Sq.HEAD / 4
    val sqWr   = io.mmio.wstrobe && selSq && mmioAligned
    // T1-ii — 0xFFC HIU_ABI_VERSION 은 RO: 쓰기는 거절 + [6]. 읽기 값은 합의 전 0 이고 그 값의
    // 출처는 값 배선 0 건(resvRd)이다 — 합의가 비0 판을 정하는 날 이 require 가 먼저 운다.
    require(Ident.PRE_AGREEMENT == 0,
      "합의 전 판 값은 0 이다 — 비0 판은 3.10 합의가 정하고, 그때 resvRd 에서 0xFFC 를 빼고 읽기를 배선한다")
    val identWr = io.mmio.wstrobe && selIdent && mmioAligned && word(R_IDENT) === Ident.ABI_VERSION / 4
    // 3.10 v1.0 묶음 — 0xFF8 HIU_SHAPE 도 RO 다: 쓰기는 거절 + [6] 이고 효과가 없다 (읽기 값은 파일 끝 identArea).
    val shapeWr = io.mmio.wstrobe && selIdent && mmioAligned && word(R_IDENT) === Ident.HIU_SHAPE / 4
    // T2 (a) — 하위 두 비트 ≠ 0 쓰기는 sub-word 쓰기의 장치 포트 표현이다: 페이지 어디서든 거절 +
    // [6]. own · cq · cfg 세 구역은 유닛이 자기 수락(ready ∧ 스트로브)으로 거절한다(유닛
    // faultBadWrite — [6] 합류). 여기는 나머지 전부 — 조립 구역의 wr 은 전부 mmioAligned 를
    // 요구해 효과가 없다 (소거 스테이징의 무장도 서지 않는다 — E.12.1 1항).
    val unalWr = io.mmio.wstrobe && !mmioAligned && !(selOwn || selCq || selCfg)
    when(legWr || (sqWr && (isSqRw || isSqRo)) || identWr || shapeWr || unalWr) { surfBadWr := True }
  }

  // ═══ FP_BIND 예약 거절 — 수락 게이트된 별도 sticky (결함 D1 수리 갈래 (b)) ═══
  //
  // 0xF04 FP_BIND 의 [30:24] 예약 비0 은 거절 + [6] 이다. D1 이전에는 그 거절이 fpArea 안에서
  // 수락 *전에*(선택자 표 초기화 소거 중 · ready = 0) surfBadWr 을 세웠다. 이제 ready 하강은
  // 정렬 FP 쓰기에만 걸리고, 거절은 수락(fps.io.loadReady — 그 쓰기의 ready)된 기입에서만
  // 선다. surfBadWr 에 loadReady 를 매지 않고 원천별 sticky 로 뗀 이유는 측정이다: 조립
  // sticky 의 콘에 절단 핀(fps__io_loadReady)이 들면 cover 의 절단 무관 증인 판별(④)이 운다
  // (갈래 (a) 실측 — rtl/README.md 끝 장 「페이지 처분」). 기능은 같다 — [6] 한 비트로 합류하고 해제는
  // 0xF84[6] 하나다 (IO 해제선은 새로 만들지 않는다 — io.faultClear 주석의 규율).
  val fpBindArea = new Area { // 공개 — 위와 같은 이유
    val rej = fpArea.wr && fpArea.isBind && fpArea.bindRsvBad && fps.io.loadReady
    io.fault.fpCfgBadWrite := StickyFault(rej, fclr(Fault.B_CFG_BADWRITE))
  }

  // ═══ 0xFF8 HIU_SHAPE — 형상 읽기 (3.10 v1.0 묶음 RTL 파도 W1, 2026-10-11) ═══
  //
  // 정본 E.1.2 의 RO 워드: [7:0] 실재 파티션 수 · [23:8] 파티션당 저장 칸 수(*개수* — 로그가
  // 아니다) · [31:24] 0. 기본 형상(파티션 4 × 색인 16)에서 0x0000_1004 다. 값은 형상 cfg 한 곳
  // (cfg.xlateParts · cfg.xlateIdx)에서 오고, 「칸 수 = 색인 수」는 저장이 직접 사상 · 연관도 1 이라서
  // 다 — 그 전제를 아래 require 가 저장 인스턴스(hiu.xlate)의 실물 크기에 묶는다: 저장 줄 수가
  // 파티션 × 칸이고 파티션별 유효 비트 폭이 칸 수다(색인 하나에 후보 하나). 연관 형상이 들어오면
  // 이 require 가 먼저 운다 — 칸 수의 출처는 W3 부터 저장 쪽 한 정의(XlateStore.capPerPart)다. 옛
  // 생성 이름 when_XlateStore_l200 함정은 W3 의 이름 있는 installFire(DP-22)로 사라졌다.
  // 읽기는 xlateArea 관측 워드와 같은 꼴이다: rvalid 는 resvRd(selUnwired 가 selIdent 를 센다)가
  // 주고 여기는 rdata 만 *마지막 대입*으로 덮는다. 값이 elaborate 상수라 수락 사이클 스냅숏이 따로
  // 필요 없다. 쓰기 거절 + [6] 은 위 pageArea.shapeWr 이고, 0xFFC 는 합의 전 0 그대로다.
  val identArea = new Area { // 공개 — 위와 같은 이유
    val parts      = cfg.xlateParts
    val capPerPart = XlateStore.capPerPart(cfg) // 직접 사상 — 파티션당 저장 칸 수 = 색인 수 (한 정의)
    require(hiu.xlate.store.wordCount == parts * capPerPart &&
            hiu.xlate.validBits.forall(_.getWidth == capPerPart),
      s"HIU_SHAPE 칸 수 유도(직접 사상 · 연관도 1)가 저장 실물과 어긋난다 — 저장 줄 ${hiu.xlate.store.wordCount} · 파티션 $parts · 칸 $capPerPart")
    require(parts >= 1 && parts <= 0xFF && capPerPart >= 1 && capPerPart <= 0xFFFF,
      s"HIU_SHAPE 필드 밖 형상 — [7:0] 파티션 $parts · [23:8] 칸 $capPerPart (조용히 자르지 않는다)")
    val shape = B((capPerPart.toLong << 8) | parts.toLong, 32 bits)
    val rd = io.mmio.rstrobe && !io.mmio.wstrobe && selIdent && mmioAligned && word(R_IDENT) === Ident.HIU_SHAPE / 4
    val rv = RegNext(rd) init (False)
    when(rv) { io.mmio.rdata := shape }
  }

  // ═══ 0xEC4 MASK_DUP_CAPTURE — 읽기 결선 · 쓰기 거절 (3.10 v1.0 묶음 RTL 파도 W1, 2026-10-11) ═══
  //
  // 워드의 행위(첫 사건 보존 · 해제 · 세움 우선 · [16] = [12] 레지스터 그 자체)는 MaskUnit.dupCapture
  // 가 든다 — 이 Area 는 마스킹 구역의 워드 17 을 디코드해 읽기를 결선하고 쓰기를 거절할 뿐이다.
  // maskArea 안에 두면 그 아래의 피인용 좌표가 밀리므로 파일 끝에 둔다.
  // 읽기: 마스킹 구역의 다른 RO 워드와 같은 규약 — 수락 사이클(rd)의 값을 잡아 다음 사이클에 낸다
  // (MmioConfig 포트 계약 「수락 다음 사이클에 rdata 유효」). rvalid 는 mapRv 가 이미 준다(maskArea.rd
  // 가 이 워드를 센다 — maskArea.readValue 의 기본값 0 이 mapRdReg 에 실린다). 여기는 rdata 만
  // *마지막 대입*으로 덮는다(mapRv 대입보다 뒤). 읽기는 아무것도 해제하지 않는다 — 이 경로는
  // mask 의 어떤 입력(faultClearNonceDup · rekey · keyWr · nonceWr)에도 닿지 않는다.
  // 쓰기: RO 라 거절 + [6] (E.1.1) 이고 효과가 없다 — 캡처를 쓰는 MMIO 경로가 없다.
  val dupArea = new Area { // 공개 — 위와 같은 이유
    val isDup = word(R_MASK) === M_DUP_CAPTURE / 4
    val rd    = maskArea.rd && isDup
    val wr    = maskArea.wr && isDup
    val reg   = RegNextWhen(mask.dupCapture, rd) init (B(0, 32 bits))
    val rv    = RegNext(rd) init (False)
    when(wr) { surfBadWr := True }
    when(rv) { io.mmio.rdata := reg }
  }
}

// ── GUARD-MAP — AbortSurface 열셋 (파도 4, 2026-09-26) ──────────────────────
//
// 재조립 문맥 소거의 호스트 쪽 문(0xF40 구역)은 선-formal 없이 착지했다 (결정 A,
// 2026-08-25 — 정본 6.3 의 1단 결손). rtl/formal/tla/AbortSurface.tla 가 그 1단이고
// 가드 열셋의 RTL 주장이 아래다. 열둘은 AbortStaging(위 클래스), ro_rejected 와
// reject_loud 의 [6] 결선은 abortArea 다. 파일 머리가 아니라 끝에 둔 것은 앞쪽
// 익명 when 의 줄 좌표(when_Wt64Top_lNNNN)를 밀지 않기 위해서다 (XlateStaging 선례).
// sub-word(하위 두 비트 ≠ 0) 쓰기의 처분은 모델에서 가드가 아니라 상수 Subword 다 —
// 판정 T2 (a) 의 거절 + [6] 은 페이지 통합(pageArea.unalWr — 페이지 전역 한 식)이 착지했고 그
// 가드는 MmioPage.unaligned_rejected 한 줄이 진다 (아래 MmioPage 절). 이 모델의 Subword 는 "reject" 가 오늘의 RTL 이다.
//
// GUARD-MAP: AbortSurface.poison_trace_zero -> AbortStaging 의 tag1RsvBad = (wdata & A_TAG1_RSV) ≠ 0 이고 A_TAG1_RSV 는 [27] poison · [26] trace 를 포함한다 (태그 워드 코덱의 TAG1 필드 마스크 poison ‖ trace ‖ 예약 — 태그 코덱 전파 파도). 그 비트가 선 TAG1 기입은 okTag1 이 서지 않아 스테이징·무장 [1] 이 움직이지 않고 badWrite 의 TAG1 항이 선다
// GUARD-MAP: AbortSurface.epoch_word_rsv_strict -> 같은 tag1RsvBad 의 [25:16] 예약 절반 — 비0 TAG1 기입은 okTag1 이 서지 않고 badWrite 의 TAG1 항이 선다 (정본 E.1.2 0xF44 「처분은 셋 다 같다」 — 마스크가 한 벌이라 사유별 판정 회로가 따로 없다)
// GUARD-MAP: AbortSurface.shape_word_rsv_strict -> tag2RsvBad = (wdata & A_TAG2_RSV) ≠ 0 — [31:16] 비0 TAG2 기입은 okTag2 가 서지 않고 badWrite 가 선다. 마스크는 태그 워드 코덱(Types.Tag.TAG2_RSV_LO)에서 끌어온다
// GUARD-MAP: AbortSurface.fire_rsv_strict -> fireRsvBad = (wdata & A_FIRE_RSV) ≠ 0 — [31:1] 비0 발화 기입은 okFire 가 서지 않아 발화도 무장 소진도 없고 badWrite 가 선다
// GUARD-MAP: AbortSurface.ro_rejected -> abortArea 에서 0xF50 · 0xF54 · 0xF58(isCnt · isInc · isArm)의 정렬 쓰기는 surfBadWr 을 세우고, 워드 디코드가 배타라 stg 의 selTag0/1/2 · selFire 어느 것도 서지 않는다 — 스테이징·무장·발화 어느 것도 움직이지 않는다
// GUARD-MAP: AbortSurface.legal_first -> 스테이징 대입 · 무장 상승(armed(i) := True) · 무장 소진(armed := 0) · 발화(io.fire) 가 전부 okTag0/1/2 · okFire 의 when/연언 안에 있고, ok* 는 각 워드의 거절 판정(tag1RsvBad · tag2RsvBad · fireRsvBad)의 부정을 연언으로 든다 — 거절된 기입이 세우는 것은 badWrite 하나뿐이다 (워드의 적법성 검사가 무장보다 앞선다)
// GUARD-MAP: AbortSurface.reject_loud -> AbortStaging.badWrite = 세 거절 판정(TAG1 · TAG2 · FIRE)의 논리합이고, abortArea 가 그것과 RO 세 워드 쓰기를 surfBadWr → FAULT_STATUS [6] sticky(cfgSurfBadWrite)로 잇는다. 무장 미완 발화는 badWrite 에 들지 않는다 (무시는 거절이 아니다)
// GUARD-MAP: AbortSurface.arm_on_accept -> when(okTag0/1/2) 의 본문이 각각 armed(0/1/2) := True 를 대입한다 — 수락된 스테이징 기입은 무장 상태와 값에 무관하게 자기 비트를 세운다 (같은 사이클의 okFire 가 마지막 대입으로 이긴다 — 잔류 소진)
// GUARD-MAP: AbortSurface.arm_own_word -> 무장 비트 i 의 True 대입은 when(okTag_i) 안에만 있다 — 한 워드의 기입이 다른 워드의 비트를 세우는 경로가 없다
// GUARD-MAP: AbortSurface.stage_writes_value -> when(okTag_i) 가 매 수락 기입마다 tag_i := wdata 를 대입한다 (TAG2 는 정의 비트 [15:0] 만) — 무장이 이미 선 워드의 재기입도 값을 덮는다. 조건이 무장 상태를 보지 않는다
// GUARD-MAP: AbortSurface.fire_needs_armed -> io.fire 의 연언에 armed.andR 가 있다 — armed 는 레지스터 값이라 앞선 사이클들의 수락 기입 셋이 모두 와야 선다
// GUARD-MAP: AbortSurface.fire_needs_one -> io.fire 의 연언에 io.wdata(0) 이 있다 — [0]=0 의 수락된 발화 기입은 소거 없이 무장만 내린다
// GUARD-MAP: AbortSurface.fire_drains_arm -> when(okFire) { armed := 0 } — 전건이 okFire 이고 io.fire(소거의 성립)가 아니다. 무장 미완 · [0]=0 · 없는 태그 어느 경우든 수락된 발화 기입은 무장 셋을 전부 내린다

// ── GUARD-MAP — MmioPage 아홉 (파도 4 페이지 통합, 2026-09-26) ─────────────────────────
//
// 4 KiB 구성 페이지의 처분(rtl/formal/tla/MmioPage.tla)은 한 모듈의 것이 아니다 — 조립이 직접
// 디코드하는 구역은 이 파일이, own · cq · cfg 세 구역은 각 유닛이 자기 수락(ready ∧ 스트로브)
// 으로 진다. 가드당 저장소 전체 한 줄 규율이라 정식 줄은 여기 하나씩이고 유닛 쪽 이행 지점은
// 줄 안에 이름으로 든다. 발행 펄스 관례: fps.io.progWr/bindWr 와 own · cq · cfgBlk 의 스트로브는
// raw 로 나가고 유닛이 자기 수락으로 게이트한다 — StepSequencer 는 loadReady 로(그 유닛에는
// 형식 태스크가 0 건), 나머지 셋은 acceptW 로. 파일 끝에 둔 이유는 AbortSurface 절과 같다.
//
// GUARD-MAP: MmioPage.rsp_on_accept -> 조립이 직접 응답하는 읽기(mapRd · resvRd → rvalid)는 ready 가 1 인 접근에서만 선다 — ready 하강은 정렬 FP_PROG/FP_BIND *쓰기*(fpArea.wr — D1 (b))와 주소 · 상태로 적법한 XLATE_ENTRY_COMMIT *쓰기*(xlateArea 의 wrEnt ∧ isCommit ∧ xstg.io.needReady)뿐이라 이 구역의 읽기는 언제나 수락이고 rvalid 는 그 수락 다음 사이클 1펄스다. own · cq · cfg 구역의 rvalid 는 각 유닛의 acceptR(ready ∧ rstrobe) 다음 사이클이다 (own · cq 는 ready 상수 1 · cfgBlk 는 소거·CHECK 중 ready 0)
// GUARD-MAP: MmioPage.effect_on_accept -> 조립 구역 쓰기의 효과와 거절선(maskArea · dupArea · fpArea · abortArea · faultArea · xlateArea · pageArea 의 wr · surfBadWr)은 ready 가 1 인 쓰기에서만 선다 — 소거를 기다리는 FP_BIND 의 예약 거절은 surfBadWr 이 아니라 fpBindArea.rej(= fpArea.wr ∧ isBind ∧ bindRsvBad ∧ fps.io.loadReady) → io.fault.fpCfgBadWrite 로, 0xC00 COMMIT 의 데이터 사유 거절은 xstg.io.badData(= cmAcc ∧ cmDataBad) → io.fault.xlateCfgBadWrite 로 수락에 매이고, 정지된 COMMIT 의 커밋은 xstg 의 installReady 게이트(cmAcc)가 막는다. 발행 펄스 fps.io.progWr/bindWr 는 raw 이고 StepSequencer 가 loadReady 로 스스로 게이트하며(유닛 수락 관례), own · cq · cfgBlk 는 자기 acceptW 로 게이트한다
// GUARD-MAP: MmioPage.ro_rejected -> RO 워드의 정렬 쓰기는 거절 + [6] 이고 상태를 움직이지 않는다: 조립 구역은 maskArea(0xEC0) · dupArea(0xEC4 — 3.10 v1.0 묶음) · fpArea(0xF08) · abortArea(0xF50–0xF58) · faultArea(0xF80 · 0xF88 · 0xF8C) · xstg(0xE04–0xE0C) · pageArea(0x38C SQ_HEAD 의 isSqRo · 0xFF8 의 shapeWr · 0xFFC 의 identWr)가 surfBadWr 로, 유닛 구역은 OwnershipTable statusWr(0x204) · CompletionUnit isRoOff 가 자기 faultBadWrite 로
// GUARD-MAP: MmioPage.wo_read_zero -> WO 워드의 읽기는 0 이다: 조립 구역의 readValue 가 WO 워드(키 · 논스 · MASK_REKEY · FP_PROG · FP_BIND · ABORT_TAG0–2 · ABORT_FIRE · FAULT_CLEAR · CAP_CLEAR)를 덮지 않고, 변환 WO(0xC00–0xDFC — 기저마다 VPN · FRAME · COMMIT · VPN_HI 와 예약-엄격 28 워드(+0x10..+0x7C) 전부 · 0xE00 · 0xE10)는 resvRd(값 배선 0 건)로 0 을 낸다 · OwnershipTable 은 OWN_SET/OWN_CLR 에 rdSel 0 · CompletionUnit 은 IRQ_CLEAR 를 readValue 에서 뺀다
// GUARD-MAP: MmioPage.resv_lenient -> 표에 없는 *정렬* 워드 오프셋(0x120–0x1FF · 구역 안 미정의 워드 — 0xC00 기저의 예약-엄격 28 워드는 표의 워드라 여기 들지 않는다(nocons_rejected) · 0x394–0x3FC · 0xFC0–0xFF4)의 쓰기는 surfBadWr 을 세우는 어느 식에도 들지 않는다 — pageArea 의 식 다섯은 물려받은 구간 · 명령 링 표 워드 다섯 · 0xFF8 · 0xFFC · 비정렬만 들고, dupArea 는 0xEC4 하나만 든다(마스킹 구역의 정의 워드는 이제 0..17). 유닛 구역의 표 밖 정렬 오프셋도 유닛 거절식에 없다
// GUARD-MAP: MmioPage.unaligned_rejected -> 비정렬 쓰기는 페이지 어디서든 거절 + [6] 이고 효과가 없다: own · cq · cfg 밖은 pageArea.unalWr(= wstrobe ∧ !mmioAligned ∧ !(selOwn ∨ selCq ∨ selCfg)) → surfBadWr 이고 조립 구역의 wr 은 전부 mmioAligned 를 요구한다 · 세 유닛 구역은 MmioConfig chkUnalWr · OwnershipTable 과 CompletionUnit badWrite 의 (acceptW ∧ !aligned) 가 자기 faultBadWrite 로 (판정 T2 (a))
// GUARD-MAP: MmioPage.leg_write_rejected -> pageArea.legWr = wstrobe ∧ selLeg(접두 비교 둘 — addr[11:8] = 0 · addr[11:5] = 0x08) → surfBadWr. 이 구간은 ready 가 1 이라 수락 = 스트로브이고 어느 유닛 스트로브도 서지 않아 효과가 없다. 읽기는 resvOffset 경로의 0 이다 (판정 T3 (d))
// GUARD-MAP: MmioPage.nocons_rejected -> 소비 회로가 없는 RW 워드의 정렬 쓰기는 거절 + [6] 이다: 명령 링 넷(0x380 · 0x384 · 0x388 · 0x390 — pageArea.isSqRw) → surfBadWr · 완료 링 base 둘(0x300 · 0x304 — CompletionUnit isBase) → 그 유닛 badWrite · 0xC00 기저의 예약-엄격 28 워드(+0x10..+0x7C — 3.10 v1.0 묶음이 표의 워드로 등재) → XlateStaging isRsvw 의 entRej → badWrite → surfBadWr. 어느 쪽에도 저장 레지스터가 없어 읽기는 0 이다 (판정 T1-i β)
// GUARD-MAP: MmioPage.reject_loud -> 거절은 전부 FAULT_STATUS [6] 에 닿는다: 조립 거절선 surfBadWr → io.fault.cfgSurfBadWrite(StickyFault) · FP_BIND 예약 거절 → io.fault.fpCfgBadWrite · 0xC00 COMMIT 데이터 사유 거절 → io.fault.xlateCfgBadWrite · 유닛 faultBadWrite 셋(cfgBlk · own · cq)이 faultWords.status(B_CFG_BADWRITE) 논리합에서 한 비트로 합류한다. 해제는 0xF84[6] 하나다
// ── GUARD-MAP — 미적중 관측면(XlateObs.tla)의 포장·읽기 쪽 가드 셋 (파도 4, 2026-09-26) ──
// 파이프라인 쪽 셋(obs_part_stalled · obs_vpn_stalled · obs_no_residue)은 hiu/HiuPipeline.scala
// 파일 끝이 든다. 파일 *끝*에 둔 것은 앞쪽 익명 when 의 줄 좌표를 밀지 않기 위해서다.
// GUARD-MAP: XlateObs.obs_stall_live -> xlateArea 의 obsStatus[0] = hiu.missStall = missWait(s3.valid ∧ ¬lookAny — ¬(판정 래치 ∨ 조회 적중), HiuPipeline 클래스 끝 · 3.10 v1.0 묶음 W2)이다 — 지금 정지 중인가의 레벨이지 sticky 가 아니다. 정지가 풀리는 사이클(항목 기입의 채움 바이패스 적중)에 0 이 되고, 판정이 래치된 요청은 hold 로 머무는 동안 그 항목이 밀려나도 다시 1 이 되지 않는다
// GUARD-MAP: XlateObs.obs_sticky -> obsStatus[1] = hiu.io.missNotice = StickyFault(set = missWait, clear = missClear) — 미적중 sticky 그 자체다(set 원천 missWait 는 판정 래치를 아는 정지다 — 래치된 요청의 항목이 밀려나도 [1] 을 세우지 않는다). [0] 과 [1] 은 서로 다른 넷에서 온다 — 정지가 끝나도 [1] 은 0xE10 해제(또는 IO 해제선)가 내릴 때까지 1 이다
// GUARD-MAP: XlateObs.obs_read_pure -> 읽기 경로(obsRd → obsReg/obsRv → io.mmio.rdata)는 레지스터 두 개와 rdata 덮어쓰기뿐이다 — hiu.io.missClear(= IO 해제선 ∨ xstg.io.missClr — 문의 0xE10 *쓰기*) · hiu.io.install · hiu.io.flush(문의 쓰기 판정)의 콘에 rstrobe 가 없다. 읽기는 hiu 에 해제 · 설치 · flush 어느 명령도 내지 않고, hiu 의 요청 · hold · hostRsp 입력은 최상위 IO 직결이라 읽기가 닿지 않는다 (조립 하네스 a_hiu_pass · hiu 가 그 명령 없이 sticky 를 내리지 않는다는 절반은 obs_sticky — HiuPipeline 의 StickyFault)
// ── GUARD-MAP — XlateSurface 의 조립 쪽 가드 하나 (3.10 v1.0 묶음 W3, 2026-10-13) ──────────────────
// 문의 스물넷은 XlateStaging.scala, 저장 쪽 넷은 hiu/XlateStore.scala 끝이 든다. 이 가드가 여기 있는
// 이유: 문은 VPN 을 내고 칸 색인 · 태그를 가르는 결선이 xlateArea 에 산다. RTL 측정은 이중 유효
// 불변식이 아니라 XlateDoor/door.sby 의 (a)(b) 단언이다 — 설치와 조회가 다른 분할을 쓰는 결함은 조회
// 후보가 한 칸뿐이라 「두 칸 동시 유효」로 나타나지 않고 V=1 미적중 · V=0 뒤 적중으로 나타난다.
// GUARD-MAP: XlateSurface.commit_replaces_vpn -> xlateArea 의 hiu.io.install.idx := XlateStore.idxOf(xstg.io.commit.vpn, idxW) · hiu.io.install.tag := XlateStore.tagOf(xstg.io.commit.vpn, idxW) 가 XlateStore 조회의 reqIdx = idxOf(lookup.vpn, idxW) · reqTag = tagOf(lookup.vpn, idxW) 와 *같은 함수*다 — 같은 (파티션, VPN) 의 COMMIT 은 늘 같은 칸(commitSel @@ idx)으로 가서 그 칸을 덮으므로 그 (파티션, VPN) 이 두 칸에 유효할 수 없고, 대기 중에는 fillShadow 가 그 칸의 옛 판을 가린다 (직접 사상 · 연관도 1 — DP-1 · DP-2)
