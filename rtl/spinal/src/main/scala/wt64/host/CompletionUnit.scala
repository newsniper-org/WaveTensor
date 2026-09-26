// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// CompletionUnit — 완료 큐 · 완료 통지 · 드레인 관측면
//                  (정본 부록 E.5 · E.6 · E.11, §3.7 드레인 규약, §2.6 배압)
//
// 이 모듈이 담는 것은 호스트-장치 경계의 완료 방향 표면 셋이다:
//
//   1. 완료 큐 (E.5)   — 링. 생산자는 장치(tail 전진), 소비자는 호스트(head
//      전진). 크기는 2의 거듭제곱 (나머지 연산이 마스크가 된다). head == tail
//      은 *빈 링*, 가득 참은 (tail+1) mod size == head — 한 칸을 비워 두
//      상태를 구별한다. 구별하지 못하는 인코딩은 조용히 틀린다 (E.5 문면).
//      완료 항목(디스크립터)은 32 B 고정이다 — 가변 길이 파싱 상태 기계를
//      만들지 않기 위해서다 (E.5 4항). 그 32 B *안쪽*의 배치는 아래
//      「완료 디스크립터」 절과 `object HostDesc` 가 소유한다.
//   2. 완료 통지 (E.6) — 통지는 *완료 링에 항목을 넣는 것*이고 그것이 유일한
//      통지 수단이다. 인터럽트는 선택적 가속이며 마스크로 끌 수 있다 — 끄면
//      호스트가 링을 폴링하고 기능이 줄지 않는다. 인터럽트 상태는 sticky 이며
//      명시적 해제까지 유지된다.
//   3. 드레인 관측면 (E.11) — §3.7 드레인 정의역 여섯 항의 진행 중 개수 +
//      자기 완료 큐 점유, 그리고 「전부 0」 비트. 읽기 전용. 이 표면은 새
//      상태를 만들지 않는다 — 각 유닛이 이미 가진 점유 상태의 집계 배선일
//      뿐이다 (여섯 카운트의 배선은 top 몫). 기계에 드레인 *모드*는 없다
//      (§3.7 — 드레인의 수행은 호스트 의무다). 관측 부류는 상태 표면이다
//      (§5.8 닫힌 4부류 안).
//
// ## 완료 디스크립터 — 워드 정렬 + kind (호스트 ABI 결정 5, 2026-08-25)
//
// 앞 착지는 링을 *불투명 256비트 전송로*로 두고 배치를 top 의 조립 한 줄에
// 맡겼다. 그 한 줄은 하위부터 total(8) ‖ base(8) ‖ 태그(80 통째) ‖ 상위 0 —
// 즉 **12 B 의 비트 팩킹**이었고, 두 결함을 동시에 갖고 있었다:
//
//   (1) 정본이 정한 적 없는 태그 80b 팩킹 순서를 생성된 SV 한 줄로 굳혔다
//       (Common.scala `Types.Tag` 주석이 그 공백의 정체를 든다).
//   (2) 「12 B 만 유의미」라는 사실이 코드에 없었다. 이 링은 장치 상주 `Mem`
//       이라 실제 기입은 전폭이었지만, 호스트 메모리 링으로 옮기는 순간 같은
//       조립이 12 B 부분 기입이 되고 그 칸의 *이전 항목 태그가 남는다* —
//       §3.6.3 해설이 flush 에 대해 경계한 것과 같은 형태의 잔류다.
//
// 정본 E.5.3 이 확정한 배치는 다음 여덟 워드다 (E.5.1 태그 직렬화 + E.5.2 kind):
//
//   +0x00 CD_KIND   [7:0] kind = 0x01 · [31:8] 예약 = 0
//   +0x04 CD_TAG0   [31:0] wave 번호
//   +0x08 CD_TAG1   [31:28] 에포크 · [27] poison(장치 저작) · [26] trace · [25:16] 예약 = 0 · [15:0] LNID
//   +0x0C CD_TAG2   [31:16] 예약 = 0 · [15:8] 정밀도 · [7:0] 차원
//   +0x10 CD_BASE   [7:0] 결속 LBID · [31:8] 예약 = 0
//   +0x14 CD_TOTAL  [31:0] 조각 선언 총개수 — *폭 미확정 값의 그릇*
//   +0x18 CD_RSV0   예약 = 0
//   +0x1C CD_RSV1   예약 = 0
//
// `0x340` CQ_WINDOW[0..7] 이 내는 여덟 워드가 이 배치 그대로다 — 창은 장치가
// 기입한 32 B 를 *전량* 낸다 (E.5.3).
//
// kind 는 *되돌림의 수단*이다 — 배치 개정이 새 kind 값의 **단조 추가**가 되고
// 옛 호스트는 모르는 kind 를 *건너뛴다*(head 를 한 칸 전진). E.5 2항 「구별하지
// 못하는 인코딩은 조용히 틀린다」의 대우를 디스크립터 축에 세운 것이다. 건너뛰기가
// 가능한 것은 디스크립터가 32 B 고정이기 때문이며 — 가변 길이였다면 모르는 항목의
// 길이를 몰라 링이 그 자리에서 영구히 멈춘다 — *고정 폭이 되돌림의 전제다*.
//
// **여백 정책 — 장치가 32 B 전량을 기입한다 (예약은 0), 호스트는 예약을
// 무시한다.** 두 의무는 서로를 대체하지 않는다: 기입 의무는 *잔류*를 없애기
// 위한 것이고 무시 의무는 *하위 호환*을 위한 것이다. 장치가 0 을 쓰는 이유는
// 호스트가 그것을 검사하기 때문이 아니다 (E.5.3 여백 정책 3항).
//
// 이 표면은 §5.7 함정의 두 정책 중 *돌려주는 쪽*이다. 받아들이는 쪽 정책(예약
// 비0 은 malformation)을 여기 옮겨 오면 예약에 필드를 넣는 개정이 옛 호스트를
// 전부 깨뜨린다. 명령 디스크립터가 *반대쪽*이며 E.5.4 가 그렇게 정한다 — 같은
// 32 B 형식과 같은 태그 코덱을 쓰므로 정책까지 같아야 할 것처럼 보이는 자리이고,
// 그래서 특히 밟기 쉽다. 같은 것은 *직렬화*이고 다른 것은 *처분*이다.
//
// 전량 기입이 *의무*인 이유가 위 (2) 다. 정본 함정의 논거를 옮겨 적자면: 변환
// 저장에는 유효 비트라는 방벽이 있어 남은 데이터가 읽히지 않지만 **링 칸에는 그
// 방벽이 없다** — head 와 tail 은 「이 칸이 유효한가」만 말하고 「이 칸의 어느
// 바이트가 이번 것인가」는 말하지 않는다. 방벽이 없으므로 잔류가 곧 오독이며,
// *전량 기입이 방벽을 대신한다*.
//
// 구현이 그 의무를 이행하는 방식은 디스크립터를 **색인 0..7 위의 전사 함수**로
// 짓는 것이다 (`HostDesc.completion`). 전사 함수에는 미정의 워드가 존재할 수
// 없으므로 전량 기입이 *구조*다 — 검사가 아니라 표현 불가능성이다.
//
// ## 태그를 「해석」하지 않는다는 규율은 유지된다
//
// 이 모듈이 태그 필드를 이름으로 받게 됐지만, 어느 필드도 비교·분기·주소
// 산출에 쓰지 않는다 — 명명된 자리에 놓기만 한다. §1.4.4 「wave 는 불투명
// 식별자」가 금지한 것은 *해석*이고 여기서 하는 것은 *보존*이다. 조립의
// 유일 지점 규범도 지켜진다: 워드로 펴는 코드는 `Types.Tag.toWords` 한 곳이고
// 이 파일은 그것을 호출할 뿐 자기 팩킹을 갖지 않는다.
//
// ## 오버플로 처분 — E.5 그대로 (배압 규약 정합)
//
// 완료 링이 가득이면 장치는 *배압으로 정지*한다 (§2.6) — comp.ready 강하가
// 그 배압이다. ready 가 낮다고 알린 사이클에 온 valid(= 가득인 링에 밀어
// 넣기)가 E.5 의 오버플로이며 처분은 loud sticky fault 다 (§3.8 「오버플로」
// 항 · SharedUnit/FabricMerge 의 같은 배압 규약). 그 갈래는 어떤 링 상태에도
// 쓰지 않는다 — 밀어 넣어진 항목은 저장에 닿지 않는다 (FAB-10 과 동형).
// 이 fault 는 오버플로 전용이며 다른 신호와 폴딩하지 않는다 (§5.6 — 폴딩
// 여부는 신호마다 명시).
//
// **해제 경로는 이 모듈 밖이다.** 정본 E.1.2 가 링 오버플로를 장치 전역 fault
// 워드의 `0xF80[16]` 으로 배정했으므로 sticky 를 내리는 표면도 그쪽(`0xF84`
// W1C)이다 — 이 모듈은 `io.faultClearOverflow` 입력으로 그 해제를 받는다.
// 옛 착지는 완료 구역 안에 자기 FAULT/FAULT_CLEAR 두 워드를 두고 있었고
// (구역 안 `+0x1C`/`+0x20`), 새 맵에서 그 자리는 각각 *미정의 오프셋* 과
// *IRQ_STATUS* 다. 두 워드를 지우는 것이 이 이동의 안전 논거다 — 남겨 두면
// 정본을 따라 IRQ_STATUS 를 읽는 드라이버가 옛 FAULT_CLEAR 를 밟는다.
//
// ## FAB-6 앵커 — 이 모듈이 호스트 의무의 장치 쪽 실물 표면이다
//
// E.6 4항 「호스트는 완료 링을 결국 비운다」는 장치 규범이 아니라 호스트 ABI
// 의무다 (§3.10). FAB-6 진행성의 조건부 의무 사슬을 하류로 따라가면 마지막에
// 기계 밖 — 완료 링을 읽는 호스트 — 이 나오고, 무조건 의무가 놓일 자리는
// 그곳 하나다 (E.6 해설). 그 의무를 선-formal 은 Fabric.tla 의 bp_relief
// 공정성 가정으로 걸어 검증했고, 정식 매핑 줄(ENV)은 fabric/FabricMerge.scala
// 머리가 소유한다 — 가드당 저장소 전체 정확히 1줄이므로 여기 다시 적지
// 않는다 (MmioConfig 의 Route 가드 서술 선례). 접점만 남긴다:
//
//   · Fabric.bp_relief (FabricMerge 의 ENV 줄) — 그 줄이 가리키는 호스트
//     의무 「완료 링을 결국 비운다」의 장치 쪽 실물이 이 모듈의 head 배수
//     표면(CQ_HEAD 기입 + 엔트리 창 읽기)이다. RTL 검사가 아니라 표면 제공
//     이다 — 장치는 이행을 강제할 수단을 두지 않는다 (E.6: 타임아웃은
//     조용한 실패의 다른 이름이다, E.3 과 같은 처분).
//
// GUARD-MAP 줄 없음 — 이 모듈 소유의 선-formal 모델은 없다 (완료 큐·통지는
// Fabric.tla 가 bp_relief 가정으로, 배압 처분은 SharedUnit.tla 가 같은 규약
// 으로 이미 다뤘다). 후속 모델이 서면 그때 정식 줄이 이 파일로 온다.
//
// ## MMIO 자리 — 정본 E.1.2 「완료 방향 — 0x300 구역」 그대로
//
// 상위 데코더가 `0x300`–`0x37F` 를 갈라 이 모듈에 넣는다 — addr 는 구역 안
// 바이트 오프셋이다. 표에 없는 *정렬* 오프셋·비정렬 *읽기*는 예약 *오프셋* 정책이다 (비정렬 *쓰기*는 거절 + loud — 판정 T2)
// (§3.7 — 쓰기 무시 · 읽기 0. 명령 인코딩의 예약 *필드*와 정반대 정책임에
// 주의 — 그쪽은 0 이 아니면 malformation 이다).
//
// **오프셋 배치는 더는 이 구현의 잠정 결정이 아니다.** 앞 착지는 자기 배치를
// 두고 그것을 §3.10 합의의 입력이라 적었는데, 그 사이 정본 E.1.2 가 구역
// 배정 원칙 넷을 적용해 워드를 전수로 확정했다. 값의 단일 출처는 그 표 하나다
// — 아래 상수는 그것의 전사이며, 이 파일이 새로 정하는 오프셋은 하나도 없다.
//
//   +0x00 CQ_BASE_LO   RW  UNWIRED — 쓰기 거절 + loud · 읽기 0 (판정 T1-i β) — 링 기저 하위 32b (이 링은 장치 상주)
//   +0x04 CQ_BASE_HI   RW  UNWIRED — 쓰기 거절 + loud · 읽기 0 (판정 T1-i β) — 상위 32b (LO 스테이징 · HI 커밋 발화)
//   +0x08 CQ_SIZE      RW  [4:0] log2(엔트리 수) · [31:5] 예약 = 0 (엄격)
//   +0x0C CQ_HEAD      RW  소비 색인 — *호스트 갱신* (E.5 표의 RW 그대로)
//   +0x10 CQ_TAIL      RO  생산 색인 — *장치 갱신* (E.5 표의 RO 그대로)
//   +0x20 IRQ_STATUS   RO  [0] sticky 인터럽트 상태 (E.6)
//   +0x24 IRQ_MASK     RW  [0] 1 = 마스크 · [31:1] 예약 = 0 (엄격). reset 값 1
//                          — 인터럽트는 opt-in 가속이다 (E.6 함정: 인터럽트를
//                          정상 경로의 전제로 두지 말 것. 기본이 폴링이어야
//                          그 함정이 닫힌다)
//   +0x28 IRQ_CLEAR    WO  [0] 에 1 기입 = 명시적 해제 · [31:1] 예약(엄격)
//   +0x40~+0x5C 엔트리 창 RO  head 가 가리키는 항목의 8워드 (빈 링이면 0)
//   +0x60~+0x74 드레인 카운트 RO  §3.7 여섯 항 (E.11 — 아래 io.drain 순서)
//   +0x78 CQ_OCC       RO  자기 완료 큐 점유 (E.11 집계의 일곱째 관측)
//   +0x7C DRAIN_ALLZERO RO [0] 전부 0 — 여섯 카운트 + 완료 큐 점유
//
// CQ_SIZE 는 정본이 *지수 인코딩*을 규범화했다 — `[4:0]` 이 log2(엔트리 수)
// 이고, 그래야 E.5 1항 「2의 거듭제곱」이 기입 시점 검사 없이 구조로 성립한다.
// 옛 착지는 엔트리 수를 그대로 돌려주고 있었다 (깊이 8 이면 8). 재인코딩의
// 결과는 3 이다 — 같은 워드가 다른 뜻을 갖게 되므로 이동이 아니라 *의미
// 변경*이며, 드라이버가 옛 값을 새 인코딩으로 읽으면 8 을 2^8 로 오해한다.
// 옛 자리(`+0x00`)를 반드시 비워야 하는 이유가 여기 있다.
//
// 「전부 0」 비트는 읽기 수락 사이클의 조합 스냅샷 하나가 단일 32비트 읽기로
// 나간다 — 호스트가 여섯(+1) 카운트를 개별로 읽는 동안 상태가 움직이는 찢김을
// 이 비트 하나가 닫는다 (E.11 규범). 완료 큐 점유를 논리합에 넣는 것은 지시된
// 집계이며 보수 방향이다 — 링 배수는 어차피 호스트의 E.6 의무라서 드레인
// 완주를 새로 막지 않는다 (E.11 문면은 여섯이다 — 보고서 model_feedback 참조).
//
// ## 「예약」과 「미배선」을 코드에서 가른다
//
// CQ_BASE_LO/HI 는 *표에 있는* 워드인데 이 구현에 소비자가 없다 — 링이 장치
// 상주(내부 `Mem`)라 기저 주소를 소비하지 않기 때문이다 (정본 E.1.3 등재).
// 처분은 정본 E.1.3 규범 끝(소비 회로가 없는 RW 워드 — 판정 T1-i β)이다: 쓰기 거절 + loud · 읽기 0. 예약(쓰기 무시)과 *사실*이 다르므로
// 이름 있는 상수와 `UNWIRED` 주석을 갖는다 — 다음 사람이 「예약인가 미배선
// 인가」를 물었을 때 답이 코드에 있어야 한다 (`object Wt64Top` 의 같은 처분).
// 명령 방향(`0x380`–`0x3FF`)은 이 모듈의 구역이 아예 아니다 — 상위 데코더가
// 별 구역(`R_SQ`)으로 든다.
//
// ## 기입 거절 — RO 오프셋과 예약 비트 (E.1.1 엄격 정책)
//
// 정본 E.1.2 는 이 구역의 예약 *비트*를 엄격으로 못박고 (CQ_SIZE `[31:5]` ·
// IRQ_MASK/IRQ_CLEAR `[31:1]`), E.1.2 해설은 「RO 오프셋 쓰기」를 FAULT_STATUS
// `[6]`「거절된 구성 기입」에 접는다. 이 모듈은 그 둘을 자기 sticky
// (`io.faultBadWrite`)로 들고 top 이 `0xF80[6]` 에서 합류시킨다 — 하위 유닛의
// sticky 를 top 이 대신 들지 않는다는 규율은 MmioConfig 선례 그대로다.
//
// CQ_SIZE 는 정본이 RW 지만 이 구현에서 링 크기는 *elaborate 상수*다. 다른
// 크기를 요구하는 기입은 이행할 수단이 없고, 조용히 무시하면 호스트는 자기가
// 정한 크기의 링이 있다고 믿는다 — 그래서 「현재 크기와 같은 값」만 수락(무동작)
// 이고 다른 값은 거절 + loud 다. 링의 거처(호스트 메모리 / 장치 상주) 합의가
// 서면 이 워드가 진짜 RW 가 될 자리이며 그때까지의 처분이다 (§3.10 입력).
// CQ_HEAD 의 마스크 밖 상위 비트만 정본이 *정규화*(관대)로 정했다 — 링 크기
// 마스크가 곧 mod size 이기 때문이며, 이 모듈은 그 한 워드만 관대하다.

