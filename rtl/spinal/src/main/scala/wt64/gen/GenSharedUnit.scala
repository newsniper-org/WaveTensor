// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

package wt64.gen

import wt64.Wt64
import wt64.fabric.{SharedUnit, SharedUnitParams}

/** FAB-2 공유 유닛 처분 구조 생성기.
  *
  * 두 형상을 낸다 — 기본 깊이와 깊이 0. 깊이 0(「항상 배압」)은 정본
  * §2.2 3항이 명시적으로 적법하다고 적은 경계 형상이므로, elaborate 가
  * 실제로 서는지를 생성 단계에서 상시 확인한다 (§6.7: 조건이 안 맞으면
  * 스스로 건너뛰고 통과로 보고하는 검사를 두지 않는다).
  */
object GenSharedUnit extends App {
  private val target = if (args.nonEmpty) args(0) else "."

  private val r1 = Wt64.config(target).generateSystemVerilog(
    new SharedUnit(SharedUnitParams()))
  println(s"[wt64] 생성: ${r1.toplevelName} → $target")

  private val r2 = Wt64.config(target).generateSystemVerilog(
    new SharedUnit(SharedUnitParams(queueDepth = 0))
      .setDefinitionName("SharedUnitDepth0"))
  println(s"[wt64] 생성: ${r2.toplevelName} → $target")
}
