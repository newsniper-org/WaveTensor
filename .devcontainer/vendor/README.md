# `.devcontainer/vendor/` — 보관본 (내용이지 선언이 아니다)

*착지 2026-09-11. 사용자 판정 「landing → commit → 대기」 —
`.claude-memos/toolchain_pin_axis.md` §3 의 선택지 ⒜(저장소 안), **jar 하나만**.*

이 디렉터리는 환경 정의(`../Dockerfile`)가 상류에서 받아 오던 자산 가운데
**상류가 계속 준다는 보장이 없는 것**의 사본을 둔다. 정본 §6.6.2 의 말로:
내용 고정(해시)은 필요조건이고, 재현의 충분조건은 그 내용을 이쪽이 보관하는
것이다. 실증 — `tla2tools.jar` 는 세 주 사이 두 번 죽었다(`cdc769d` 8/29 ·
`ddcf150` 9/11). 보관본이 서면 상류 푸시는 더는 수리 사건이 아니라 **선택적
업그레이드**다.

## 규율 — 보관본과 핀은 둘째 선언처가 아니다

- **핀**은 `../Dockerfile` 의 `ARG TLA_BLAKE2B512` 와 `../devcontainer.json`
  의 같은 키, 정확히 **둘**이다. 그것은 변하지 않았다.
- **보관본**은 그 핀이 가리키는 *내용*이다. 선언이 아니다. 둘이 어긋나면
  `scripts/lint_toolchain_pins.py` 가 크게 실패한다 (보관 jar 의 BLAKE2b-512
  ≠ `TLA_BLAKE2B512`). `--self-test` 가 그 변이 셋 — 보관본 1바이트 훼손 ·
  핀만 갱신 · 보관본 부재 — 을 매 게이트마다 문다.
- 빌드는 `COPY` 뒤에 `b2sum -c` 를 **그대로** 둔다. 보관본이 조용히 바뀌는 것을
  lint 가 놓쳐도 빌드가 잡는다 (두 그물, 같은 값).

## 재핀 절차 — 이제 이렇게 바뀐다

전에는 「상류 URL 이 다른 바이트를 주면 빌드가 죽고 → 핀 둘을 고친다」였다
(수리 사건). 지금은 **상류가 밀어도 아무것도 깨지지 않는다.** 올리고 싶을 때:

1. 상류에서 새 자산을 받아 `b2sum` · `TLC2 Version …` 자기보고를 잰다.
2. `tla2tools.jar` 를 **교체**한다 (git 이력에 옛 사본이 남는다 — 아래 대가).
3. 핀 넷(`TLA_VERSION` · `TLA_BLAKE2B512` · `TLA_TLC_BUILD` · `TLA_TLC_REV`)을
   `../Dockerfile` 과 `../devcontainer.json` 에서 갱신한다.
4. `make rtl-pins` (보관본↔핀 일치 + 자기시험) → `podman build --no-cache`
   완주 + 스모크 → 374 run 배터리.
5. 번들 구성이 바뀌었으면 아래 번들표와 `licenses/` 를 **다시 실측**해 고친다
   (그때 표의 `@c3af5e2` 출처 좌표도 새 rev 로 — 그 좌표는 라이선스 본문을
   가져온 상류 커밋의 기록이지 현행 핀이 아니다; 본문이 같으면 옛 좌표도
   여전히 참이다). **이 문서는 핀 값(해시·크기·build·rev)을 담지 않는다** —
   `lint_toolchain_pins.py` 가 128-hex 와 `YYYY.MM.DD.HHMMSS` 꼴을 이 파일에서
   금지한다(V4·V5). 그래서 재핀 자체로는 여기 갱신할 것이 없다.

## 대가 — 적어 두고 감수한다

- **git 에 4.3 MiB 급 바이너리**가 든다(정확한 크기는 `stat`; 여기 적지
  않는다 — 아래 「실측」 참조). 재핀할 때마다 새 사본이 이력에 영구히 쌓인다
  (되돌릴 수 없다). 상류가 롤링이라 재핀은 반복 이벤트이나,
  이제 재핀은 **선택**이지 강제가 아니므로 빈도는 이쪽이 정한다.
