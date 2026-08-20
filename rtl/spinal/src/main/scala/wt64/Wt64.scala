// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

package wt64

import spinal.core._

/** WT64v1 재구현의 생성 설정.
  *
  * 생성 설정을 **단 한 곳에서만** 정의한다. 정본 §1.4.5 「태그 조립은 한 곳에서」의
  * 논리를 툴체인 층에 그대로 적용한 것이다 — 참조 구현은 같은 관용구를 30곳
  * 이상에 복제했고, 그래서 개정이 30곳을 동시에 고치는 일이 됐다.
  * 복제된 설정은 반드시 드리프트한다.
  */
object Wt64 {

  /** 생성물에 박히는 헤더.
    *
    * 두 가지를 동시에 한다 — 라이선스 고지(CONTRIBUTING §2 의 HW 등급)와
    * *이것이 생성물이라는 사실*의 고지. 후자가 없으면 누군가 반드시 손으로
    * 고치고, 다음 생성에서 조용히 사라진다.
    */
  val rtlHeader: String =
    """SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
      |SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
      |
      |=== 생성물이다. 손으로 고치지 말 것. ===
      |고칠 곳은 rtl/spinal/ 의 생성기이고, 고친 뒤 `make rtl-gen` 으로 다시 낸다.
      |여기 직접 쓴 수정은 다음 생성에서 조용히 사라진다.
      |""".stripMargin

  /** 생성 설정.
    *
    * 두 헤더 옵션을 끄는 것은 취향이 아니라 요건이다. 생성물은 **생성기
    * 소스의 순수 함수**여야 한다 — 그래야 "재생성해서 바이트 비교" 라는
    * 최신성 검사가 성립하고, 그것이 이 저장소가 `include/generated/` 에
    * 이미 쓰고 있는 방식이다 (`lint_isa_tables_fresh.py`).
    *
    *  - `headerWithDate = false`
    *      날짜가 박히면 같은 입력이 매번 다른 출력을 낸다. 생성물을 커밋하는
    *      것도 diff 로 검토하는 것도 의미를 잃는다.
    *
    *  - `headerWithRepoHash = false`
    *      이쪽은 이유가 하나 더 있다. 박히는 값은 *생성 시점의 HEAD* 인데,
    *      생성물은 그 다음 커밋에 담긴다. 즉 파일 안의 해시는 **그 파일을
    *      담은 커밋을 결코 가리키지 않는다** — 출처 표기로서 틀렸다.
    *      진짜 출처는 git 자신이 갖고 있다: 생성물과 생성기를 함께 커밋하므로
    *      그 커밋이 곧 답이다. 틀린 출처를 박느니 안 박는 편이 낫다.
    */
  def config(targetDirectory: String = "."): SpinalConfig =
    SpinalConfig(
      targetDirectory    = targetDirectory,
      rtlHeader          = rtlHeader,
      headerWithDate     = false,
      headerWithRepoHash = false,
    )
}
