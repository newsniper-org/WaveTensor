// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// MaskUnit — 주소 마스킹 (정본 §5.2 · §5.3 · 부록 E.9). HiuPipeline s4
// 「마스킹(자리)」의 실물이 될 유닛이다 (결선은 통합자 몫).
//
// ## GUARD-MAP — Mask 모델 (2026-09-15 신설, 정본 7fa5f2e)
//
// SEC-1 마스크 정확성은 형식 증명 대상이 아니라 golden 대조 축 (b) —
// §5.8 함정 「SEC-1 은 형식이 아니라 대조다」(대조 하네스는 cocotb 몫). 그
// 축에는 GUARD-MAP 줄이 없다(SEC-1 은 애초에 Mask.tla 의 AllGuards 가
// 아니다). 제어면(키·논스 저장의 파티션별 스코프, REKEY 유휴 수락, 키
// 기입의 유효 하강 범위)은 `rtl/formal/tla/Mask.tla` 가 선-formal 로
// 소유하고, 아래 세 줄이 그 가드를 후-formal(rtl/formal/sby/HiuMask/
// hiumask.sby)에 잇는다. `Mask` 는 2026-09-22 파도 D 부터 lint_guard_map.ENFORCED 안이라
// 전수성(가드당 정확히 1줄)이 강제된다 — 넷째 가드
// `rekey_explicit_target` 은 MASK_PART 창 대 MASK_REKEY 필드의 *라우팅*
// 문제라 Wt64Top 의 MMIO 디코드(maskArea) 소관이고 이 유닛에는 그 개념
// 자체가 없다(이 파일에는 "창"이 없다 — keyWr.part/rekey.part 는 이미
// 분리된 자유 입력으로 도착한다). 그 가드의 GUARD-MAP 정식 줄은 top/
// Wt64Top.scala 머리의 GUARD-MAP 절에 있다 (조립층 assembly.sby 가 잰다).
// GUARD-MAP: Mask.key_scoped_storage -> 저장은 파티션별이다(key 를
//   parts 벌 둔다, 아래 key 선언). HiuMask 합성이 REKEY(p) 수락 다음
//   사이클의 유도 초기 상태(st_4..st_11)를 keyWr 입력만으로 다시 지은
//   독립 섀도우의 p 슬롯과 대조한다 — 재구현 착수 시점의 전역 1벌
//   저장에 걸면 반례가 난다(hiumask.sby PROVES 앵커 · §역-변이 mutG).
// GUARD-MAP: Mask.key_write_own_only -> 키 기입은 그 파티션의 maskValid
//   만 떨어뜨린다(아래 keyWr 처리, `maskValid(io.keyWr.part) := False`).
//   HiuMask 합성이 파티션 p 로 향한 키 기입 에지에서 q != p 의 maskReady
//   가 불변임을 잰다 — 재구현 착수 시점의 전 파티션 무효화(for 문)에
//   걸면 반례가 난다(hiumask.sby PROVES 앵커 · §역-변이 mutF).
// GUARD-MAP: Mask.rekey_idle_only -> REKEY 는 엔진이 유휴(phase=IDLE)일
//   때만 수락된다(io.rekey.ready = !engineBusy, 아래 FSM). HiuMask
//   합성이 rekeyFire 발화 사이클의 phase 가 IDLE 였음을 잰다 — 이 축의
//   로직은 이번 파도가 건드리지 않았고 회귀 그물로만 선다.
// (넷째 가드 Mask.rekey_explicit_target 의 GUARD-MAP 정식 줄은 top/Wt64Top.scala
//   머리로 옮겼다 — MASK_PART 창(0xEA0) 대 MASK_REKEY(0xEBC) 필드의 라우팅은
//   Wt64Top.maskArea 소관이고, 이 유닛에는 "창" 개념 자체가 없다 —
//   keyWr.part/rekey.part 는 이미 분리된 자유 입력으로 여기 도착한다.)
//
//   · Decode.stall_uniform / SEC-2 와의 접점 — 상태열(§3.2 여섯 단계)의
//     소유자는 HiuPipeline 이고 그 GUARD-MAP 줄도 그쪽에 있다. 이 유닛의
//     의무는 그 계약이 성립할 전제다: 요청 경로(req→rsp)가 **경로 무관
//     고정 1사이클**이고, 유일한 정지원이 공통 enable(io.en — 파이프의
//     advance 가 물릴 자리) 하나라는 것. 요청별·데이터별로 지연이 갈리는
//     분기가 이 파일에 존재하지 않는다 — 마스크 미준비조차 경로를 가르지
//     않고 sticky fault 로만 나타난다 (§5.3 「어느 경로를 타든 같은 사이클」).
//   · 재키잉 엔진(42사이클)은 요청 경로 **밖**이다 — 구성 시점 사건이고,
//     E.9 4항이 재키잉을 해당 파티션 flush 와 묶으므로 요청과의 경합은
//     호스트 규율(ENV 성격)이다. 위반은 faultNoMask 가 크게 알린다.
//
// ## GUARD-MAP — MaskEngine 모델 (2026-09-22 신설, 파도 D — FINAL 엣지 동시 기입)
//
// `rtl/formal/tla/MaskEngine.tla` 는 Mask.tla 과 분업해 재키잉 엔진 창의
// **시간 축**만 재는 선-formal 모델이다 (Mask = 「어느 파티션」 · MaskEngine =
// 「언제」 — E.9 4항의 두 면). 후-formal 앵커는 넷 다
// rtl/formal/sby/MaskUnit/engine.sby — MaskUnit 단독 하네스다. HiuMask 합성
// 태스크(bmc 24)로는 수락 뒤 43 엣지의 FINAL 에 닿지 않아 그쪽에 단언을
// 더하면 공허하다. `MaskEngine` 은 lint_guard_map.ENFORCED 안이다(2026-09-22 등재).
// GUARD-MAP: MaskEngine.dirty_scoped -> busy 중 기입은 **활성 파티션(actPart)
//   으로 향한 것만** compDirty 를 세운다 — 기입 표면의
//   `engineBusy && io.keyWr.part === actPart` (논스 동형) 와 FINAL 가지의
//   같은 사이클 항 wrActNow (actPart 한정). 타 파티션 기입은 E.9 4항
//   「사정권 밖」. engine.sby 가 a_clean_final_validates · a_clean_final_quiet
//   + W3 로 잰다 (변이 mutB: 파티션 무관 dirty 에 반례).
// GUARD-MAP: MaskEngine.dirty_no_validate -> dirty 한 완료는 활성 파티션을
//   유효화하지 않는다 — FINAL 가지 `maskValid(actPart) := !dirtyNow`
//   (dirtyNow = compDirty || wrActNow). engine.sby 가
//   a_dirty_final_no_validate 로 잰다 (변이 mutD: dirty 완료도 유효화).
// GUARD-MAP: MaskEngine.dirty_loud -> 유효화하지 않은 완료는 sticky
//   faultWrDuringRekey 를 세운다 — **FINAL 사이클 자체의 활성 파티션 기입도
//   포함** (같은 사이클 항 wrActNow 를 dirtyAtFinal 에 직접 OR — 레지스터
//   compDirty 는 그 기입을 다음 사이클에야 본다). engine.sby 가
//   a_final_overlap_loud · a_dirty_final_loud 로 잰다 (변이 mutA:
//   dirtyAtFinal 을 compDirty 만으로 = 파도 D 이전 판 1666c7a 에 반례).
// GUARD-MAP: MaskEngine.invalidate_beats_validate -> 완료와 같은 사이클의
//   활성 파티션 기입은 유효화를 이긴다(무효) — 기입 표면을 FSM **뒤**에 둔
//   텍스트 순서에 더해 FINAL 가지의 `!dirtyNow` 가 같은 값을 식으로 명시.
//   engine.sby 가 a_final_overlap_no_validate 로 잰다 (변이 mutC: 유효화가
//   이기게 뒤집으면 반례).
//
// ## §5.2.3 — 준거해야 할 구조 세 단계 (하나라도 빠지면 표준이 아니다)
//
//   1. 부표준키 유도 — 본 라운드 함수를 쓰되 **최종 덧셈이 없다.**
//   2. 본 라운드 — 유도 단계의 상태가 아니라 **부표준키로 다시 구성한
//      상태** 위에서 라운드를 돈다 (§5.2.3 함정: 1↔2 를 잇는 지점이 가장
//      틀리기 쉽다 — 참조 구현은 유도 상태를 그대로 넘겨서 틀렸다).
//   3. 최종 덧셈 — 라운드 결과에 초기 상태를 더한다.
//
// 아래 FSM 의 HROUND / HEXTRACT·CROUND / FINAL 이 그 세 단계의 실물이다.
//
// ## golden 관측 지점 (scripts/golden_xchacha.py — 허용 오라클)
//
// 마스크 논리는 golden 의 알고리즘을 관측해 동형 구현했다. 항목별 관측:
//
//   · CHACHA_CONST — 상수 4워드 (아래 CONST). "expand 32-byte k" LE 분해.
//   · chacha20_state / hchacha20 — 유도 초기 상태 = CONST ‖ key 워드 8 ‖
//     논스 워드 0..3. `_key_bytes` 관측: 포트 정수의 최하위 32비트가 key
//     word 0 (h_init_w[4+n] = key[32n+31:32n]) — 여기서는 key(n) 레지스터가
//     곧 word n 이다. 논스도 같은 논거 (`_nonce_bytes`).
//   · quarter_round / COL_QUADS / DIAG_QUADS / double_round — 라운드는
//     column(0,4,8,12)(1,5,9,13)(2,6,10,14)(3,7,11,15) 다음
//     diagonal(0,5,10,15)(1,6,11,12)(2,7,8,13)(3,4,9,14) 순서가 규범이고,
//     column round 의 4쌍은 인덱스 서로소라 병렬, diagonal 도 마찬가지다.
//     (golden §5 `legacy_round_cycle` 이 기록한 확산 붕괴 사고 = 한 cycle 에
//     8쌍 전부를 직전 상태에서 계산 → diagonal 이 column 을 전량 덮음.
//     아래 구현은 라운드 하나 = 1사이클이라 그 결함형이 구조적으로 불가능
//     하다 — column 결과가 레지스터에 앉은 **위에서** diagonal 이 돈다.)
//   · hchacha20 — 부표준키 = 라운드 후 상태의 워드 0..3 ‖ 12..15,
//     **최종 덧셈 없음** (chacha20_block 과의 유일한 차이).
//   · xchacha20_block_words — 본 라운드 초기 상태 재구성:
//     [0..3]=CONST · [4..11]=부표준키 · [12]=counter=0 (고정) · [13]=0 ·
//     [14]=논스 워드 4 (바이트 16..19) · [15]=논스 워드 5 (바이트 20..23).
//     ([13]=0 이 golden 이 「편차 A」로 기록한 지점 — 폐기 RTL 은
//     [13]=논스, [15]=0 으로 어긋나 있었다.)
//   · hiu_mask64 — 마스크 64b = (w[1] << 32) | w[0], w[i] = 라운드 결과 +
//     초기 상태. 워드 0·1 의 초기 상태는 CONST(0)·CONST(1) 상수다.
//   · hiu_masked_phys — masked = phys ^ mask64 (64b 전폭). E.9 3항이 적용
//     범위를 페이지 프레임 부분으로 제한하므로, 물리 주소 = frame ‖ offset
//     (PAGE_W=12, E.2 「4 KiB 고정」) 에서 frame 이 차지하는 비트에 실리는
//     마스크 비트는 mask64[PAGE_W+FRAME_W-1 : PAGE_W] 다. 오프셋은 이
//     유닛에 아예 흐르지 않는다 (XlateStore 와 같은 구조적 배제) —
//     「하면 접근이 페이지를 넘어간다」의 구현이 배선 부재다.
//
// ## 확산 검사는 구현하지 않는다 (§5.2.4 함정)
//
// 「확산은 세어서 확인할 수 없다 — golden 과의 비트 단위 정확 비교로만
// 확인된다. `!=` 검사는 무의미하다」. 그 규율의 수신인은 검증 하네스다 —
// RTL 안에 자가 확산 검사·통계 검사를 두지 않는다. SEC-1 대조(축 (b))가
// 후속 cocotb 하네스에서 golden 정확값으로 선다.
//
// ## E.9 — 키·논스 규범의 이 파일 몫
//
//   1항 키는 구성 표면 기입 — 장치는 키를 생성하지 않는다: 이 파일에 키
//       생성 경로·난수 소비 배선이 없다 (엔트로피원 §5.4 는 별개 유닛이고,
//       이 유닛에는 조합 루프가 0개다 — SEC-5 의 승인 대상 아님).
//   2항 논스는 파티션마다 다르다: 저장이 파티션별이고, 재키잉 수락 시점에
//       「같은 키 아래 마스크 유효한 타 파티션」과의 논스 일치를 검사해
//       faultNonceDup 을 크게 세운다 (겹치면 같은 키스트림 재사용 —
//       「그것은 마스킹이 아니다」). 계산은 계속한다 — 판정이 경로·시간을
//       가르지 않게 하고, 처분은 호스트 몫이다 (loud-fault-never-silent).
//   3항 프레임 부분에만 적용: 위 관측 지점 마지막 항 — 구조로 성립.
//   4항 재키잉은 해당 파티션 flush 와 함께: flush 동반 자체는 호스트
//       의무다 (§3.10 ABI 경계 — HiuPipeline flush_on_handoff ENV 와 같은
//       자리). 이 유닛의 강제 몫은 「옛 키와 새 키의 혼합 금지」다 —
//       키 기입도 논스 기입도 **그 파티션의** 마스크 유효만 즉시
//       떨어뜨리고(정본 7fa5f2e — 저장은 파티션별, 다른 파티션은 사정권
//       밖), 계산 중 입력이 바뀐 재키잉은 결과를 유효화하지 않는다
//       (compDirty → faultWrDuringRekey). 「계산 중」의 정의역은 busy=1 인
//       사이클 전부 — 완료(FINAL) 사이클 **포함** — 에 더해 수락 사이클 자체의
//       같은-파티션(rekey.part) 기입(busy=0 이지만 유도 초기 상태가 그 옛 값을
//       래치한다)이고, 그 기입은 유효화를 막고 sticky 를 세운다 (e-defined.typ:518 「재키잉 중 입력 기입」 에 시점 예외가 없다;
//       파도 D, MaskEngine.dirty_loud). 미준비 마스크로 지나간 요청은
//       faultNoMask 가 잡는다.
//
// ## 판단 — 라운드당 고정 1사이클 (근거)
//
//   · 1사이클에 싣는 조합 깊이가 quarter-round 1개(가감·회전 8단)로 고정
//     된다 — column/diagonal 각각 4쌍은 인덱스 서로소라 폭 방향 병렬이다.
//   · 재키잉은 구성 시점 사건이라 처리량이 무의미하다 — 라운드를 겹쳐
//     펼칠 이유(면적 대가)가 없다.
//   · 라운드 경계가 레지스터 경계와 일치해 golden 의 double_round 진행과
//     사이클 단위로 맞대조된다 — 확산 붕괴 사고(위 관측 지점)의 재발이
//     구조적으로 불가능해지는 배치이기도 하다.
//   총 43사이클 (수락 1 + 유도 20 + 재구성 1 + 본 라운드 20 + 최종 덧셈 1):
//   데이터 의존 분기가 없어 어떤 키·논스든 사이클 수가 동일하다.
//
// ## fault 폴딩 규정 (§5.6 — 신호마다 명시)
//
//   faultNoMask · faultNonceDup · faultWrDuringRekey 세 sticky 는 서로
//   접지 않는다 — 셋 다 수리 주체는 호스트지만 고칠 것이 다르다 (드레인
//   순서 / 논스 배정 / 재키잉 시퀀스). 종합 신호로의 폴딩은 상위 몫이다.

