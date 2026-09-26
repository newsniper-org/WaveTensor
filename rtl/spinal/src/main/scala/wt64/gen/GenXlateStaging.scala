// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

package wt64.gen

import wt64.Wt64
import wt64.top.XlateStaging

/** 변환 저장소 호스트 쪽 문의 *상한 아래 형상* 생성기 — `make rtl-gen` 이 부른다.
  *
  * 파티션 2 판(`XlateStagingP2`) 하나만 낸다. 기본 형상(파티션 4 — 인코딩 상한)의
  * 문은 Wt64Top.sv 안에 있고 XlateStaging/props.sby 가 거기서 잰다. 상한에서는
  * 항목 배열의 형상 밖 주소 가지(entPhantom)가 elaborate 상수 False 라 어느
  * 태스크도 그 가지를 재지 못한다 — 판정 T4 (ii) 의 처분(형상 밖 주소의 LO · HI 는
  * 거절 + loud · 스테이징 부동)을 재려면 그 가지가 서는 형상이 따로 elaborate 돼야
  * 한다. 이 생성물을 XlateStaging/p2.sby 가 잰다.
  *
  * GenSharedUnit(깊이 0) · GenStepSequencer(P = 1) 선례: 경계 형상의 elaborate 가
  * 실제로 서는지를 생성 단계에서 상시 확인한다 (조건이 안 맞으면 스스로 건너뛰고
  * 통과로 보고하는 검사를 두지 않는다 — 두 선례 머리의 같은 규율).
  */
object GenXlateStaging extends App {
  private val target = if (args.nonEmpty) args(0) else "."

  private val r = Wt64.config(target).generateSystemVerilog(
    new XlateStaging(2).setDefinitionName("XlateStagingP2"))
  println(s"[wt64] 생성: ${r.toplevelName} → $target")
}