package wt64.host

import spinal.core._
import wt64.{Isa, StickyFault, Types}

/** 부록 E.5 디스크립터 프레임 — **두 링에 하나뿐인 서명**.
  *
  * ## 왜 두 방향이 한 객체에 있는가
  *
  * 태그는 명령 방향에서 호스트가 *만들어 넣고* 완료 방향에서 *돌려받는다*.
  * 두 표면의 직렬화가 갈리면 호스트 SDK 에 태그 코덱이 두 벌 생기고, 그 드리프트가
  * §1.4.4 「태그 조립은 한 곳에서」가 이름한 실패형의 *호스트 판*이 된다. 그래서
  * 결정 4·5 는 한 서명이고, 그 서명의 장치 쪽 단일 출처가 이 객체다.
  *
  * 아래 `require` 가 그 「같은 서명」을 elaborate 시점에 강제한다 — 태그 세 워드가
  * 두 방향에서 *같은 상대 오프셋* `+0x04`~`+0x0F` 에 선다는 것이 주석이 아니라 검사다
  * (정본 E.5.4 규범 1항이 그 한 줄을 요구한다).
  *
  * ## 명령 방향은 아직 UNWIRED 다 (예약이 아니다)
  *
  * 이 저장소에 명령 링 소비자는 없다 — 일의 원천이 `Wt64Top.io.instr` 외부 제시이고
  * 링에서 디스크립터를 꺼내는 경로가 없다 (E.1.3 등재). 그럼에도 상수를 여기 두는
  * 이유는 결정 A(명령 제시의 태그 사이드밴드)가 「1 디스크립터 = 1 명령 + 그 태그」를
  * 요구하기 때문이다: 소비자가 서는 날 그 파일은 이 상수를 *참조*해야 하고 자기 배치를
  * 새로 적으면 안 된다. 「이름은 있는데 회로가 없다」와 「예약이라 이름이 없다」는 다른
  * 사실이고, 그 구별이 코드에 있어야 한다 (이 파일 머리의 같은 규율).
  *
  * ## 명령 본문이 참조인 이유
  *
  * 산술이 첫째다 — 명령 최대 길이 448b = 56 B (§1.3, CH 포함 14워드) 는 32 B 에 애초에 들어가지
  * 않는다. *더 무거운 둘째*는 §1.3 이 그 상한을 「형상 파라미터이지 ISA 상수가
  * 아니다」라고 적는다는 것이다: 본문을 품는 디스크립터는 폭이 그 파라미터의
  * 함수가 되고, 디스크립터는 드라이버 구조체다. E.1.2 해설이 「바이너리도
  * 드라이버 구조체도 형상에 닿지 않는다 — INV-T1 이 지키려는 것이 그 둘」이라
  * 적은 둘 중 하나가 형상에 닿게 된다. 참조로 가면 폭이 32 B 로 고정이고, 형상에
  * 닿는 것은 *본문의 길이*뿐이며 그것은 이미 형상에 닿아도 되는 값이다.
  */