package wt64.mask

import spinal.core._
import wt64.{StickyFault, Wt64Config}
import wt64.hiu.XlateStore

/** 지역 상수 — 표준 라운드 함수의 고정 표. */
object MaskUnit {
  /** "expand 32-byte k" 의 LE 32b 워드 분해 (golden CHACHA_CONST 관측). */
  val CONST = Seq(0x61707865L, 0x3320646EL, 0x79622D32L, 0x6B206574L)
  /** 라운드 수 — golden CHACHA_ROUNDS. 20 = double round 10회. */
  val ROUNDS = 20
  /** column 4쌍 (golden COL_QUADS) — 인덱스 서로소, 폭 방향 병렬. */
  val COL = Seq(Seq(0, 4, 8, 12), Seq(1, 5, 9, 13), Seq(2, 6, 10, 14), Seq(3, 7, 11, 15))
  /** diagonal 4쌍 (golden DIAG_QUADS). */
  val DIAG = Seq(Seq(0, 5, 10, 15), Seq(1, 6, 11, 12), Seq(2, 7, 8, 13), Seq(3, 4, 9, 14))
  /** 키 워드 수 (256b) · 논스 워드 수 (192b). */
  val KEY_WORDS   = 8
  val NONCE_WORDS = 6
}

/** 주소 마스킹 유닛.
  *
  * 표면 둘: (i) E.9 키·논스 기입 + 재키잉 — 반대편은 top/호스트 (버스
  * 디코드·E.1 오프셋 배정은 상위 몫, 여기는 소박한 워드 기입 포트만 낸다).
  * (ii) 요청 경로 — 프레임 in → 마스킹된 프레임 out, 공통 enable 아래
  * 고정 1사이클 (s4 마스킹 단계의 실물).
  */
