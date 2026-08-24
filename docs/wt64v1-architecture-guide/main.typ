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

// 부록은 "부록 A" / "A.1" 형태로 번호를 매긴다. numbering 을 끄면 참조가 깨지므로
// 끄지 않고 형식만 바꾼다. *이 자리여야 한다* — 부록 파일 안에 두면 `#set` 의
// 스코프가 그 `#include` 의 콘텐츠 블록에 갇혀 첫 부록에만 걸리고, 반대로
// `#counter(heading).update(0)` 은 전역에 남아 나머지 부록이 「2장·3장…」으로
// 렌더된다 (부록 상호참조 31곳이 틀린 번호를 인쇄하던 결함).
#counter(heading).update(0)
#let _부록글자 = ("A", "B", "C", "D", "E", "F")
#set heading(numbering: (..n) => {
  let p = n.pos()
  let 글 = _부록글자.at(p.at(0) - 1)
  if p.len() == 1 { "부록 " + 글 } else { 글 + "." + p.slice(1).map(str).join(".") }
})

#include "appendix/a-capacity.typ"
#include "appendix/b-gaps.typ"
#include "appendix/c-glossary.typ"
#include "appendix/d-properties.typ"
#include "appendix/e-defined.typ"

#pagebreak()
#set heading(numbering: none)
= 참고문헌

#bibliography("refs.yml", title: none, style: "ieee")