object HostDesc {
  /** 디스크립터 폭 — 32 B 고정 (E.5 4항). 두 방향 공통. */
  val BYTES = 32
  val WORDS = BYTES / 4
  val W     = BYTES * 8

  /** kind 폭 — 선두 바이트 (E.5.2). */
  val KIND_W = 8

  /** kind 값 공간 — **두 방향이 나눠 쓰는 하나**다 (E.5.2 2항).
    *
    * 방향마다 공간을 가르면 같은 값이 두 링에서 다른 뜻이 되어 코덱이 「지금 어느
    * 링인가」를 알아야 한다. 한 공간이면 kind 하나가 「무엇이며 어느 방향인가」를
    * 함께 정하고, *잘못된 링에 놓인 디스크립터가 탐지 가능해진다.*
    *
    * 배정은 **단조 추가**다 — 배정된 값의 뜻은 재사용하지 않으며, 배치 개정은 옛
    * kind 를 고치는 것이 아니라 새 kind 를 더하는 것이다. 그래야 옛 호스트가
    * *자기가 모른다는 것을 알고* 건너뛴다 (E.5 2항의 대우).
    */
  object Kind {
    /** `0x00` 은 **부적법**이다 — 0 으로 남은 링 칸이 적법한 디스크립터로 읽히지
      * 않게 한다 (E.5.2 표). 창 읽기가 빈 링에 0 을 내는 처분과 짝이다. */
    val INVALID    = 0x00
    val COMPLETION = 0x01
    val COMMAND    = 0x02
  }

