// SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// WT64v1 재구현 — SpinalHDL 빌드 정의.
//
// ⚠️ 아래 세 버전은 .devcontainer/devcontainer.json 의 build.args 와 **반드시
//    일치**한다. 컨테이너는 이 값들로 의존을 미리 구워 두므로, 어긋나면
//    빌드가 오프라인에서 죽거나(운이 좋을 때) 다른 버전을 조용히 받아 온다
//    (운이 나쁠 때). scripts/lint_toolchain_pins.py 가 대조한다.
//
// Scala 3 는 쓸 수 없다 — SpinalHDL 은 `_3` 아티팩트를 배포하지 않는다(실측).
// 2.13.12 인 이유는 SpinalHDL 1.14.2 의 POM 이 의존하는 값이 정확히 그것이기
// 때문이다. 플러그인은 binary cross(`_2.13`) 라 다른 patch 도 될 가능성이
// 높으나, 상류가 실제로 빌드한 값을 쓰는 것이 재현성에서 가장 싸다.

ThisBuild / scalaVersion  := "2.13.12"
ThisBuild / organization  := "kr.wavetensor"
ThisBuild / version       := "0.1.0-SNAPSHOT"

val spinalVersion = "1.14.2"

lazy val wt64 = (project in file("."))
  .settings(
    name := "wt64v1-rtl",

    libraryDependencies ++= Seq(
      "com.github.spinalhdl" %% "spinalhdl-core" % spinalVersion,
      "com.github.spinalhdl" %% "spinalhdl-lib"  % spinalVersion,
    ),
    addCompilerPlugin("com.github.spinalhdl" %% "spinalhdl-idsl-plugin" % spinalVersion),

    // 경고를 오류로 올린다. 정본 §5.4.2 「전역 경고 억제 금지」의 Scala 층
    // 적용이다 — 경고를 낮추는 설정은 의도된 것을 숨기면서 진짜도 숨긴다.
    scalacOptions ++= Seq(
      "-deprecation",
      "-feature",
      "-unchecked",
      "-Xlint",
      "-Werror",
    ),

    // 출력 위치는 생성기에 **인수로** 넘긴다 (Makefile 의 rtl-gen 참조).
    // 빌드 설정으로 cwd 를 옮기지 않는 이유는 움직이는 부품을 줄이기 위해서다 —
    // 두 곳이 출력 위치를 말하면 반드시 어긋난다.
    fork := true,
  )
