// SPDX-License-Identifier: CC-BY-4.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

#import "lib/template.typ": *

#show: 문서.with(
  제목: "WaveTensor WT64v1",
  부제: "아키텍처 규범 — 재구현 기준 문서",
  판: "판 0.1 (초판)",
  날짜: "2026-08-20",
)

#include "chapters/00-preface.typ"
#include "chapters/01-isa-asm.typ"
#include "chapters/02-fabric-alu.typ"
#include "chapters/03-hiu.typ"
#include "chapters/04-ext-payload.typ"
#include "chapters/05-security.typ"
#include "chapters/06-formal.typ"

#include "appendix/a-capacity.typ"
#include "appendix/b-gaps.typ"
#include "appendix/c-glossary.typ"
#include "appendix/d-properties.typ"

#pagebreak()
#set heading(numbering: none)
= 참고문헌

#bibliography("refs.yml", title: none, style: "ieee")