  /** 워드 0 — 두 방향 공통. `[7:0]` kind · `[31:8]` 예약 = 0. */
  val W_KIND = 0

  /** 태그 세 워드의 시작 — **두 방향에서 같다** (`+0x04`~`+0x0F`).
    *
    * kind 바로 뒤인 이유: 태그는 두 방향이 *공유하는 유일한 블록*이므로 방향 고유
    * 필드보다 앞에 둔다. 앞에 두면 공유 블록의 오프셋이 방향 고유 필드의 개수·폭
    * 변화에 흔들리지 않는다. 뒤에 두면 명령 쪽 본문 참조가 넓어질 때 태그가 밀리고,
    * 그 순간 「같은 상대 오프셋」이 깨진다 (E.5.3 해설). */
  val W_TAG0 = 1
  def tagWord(i: Int): Int = W_TAG0 + i

  // ── 완료 방향 (kind = COMPLETION) — E.5.3 ──────────────────────────────
  /** `+0x10` CD_BASE — `[7:0]` 결속 LBID (§4.3) · `[31:8]` 예약 = 0. */
  val CD_W_BASE = 4
  /** `+0x14` CD_TOTAL — `[31:0]` 조각 선언 총개수 (E.10).
    *
    * *폭이 확정되지 않은 값의 그릇*이라 워드 하나를 전량 쓴다. E.10 4항이 총개수
    * 폭을 정하지 않았으므로 어떤 폭도 상위 0 확장으로 들어가고, 폭이 확정될 때 이
    * 배치가 움직이지 않는다. CD_BASE 와 한 워드를 나눠 쓰면 총개수의 확정 폭이
    * base 의 자리를 밀 수 있다 — *폭이 확정된 것을 먼저 앉히고 미확정을 뒤로
    * 민다*는 원칙(E.5.3 해설)의 적용이다. */
  val CD_W_TOTAL = 5
  /** `+0x18`·`+0x1C` — 예약 = 0. 미확정 폭 필드 *뒤*에 여백을 둔다: 총개수의
    * 그릇이 자라야 할 때 자랄 방향에 예약이 있다. 남긴 8 B 는 새 kind 가 쓸
    * 자리이기도 하다 (고정 폭이므로 빽빽하게 채워도 얻는 것이 없다). */
  val CD_W_RSV0 = 6
  val CD_W_RSV1 = 7

  // ── 명령 방향 (kind = COMMAND) — E.5.4. UNWIRED ────────────────────────
  /** `+0x10`·`+0x14` — 명령 본문 주소 64b (하위·상위). 링 기저와 *같은 주소
    * 공간*이고 장치의 그 접근은 같은 규약(§3.4.1 소유권 · §3.6 변환) 아래
    * 든다 — 디스크립터는 그 규약을 우회하는 문이 아니다. */
  val SD_W_BODY_LO = 4
  val SD_W_BODY_HI = 5
  /** `+0x18` SD_LEN — `[15:0]` 본문 길이(32b 워드 수) · `[31:16]` 예약 = 0.
    *
    * *가져오기 경계*이지 걷기의 종료 판정이 아니다 — 종료는 여전히 `bh_len`
    * (§1.3) 이고 이 워드가 그것을 이중 선언하지 않는다. 경계 안에 남는 바이트는
    * 오류가 아니다 (정렬 패딩 EH `0xF` 가 정상 형태이므로 상한이지 등호가
    * 아니다). 길이 0 은 부적법이다 — 기본 헤더 한 워드는 반드시 있다. */
  val SD_W_LEN     = 6
  val SD_LEN_W     = 16
  /** `+0x1C` — 예약 = 0. */
  val SD_W_RSV     = 7

  /** 명령 방향의 예약은 **엄격**이다 — 비0 은 malformation 이고 처분은 거절 +
    * loud fault (FAULT_STATUS `[18]`). 완료 쪽과 정책이 반대인 이유는 방향이
    * 반대이기 때문이다 (§5.7 · E.5.2 해설). 이 상수는 소비자가 서는 날 그 파일이
    * *참조*할 자리이며, 지금 이 저장소에 명령 링 소비자는 없다. */
  val SD_LEN_RSV_MASK = 0xFFFF0000L

