// SPDX-License-Identifier: CC-BY-4.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// 조판 규약 — 이 문서의 모든 시각적 구분은 여기서 한 번만 정의된다.
// 규범(지켜야 할 것)과 해설(왜 그런가)을 눈으로 구분할 수 없으면
// 재구현팀이 해설을 규범으로, 규범을 해설로 읽는다.

#let 본문색 = rgb("#1a1a1a")
#let 규범색 = rgb("#0b3d5c")
#let 측정색 = rgb("#4a4a4a")
#let 속성색 = rgb("#4a2d6b")
#let 경고색 = rgb("#8c2d1a")

// ---------------------------------------------------------------------------
// 문서 골격
// ---------------------------------------------------------------------------
#let 문서(제목: "", 부제: "", 판: "", 날짜: "", 본문) = {
  set document(title: 제목, author: "윤병익 (BYUNG-IK YEUN)")
  set page(
    paper: "a4",
    margin: (top: 25mm, bottom: 25mm, left: 24mm, right: 24mm),
    numbering: "1",
    number-align: center,
  )
  set text(
    font: ("Noto Serif CJK KR",),
    size: 10pt,
    lang: "ko",
    fill: 본문색,
  )
  set par(justify: true, leading: 0.78em, spacing: 1.15em)
  set heading(numbering: "1.1")

  show heading: it => {
    set text(font: ("Noto Sans CJK KR",), fill: 규범색)
    v(0.6em)
    it
    v(0.3em)
  }
  show heading.where(level: 1): it => {
    pagebreak(weak: true)
    set text(font: ("Noto Sans CJK KR",), size: 17pt, fill: 규범색)
    block(width: 100%)[
      #v(0.4em)
      #it
      #v(0.1em)
      #line(length: 100%, stroke: 0.8pt + 규범색)
    ]
    v(0.5em)
  }

  show raw: set text(font: ("Noto Sans Mono CJK KR",), size: 8.6pt)

  // 절 참조를 국문으로 — 기본 supplement 는 "Section" 이라 한국어 본문에서 튄다.
  // 부록은 번호 자체가 "부록 A" 이므로 "장" 을 덧붙이지 않는다.
  show ref: it => {
    let el = it.element
    if el != none and el.func() == heading {
      let n = numbering(el.numbering, ..counter(heading).at(el.location()))
      // 부록은 번호 자체가 "부록 A" 이므로 "장" 을 덧붙이지 않는다.
      let 부록인가 = type(n) == str and n.starts-with("부록")
      if el.depth == 1 and not 부록인가 { n + [장] } else { n }
    } else { it }
  }
  show link: set text(fill: 규범색)

  set table(stroke: 0.4pt + luma(160), inset: 5pt)
  show table.cell.where(y: 0): set text(
    font: ("Noto Sans CJK KR",), weight: "bold", size: 9pt,
  )

  // ---- 표지 ----
  align(center)[
    #v(5.5cm)
    #text(font: ("Noto Sans CJK KR",), size: 24pt, weight: "bold", fill: 규범색)[#제목]
    #v(0.5cm)
    #text(font: ("Noto Sans CJK KR",), size: 13pt, fill: 측정색)[#부제]
    #v(2.2cm)
    #text(size: 11pt)[#판]
    #v(0.2cm)
    #text(size: 11pt, fill: 측정색)[#날짜]
  ]
  pagebreak()

  outline(depth: 2, indent: auto)
  pagebreak()

  본문
}

// ---------------------------------------------------------------------------
// 트랙 표지 — 「측정된 것」 / 「지켜야 할 것」 / 「형식 속성」
// ---------------------------------------------------------------------------
#let 트랙(종류, 본문) = {
  let (색, 이름, 설명) = if 종류 == "측정" {
    (측정색, "측정된 것", "참조 구현에서 실제로 잰 것 · 재구현이 보존할 의무는 없다")
  } else if 종류 == "규범" {
    (규범색, "지켜야 할 것", "새 구현이 만족해야 하는 계약")
  } else {
    (속성색, "형식 속성", "선-formal 에서 증명 · 후-formal 에서 RTL 대조")
  }
  v(0.5em)
  block(
    width: 100%,
    fill: 색.lighten(93%),
    stroke: (left: 2.5pt + 색),
    inset: (left: 9pt, rest: 8pt),
    radius: 2pt,
  )[
    #text(font: ("Noto Sans CJK KR",), size: 9.5pt, weight: "bold", fill: 색)[「#이름」]
    #h(0.6em)
    #text(size: 8pt, fill: 측정색)[#설명]
    #v(0.35em)
    #본문
  ]
  v(0.3em)
}

