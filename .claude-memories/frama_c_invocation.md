---
name: frama-c-invocation
description: "frama-c 는 반드시 opam switch \"frama-c\" 를 통해 호출해야 함 — 시스템 PATH 의 frama-c 를 직접 호출 금지"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 09e02def-fe68-4449-8866-9db15ac81932
---

frama-c 는 opam switch "frama-c" 안에 설치되어 있음. 어떤 경우에도 시스템 PATH 의 frama-c 를 직접 호출하지 말고, 항상 다음 형식으로 호출:

```bash
opam exec --switch="frama-c" -- frama-c <frama-c CLI 인자들...>
```

예시:
- `opam exec --switch="frama-c" -- frama-c -wp -wp-prover alt-ergo mydriver.c`
- `opam exec --switch="frama-c" -- frama-c-gui`

**How to apply**: WaveTensor / wavetensor-drivers / Y4 프로젝트의 formal verification 단계에서 frama-c / WP / ACSL / E-ACSL 등을 호출할 때 반드시 이 wrapper 를 통해서만 실행. Makefile 이나 shell script 에서 frama-c 를 자동 호출하는 경우에도 동일한 wrapper 를 사용.