  // ── 프레임 정합 — 주석이 아니라 검사다 ────────────────────────────────
  private val tagEnd = W_TAG0 + Types.Tag.WORDS
  require(W_KIND == 0, "kind 는 선두 바이트여야 한다 (E.5.2 1항 — 순환 방지)")
  require(tagEnd <= WORDS,
    s"태그 ${Types.Tag.WORDS} 워드가 워드 $W_TAG0 부터 $WORDS 워드 프레임에 들어가지 않는다")
  // 「태그가 양방향에서 같은 상대 오프셋」— 두 방향의 방향 고유 워드가 전부
  // 태그 구간 *뒤*에 있다는 것이 그 성립 조건이고, 이 넷이 그것을 강제한다.
  require(Seq(CD_W_BASE, CD_W_TOTAL, CD_W_RSV0, CD_W_RSV1).forall(w => w >= tagEnd && w < WORDS),
    "완료 방향 워드가 태그 구간과 겹치거나 프레임 밖이다 — 「같은 상대 오프셋」이 깨진다")
  require(Seq(SD_W_BODY_LO, SD_W_BODY_HI, SD_W_LEN, SD_W_RSV).forall(w => w >= tagEnd && w < WORDS),
    "명령 방향 워드가 태그 구간과 겹치거나 프레임 밖이다 — 「같은 상대 오프셋」이 깨진다")
  require(Seq(CD_W_BASE, CD_W_TOTAL, CD_W_RSV0, CD_W_RSV1).distinct.length == 4 &&
          Seq(SD_W_BODY_LO, SD_W_BODY_HI, SD_W_LEN, SD_W_RSV).distinct.length == 4,
    "한 방향 안에서 두 필드가 같은 워드를 쓴다")
  require(Isa.LBID_W <= 32 && Isa.FRAG_TOTAL_W <= 32, "CD_BASE·CD_TOTAL 필드가 워드를 넘는다")
  require(SD_LEN_W <= 32, "SD_LEN 필드가 워드를 넘는다")

  /** 완료 디스크립터 조립 — **32 B 전량** (E.5.3 여백 정책 1항).
    *
    * 색인 0..WORDS-1 위의 *전사 함수*로 짓는다. 「기본값 0 을 깔고 덮어쓰기」가
    * 아니라 매 워드가 정확히 한 번 정의되는 형태인데, 이유는 두 가지다:
    * SpinalHDL 의 noLatchNoOverride 가 조건 없는 전면 덮어쓰기를 거부하고
    * (실측), 무엇보다 *전사 함수에는 미정의 워드가 존재할 수 없다*. 「32 B
    * 전량 기입 · 예약 0」이 검사가 아니라 구조인 지점이 여기다 — 부분 갱신으로
    * 이전 항목이 남는 경로는 표현할 수조차 없다.
    *
    * `case _` 는 예약 워드다. 새 워드가 정의되면 그 자리는 `case` 하나가 되고,
    * 그때까지는 0 이 *기입된다* — 기입되지 않고 남는 것과 다르다.
    *
    * 태그를 워드로 펴는 일은 `Types.Tag.toWords` 가 한다 — 이 함수는 그것을
    * *배치*할 뿐 자기 팩킹을 갖지 않는다 (§1.4.4 조립 단일 지점).
    *
    * `poison` 은 CD_TAG1 `[27]` 에 실릴 *장치 저작* 값이다 (1.4.4 poison 6항 ·
    * E.5.3). 입력 태그의 poison 비트는 명령 사이드밴드가 제시한 값이라 장치 저작이
    * 아니다 — 그래서 코덱이 poison 을 인자로 받고 여기가 그 원천을 댄다. 예약
    * `[25:16]` 은 코덱이 0 을 쓴다 (D2c 수리 — 태그 코덱 전파 파도).
    */
  def completion(tag: Types.Tag, poison: Bool, base: UInt, total: UInt): Vec[Bits] = {
    val tw = Types.Tag.toWords(tag, poison)
    Vec((0 until WORDS).map {
      case W_KIND     => B(Kind.COMPLETION, 32 bits) // [7:0] kind · [31:8] 예약 0
      case CD_W_BASE  => base.asBits.resize(32)      // [7:0] LBID · [31:8] 예약 0
      case CD_W_TOTAL => total.asBits.resize(32)     // [31:0] 그릇 — 상위 0 확장
      case i if i >= W_TAG0 && i < tagEnd => tw(i - W_TAG0)
      case _          => B(0, 32 bits)               // 예약 워드 — 0 을 *기입한다*
    })
  }

  /** 워드 Vec → 링 칸에 실리는 비트열. 워드 0 이 최하위다 — 창 읽기의
    * `subdivideIn(32 bits)(i)` 규약과 같은 방향이어야 호스트가 본 워드 i 와
    * 여기의 워드 i 가 같은 것을 가리킨다. */
  def pack(words: Vec[Bits]): Bits = words.reverse.reduce(_ ## _)
}

/** 지역 상수 — 전부 형상 무관 (INV-T1: 어느 값도 인스턴스 개수의 함수가
  * 아니다. 디스크립터 배치는 `HostDesc` 가 소유하고 여기는 그 폭을 전사한다).
  */
object CompletionUnit {
  /** 완료 디스크립터 — 32 B 고정 (E.5 4항). 값의 출처는 `HostDesc` 하나다. */
  val ENTRY_BYTES = HostDesc.BYTES
  val ENTRY_W     = HostDesc.W
  val ENTRY_WORDS = HostDesc.WORDS
  /** 드레인 카운트 폭 — 고정 상수. 값의 상한은 형상이 정하지만 폭은 형상의
    * 함수가 아니다 (E.10 이 조각 머리 폭에 내린 처분과 같은 논리). */
  val DRAIN_CNT_W = 16

  // ═══ MMIO 오프셋 — 구역(0x300–0x37F) 안 바이트 오프셋 ═════════════════
  // 값의 단일 출처는 정본 E.1.2 「완료 방향 — 0x300 구역」 표다 (파일 머리).

  /** UNWIRED — 표에 있고 소비자 회로가 없다. 이 링은 장치 상주(내부 `Mem`)라
    * 기저 주소를 소비하지 않는다 (정본 E.1.3 「두 링의 base」 행). 상수를
    * 두는 이유는 「예약이라 이름이 없다」와 「이름은 있는데 회로가 없다」가
    * 다른 사실이기 때문이다 — 아래 어느 회로도 이 둘을 저장·되읽기하지 않으며,
    * *그 사실 자체가* UNWIRED 의 뜻이다 — 거절선(isBase) 하나만 둘을 본다 (판정 T1-i β: 쓰기 거절 + loud · 읽기 0). */
  val OFF_CQ_BASE_LO  = 0x00
  val OFF_CQ_BASE_HI  = 0x04