- **git-lfs 를 쓰지 않는다** (선택지 ⒝ 기각). LFS 서버는 곧 새로운 상류다 —
  포인터만 남는 실패가 지금 겪은 것과 같은 모양으로 한 겹 안쪽에 선다. clone
  하나로 환경을 다시 지을 수 있어야 한다는 것이 ⒜ 의 전제다.
- **ALA 층은 여전히 보관본이 없다.** 이 파도의 범위 밖이다 (사용자 판정).
  분량으로도 위험으로도 큰 것은 그쪽이고, 그 사실은 원장 §2 그대로다.

## `tla2tools.jar` — 실측 (2026-09-11)

**핀 값은 여기 없다.** 해시·build·rev 는 `../Dockerfile` 의 `ARG TLA_*` 넷과
`../devcontainer.json` — 선언처 **둘** — 에만 있고, 이 문서에 옮겨 적으면
lint 정의역 밖의 셋째 사본이 되어 재핀 즉시 조용히 낡는다(2026-09-11 에
실제로 그렇게 적혀 있었고 확증 결함으로 지워졌다). 크기도 같은 이유로 적지
않는다 — `make rtl-pins` 의 OK 줄이 보관본의 크기와 b2 앞 12 를 매번 인쇄한다.

| | |
|---|---|
| 출처 | `github.com/tlaplus/tlaplus/releases/download/v1.8.0/tla2tools.jar` (롤링 pre-release; `v1.8.0` 은 버전이 아니라 이름이다) |
| 핀 | `../Dockerfile` `ARG TLA_VERSION` · `TLA_BLAKE2B512` · `TLA_TLC_BUILD` · `TLA_TLC_REV` (= `../devcontainer.json` `build.args` 의 같은 넷) |
| MANIFEST | `Implementation-Title: TLA+ Tools` · `Implementation-Vendor: Microsoft Corp.` · `Main-class: tlc2.TLC` · `Class-Path: CommunityModules-deps.jar CommunityModules.jar` (참조만; **번들돼 있지 않다**). `X-Git-Revision` · `Build-TimeStamp` 도 있으나 핀과 같은 값이라 여기 옮기지 않는다 |
| 엔트리 | 2,224 (`unzip -Z1 \| wc -l`; 디렉터리 포함) · 그중 파일 2,094 (`grep -vc '/$'`) |

## 번들 구성 — jar 를 열어 센 것

이것은 **fat jar** 다. 2026-08-29 실측이 그 증거였다 — Maven 얇은 jar 는
gson·javax.mail 부재로 374 run 전량 `NoClassDefFoundError`. 재배포하면 번들된
것들의 라이선스 의무가 따라온다. 그래서 무엇이 들어 있는지를 **추정이 아니라
실측**으로 적는다. 출처·버전은 상류 빌드 정의
`tlatools/org.lamport.tlatools/lib/vendored-jars.json` @`c3af5e2` 로 확정했다
(jar 자체는 shading 으로 `META-INF/maven/**` 를 지워 버전이 안 보인다).