case class MaskUnit(cfg: Wt64Config = Wt64Config()) extends Component {
  import MaskUnit._
  import XlateStore.{FRAME_W, PAGE_W}

  // 축퇴 형상 금지 — 파티션 1개면 E.9 2항(논스 파티션별)·SEC-4 격리가
  // 공허해진다 (Wt64Config nPoints require 와 같은 논거).
  require(cfg.xlateParts >= 2, "축퇴 형상 금지 — 파티션 1개면 논스 구별·격리 규범이 공허하다")
  private val parts = cfg.xlateParts
  private val partW = log2Up(parts)

  // 최종 덧셈의 상수 분해 (FINAL 가지 주석 참조) — 적용 슬라이스가 정확히
  // 워드 0 상부 + 워드 1 하부에 걸친다는 배치 전제를 명시한다.
  private val W1_W  = PAGE_W + FRAME_W - 32          // w1 에서 취하는 폭
  private val C0_LO = CONST(0) & ((1L << PAGE_W) - 1)
  private val C0_HI = CONST(0) >> PAGE_W
  private val C1_LO = CONST(1) & ((1L << W1_W) - 1)
  require(PAGE_W > 0 && PAGE_W < 32 && W1_W > 0 && W1_W <= 32,
    "적용 슬라이스가 키스트림 워드 0·1 에 걸치는 배치가 아니다 — FINAL 분해를 다시 유도하라")
  require(W1_W + (32 - PAGE_W) == FRAME_W)

  val io = new Bundle {
    // ── E.9 기입 표면 — 키 (임대별, 구성 표면 기입 — 장치는 생성하지 않는다)
    // 정본 7fa5f2e "키의 범위 — 임대마다 다르다": 저장은 파티션별이고,
    // 기입 대상은 nonceWr 과 같은 창(0xEA0 MASK_PART, 구 MASK_NONCE_PART)이
    // 정한다 — authority 는 그 창 하나가 아니라 REKEY 기입이다
    // (e-defined.typ:351 7항). part 필드는 nonceWr 과 동형.
    val keyWr = new Bundle {
      val valid = in port Bool()
      val part  = in port UInt(partW bits)
      val idx   = in port UInt(log2Up(KEY_WORDS) bits) // word n = key[32n+31:32n]
      val data  = in port Bits(32 bits)
    }
    // ── E.9 기입 표면 — 논스 (파티션별 — 2항) ─────────────────────────
    val nonceWr = new Bundle {
      val valid = in port Bool()
      val part  = in port UInt(partW bits)
      /** 워드 0..5. 6·7 기입은 무시한다 — 구성 표면의 예약 *오프셋* 정책
        * (§3.7 쓰기 무시·읽기 없음 — 명령 인코딩 예약 *필드* 정책과 정반대
        * 임에 주의. MmioConfig 머리의 같은 경고). */
      val idx   = in port UInt(3 bits)
      val data  = in port Bits(32 bits)
    }
    // ── 재키잉 (E.9 4항) — flush 동반은 호스트 의무 ────────────────────
    val rekey = new Bundle {
      val valid = in port Bool()
      /** 엔진 유휴에서만 수락 — 미수락은 ready 하강으로 관측된다 (무언
        * 드롭 아님). 호스트는 busy 해소 후 재제시한다. */
      val ready = out port Bool()
      val part  = in port UInt(partW bits)
    }
    /** 상태 표면 (§5.8 넷째 부류) — 파티션별 마스크 준비. 재키잉 완료의
      * 관측이 이 비트다 (E.9 4항 시퀀스의 완료 신호). */
    val maskReady = out port Bits(parts bits)
    val busy      = out port Bool()

    // ── 요청 경로 — s4 마스킹 단계의 실물 (고정 1사이클) ───────────────
    /** 공통 enable — HiuPipeline advance 가 물릴 자리 (stall_uniform:
      * 단계별·요청별 enable 을 만들지 않는다). */
    val en = in port Bool()
    val req = new Bundle {
      val valid = in port Bool()
      val part  = in port UInt(partW bits)
      val frame = in port UInt(FRAME_W bits)
    }
    val rsp = new Bundle {
      val valid = out port Bool()
      val frame = out port UInt(FRAME_W bits)
    }

    // ── sticky fault (폴딩 규정은 머리 주석 — 서로 접지 않는다) ────────
    val faultNoMask        = out port Bool() // 마스크 미준비 파티션의 요청 통과
    val faultNonceDup      = out port Bool() // 같은 키 아래 논스 재사용 재키잉
    val faultWrDuringRekey = out port Bool() // 계산 중 입력 기입 — 결과 무효
    val faultClearNoMask   = in port Bool()
    val faultClearNonceDup = in port Bool()
    val faultClearWrRekey  = in port Bool()
  }

  // ═══ 키·논스 저장 — E.9 공급·저장 ═══════════════════════════════════
  // key(p)(n) = 파티션 p 의 표준 key word n (관측 지점: _key_bytes — 포트
  // 정수 최하위 32b 가 word 0). 정본 7fa5f2e "키의 범위 — 임대마다 다르다"
  // — 저장은 파티션별이다 (분리되는 것은 저장이지 연산 자원이 아니다:
  // 아래 라운드망은 여전히 한 벌). 논스도 파티션별 6워드
  // (0..3 유도 단계, 4..5 본 라운드) — 이 축은 개정 전부터 이미 옳았다.
  private val key   = Vec.fill(parts)(Vec.fill(KEY_WORDS)(Reg(Bits(32 bits)) init 0))
  private val nonce = Vec.fill(parts)(Vec.fill(NONCE_WORDS)(Reg(Bits(32 bits)) init 0))

  // 파티션별 마스크 — 저장은 **적용 비트만**: 64b 키스트림(golden
  // hiu_mask64)에서 프레임 자리에 실리는 mask64[PAGE_W+FRAME_W-1:PAGE_W]
  // 슬라이스다 (E.9 3항 — 페이지 오프셋 비트·PA_W 밖 비트는 적용점이
  // 없으므로 레지스터도 두지 않는다. SEC-1 대조는 golden mask64 의 같은
  // 슬라이스와의 정확 비교로 선다 — 정보 손실 없는 사영이다).
  // reset 후 전부 미준비 — 구성하지 않은 기계가 우연히 마스킹하는 것을
  // 막는다.
  private val maskFrame = Vec.fill(parts)(Reg(UInt(FRAME_W bits)) init 0)
  private val maskValid = Vec.fill(parts)(RegInit(False))

  // ═══ 라운드 조합망 — 라운드 1개 = 1사이클 (판단·근거는 머리 주석) ════
  /** quarter-round (golden quarter_round 동형 — RFC 8439 §2.1 순서 그대로.
    * 가산은 동폭 wrap = mod 2^32). */
  private def qr(v: Seq[UInt]): Seq[UInt] = {
    val (a, b, c, d) = (v(0), v(1), v(2), v(3))
    val a1 = a + b
    val d1 = (d ^ a1).rotateLeft(16)
    val c1 = c + d1
    val b1 = (b ^ c1).rotateLeft(12)
    val a2 = a1 + b1
    val d2 = (d1 ^ a2).rotateLeft(8)
    val c2 = c1 + d2
    val b2 = (b1 ^ c2).rotateLeft(7)
    Seq(a2, b2, c2, d2)
  }

  /** 라운드망 — 고정 표(quads)의 4쌍을 폭 방향 병렬로 적용한다. 두 표
    * 각각이 인덱스 0..15 를 정확히 한 번씩 덮으므로 out 은 전폭 구동이다.
    * elaborate 시점 상수 표 전개 — 하드웨어에 선형 루프가 없다. */
  private def roundNet(s: Vec[UInt], quads: Seq[Seq[Int]]): Vec[UInt] = {
    val out = Vec(UInt(32 bits), 16)
    for (q <- quads; (i, v) <- q.zip(qr(q.map(s(_))))) out(i) := v
    out
  }

  // ═══ 재키잉 엔진 — §5.2.3 세 단계의 FSM ══════════════════════════════
  // IDLE → HROUND×20 (유도 — 최종 덧셈 없음) → HEXTRACT (부표준키로 초기
  // 상태 **재구성** — §5.2.3 함정의 지점) → CROUND×20 (본 라운드) →
  // FINAL (최종 덧셈 + 마스크 기입) → IDLE. 데이터 의존 분기 없음 —
  // 어떤 입력이든 42사이클 동일 (경로 무관 고정 사이클, §5.3 정합).
  // 상태 부호 — 지역 UInt 상수. SpinalEnum 은 시뮬 전용 *_string 신호를
  // 생성해 -Wall 청정을 깨므로 쓰지 않는다 (저장소 전례와 같은 선택).
  private val PH_IDLE     = 0
  private val PH_HROUND   = 1
  private val PH_HEXTRACT = 2
  private val PH_CROUND   = 3
  private val PH_FINAL    = 4
  private val phase     = Reg(UInt(3 bits)) init PH_IDLE
  private val st        = Vec.fill(16)(Reg(UInt(32 bits)) init 0)
  private val cnt       = Reg(UInt(5 bits)) init 0
  private val actPart   = Reg(UInt(partW bits)) init 0
  private val compDirty = RegInit(False) // 계산 중 입력 기입 감지 (E.9 4항 혼합 금지)

  private val engineBusy = phase =/= PH_IDLE
  io.busy        := engineBusy
  io.rekey.ready := !engineBusy
  private val rekeyFire = io.rekey.valid && io.rekey.ready

  // 짝수 라운드 = column, 홀수 = diagonal — double_round 의 규범 순서
  // (column round 결과가 레지스터에 앉은 위에서 diagonal 이 돈다).
  private val roundNext = Mux(cnt(0), roundNet(st, DIAG), roundNet(st, COL))

  // 논스 재사용 검사 (E.9 2항) — 마스크 유효한 타 파티션과의 논스 전폭
  // 일치. 고정 병렬 비교 — 경로·시간 불변.
  //
  // 이 검사는 "논스는 파티션마다 다르다"(1절)의 건전하되 불완전한 부분
  // 집행이다 — **쌍 불변식(키, 논스) 유일성을 강제하는 기전으로 읽어서는
  // 안 된다**(FAULT_STATUS[12] 강등 해설, e-defined.typ:1559-1583). 키가
  // 파티션별로 갈라진 뒤에도(정본 7fa5f2e) 로직은 바뀌지 않는다 — 강등의
  // 범위는 그 쌍 불변식이지 이 절 전체가 아니다. "같은 키 아래" 라는
  // 옛 전제(키가 전역 1벌이던 시절 — 아래 §변경 이력)는 더는 성립하지
  // 않지만, 검사 자체는 여전히 유효한 감시자다: 두 파티션이 (서로 다른
  // 키라도) 같은 논스를 쓰면 그 자체가 §3.7 구성 규율 위반의 신호이고,
  // 호스트가 수리할 축은 여전히 논스 배정이다.
  private val nonceFlat = Vec(nonce.map(_.asBits)) // 파티션당 192b
  private val reqNonce  = nonceFlat(io.rekey.part)
  private val nonceDup = (0 until parts)
    .map(q => maskValid(q) && (U(q, partW bits) =/= io.rekey.part) && (nonceFlat(q) === reqNonce))
    .reduce(_ || _)
  private val nonceDupFire = rekeyFire && nonceDup

  // 논스 기입 적중 — 워드 0..5 만 (idx 6·7 은 예약 오프셋 정책으로 무시 —
  // io 주석). 기입 표면(FSM 뒤)과 FINAL 가지가 같은 식을 본다 — Scala
  // 클래스 본문의 전방 참조는 elaborate 시 null 이라 정의를 FSM 앞에 둔다.
  private val nonceWrHit = io.nonceWr.valid && io.nonceWr.idx < NONCE_WORDS
  // **이 사이클**의 활성 파티션 기입 — 레지스터 compDirty 가 아직 보지 못한
  // 같은 사이클 항. FINAL 가지가 dirtyAtFinal · maskValid 에 직접 OR 한다
  // (머리 GUARD-MAP: MaskEngine.dirty_loud · invalidate_beats_validate).
  // 파티션 한정(actPart)은 dirty_scoped 와 같은 스코프다.
  private val wrActNow = (io.keyWr.valid && io.keyWr.part === actPart) ||
                         (nonceWrHit && io.nonceWr.part === actPart)

  private val dirtyAtFinal = False // FINAL 에서 오염(레지스터 ∨ 같은 사이클)이었는가 → sticky

  switch(phase) {
    is(PH_IDLE) {
      when(rekeyFire) {
        // 유도 초기 상태 — CONST ‖ key ‖ 논스 워드 0..3 (관측 지점:
        // chacha20_state / hchacha20 의 h_init 배치).
        // E.9 4항 "엔진은 그 파티션의 키와 논스를 읽는다" — io.rekey.part
        // 가 지목한 파티션의 저장을 그대로 읽는다(authority 는 REKEY 기입
        // 하나, e-defined.typ:351 7항 — MASK_PART 창과는 별개).
        for (i <- 0 until 4) st(i)      := U(CONST(i), 32 bits)
        for (i <- 0 until 8) st(4 + i)  := key(io.rekey.part)(i).asUInt
        for (i <- 0 until 4) st(12 + i) := nonce(io.rekey.part)(i).asUInt
        actPart   := io.rekey.part
        cnt       := 0
        compDirty := False
        // 재계산 개시 — 옛 마스크는 이 순간부터 무효다 (혼합 금지).
        maskValid(io.rekey.part) := False
        phase := PH_HROUND
      }
    }
    is(PH_HROUND) {
      // §5.2.3 1항 — 부표준키 유도의 라운드. 최종 덧셈은 어디에도 없다.
      for (i <- 0 until 16) st(i) := roundNext(i)
      cnt := cnt + 1
      when(cnt === ROUNDS - 1) {
        phase := PH_HEXTRACT
        cnt   := 0
      }
    }
    is(PH_HEXTRACT) {
      // §5.2.3 2항 — 부표준키(유도 결과 워드 0..3 ‖ 12..15, 덧셈 없음 —
      // 관측 지점: hchacha20)로 본 라운드 초기 상태를 **다시 구성**한다.
      // 유도 상태를 그대로 넘기지 않는다 — §5.2.3 함정이 지목한 지점.
      // 배치 관측 지점: xchacha20_block_words — [12]=counter=0 고정 ·
      // [13]=0 (「편차 A」의 정정) · [14..15]=논스 워드 4..5.
      st(0) := U(CONST(0), 32 bits)
      st(1) := U(CONST(1), 32 bits)
      st(2) := U(CONST(2), 32 bits)
      st(3) := U(CONST(3), 32 bits)
      st(4) := st(0)
      st(5) := st(1)
      st(6) := st(2)
      st(7) := st(3)
      st(8)  := st(12)
      st(9)  := st(13)
      st(10) := st(14)
      st(11) := st(15)
      st(12) := 0
      st(13) := 0
      st(14) := nonce(actPart)(4).asUInt
      st(15) := nonce(actPart)(5).asUInt
      phase := PH_CROUND
    }
    is(PH_CROUND) {
      // §5.2.3 2항 후반 — 재구성된 상태 위의 본 라운드.
      for (i <- 0 until 16) st(i) := roundNext(i)
      cnt := cnt + 1
      when(cnt === ROUNDS - 1) {
        phase := PH_FINAL
      }
    }
    is(PH_FINAL) {
      // §5.2.3 3항 — 최종 덧셈. 마스크 = 워드 1 ‖ 워드 0 (관측 지점:
      // hiu_mask64 — (w[1]<<32)|w[0], w[i]=라운드 결과+초기 상태). 워드
      // 0·1 의 초기 상태는 재구성 상태의 [0]·[1] = CONST 상수 그 자체다.
      //
      // 적용 비트만 물질화한다 — 64b 키스트림 (w1 ‖ w0) 의 적용 슬라이스
      // [PAGE_W+FRAME_W-1 : PAGE_W] 밖 비트(오프셋 자리·PA_W 밖)는 배선
      // 자체를 만들지 않는다 (미사용 비트 0 이 -Wall 청정의 실물이다):
      //   · w0 = st(0)+CONST(0) 의 하위 PAGE_W 비트는 값이 버려지지만
      //     carry 는 상위로 전파된다 — 상수 가산의 carry-out 은
      //     a + c ≥ 2^PAGE_W ⟺ a ≥ 2^PAGE_W − c 비교 하나로 정확하다.
      //   · w1 = st(1)+CONST(1) 은 하위 w1w 비트만 필요 — 절단 가산
      //     (wrap) 이 전폭 가산의 하위 비트와 동치다.
      // 저장 배치: maskFrame[FRAME_W-1 : 32-PAGE_W] = w1[w1w-1:0] =
      // mask64[PAGE_W+FRAME_W-1 : 32] · maskFrame[31-PAGE_W : 0] =
      // w0[31 : PAGE_W] = mask64[31 : PAGE_W].
      val carry0 =
        if (C0_LO == 0) False
        else st(0)(PAGE_W - 1 downto 0) >= U((1L << PAGE_W) - C0_LO, PAGE_W bits)
      val hi0 = st(0)(31 downto PAGE_W) + U(C0_HI, (32 - PAGE_W) bits) + carry0.asUInt.resize(32 - PAGE_W)
      val lo1 = st(1)(W1_W - 1 downto 0) + U(C1_LO, W1_W bits)
      maskFrame(actPart) := lo1 @@ hi0
      // FINAL 사이클의 활성 파티션 기입은 compDirty 레지스터에 **다음**
      // 사이클에야 실리므로 같은 사이클 항(wrActNow)을 직접 본다 — 이
      // 사이클은 busy=1 · ready=0 으로 장치 자신이 「재키잉 중」이라 말하고
      // FAULT_STATUS [13] 에는 시점 예외가 없다 (e-defined.typ:518 「재키잉 중 입력 기입」).
      // 파도 D 이전 판(1666c7a)은 compDirty 만 실어 수락+42 엣지 기입이
      // 유효만 떨어뜨리고 fault 는 침묵했다 — 같은 호스트 행위가 1사이클
      // 타이밍에 따라 두 판정을 받는 관측 결손(정본 5장 「조용한 소실」과
      // 동형; 안전 결손은 아니다 — 마스크는 유효화되지 않았다).
      val dirtyNow = compDirty || wrActNow
      dirtyAtFinal := dirtyNow
      // 계산 중 입력이 바뀌었으면 유효화하지 않는다 — 옛/새 입력 혼합
      // 마스크를 쓰는 창을 만들지 않는다 (E.9 4항). 미유효는 maskReady
      // 로 관측되고 sticky 가 크게 알린다 — 조용한 미완이 아니다. 같은
      // 사이클의 활성 파티션 기입은 아래 기입 표면의 무효화가 텍스트
      // 순서로도 이기지만, 의도를 식으로 드러낸다
      // (MaskEngine.invalidate_beats_validate).
      maskValid(actPart) := !dirtyNow
      phase := PH_IDLE
    }
  }

  // ═══ 기입 표면 — FSM 뒤에 두어 유효화와 겹치면 무효화가 이긴다 ═══════
  // (StickyFault 의 「발화가 해제를 이긴다」와 같은 방향 — 안전한 쪽 우선.)
  when(io.keyWr.valid) {
    key(io.keyWr.part)(io.keyWr.idx) := io.keyWr.data
    // 키 변경은 **그 파티션만** 무효화한다 (정본 7fa5f2e, e-defined.typ:339 「기입은 그 파티션의 마스크 유효를 즉시 떨어뜨린다」
    // — E.9 4항 "다른
    // 파티션이 그 변경의 사정권 밖"). 옛 키 마스크와 새 키 마스크의 혼합
    // 금지는 그 파티션 안에서 성립하면 족하다 — 재키잉이 뒤따라야 한다.
    maskValid(io.keyWr.part) := False
    // rekeyFire 와 같은 사이클의 기입도, **그 기입이 지금 계산 중인
    // 파티션(actPart)이나 이번에 수락되는 REKEY 의 대상과 같을 때만**
    // dirty 다 — 논스 기입(아래)과 동형 스코프. 유도 초기 상태는 이
    // 사이클의 (옛) 레지스터 값을 래치하므로, 결과를 유효화하면 새 키
    // 아래에서 옛 키 마스크가 쓰이는 창이 생긴다. 이 when 이 switch 뒤라
    // IDLE 가지의 compDirty := False 를 이긴다 (텍스트 순서 — 의도).
    when((engineBusy && io.keyWr.part === actPart) ||
         (rekeyFire && io.keyWr.part === io.rekey.part)) { compDirty := True }
  }
  // 논스 기입 — 워드별 등가 비교 디코드 (Vec 동적 색인은 8→6 원핫
  // 디코더의 미사용 비트를 만든다 — 표 조회 형태로 적어 미사용 비트 0).
  // idx 6·7 은 어느 비교에도 맞지 않아 무시된다 (예약 오프셋 정책 — io
  // 주석). nonceWrHit 의 정의는 FSM 앞(dirtyAtFinal 위) — FINAL 가지가 같은
  // 식을 보기 때문이다.
  for (i <- 0 until NONCE_WORDS) {
    when(io.nonceWr.valid && io.nonceWr.idx === i) {
      nonce(io.nonceWr.part)(i) := io.nonceWr.data
    }
  }
  when(nonceWrHit) {
    maskValid(io.nonceWr.part) := False
    when((engineBusy && io.nonceWr.part === actPart) ||
         (rekeyFire && io.nonceWr.part === io.rekey.part)) { compDirty := True }
  }

  io.maskReady := maskValid.asBits

  // ═══ 요청 경로 — 고정 1사이클, 공통 enable 하나 (SEC-2 전제) ═════════
  // 적용 비트: 물리 주소 = frame ‖ offset 에서 frame 자리의 마스크 비트
  // = mask64[PAGE_W+FRAME_W-1 : PAGE_W] (관측 지점: hiu_masked_phys +
  // E.9 3항). 오프셋은 이 유닛에 흐르지 않는다 — 구조적 배제.
  private val rValid = RegInit(False)
  private val rFrame = Reg(UInt(FRAME_W bits)) init 0
  when(io.en) {
    rValid := io.req.valid
    // 미준비 마스크도 경로를 가르지 않는다 — XOR 는 무조건 수행되고
    // (미준비면 reset 값 0 마스크 = 항등이지만, 아래 sticky 가 그 통과를
    // 크게 알린다), 지연·상태열은 준비 여부와 무관하게 동일하다 (§5.3).
    rFrame := io.req.frame ^ maskFrame(io.req.part)
  }
  io.rsp.valid := rValid
  io.rsp.frame := rFrame

  // 미준비 파티션의 유효 요청 통과 = 재키잉 규율 위반의 관측 (E.9 4항의
  // 이 유닛 쪽 감시자 — flush·드레인 시퀀스는 호스트 의무).
  private val noMaskFire = io.en && io.req.valid && !maskValid(io.req.part)

  // ═══ sticky fault — 세운다 / 명시적 해제 외엔 내리지 않는다 ══════════
  io.faultNoMask        := StickyFault(noMaskFire, io.faultClearNoMask)
  io.faultNonceDup      := StickyFault(nonceDupFire, io.faultClearNonceDup)
  io.faultWrDuringRekey := StickyFault(dirtyAtFinal, io.faultClearWrRekey)
}