  val OFF_CQ_SIZE     = 0x08 // RW  [4:0] log2(엔트리 수) · [31:5] 예약(엄격)
  val OFF_CQ_HEAD     = 0x0C // RW  마스크 밖 상위는 *정규화*(관대) — E.1.2
  val OFF_CQ_TAIL     = 0x10 // RO
  val OFF_IRQ_STATUS  = 0x20 // RO
  val OFF_IRQ_MASK    = 0x24 // RW  [31:1] 예약(엄격)
  val OFF_IRQ_CLEAR   = 0x28 // WO  [31:1] 예약(엄격)
  val OFF_WINDOW      = 0x40 // ~0x5C — head 엔트리 8워드 (RO)
  val OFF_DRAIN       = 0x60 // ~0x74 — 여섯 카운트 (RO)
  val OFF_CQ_OCC      = 0x78 // RO
  val OFF_ALLZERO     = 0x7C // RO

  /** 드레인 카운트 워드 수 — §3.7 정의역 여섯 항 (E.11). */
  val DRAIN_WORDS = 6

  // ═══ 워드 안의 예약 비트 — 엄격 (비0 기입은 거절 + loud fault) ════════
  // 적재 마스크의 *여집합으로 유도*한다 — 두 상수가 따로 표류할 자리를
  // 없앤다 (`object Wt64Top` 의 `rsv()` · MmioConfig.LNID_RSV_MASK 선례).
  private def rsv(loadMask: Long): Long = (~loadMask) & 0xFFFFFFFFL
  val CQ_SIZE_RSV   = rsv(0x0000001FL) // [31:5]
  val IRQ_MASK_RSV  = rsv(0x00000001L) // [31:1]
  val IRQ_CLEAR_RSV = rsv(0x00000001L) // [31:1]
}

/** §3.7 드레인 정의역 여섯 항의 진행 중 개수 — E.11 의 입력면.
  *
  * 각 유닛이 자기 점유 상태를 노출하고 top 이 여기로 배선한다. 이 번들은
  * 새 상태가 아니라 이미 있는 점유의 집계 어휘다 (E.11 해설).
  */
case class DrainCounts() extends Bundle {
  import CompletionUnit.DRAIN_CNT_W
  val pipe     = UInt(DRAIN_CNT_W bits) // ① 요청 파이프라인 안의 요청 (§3.2 여섯 단계)
  val pending  = UInt(DRAIN_CNT_W bits) // ② 공유 유닛의 보류 자원 (§2.2)
  val output   = UInt(DRAIN_CNT_W bits) // ③ 생산자 출력 자원·병합 중 전송 (§2.6)
  val ownSlots = UInt(DRAIN_CNT_W bits) // ④ 소유 구간 진행 중 결과 슬롯 (§2.4)
  val contexts = UInt(DRAIN_CNT_W bits) // ⑤ 활성 재조립 문맥 — 미완 포함 (§4.3)
  val tokens   = UInt(DRAIN_CNT_W bits) // ⑥ 미완료 순서 토큰 (§4.4)
}

/** 완료 큐 · 통지 · 드레인 관측면.
  *
  * 버스 프로토콜은 상위 몫이다 (MmioConfig 선례) — 소박한 동기 인터페이스:
  * ready 는 상시 높다 (다사이클 연산이 없다). 읽기는 수락 다음 사이클에
  * rdata 유효 (rvalid 1펄스). 쓰기는 1사이클 커밋.
  *
  * @param cqDepth 완료 링 깊이 (엔트리 수). 2의 거듭제곱 (E.5 — 나머지가
  *                마스크가 된다). 한 칸을 비우는 인코딩이라 수용량은
  *                cqDepth-1 이다. Wt64Config 승격 후보 — 보고서 promote 의
  *                diff 제안 참조 (그때까지 생성자 파라미터로 둔다).
  */
class CompletionUnit(val cqDepth: Int = 8) extends Component {
  import CompletionUnit._

  require(cqDepth >= 2 && isPow2(cqDepth),
    "링 크기는 2의 거듭제곱 >= 2 — E.5 (한 칸을 비워 빈/가득을 구별하므로 1이면 수용량 0)")

  private val ptrW = log2Up(cqDepth)

  val io = new Bundle {
    // ── MMIO (0x300 영역 안 바이트 오프셋 — 상위 데코더가 가른다) ───────
    val addr    = in  port UInt(8 bits)
    val wstrobe = in  port Bool()
    val wdata   = in  port Bits(32 bits)
    val rstrobe = in  port Bool()
    val rdata   = out port Bits(32 bits)
    val rvalid  = out port Bool()
    val ready   = out port Bool()

    // ── 완료 항목 수락 — push 규약 (§2.6): 상류는 ready 를 보고 정지한다.
    //    ready 가 낮은 사이클의 valid 는 가득인 링에 밀어 넣기 = E.5 오버플로.
    //
    //    **명명 필드로 받는다 — 앞판의 불투명 256비트가 아니다.** 조립을 상류
    //    (top)에 맡기면 「32 B 전량 기입 · 예약 0」이 이 모듈 밖의 사실이 되고,
    //    이 모듈의 하네스로는 잴 수 없다. E.5 를 소유한 유닛이 E.5 디스크립터를
    //    조립하는 것이 자리 배치로도 옳다 (파일 머리 「완료 디스크립터」 절).
    //    필드를 이름으로 받는 것과 그 값을 *해석*하는 것은 다르다 — 아래 어느
    //    회로도 태그를 비교·분기·주소 산출에 쓰지 않는다 (§1.4.4).
    val comp = new Bundle {
      val valid = in  port Bool()
      val tag   = in(Types.Tag())                     // §1.4.4 — 보존만 한다
      val base  = in  port UInt(Isa.LBID_W bits)      // 결속 LBID (§4.3)
      val total = in  port UInt(Isa.FRAG_TOTAL_W bits) // 조각 선언 총개수 (E.10)
      val ready = out port Bool()
    }

    // ── 완료 통지 — 인터럽트 선 (E.6: 선택적 가속. 통지 자체는 링 항목이다)
    val irq = out port Bool()

    // ── E.11 여섯 카운트 (top 배선 — 각 유닛의 점유 관측 출력에서 온다) ──
    val drain = in port DrainCounts()

    // ── loud fault 관측 — 합성 가능한 sticky 상태 비트 (§3.8 오버플로).
    //    해제는 장치 전역 fault 표면의 명시적 W1C 뿐이다 (`0xF84[16]`) —
    //    top 이 그 펄스를 아래 입력으로 준다. 배압 해제가 fault 를 함께
    //    지우는 동반 클리어는 금지다 (§2.6 함정) — 이 입력의 유일한 원천이
    //    호스트의 명시 기입이라는 사실이 그 금지의 이행이다.
    val faultOverflow      = out port Bool()
    val faultClearOverflow = in  port Bool()

    /** 거절된 구성 기입 — RO 오프셋 쓰기 + 워드 안 예약 비트 비0 + 이행할 수
      * 없는 CQ_SIZE 값 (파일 머리 「기입 거절」). top 이 `0xF80[6]` 에서
      * MmioConfig·top 표면의 같은 부류와 합류시킨다 (§5.6 — 폴딩 지점을
      * 신호마다 명시). 해제는 `0xF84[6]` W1C. */
    val faultBadWrite      = out port Bool()
    val faultClearBadWrite = in  port Bool()
  }