| 패키지 접두 | 엔트리 | 정체 (상류 `vendored-jars.json` @`c3af5e2`) | 라이선스 | 본문 (`licenses/`) | 본문 출처 |
|---|---|---|---|---|---|
| `tlc2/` `tla2sany/` `pcal/` `tla2tex/` `util/` `formatter/` `model/` | 588+171+92+34+52+102+4 | TLA+ Tools 자체 (`tlatools/org.lamport.tlatools/src/`) | **MIT** | `tla2tools-LICENSE.txt` · `tla2tools-License-in-jar.txt` | 상류 저장소 `LICENSE` @`c3af5e2` (HP · Microsoft · Linux Foundation) · jar 안 `License.txt` (Microsoft Research 2019) — 둘 다 MIT, 저작권 줄만 다르다 |
| `org/jline/` | 348 | jline-{builtins,console,reader,terminal} **3.25.0** | **BSD-3-Clause** | `jline-3.25.0-LICENSE.txt` | jar 안 `jline-LICENSE.txt` |
| `org/eclipse/lsp4j/` | 260 | org.eclipse.lsp4j.{debug,jsonrpc,jsonrpc.debug} **0.21.1** | **EPL-2.0 OR BSD-3-Clause** (EDL-1.0) | `lsp4j-0.21.1-LICENSE.txt` · `lsp4j-0.21.1-NOTICE.txt` | jar 에 **없음** → `github.com/eclipse-lsp4j/lsp4j` 태그 `v0.21.1` 의 `LICENSE` · `NOTICE` |
| `com/google/gson/` (+ `META-INF/proguard/gson.pro` · `META-INF/versions/9/module-info.class`) | 231 | gson **2.14.0** | **Apache-2.0** | `gson-2.14.0-LICENSE.txt` | jar 에 **없음** → 상류 `lib/gson/gson-LICENSE` @`c3af5e2` |
| `javax/mail/` `com/sun/mail/` (+ `META-INF/mailcap` · 루트 `module-info.class` — `strings` 로 `com.sun.mail.smtp` / `1.6.8` / `SMTPProvider` 확인, 즉 `smtp-1.6.8.jar` 의 모듈 서술자가 루트에 남은 것) | 120+89 | com.sun.mail:{mailapi,smtp} **1.6.8** (Jakarta Mail 계보) | **EPL-2.0 OR GPL-2.0 WITH Classpath-exception-2.0** | `javamail-1.6.8-LICENSE.md` · `javamail-1.6.8-NOTICE.md` | jar 안 `META-INF/LICENSE.md` — `mailapi-1.6.8.jar` 의 것과 **바이트 동일**(b2 `6fe10aa7…`)임을 대조해 귀속. NOTICE 는 shading 이 지웠으므로 `mailapi-1.6.8.jar` 에서 복원 |
| `javax/activation/` | 22 | javax.activation **1.1** (Eclipse Orbit 재포장 `javax.activation_1.1.0.v201211130549`; 실체는 **Apache Geronimo** Activation 1.1) | **Apache-2.0** | `javax.activation-1.1-LICENSE.txt` · `javax.activation-1.1-NOTICE.txt` | jar 에 **없음** → 상류 `lib/javax.mail/javax.activation_1.1.0.v201211130549.jar` 안 `META-INF/LICENSE.txt` · `NOTICE.txt` (`about.html`: 「Your use of the Activation Framework code is subject to the terms and conditions of the Apache License Version 2.0」) |
| `com/opencastsoftware/prettier4j/` | 52 | prettier4j **0.3.2** | **Apache-2.0** | `prettier4j-0.3.2-LICENSE.txt` | jar 에 **없음** → `github.com/opencastsoftware/prettier4j` 태그 `v0.3.2` 의 `LICENSE` (저작권 줄이 템플릿 `[yyyy] [name of copyright owner]` 그대로다 — 상류가 그렇게 배포한다) |
| `org/apache/commons/math3/` | 18 (클래스 11 + 패키지 안 라이선스 사본 2 + 디렉터리 5) | commons-math3 **3.2** 의 일부(exception · primes · util)를 상류가 **소스로 복사**해 둔 것 (`src/org/apache/commons/math3/`) | **Apache-2.0** | `commons-math3-3.2-LICENSE.txt` · `commons-math3-3.2-NOTICE.txt` | jar 안 `CommonsMath-LICENSE.txt` · `CommonsMath-NOTICE.txt` |
| `org/eclipse/xtext/xbase/lib/` | 6 (클래스 2: `Pure` · `util/ToStringBuilder`) | 상류 소스 트리의 **스텁** (`src/org/eclipse/xtext/…`, 빈 구현) — 패키지 이름만 Xtext 의 것 | ⚠️ **미확정** — 소스에 라이선스 머리말이 없다. 상류 트리 안이므로 상류 MIT 로 읽는 것이 자연스러우나 Xtext(EPL-2.0) API 의 이름을 빌린 것이라 그렇게 **단정하지 않는다** | — | — |

**못 찾은 것 / 재지 않은 것 (정직 기록):**

- `org/eclipse/xtext` 둘의 라이선스 — 위 표대로 미확정. 2 클래스, 빈 구현.
- `smtp-1.6.8.jar` 의 `META-INF/javamail.providers` · `services/javax.mail.Provider`
  는 fat jar 에 **없다** (`javamail.default.address.map` 0 B 만 남았다). 즉 SMTP
  프로바이더 등록은 shading 에서 떨어졌다 — TLC 의 메일 기능이 실제로 도는지는
  이 저장소가 쓰지 않으므로 **재지 않았다.**
