// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

package wt64.gen

import spinal.core.HardType
import wt64.{Wt64, Wt64Config}
import wt64.fabric.{FabricMerge, ResultBeat}

/** FabricMerge 생성기.
  *
  * 페이로드는 ResultBeat(조각 머리 + 본문) — 본문 폭 64 는 생성용 자리값이다.
  * 정본 §2.3.1 이 재구현 폭을 측정 후 결정으로 미루므로, 여기 값은 계약이
  * 아니라 elaborate 인수다 (FabricMerge 는 페이로드를 해석하지 않는다).
  */
object GenFabricMerge extends App {
  private val target = if (args.nonEmpty) args(0) else "."
  private val report = Wt64.config(target).generateSystemVerilog(
    FabricMerge(Wt64Config(), HardType(ResultBeat(bodyW = 64)))
  )
  println(s"[wt64] 생성: ${report.toplevelName} → $target")
}
