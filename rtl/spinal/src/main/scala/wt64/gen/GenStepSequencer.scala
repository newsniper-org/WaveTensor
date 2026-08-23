// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

package wt64.gen

import wt64.Wt64
import wt64.fp.{StepSeqParams, StepSequencer}

/** step sequencer 골격 생성기 (정본 §2.5).
  *
  * 두 형상을 낸다 — 기본(P = 10, 참조 구현의 step 프로그램 전 상주 형상)과
  * P = 1. P = 1 은 §2.5 규범(P >= 1)의 경계 형상이므로 elaborate 가 실제로
  * 서는지를 생성 단계에서 상시 확인한다 (§6.7: 조건이 안 맞으면 스스로
  * 건너뛰고 통과로 보고하는 검사를 두지 않는다 — GenSharedUnit 깊이 0 선례).
  * 전 상주 형상에서 능력 부재 경로는 도달 가능하다(결속 전 조회) — 「도달
  * 불가한 채 계약으로만 존재」는 호스트가 10종을 전부 결속한 뒤의 이야기다.
  *
  * FAB-7 매핑 전 축: 곱셈 연산자 유일성은 StepSequencer elaborate 자체가
  * require 로 강제한다 — 이 생성이 성공했다는 사실이 그 검사의 통과다.
  */
object GenStepSequencer extends App {
  private val target = if (args.nonEmpty) args(0) else "."

  private val r1 = Wt64.config(target).generateSystemVerilog(
    new StepSequencer(StepSeqParams()))
  println(s"[wt64] 생성: ${r1.toplevelName} → $target")

  private val r2 = Wt64.config(target).generateSystemVerilog(
    new StepSequencer(StepSeqParams(progDepth = 1))
      .setDefinitionName("StepSequencerP1"))
  println(s"[wt64] 생성: ${r2.toplevelName} → $target")
}