  io.ready := True // 다사이클 수락이 없다 — 예약 정책 포함 모든 접근이 1사이클

  // ═══ 완료 링 — E.5 인코딩 그대로 ════════════════════════════════════
  // 갱신 주체는 표 그대로: tail 은 장치(push), head 는 호스트(MMIO 기입) —
  // 서로 다른 레지스터라 경합 표면이 없다. head 는 기입 워드 전폭을 마스크로
  // 정규화해 든다 (MmioConfig 의 엔트리 마스크 선례 — 정책이 상수 한 곳에
  // 보인다). 마스크가 곧 mod size 다 (E.5 1항 — 2^k 크기의 이유). 정규화로
  // 0 이 되는 상위 비트는 예약 비트의 관대 정책과 같다: 쓰기 무시 · 읽기 0.
  val headReg = Reg(Bits(32 bits)) init 0
  val head    = headReg(ptrW - 1 downto 0).asUInt
  val tail    = RegInit(U(0, ptrW bits))
  val ring = Mem(Bits(ENTRY_W bits), cqDepth)

  val empty = head === tail                // E.5 2항 — 빈 링
  val full  = (tail + 1) === head          // E.5 2항 — 가득 (한 칸 비움)
  val occ   = tail - head                  // 점유 — 감산이 폭으로 wrap (<= cqDepth-1)

  // 배압: 받을 수 없음이 상류에 보인다 (§2.6 — 배압은 오류가 아니다).
  io.comp.ready := !full

  // ═══ 디스크립터 조립 — 32 B 전량 (파일 머리 「완료 디스크립터」 절) ═══
  // descWords 여덟 개가 *전부* 구동된다 (색인 위의 전사 함수). 미구동
  // 워드가 없으므로 부분 갱신 경로가 존재하지 않는다 — 이전 항목 잔류의 부재가
  // 검사가 아니라 구조다. desc 는 그 여덟 워드를 워드 0 = 최하위로 묶은 것이고,
  // 창 읽기의 subdivideIn 과 같은 방향이라 「호스트가 본 워드 i」와 「여기의
  // 워드 i」가 같은 것을 가리킨다.
  //
  // CD_TAG1 `[27]` poison — *장치 저작*이고 오늘 원천이 0건이다 (정본 3.9 · E.1.3
  // 「CD_TAG1 poison · trace」 행: 유일한 후보 원천 FAULT `[17]` 엔트로피 건강성이
  // 미착지). 그래서 상수 0 이다. 입력 태그의 poison 은 명령 사이드밴드가 제시한
  // 비트라 원천이 아니다 — 그것을 반향하던 것이 D2c 다. 원천이 서는 날 이 한 줄이
  // 장치 안 전파(1.4.4 poison 2항 — 논리합)의 결과로 바뀐다.
  val devPoison = False
  val descWords = HostDesc.completion(io.comp.tag, devPoison, io.comp.base, io.comp.total)
  val desc      = HostDesc.pack(descWords)

  // 수락 = 통지 (E.6 1항 — 링에 항목을 넣는 것이 통지다).
  val doPush = io.comp.valid && !full
  when(doPush) { tail := tail + 1 }
  ring.write(tail, desc, doPush) // 마스크 없음 = 칸 전폭 기입

  // 가득인 링에 밀어 넣기 — E.5 오버플로. loud sticky, 링 상태 불변
  // (이 갈래는 head·tail·ring 어디에도 쓰지 않는다 — FAB-10 동형).
  val shove = io.comp.valid && full

  // ═══ MMIO 접근 수락 ═════════════════════════════════════════════════
  val aligned = io.addr(1 downto 0) === 0 // 비정렬 *쓰기*는 거절 + loud (T2 — badWrite) · 비정렬 읽기는 0 (§3.7)
  val acceptW = io.wstrobe                 // 동시 제시면 쓰기 우선 (MmioConfig 선례)
  val acceptR = !io.wstrobe && io.rstrobe

  // ═══ 워드 판정 — 정본 표의 자리마다 하나 ════════════════════════════
  // 처분(RW / RO / WO / UNWIRED)이 워드마다 갈리므로 판정도 워드마다 선다.
  val isSize   = io.addr === OFF_CQ_SIZE
  val isHead   = io.addr === OFF_CQ_HEAD
  val isTail   = io.addr === OFF_CQ_TAIL
  val isIrqSt  = io.addr === OFF_IRQ_STATUS
  val isIrqMk  = io.addr === OFF_IRQ_MASK
  val isIrqClr = io.addr === OFF_IRQ_CLEAR
  val isWindow = io.addr(7 downto 5) === (OFF_WINDOW >> 5)
  val isDrain  = (0 until DRAIN_WORDS).map(i => io.addr === (OFF_DRAIN + 4 * i)).reduce(_ || _)
  val isOcc    = io.addr === OFF_CQ_OCC
  val isAllZ   = io.addr === OFF_ALLZERO
  /** 정본이 RO 로 정한 오프셋 전수 — 쓰기는 거절 + loud (E.1.2 해설). */
  val isRoOff  = isTail || isIrqSt || isWindow || isDrain || isOcc || isAllZ

  // ═══ 쓰기 — 1사이클 커밋. 표에 없는 오프셋은 무시 ═══════════════════
  val doWr = acceptW && aligned

  // 예약 비트 검사 — 엄격 워드 셋 (E.1.1: 비0 기입은 거절 + loud fault).
  val sizeRsvBad = (io.wdata & B(CQ_SIZE_RSV,   32 bits)) =/= 0
  val mkRsvBad   = (io.wdata & B(IRQ_MASK_RSV,  32 bits)) =/= 0
  val clrRsvBad  = (io.wdata & B(IRQ_CLEAR_RSV, 32 bits)) =/= 0

