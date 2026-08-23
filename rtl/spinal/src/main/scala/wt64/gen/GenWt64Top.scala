// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

package wt64.gen

import wt64.{Wt64, Wt64Config}
import wt64.top.Wt64Top

/** top-level 조립 생성기 — args(0) = 출력 디렉터리.
  *
  * 형상은 Wt64Config 기본값 (승격 3건 — ownEntries 64 · cqDepth 8 ·
  * stepProgDepth 10 — 이 여기서 하위 유닛 전부에 한 곳 정의로 흐른다).
  */
object GenWt64Top extends App {
  private val target = if (args.nonEmpty) args(0) else "."
  private val report = Wt64.config(target).generateSystemVerilog(new Wt64Top(Wt64Config()))
  // 조용히 끝나지 않게 무엇을 어디에 냈는지 말한다.
  println(s"[wt64] 생성: ${report.toplevelName} → $target")
}
