// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

package wt64.gen

import wt64.{Wt64, Wt64Config}
import wt64.fabric.ResultBank

/** ResultBank 생성기 — 형태는 ToolchainCheck 과 동일 (args(0) = 출력 디렉터리). */
object GenResultBank extends App {
  private val target = if (args.nonEmpty) args(0) else "."
  private val report = Wt64.config(target).generateSystemVerilog(new ResultBank(Wt64Config()))
  // 조용히 끝나지 않게 무엇을 어디에 냈는지 말한다.
  println(s"[wt64] 생성: ${report.toplevelName} → $target")
}
