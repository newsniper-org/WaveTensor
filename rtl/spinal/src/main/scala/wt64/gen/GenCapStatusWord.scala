// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

package wt64.gen

import wt64.Wt64
import wt64.host.CapStatusWord
import wt64.top.Wt64Top

/** CapStatusWord 생성기 — args(0) = 출력 디렉터리.
  *
  * 형상 파라미터가 없다 — 축 수는 ABI(`Wt64Top.Fault.N_CAP_BITS`)이지 형상이
  * 아니다. 독립본은 후-formal(rtl/formal/sby/CapStatusWord)의 [files] 입력이고,
  * Wt64Top.sv 안에도 같은 모듈이 인라인된다 (sim 은 top 본을 읽는다).
  */
object GenCapStatusWord extends App {
  private val target = if (args.nonEmpty) args(0) else "."
  private val report = Wt64.config(target)
    .generateSystemVerilog(CapStatusWord(nBits = Wt64Top.Fault.N_CAP_BITS))
  // 조용히 끝나지 않게 무엇을 어디에 냈는지 말한다.
  println(s"[wt64] 생성: ${report.toplevelName} → $target")
}