- `META-INF/javamail.default.address.map` 은 fat jar 에 **0 B** 로 있다. `mailapi` ·
  `smtp` 어느 쪽 jar 에도 그 이름이 없어 출처를 **정하지 못했다** (상류 빌드가
  만든 것으로 보이나 재지 않았다).
- `CommunityModules.jar` — MANIFEST `Class-Path` 가 가리키지만 번들되지 않았고
  이 저장소는 쓰지 않는다. 라이선스는 조사하지 않았다.
- 위 표의 「엔트리」는 각 행의 **첫 접두 그대로** `unzip -Z1 tla2tools.jar |
  grep -c '^<접두>'` 한 값이다(디렉터리 엔트리 포함; 접두 자체의 디렉터리
  엔트리도 든다). 2026-09-11 첫 판은 셋을 상위 디렉터리 접두로 세어 놓고
  (`^com/opencastsoftware/` 53 · `^org/apache/commons/` 19 · `^com/sun/` 90)
  「`awk -F/ '{print $1}' | sort | uniq -c` 를 그대로 옮겼다」고 적었는데, 그
  명령은 최상위 조각별 합(`org` 636 · `com` 375 · `javax` 143 …)만 내고
  패키지별 수치를 낼 수 없다 — 확증 결함으로 고쳤다.
  총합 2,224 와의 대조는 그 최상위 합으로 한다: `org` 636 = jline 348 + lsp4j
  260 + math3 18 + xtext 6 + 상위 디렉터리 엔트리 4(`org/` `org/eclipse/` `org/apache/`
  `org/apache/commons/`); `com` 375 = gson 231 + sun/mail 89 + prettier4j 52 +
  상위 디렉터리 엔트리 3(`com/` `com/sun/` `com/opencastsoftware/`); `javax` 143 = mail
  120 + activation 22 + `javax/` 1; 나머지 `tlc2` 588 · `tla2sany` 171 ·
  `formatter` 102 · `pcal` 92 · `util` 52 · `tla2tex` 34 · `META-INF` 22 ·
  `model` 4 · 최상위 파일 5 (`License.txt` · `jline-LICENSE.txt` ·
  `CommonsMath-LICENSE.txt` · `CommonsMath-NOTICE.txt` · `module-info.class`
  — 마지막 것은 위 javamail 행에 귀속). 합 2,224.

## `licenses/` 색인 (BLAKE2b-512 앞 16)

```
92c1a9ad7485b46b commons-math3-3.2-LICENSE.txt     ← jar
1835fbdd3aa0d236 commons-math3-3.2-NOTICE.txt      ← jar
1bbdb8ea81b42a8c gson-2.14.0-LICENSE.txt           ← 상류 lib/gson/gson-LICENSE
6fe10aa7757c6f3b javamail-1.6.8-LICENSE.md         ← jar META-INF/LICENSE.md
ac1e2a687e9c17b7 javamail-1.6.8-NOTICE.md          ← 상류 lib/javax.mail/mailapi-1.6.8.jar
1bbdb8ea81b42a8c javax.activation-1.1-LICENSE.txt  ← 상류 lib/javax.mail/javax.activation_1.1.0….jar (gson 것과 같은 Apache-2.0 원문)
4ffb8177f27b958a javax.activation-1.1-NOTICE.txt   ← 같은 jar
c74f9932d8eed6c5 jline-3.25.0-LICENSE.txt          ← jar
3b4eff2c18ca0c47 lsp4j-0.21.1-LICENSE.txt          ← eclipse-lsp4j/lsp4j @v0.21.1
fb6662370044200d lsp4j-0.21.1-NOTICE.txt           ← 같은 태그
43452dd4216bba83 prettier4j-0.3.2-LICENSE.txt      ← opencastsoftware/prettier4j @v0.3.2
29108927f6fbed41 tla2tools-LICENSE.txt             ← tlaplus/tlaplus LICENSE @c3af5e2
e903bb3161a5c9e4 tla2tools-License-in-jar.txt      ← jar License.txt
```

이 파일들은 **이 저장소의 라이선스가 아니다.** 저장소 자체의 라이선스는
루트 `LICENSE.md` 이고, 그 §7 이 이 디렉터리를 가리킨다. 여기 것은 보관본을
재배포하는 데 따르는 남의 의무를 그대로 옮겨 둔 것이다.