// ---------------------------------------------------------------------------
// 규범 문장 — 재구현이 반드시 지켜야 하는 것
// ---------------------------------------------------------------------------
#let 규범(라벨: none, 본문) = {
  block(
    width: 100%,
    fill: 규범색.lighten(95%),
    stroke: 0.6pt + 규범색.lighten(50%),
    inset: 8pt,
    radius: 2pt,
  )[
    #if 라벨 != none [
      #text(font: ("Noto Sans CJK KR",), size: 8.5pt, weight: "bold", fill: 규범색)[#라벨]
      #v(0.25em)
    ]
    #본문
  ]
}

// 해설 — 왜 그렇게 정했는가. 지킬 의무 없음.
#let 해설(라벨: none, 본문) = {
  block(
    width: 100%,
    inset: (left: 10pt, rest: 6pt),
    stroke: (left: 1.2pt + luma(190)),
  )[
    #if 라벨 != none [
      #text(font: ("Noto Sans CJK KR",), size: 8.5pt, weight: "bold", fill: 측정색)[#라벨]
      #v(0.2em)
    ]
    #text(size: 9pt, fill: 측정색)[#본문]
  ]
}

// 경고 — 재구현이 밟기 쉬운 함정
#let 함정(라벨: none, 본문) = {
  block(
    width: 100%,
    fill: 경고색.lighten(94%),
    stroke: (left: 2.5pt + 경고색),
    inset: (left: 9pt, rest: 8pt),
    radius: 2pt,
  )[
    #text(font: ("Noto Sans CJK KR",), size: 9pt, weight: "bold", fill: 경고색)[⚠ 함정#if 라벨 != none [ — #라벨]]
    #h(0.5em)
    #본문
  ]
}

// ---------------------------------------------------------------------------
// 출처 등급 배지 — 모든 수치에 붙는다
// ---------------------------------------------------------------------------
#let 등급(종류) = {
  let (색, 글) = if 종류 == "실측" {
    (rgb("#1d6b3a"), "실측")
  } else if 종류 == "유도" {
    (rgb("#8a6d1f"), "유도")
  } else if 종류 == "목표" {
    (rgb("#1f5a8a"), "목표")
  } else {
    (경고색, "미측정")
  }
  box(
    fill: 색.lighten(88%),
    stroke: 0.4pt + 색,
    inset: (x: 3.5pt, y: 1.2pt),
    radius: 2pt,
    baseline: 1.5pt,
  )[#text(size: 7.2pt, font: ("Noto Sans CJK KR",), weight: "bold", fill: 색)[#글]]
}

// ---------------------------------------------------------------------------
// 용어 정의 — 정의 없이 쓰는 낱말이 없어야 한다
// ---------------------------------------------------------------------------
#let 정의(용어, 본문) = {
  block(width: 100%, inset: (y: 3pt))[
    #text(font: ("Noto Sans CJK KR",), weight: "bold", fill: 규범색)[#용어]
    #h(0.4em) — #h(0.2em) #본문
  ]
}

// 형식 속성 항목
#let 속성(번호, 단계: "선", 본문) = {
  let 단계글 = if 단계 == "선" { "선-formal" } else if 단계 == "후" { "후-formal" } else { 단계 }
  block(width: 100%, inset: (y: 2.5pt))[
    #box(
      fill: 속성색.lighten(90%), stroke: 0.4pt + 속성색,
      inset: (x: 3.5pt, y: 1.2pt), radius: 2pt, baseline: 1.5pt,
    )[#text(size: 7.2pt, font: ("Noto Sans CJK KR",), weight: "bold", fill: 속성색)[#번호]]
    #h(0.3em)
    #box(inset: (x: 2pt))[#text(size: 7.5pt, fill: 측정색)[#단계글]]
    #h(0.2em)
    #본문
  ]
}