  /** 이 구현이 이행할 수 있는 유일한 CQ_SIZE 값 — 링이 장치 상주라 크기가
    * elaborate 상수다. 다른 값을 요구하는 기입은 거절 + loud (파일 머리). */
  val sizeValBad = io.wdata(4 downto 0).asUInt =/= U(log2Up(cqDepth), 5 bits)

  // 해제 펄스 — 거절된 기입은 발화하지 않는다 (반쯤 수락이 없다).
  val irqClrPulse = doWr && isIrqClr && !clrRsvBad && io.wdata(0)

  // 인터럽트 마스크 — reset 1 (끔). 인터럽트는 opt-in 가속이다 (E.6 함정 —
  // 켜져 있어야 도는 설계는 인터럽트 지원 호스트를 전제한다). 정의 비트는
  // [0] 하나이고 [31:1] 은 *엄격* 예약이라 정규화가 아니라 거절이다.
  val irqMaskReg = Reg(Bits(32 bits)) init 1
  val irqMask    = irqMaskReg(0)

  // head 는 호스트가 소비한 만큼 전진시키는 값이다 (E.5 표 — RW). 마스크 밖
  // 비트는 버린다 (2^k 크기 — 나머지 연산이 마스크다. 이 한 워드만 정본이
  // 정규화로 정했다). 값의 적법성(전진이 tail 을 넘지 않음)은 호스트 ABI
  // 의무다 — 장치는 강제 수단을 두지 않는다 (E.6 — 타임아웃은 조용한 실패의
  // 다른 이름).
  when(doWr && isHead)                 { headReg := io.wdata & B(cqDepth - 1, 32 bits) }
  when(doWr && isIrqMk && !mkRsvBad)   { irqMaskReg := io.wdata }

  // CQ_BASE_LO/HI — UNWIRED. 소비 회로가 없는 RW 워드라 쓰기는 거절 + loud · 읽기 0 이다 (정본 E.1.3 규범 끝 · 판정 T1-i β —
  // 레지스터만 실물화해 되읽기를 주는 것은 금지 · 소비 회로가 서면 수락으로 넓힌다). 옛 처분은 「*거절도 아니다*」였다.
  val isBase = io.addr === OFF_CQ_BASE_LO || io.addr === OFF_CQ_BASE_HI

  // 거절 — 비정렬 쓰기(T2) · RO 오프셋 쓰기 · 소비 없는 base 쓰기(T1-i) · 예약 비트 비0 · 이행 불가 CQ_SIZE 값.
  val badWrite = (acceptW && !aligned) || doWr && (isRoOff || isBase ||
    (isSize   && (sizeRsvBad || sizeValBad)) ||
    (isIrqMk  && mkRsvBad) ||
    (isIrqClr && clrRsvBad))

  // ═══ 통지 상태 — sticky, 명시적 해제까지 유지 (E.6 3항) ═════════════
  // set 원천은 항목 삽입(doPush) 하나다 — 통지가 곧 삽입이라는 E.6 1항의
  // 상태화. 해제와 삽입이 같은 사이클이면 삽입이 이긴다 (StickyFault 규약 —
  // 해제로 통지를 삼키는 창이 없다).
  val irqSticky = StickyFault(set = doPush, clear = irqClrPulse)
  io.irq := irqSticky && !irqMask

  // ═══ 오버플로 fault — 세운다 / 명시적 해제 외엔 내리지 않는다 ═══════
  // 해제 원천은 장치 전역 fault 표면(`0xF84[16]`) 하나다 — top 이 준다.
  val faultOv = StickyFault(set = shove, clear = io.faultClearOverflow)
  io.faultOverflow := faultOv

  // ═══ 거절된 구성 기입 — 같은 규약의 sticky (`0xF80[6]` 에서 합류) ════
  io.faultBadWrite := StickyFault(set = badWrite, clear = io.faultClearBadWrite)

  // ═══ E.11 집계 — 조합. 새 상태 없음 (해설 문면 그대로) ═══════════════
  val cntVec = Vec(io.drain.pipe, io.drain.pending, io.drain.output,
                   io.drain.ownSlots, io.drain.contexts, io.drain.tokens)
  // 「전부 0」 — 여섯 카운트 + 자기 완료 큐 점유의 단일 비트 스냅샷.
  val allZero = cntVec.map(_ === 0).reduce(_ && _) && occ === 0

  // ═══ 읽기 — 수락 다음 사이클 rdata (예약 오프셋은 0 — §3.7) ═════════
  // 레지스터·카운트 읽기는 수락 사이클의 조합값을 rdataReg 에 스냅한다 —
  // ALLZERO 가 단일 읽기 원자 스냅샷이 되는 지점이 정확히 여기다 (E.11).
  // WO 워드(IRQ_CLEAR)와 UNWIRED 워드(CQ_BASE_LO/HI)는 아래에 없다 — 읽기 0
  // 이 그 처분의 이행이다 (WO 의 되읽기를 주지 않는다 · 미배선은 값이 없다).
  val readValue = Bits(32 bits)
  readValue := 0
  when(aligned) {
    switch(io.addr) {
      // CQ_SIZE — *지수* 인코딩 (E.1.2). 엔트리 수가 아니라 log2 다.
      is(OFF_CQ_SIZE)    { readValue := B(log2Up(cqDepth), 32 bits) }
      is(OFF_CQ_HEAD)    { readValue := headReg }
      is(OFF_CQ_TAIL)    { readValue := tail.resize(32).asBits }
      is(OFF_IRQ_STATUS) { readValue := irqSticky.asBits.resize(32) }
      is(OFF_IRQ_MASK)   { readValue := irqMaskReg }
      is(OFF_CQ_OCC)     { readValue := occ.resize(32).asBits }
      is(OFF_ALLZERO)    { readValue := allZero.asBits.resize(32) }
      // 드레인 여섯 카운트 — +0x60 + 4·i (E.11 · §3.7 정의역 순서)
      for (i <- 0 until DRAIN_WORDS) {
        is(OFF_DRAIN + 4 * i) { readValue := cntVec(i).resize(32).asBits }
      }
    }
  }

  // 엔트리 창 — head 항목을 동기 읽기로 낸다. 빈 링이면 0 (미기입 저장소를
  // 관측면에 내지 않는다 — head∈[head,tail) 인 항목만 창에 실린다).
  val ringRd = ring.readSync(head, acceptR)

  val rdataReg = Reg(Bits(32 bits)) init 0
  val winSel   = RegInit(False)
  val winWord  = Reg(UInt(3 bits)) init 0
  io.rvalid := RegNext(acceptR, False)
  when(acceptR) {
    rdataReg := readValue
    winSel   := aligned && isWindow && !empty
    winWord  := io.addr(4 downto 2)
  }
  io.rdata := winSel ? ringRd.subdivideIn(32 bits)(winWord) | rdataReg
}
