// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

package wt64.gen

import spinal.core._
import wt64.Wt64

/** ⚠️ 이것은 설계가 *아니다*.
  *
  * WT64v1 의 어떤 계약도 구현하지 않으며, 재구현 설계가 착지하면 삭제된다.
  * 존재 이유는 하나 — `make rtl-gen` 이 **무언가를 실제로 하는지** 판정할
  * 대상을 주는 것이다.
  *
  * 정본 §6.7 이 지목한 실패형 중 하나가 *"조건이 안 맞으면 스스로 건너뛰고
  * 통과로 보고하는 테스트"* 다. 생성할 것이 없을 때 조용히 성공하는
  * `rtl-gen` 은 정확히 그 형태다. 그래서 자리를 비워 두지 않는다.
  *
  * 이 컴포넌트가 검사하는 것:
  *   · sbt 런처가 `project/build.properties` 의 버전을 부트스트랩하는가
  *   · Scala 컴파일러와 SpinalHDL idsl 컴파일러 플러그인이 함께 서는가
  *   · `SpinalSystemVerilog` 가 실제로 파일을 뱉는가
  *   · 생성이 **결정적**인가 (날짜·시각이 박히지 않는가)
  */
class ToolchainCheck extends Component {
  val io = new Bundle {
    val a = in port Bits(8 bits)
    val b = in port Bits(8 bits)
    val q = out port Bits(8 bits)
  }
  io.q := io.a ^ io.b
}

object ToolchainCheck extends App {
  private val target = if (args.nonEmpty) args(0) else "."
  private val report = Wt64.config(target).generateSystemVerilog(new ToolchainCheck)
  // 조용히 끝나지 않게 무엇을 어디에 냈는지 말한다.
  println(s"[wt64] 생성: ${report.toplevelName} → $target")
}
