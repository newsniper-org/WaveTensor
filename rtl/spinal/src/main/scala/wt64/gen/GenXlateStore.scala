// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

package wt64.gen

import wt64.{Wt64, Wt64Config}
import wt64.hiu.XlateStore

/** 변환 저장 블록 생성기 — `make rtl-gen` 이 부른다.
  * args(0) = 출력 디렉터리. 형상은 Wt64Config 기본값 (파티션 4 × 색인 16,
  * 부록 E.2 의 참조 형상). */
object GenXlateStore extends App {
  private val target = if (args.nonEmpty) args(0) else "."
  private val report =
    Wt64.config(target).generateSystemVerilog(new XlateStore(Wt64Config()))
  // 조용히 끝나지 않게 무엇을 어디에 냈는지 말한다.
  println(s"[wt64] 생성: ${report.toplevelName} → $target")
}
