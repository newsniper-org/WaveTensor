// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// Wt64Top — WT64v1 재구현의 top-level 조립.
//
// 착지한 유닛 전부를 한 지붕 아래 인스턴스하고, 보고서(promote)가 확정한
// 경계 계약대로 배선한다. 이 파일은 **조립**이다 — 판정·상태·fault 의 원천은
// 전부 하위 유닛에 있고, 여기서 새로 만드는 상태는 MMIO 잠정 표면의 스테이징
// 레지스터(E.9 논스 파티션 선택·E.12 소거 태그)뿐이다.
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
// ## MMIO 디코드 — E.1 영역 배치 그대로 + 잠정 확장 (모두 4 KiB 블록 안)
//
//   0x000–0x1FF  기존 배정·예약 (E.1) — 이 조립은 배선하지 않는다: 쓰기 무시 ·
//                읽기 0 (§3.7 예약 *오프셋* 정책)
//   0x200–0x2FF  OwnershipTable (E.7)
//   0x300–0x3FF  CompletionUnit (E.5 · E.6 · E.11 드레인 읽기)
//   0x400–0x7FF  MmioConfig — LNID 소유 표 (§3.7.1)
//   0x800–0xBFF  MmioConfig — LBID 사상표 (§3.7.1)
//   0xC00–0xCFF  **잠정 배정** (E.1 은 예약 — 개정 제안, 보고서 model_feedback):
//                E.9 키·논스·재키잉 / step 프로그램 적재(§2.5) / E.12 문맥 소거.
//                E.9·E.12 는 정본이 MMIO 표면을 규범으로 세웠으나 E.1 이
//                오프셋을 배정하지 않았다 — 배정 없는 표면은 배선할 수 없으므로
//                여기서 잠정 확정하고 되돌린다. 워드 배치는 아래 loc Area.
//   그 밖        예약 — 쓰기 무시 · 읽기 0 (§3.7)
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
// ## 태그 사이드밴드 (잠정)
//
// 명령 제시(io.instr)는 태그를 사이드밴드로 동반한다 — 조각 머리가 조각과
// 같은 beat 에 있는 것(E.10 도착의 원자성)과 같은 처분이다. 태그는 통째로만
// 나른다 — 조립·분해는 Types.Tag 한 곳 (§1.4.4 · wave 불투명 식별자: 등가
// 비교·보존 외 해석 없음. 이 파일에 태그 슬라이스는 없다).
//
// ## GUARD-MAP 정식 줄 없음 — 접점 서술 (lint 가 파싱하지 않는 형태)
//
//   · Route.view_sync (정식 줄: RouteJudge) — MmioConfig.viewWr/bankWr 를
//     RouteJudge 에 **직결**한 것이 이 파일이다. 사이 레지스터 단 없음 —
//     기입 사이클 즉시 반영이라는 그 줄의 전제가 배선으로 성립한다.
//   · Platform.owner_check (정식 줄: HiuPipeline) — 판정이 소비하는
//     io.owner.devOwned 의 원천을 OwnershipTable.query 로 직결했다. 조합
//     0사이클 계약(OwnershipTable io.query 주석)이 승인(D11)의 전제다.
//   · Fabric.bp_relief (정식 ENV 줄: FabricMerge — 불변) — 호스트 배수
//     의무의 장치 쪽 실물(완료 링)에 Reassembly.deliver 를 배압 보존으로
//     이었다 (deliver.ready = comp.ready — 링 가득이면 인도가 선다).
//   · Decode.stall_uniform (정식 줄: HiuPipeline) — 마스킹 단(s4)의 몸인
//     MaskUnit 의 io.en 에 파이프 advance(= hiu.req.ready)를 그대로
//     물렸다 — HiuPipeline 결선 계약의 통합자 몫 이행. 정지 원천이
//     무엇이든 파이프와 s4 왕복이 함께 선다.
//   · Isolation.no_early_forward (정식 줄: HiuPipeline) — hiu.io.mask 는
//     MaskUnit 하나에만 직결했다. req 를 다른 소비자에 내지 않고 rsp 를
//     MaskUnit 밖에서 구동하지 않는다 (io.mask 주석의 결선 계약).
package wt64.top

