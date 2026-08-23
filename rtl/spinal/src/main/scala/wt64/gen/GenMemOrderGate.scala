// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

package wt64.gen

import wt64.Wt64
import wt64.memorder.{MemOrderGate, MemOrderGateParams}

/** EXT-6 발화 게이트 생성기.
  *
  * 형상은 기본값(nSlots = 4, reqW = 16) 하나다 — reqW 는 불투명 기술자
  * 폭의 생성용 자리값이며 계약이 아니라 elaborate 인수다 (MemOrderGate 는
  * payload 를 해석하지 않는다). nSlots 의 바닥 3 은 파라미터 require 가
  * 지키므로 (선-formal ASSUME 동형) 경계 형상을 따로 내지 않는다.
  */
object GenMemOrderGate extends App {
  private val target = if (args.nonEmpty) args(0) else "."
  private val report = Wt64.config(target).generateSystemVerilog(
    MemOrderGate(MemOrderGateParams())
  )
  println(s"[wt64] 생성: ${report.toplevelName} → $target")
}