import spinal.core._
import spinal.lib._
import wt64._
import wt64.decode.{DecodeWalk, OperandDecode}
import wt64.route.{RouteJudge, RouteTok}
import wt64.payload.Reassembly
import wt64.memorder.{MemOrderGate, MemOrderGateParams}
import wt64.hiu.{HiuPipeline, MmioConfig, OwnershipTable, XlatePerm, XlateStore}
import wt64.fabric.{FabricMerge, ProducePort, ResultBank, ResultBeat, SharedUnit, SharedUnitParams}
import wt64.mask.MaskUnit
import wt64.fp.{StepSeqParams, StepSequencer}
import wt64.host.CompletionUnit

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

  private val partW = log2Up(cfg.xlateParts)
  private val idxW  = log2Up(cfg.xlateIdx)
  private val xTagW = VPN_W - idxW
  private val slotW = log2Up(cfg.slotCap) max 1

  // MASK_STATUS 워드 배치([7:0] = maskReady)가 넘치지 않는 형상만 받는다.
  require(cfg.xlateParts <= 8, "MASK_STATUS 잠정 배치는 파티션 8 이하 — 넘으면 loc 워드 배치 합의부터 다시")

  /** MemOrderGate 불투명 기술자 폭 — 태그(통째) ‖ MEM 본문(addr_mode 4 ·
    * stride 12 · 오프셋 32, §1.3.2). 태그는 여기서도 불투명하다 —
    * MemOrderGate 는 해석하지 않고 나른다 (wave/addr_not_gating 의 전제). */
  private val mogReqW = Isa.TAG_W + 4 + 12 + 32

  // ═══ 인스턴스 — 15유닛 (XlateStore 는 HiuPipeline 내장 = 조립 14 + 1) ═══
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

  // ═══ IO ══════════════════════════════════════════════════════════════
  val io = new Bundle {
    // ── 명령 제시 — 태그는 사이드밴드 (머리 주석 「태그 사이드밴드」) ────
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
    val install = new Bundle {
      val valid = in port Bool()
      val ready = out port Bool()
      val part  = in port UInt(partW bits)
      val idx   = in port UInt(idxW bits)
      val tag   = in port UInt(xTagW bits)
      val frame = in port UInt(FRAME_W bits)
      val perm  = in(XlatePerm())
    }
    val flush = new Bundle {
      val valid = in port Bool()
      val part  = in port UInt(partW bits)
    }
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
      val hiuPerm       = out port Bool()
      val hiuMiss       = out port Bool() // 미적중 통지 — fault 아님 (§3.8)
      val cfgDupOwner   = out port Bool()
      val cfgBadWrite   = out port Bool()
      val ownCollide    = out port Bool()
      val fabricBp      = out port Bool()
      val sharedBp      = out port Bool()
      val bankWrite     = out port Bool()
      val maskNoMask    = out port Bool()
      val maskNonceDup  = out port Bool()
      val maskWrRekey   = out port Bool()
      val fpBp          = out port Bool()
      val fpBadProg     = out port Bool()
      val cqOverflow    = out port Bool() // 해제는 MMIO FAULT_CLEAR (호스트 대면 표면)
    }
    /** 명시적 해제 — 신호별 (cqOverflow 는 자기 MMIO 표면으로 해제한다). */
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

  // ═══ 디코드 사슬 — DecodeWalk → OperandDecode (방출면 1:1) ═══════════
  walk.io.iValid      := io.instr.valid
  walk.io.iInstr      := io.instr.words
  walk.io.iFaultClear := io.faultClear.decodeWalk

  od.io.iValid       := walk.io.oValid
  od.io.iMalformed   := walk.io.oMalformed
  od.io.iCapAbsent   := walk.io.oCapAbsent
  od.io.iExecValid   := walk.io.oExecValid
  od.io.iInstr       := walk.io.oInstr
  od.io.iSlotPresent := walk.io.oSlotPresent
  od.io.iSlotCode    := walk.io.oSlotCode
  od.io.iSlotOff     := walk.io.oSlotOff
  od.io.iFaultClear  := io.faultClear.operandDecode

  /** 태그 사이드밴드 정렬 — DecodeWalk 방출 단(1 레지스터)과 같은 지연.
    * 태그는 통째로 나른다 — 슬라이스 없음 (§1.4.4). */
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
  rj.io.faultClear := io.faultClear.route
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

  reasm.io.faultClear     := io.faultClear.reasm
  reasm.io.capAbsentClear := io.faultClear.reasmCap

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

  hiu.io.install.valid := io.install.valid
  hiu.io.install.part  := io.install.part
  hiu.io.install.idx   := io.install.idx
  hiu.io.install.tag   := io.install.tag
  hiu.io.install.frame := io.install.frame
  hiu.io.install.perm  := io.install.perm
  io.install.ready     := hiu.io.install.ready
  hiu.io.flush.valid   := io.flush.valid
  hiu.io.flush.part    := io.flush.part
  hiu.io.hostRsp.valid := io.hostRsp.valid
  hiu.io.hostRsp.frame := io.hostRsp.frame
  hiu.io.hostRsp.perm  := io.hostRsp.perm
  hiu.io.faultClear    := io.faultClear.hiuPerm
  hiu.io.missClear     := io.faultClear.hiuMiss

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
  shared.io.faultClear  := io.faultClear.sharedBp

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
  merge.io.faultClear := io.faultClear.fabricBp

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
  bank.io.faultClear    := io.faultClear.bankWrite

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
  fps.io.faultClearBp      := io.faultClear.fpBp
  fps.io.faultClearBadProg := io.faultClear.fpBadProg

  // ═══ 완료 유닛 — 인도 → 완료 링 (E.5) + E.11 집계 ════════════════════
  // 인도 = 완료 통지 (E.6 1항 — 링 삽입이 유일한 통지 수단). 디스크립터는
  // 32 B 고정(E.5 4항)이고 이 조립의 잠정 배치는 하위부터 total(8) ·
  // base(8) · tag(80, 통째) · 상위 0 — 호스트 ABI 합의 입력이다
  // (model_feedback). 배압 보존: 링 가득 → comp.ready 하강 → 인도 대기.
  cq.io.comp.valid := reasm.io.deliver.valid
  cq.io.comp.payload := B(0, CompletionUnit.ENTRY_W - Isa.TAG_W - Isa.LBID_W - Isa.FRAG_TOTAL_W bits) ##
    reasm.io.deliver.payload.tag.asBits ##
    reasm.io.deliver.payload.base.asBits ##
    reasm.io.deliver.payload.total.asBits
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

  // ═══ MMIO 디코드 — E.1 영역 배치 (머리 주석의 표) ════════════════════
  private val mmioAligned = io.mmio.addr(1 downto 0) === 0
  private val selOwn = io.mmio.addr(11 downto 8) === OwnershipTable.REGION
  private val selCq  = io.mmio.addr(11 downto 8) === 0x3
  private val selCfg = io.mmio.addr(11 downto 10) === (MmioConfig.LNID_TBL_BASE >> 10) ||
    io.mmio.addr(11 downto 10) === (MmioConfig.LBID_TBL_BASE >> 10)
  private val selLoc = io.mmio.addr(11 downto 8) === 0xC // 잠정 배정 (머리 주석)

  // 영역별 스트로브 게이트 — 한 접근은 정확히 한 블록에 닿는다.
  own.io.addr    := io.mmio.addr
  own.io.wdata   := io.mmio.wdata
  own.io.wstrobe := io.mmio.wstrobe && selOwn
  own.io.rstrobe := io.mmio.rstrobe && selOwn
  own.io.faultClearCollide := io.faultClear.ownCollide

  cq.io.addr    := io.mmio.addr(7 downto 0)
  cq.io.wdata   := io.mmio.wdata
  cq.io.wstrobe := io.mmio.wstrobe && selCq
  cq.io.rstrobe := io.mmio.rstrobe && selCq

  cfgBlk.io.addr    := io.mmio.addr
  cfgBlk.io.wdata   := io.mmio.wdata
  cfgBlk.io.wstrobe := io.mmio.wstrobe && selCfg
  cfgBlk.io.rstrobe := io.mmio.rstrobe && selCfg
  cfgBlk.io.faultClearDup := io.faultClear.cfgDupOwner
  cfgBlk.io.faultClearBad := io.faultClear.cfgBadWrite

  // ── 0xC00 지역 표면 — E.9 · E.12 · step 적재 (잠정 워드 배치) ─────────
  //
  //   워드 색인(addr[7:2]) 기준:
  //     0..7   KEY[0..7]        WO  E.9 1항 — 키 기입 (읽기 0: 키는 되읽지
  //                                 않는다 — 상태 표면 최소화, §5.8)
  //     8      NONCE_PART       RW  논스 기입 대상 파티션 선택
  //     9..14  NONCE[0..5]      WO  E.9 2항 — 선택 파티션의 논스 워드
  //     15     REKEY            WO  [partW-1:0] 파티션 — 유휴가 아니면 유실
  //                                 (MASK_STATUS 로 관측 — MaskUnit 계약)
  //     16     MASK_STATUS      RO  [parts-1:0] maskReady · [8] busy ·
  //                                 [9] rekey ready
  //     17     FP_PROG          WO  [31:24] slot · [23:16] idx · [15:0] step
  //     18     FP_BIND          WO  [31] en · [23:16] slot · [15:0] key
  //     19     FP_STATUS        RO  [0] loadReady · [1] busy
  //     20     ABORT_W0         WO  E.12 — 소거 태그 wave (32b 통째)
  //     21     ABORT_W1         WO  [31:16] thread · [15:0] lnid
  //     22     ABORT_W2         WO  [15:8] precision · [7:0] dim
  //     23     ABORT_FIRE       WO  [0]=1 기입 = 소거 발화 (없는 태그 무시 —
  //                                 E.12 3항, Reassembly 소관)
  //     24     ABORT_COUNT      RO  소거 카운트 (E.12 2항 회계)
  //     25     REASM_INCOMPLETE RO  미완 문맥 수 (진단 — §4.3)
  //     그 밖  예약 — 쓰기 무시 · 읽기 0 (§3.7)
  //
  // 태그 스테이징이 3워드 + 발화 1워드인 이유: 태그 80b 는 32b 버스 한
  // 번에 실리지 않는다 — E.7 이 「한 워드 전이」로 얻은 원자성을 여기서는
  // 명시적 발화 워드가 대신한다 (부분 기입 상태는 발화 전엔 효과가 없다).
  private val loc = new Area {
    val wordOff = io.mmio.addr(7 downto 2)
    val wr = io.mmio.wstrobe && selLoc && mmioAligned
    val rd = io.mmio.rstrobe && !io.mmio.wstrobe && selLoc && mmioAligned

    // E.9 키 기입 — 워드 색인 0..7 (표 조회 형태의 등가 비교 디코드).
    mask.io.keyWr.valid := wr && wordOff < 8
    mask.io.keyWr.idx   := wordOff(2 downto 0)
    mask.io.keyWr.data  := io.mmio.wdata

    // E.9 논스 — 파티션 선택 레지스터 + 워드 기입.
    val noncePart = Reg(UInt(partW bits)) init 0
    when(wr && wordOff === 8) { noncePart := io.mmio.wdata(partW - 1 downto 0).asUInt }
    mask.io.nonceWr.valid := wr && wordOff >= 9 && wordOff <= 14
    mask.io.nonceWr.part  := noncePart
    // 색인 9..14 는 하위 3비트 001..110 구간이라 (하위 3비트 − 1) 이 곧
    // 논스 워드 0..5 다 — 전폭 감산 뒤 절단(미사용 상위 비트)을 만들지
    // 않는 폭 정합 산술.
    mask.io.nonceWr.idx   := wordOff(2 downto 0) - 1
    mask.io.nonceWr.data  := io.mmio.wdata

    // E.9 재키잉 — 유휴가 아니면 유실(ready 관측은 MASK_STATUS). E.9 4항의
    // flush 동반·드레인 순서는 호스트 ABI 의무다 (§3.10).
    mask.io.rekey.valid := wr && wordOff === 15
    mask.io.rekey.part  := io.mmio.wdata(partW - 1 downto 0).asUInt

    // step 프로그램 적재 (§2.5 — 재적재는 §3.7 드레인 규약 아래, 호스트 의무).
    fps.io.progWr.valid := wr && wordOff === 17
    fps.io.progWr.slot  := io.mmio.wdata(31 downto 24).asUInt
    fps.io.progWr.idx   := io.mmio.wdata(23 downto 16).asUInt
    fps.io.progWr.step  := io.mmio.wdata(15 downto 0)
    fps.io.bindWr.valid := wr && wordOff === 18
    fps.io.bindWr.key   := io.mmio.wdata(15 downto 0)
    fps.io.bindWr.en    := io.mmio.wdata(31)
    fps.io.bindWr.slot  := io.mmio.wdata(23 downto 16).asUInt

    // E.12 소거 태그 스테이징 — 필드별 레지스터, 조립은 Tag 번들 필드
    // 대입으로만 (슬라이스 없음 — §1.4.4 태그 조립 규율).
    val abWave   = Reg(UInt(Isa.WAVE_W bits)) init 0
    val abThread = Reg(UInt(Isa.THREAD_W bits)) init 0
    val abLnid   = Reg(UInt(Isa.LNID_W bits)) init 0
    val abPrec   = Reg(UInt(Isa.PRECISION_W bits)) init 0
    val abDim    = Reg(UInt(Isa.DIM_W bits)) init 0
    when(wr && wordOff === 20) { abWave := io.mmio.wdata.asUInt }
    when(wr && wordOff === 21) {
      abThread := io.mmio.wdata(31 downto 16).asUInt
      abLnid   := io.mmio.wdata(15 downto 0).asUInt
    }
    when(wr && wordOff === 22) {
      abPrec := io.mmio.wdata(15 downto 8).asUInt
      abDim  := io.mmio.wdata(7 downto 0).asUInt
    }
    reasm.io.abort.valid         := wr && wordOff === 23 && io.mmio.wdata(0)
    reasm.io.abort.tag.wave      := abWave
    reasm.io.abort.tag.thread    := abThread
    reasm.io.abort.tag.lnid      := abLnid
    reasm.io.abort.tag.precision := abPrec
    reasm.io.abort.tag.dim       := abDim

    // 상태 워드 조립 (RO)
    val maskStat = Bits(32 bits)
    maskStat := 0
    maskStat(cfg.xlateParts - 1 downto 0) := mask.io.maskReady
    maskStat(8) := mask.io.busy
    maskStat(9) := mask.io.rekey.ready
    val fpStat = Bits(32 bits)
    fpStat := 0
    fpStat(0) := fps.io.loadReady
    fpStat(1) := fps.io.oBusy

    // 읽기 — 수락 다음 사이클 (하위 블록들과 같은 1사이클 규약). 예약·WO
    // 오프셋은 0 이다 (§3.7).
    val rdReg = Reg(Bits(32 bits)) init 0
    val rv    = RegNext(rd, False)
    when(rd) {
      rdReg := 0
      switch(wordOff) {
        is(8)  { rdReg := noncePart.asBits.resize(32) }
        is(16) { rdReg := maskStat }
        is(19) { rdReg := fpStat }
        is(24) { rdReg := reasm.io.abortCount.asBits.resize(32) }
        is(25) { rdReg := reasm.io.incomplete.asBits.resize(32) }
      }
    }
  }

  // ── ready — 영역별 (구성 검사·초기화 소거 중에는 그 블록이 낮춘다) ────
  io.mmio.ready := True
  when(selOwn) { io.mmio.ready := own.io.ready }
  when(selCq)  { io.mmio.ready := cq.io.ready }
  when(selCfg) { io.mmio.ready := cfgBlk.io.ready }
  // step 적재 워드만 선택자 표 초기화 소거를 기다린다 (StepSequencer 계약).
  when(selLoc && (loc.wordOff === 17 || loc.wordOff === 18)) {
    io.mmio.ready := fps.io.loadReady
  }

  // ── 읽기 응답 병합 — 스트로브가 배타라 rvalid 도 배타다 ───────────────
  // 예약 영역(과 0xC00 지역의 비정렬 접근)도 rvalid 는 돌려준다 — 읽기 0
  // (§3.7. 응답 없는 읽기는 예약 정책이 아니라 버스 행 멈춤이다).
  private val resvRd = io.mmio.rstrobe && !io.mmio.wstrobe &&
    ((!selOwn && !selCq && !selCfg && !selLoc) || (selLoc && !mmioAligned))
  private val resvRv = RegNext(resvRd, False)

  io.mmio.rvalid := own.io.rvalid || cq.io.rvalid || cfgBlk.io.rvalid || loc.rv || resvRv
  io.mmio.rdata := 0
  when(own.io.rvalid)    { io.mmio.rdata := own.io.rdata }
  when(cq.io.rvalid)     { io.mmio.rdata := cq.io.rdata }
  when(cfgBlk.io.rvalid) { io.mmio.rdata := cfgBlk.io.rdata }
  when(loc.rv)           { io.mmio.rdata := loc.rdReg }

  // ═══ sticky fault 관측면 — 원천별 수출 (여기서 접지 않는다, §5.6) ═════
  io.fault.decodeWalk    := walk.io.oFault
  io.fault.operandDecode := od.io.oFault
  io.fault.route         := rj.io.fault
  io.fault.reasm         := reasm.io.fault
  io.fault.reasmCap      := reasm.io.capAbsent
  io.fault.hiuPerm       := hiu.io.faultPerm
  io.fault.hiuMiss       := hiu.io.missNotice
  io.fault.cfgDupOwner   := cfgBlk.io.faultDupOwner
  io.fault.cfgBadWrite   := cfgBlk.io.faultBadWrite
  io.fault.ownCollide    := own.io.faultCollide
  io.fault.fabricBp      := merge.io.fault
  io.fault.sharedBp      := shared.io.faultBpViolation
  io.fault.bankWrite     := bank.io.fault
  io.fault.maskNoMask    := mask.io.faultNoMask
  io.fault.maskNonceDup  := mask.io.faultNonceDup
  io.fault.maskWrRekey   := mask.io.faultWrDuringRekey
  io.fault.fpBp          := fps.io.faultBpViolation
  io.fault.fpBadProg     := fps.io.faultBadProg
  io.fault.cqOverflow    := cq.io.faultOverflow

  mask.io.faultClearNoMask   := io.faultClear.maskNoMask
  mask.io.faultClearNonceDup := io.faultClear.maskNonceDup
  mask.io.faultClearWrRekey  := io.faultClear.maskWrRekey
}
