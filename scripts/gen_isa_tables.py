#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""v1.8.0a §23.9 COMMIT 1 — single-source ISA table generator.

Reads isa/wt64v1_isa.json (the ONE machine-readable ISA source, spec
§23.6/§23.8(3)) and emits five artifacts, all COMMITTED to git:

  include/generated/isa_eh_codes.vh          EH_* localparams (EHDecode.v)
  include/generated/isa_ehshape_case_body.vh legality case body (EHDecode.v)
  include/generated/isa_opcode_wires.vh      is_alu_binary + opcode_supported
  asm/generated_isa_tables.py                assembler + golden-model tables
  .claude-memos/generated/isa_tables_frag.md spec opcode/legality tables

Modes:
  generate   (re)write all five artifacts in place
  --check    regenerate to a temp dir and byte-diff against the committed
             files; exit 0 if identical, exit 1 with unified diffs otherwise
             (same exit-code contract as scripts/lint_frag_total_m1_held.py)

Determinism contract (pinned by test_generation_deterministic): sorted
iteration everywhere, fixed hex formatting, no timestamps. The only
run-varying content is nothing — the sha256 of the SOURCE is embedded so a
reader can verify which source produced an artifact.

Strict validation (pinned by test_json_schema_strictness): unknown keys
rejected, opcode/mnemonic uniqueness enforced, fp_block cross-consistency
(every 0x70-block opcode entry needs an fp_block.ops row and vice versa),
non-reserved fp ops must have at least one legal mode combination.

stdlib only — json is deliberate (not YAML): PyYAML would be this repo's
first third-party non-cocotb dependency (spec §23.6 recorded substitution).
"""

import argparse
import difflib
import hashlib
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SOURCE = REPO / "isa" / "wt64v1_isa.json"

ARTIFACTS = {
    "eh_codes":  REPO / "include" / "generated" / "isa_eh_codes.vh",
    "case_body": REPO / "include" / "generated" / "isa_ehshape_case_body.vh",
    "wires":     REPO / "include" / "generated" / "isa_opcode_wires.vh",
    "pytables":  REPO / "asm" / "generated_isa_tables.py",
    "specfrag":  REPO / ".claude-memos" / "generated" / "isa_tables_frag.md",
}

SPDX_VH = (
    "// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0\n"
    "// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors\n"
)
SPDX_PY = (
    "# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0\n"
    "# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors\n"
)
SPDX_MD = (
    "<!-- SPDX-License-Identifier: CC-BY-4.0 -->\n"
    "<!-- SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors -->\n"
)


class SchemaError(Exception):
    pass


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

_TOP_KEYS = {"_doc", "_schema_version", "eh_codes", "eh_name_to_code",
             "flag_bits", "all_data_ehs", "hl_only_mnemonics",
             "reduce_op_codes", "opcodes", "fp_block", "einsum_signatures",
             "eh_body_layouts", "dim_literals"}
_OPCODE_KEYS = {"mnemonic", "code", "desc", "notes", "asm_legality",
                "rtl_legality", "rtl_alu_binary", "stub_v18"}
_ASM_LEG_KEYS = {"required", "forbidden", "allow_imm_xor_opref",
                 "require_opb_flag", "require_imm16", "require_precision_eh"}
_RTL_LEG_KEYS = {"req_port", "req_mem", "req_subscript", "req_opref",
                 "req_imm16", "forbid_subscript", "forbid_mem",
                 "forbid_imm_any", "forbid_opref"}
_FP_BLOCK_KEYS = {"_doc", "mode_byte_fields", "dtype_codes", "ops"}
_FP_OP_KEYS = {"code", "mnemonic", "legal_dtypes", "legal_acc", "legal_rnd"}
_EH_NAMES = {"port", "imm16", "imm32", "imm64", "mem", "subscript",
             "opref", "precision", "nop_pad"}


def _reject_unknown(d, allowed, where):
    unknown = set(d) - allowed
    if unknown:
        raise SchemaError(f"{where}: unknown key(s) {sorted(unknown)}")


def validate(src):
    _reject_unknown(src, _TOP_KEYS, "top level")
    if src.get("_schema_version") != 1:
        raise SchemaError("unsupported _schema_version")

    seen_codes, seen_mnems = set(), set()
    for op in src["opcodes"]:
        where = f"opcode {op.get('mnemonic', '?')}"
        _reject_unknown(op, _OPCODE_KEYS, where)
        code = op["code"]
        if not isinstance(code, int) or not (0 <= code <= 0xFF):
            raise SchemaError(f"{where}: bad code {code!r}")
        if code in seen_codes:
            raise SchemaError(f"{where}: duplicate code 0x{code:02X}")
        if op["mnemonic"] in seen_mnems:
            raise SchemaError(f"{where}: duplicate mnemonic")
        seen_codes.add(code)
        seen_mnems.add(op["mnemonic"])
        _reject_unknown(op["asm_legality"], _ASM_LEG_KEYS, f"{where}.asm_legality")
        _reject_unknown(op["rtl_legality"], _RTL_LEG_KEYS, f"{where}.rtl_legality")
        for k in ("required", "forbidden"):
            bad = set(op["asm_legality"][k]) - _EH_NAMES
            if bad:
                raise SchemaError(f"{where}.asm_legality.{k}: unknown EH {sorted(bad)}")

    fp = src["fp_block"]
    _reject_unknown(fp, _FP_BLOCK_KEYS, "fp_block")
    fp_op_codes = set()
    for fop in fp["ops"]:
        where = f"fp_block op {fop.get('mnemonic', '?')}"
        _reject_unknown(fop, _FP_OP_KEYS, where)
        fp_op_codes.add(fop["code"])
        if not (fop["legal_dtypes"] and fop["legal_acc"] and fop["legal_rnd"]):
            raise SchemaError(f"{where}: no legal mode combination (all-illegal fp op)")
    block_opcodes = {op["code"] for op in src["opcodes"] if 0x70 <= op["code"] <= 0x7F}
    if block_opcodes != fp_op_codes:
        raise SchemaError(
            f"fp_block cross-consistency: opcodes[] 0x70-block {sorted(hex(c) for c in block_opcodes)} "
            f"!= fp_block.ops {sorted(hex(c) for c in fp_op_codes)}")


# ---------------------------------------------------------------------------
# Emitters
# ---------------------------------------------------------------------------

def _hdr_vh(src_sha):
    return (SPDX_VH +
            f"// GENERATED by scripts/gen_isa_tables.py from isa/wt64v1_isa.json\n"
            f"// sha256={src_sha} — DO NOT EDIT (edit the JSON, regenerate, commit both)\n")


def emit_eh_codes(src, src_sha):
    lines = [_hdr_vh(src_sha)]
    for name, code in src["eh_codes"].items():
        lines.append(f"    localparam [3:0] EH_{name:<10} = 4'h{code:X};")
    return "\n".join(lines) + "\n"


def emit_case_body(src, src_sha):
    lines = [_hdr_vh(src_sha)]
    lines.append("// One case arm per opcode (no comma grouping — deterministic emission).")
    for op in sorted(src["opcodes"], key=lambda o: o["code"]):
        r = op["rtl_legality"]
        lines.append(f"            8'h{op['code']:02X}: begin  // {op['desc']}")
        if op["notes"]:
            for note_line in _wrap(op["notes"], 66):
                lines.append(f"                // {note_line}")
        assigns = []
        for flag in ("req_port", "req_mem", "req_subscript", "req_opref", "req_imm16",
                     "forbid_subscript", "forbid_mem", "forbid_imm_any", "forbid_opref"):
            if r[flag]:
                assigns.append(f"                {flag:<16} = 1'b1;")
        lines.extend(assigns if assigns else ["                ;"])
        lines.append("            end")
    lines.append("            default: begin")
    lines.append("                forbid_subscript = 1'b1; forbid_mem = 1'b1;")
    lines.append("                forbid_imm_any   = 1'b1; forbid_opref = 1'b1;")
    lines.append("            end")
    return "\n".join(lines) + "\n"


def emit_wires(src, src_sha):
    alu = [op["code"] for op in sorted(src["opcodes"], key=lambda o: o["code"])
           if op["rtl_alu_binary"]]
    supported = [op["code"] for op in sorted(src["opcodes"], key=lambda o: o["code"])]
    lines = [_hdr_vh(src_sha)]
    lines.append("    // ALU-binary membership: exactly-one-of {IMM*, OPREF} enforced")
    lines.append("    // (alu_binary_xor_err). NOTE: 0x63/64/65 are asm-side XOR-checked")
    lines.append("    // but deliberately NOT RTL-checked — documented asymmetry, see")
    lines.append("    // isa/wt64v1_isa.json notes and spec §23.9.")
    lines.append("    wire is_alu_binary =")
    lines.append("        " + " ||\n        ".join(
        f"(cb_opcode == 8'h{c:02X})" for c in alu) + ";")
    lines.append("")
    lines.append("    wire opcode_supported =")
    lines.append("        " + " ||\n        ".join(
        f"(cb_opcode == 8'h{c:02X})" for c in supported) + ";")
    lines.append("")
    lines.append("    // v1.8.0a COMMIT 2 — FP-block mode-byte legality ROM (spec §23.6a).")
    lines.append("    // Index = {cb_opcode[3:0], dtype[3:0], acc[1:0], rnd[1:0]} (12 bits).")
    lines.append("    // Unlisted (op, dtype, acc, rnd) combinations are ILLEGAL")
    lines.append("    // (restrictive-first; loosening later is non-breaking).")
    rom = 0
    for fop in src["fp_block"]["ops"]:
        for dt in fop["legal_dtypes"]:
            for ac in fop["legal_acc"]:
                for rn in fop["legal_rnd"]:
                    idx = ((fop["code"] & 0xF) << 8) | (dt << 4) | (ac << 2) | rn
                    rom |= 1 << idx
    lines.append(f"    localparam [4095:0] FP_LEGAL_ROM = 4096'h{rom:01024X};")
    lines.append("    wire in_fp_block = (cb_opcode[7:4] == 4'h7);")
    return "\n".join(lines) + "\n"


def _set_literal(items):
    """Deterministic set literal — repr(set) iterates in hash order, which
    varies per process (PYTHONHASHSEED) and would break the freshness
    byte-diff. Caught by test_generation_deterministic on first run."""
    items = sorted(items)
    if not items:
        return "set()"
    return "{" + ", ".join(repr(x) for x in items) + "}"


def emit_pytables(src, src_sha):
    L = [SPDX_PY,
         '"""GENERATED by scripts/gen_isa_tables.py from isa/wt64v1_isa.json',
         f'sha256={src_sha} -- DO NOT EDIT (edit the JSON, regenerate, commit both).',
         '"""', ""]
    L.append("MNEMONIC_TO_OPCODE = {")
    for op in sorted(src["opcodes"], key=lambda o: o["code"]):
        L.append(f"    {op['mnemonic']!r}: 0x{op['code']:02X},")
    L.append("}")
    L.append("")
    L.append("OPCODE_TO_MNEMONIC = {v: k for k, v in MNEMONIC_TO_OPCODE.items()}")
    L.append("")
    L.append("HL_ONLY_MNEMONICS = " + _set_literal(src["hl_only_mnemonics"]))
    L.append("")
    L.append("FLAG_BITS = {")
    for name, bit in src["flag_bits"].items():
        L.append(f"    {name!r}: {bit},")
    L.append("}")
    L.append("")
    for name, code in src["eh_codes"].items():
        L.append(f"EH_{name} = 0x{code:X}")
    L.append("")
    L.append("EH_NAME_TO_CODE = {")
    for name, code in src["eh_name_to_code"].items():
        L.append(f"    {name!r}: 0x{code:X},")
    L.append("}")
    L.append("")
    L.append("REDUCE_OP_CODE = {")
    for name, code in src["reduce_op_codes"].items():
        L.append(f"    {name!r}: {code},")
    L.append("}")
    L.append("")
    L.append("ALL_DATA_EHS = " + _set_literal(src["all_data_ehs"]))
    L.append("")
    L.append("# int keys, mutable-set values — exact schema of the historical")
    L.append("# hand-written _LEGAL so pin tests pass unchanged. Carries the")
    L.append("# DECLARED required set (incl. the unenforced 'port' under")
    L.append("# allow_imm_xor_opref — documented asymmetry, see JSON _doc).")
    L.append("LEGAL = {")
    for op in sorted(src["opcodes"], key=lambda o: o["code"]):
        a = op["asm_legality"]
        L.append(f"    0x{op['code']:02X}: dict(")
        L.append(f"        required={_set_literal(a['required'])},")
        L.append(f"        forbidden={_set_literal(a['forbidden'])},")
        L.append(f"        allow_imm_xor_opref={a['allow_imm_xor_opref']!r},")
        L.append(f"        require_opb_flag={a['require_opb_flag']!r},")
        L.append(f"        require_imm16={a['require_imm16']!r},")
        L.append(f"        require_precision_eh={a.get('require_precision_eh', False)!r},")
        L.append("    ),")
    L.append("}")
    L.append("")
    stubs = sorted(op["code"] for op in src["opcodes"] if op.get("stub_v18"))
    L.append("STUB_OPS_V18 = frozenset([" +
             ", ".join(f"0x{c:02X}" for c in stubs) + "])")
    L.append("")
    L.append("FP_MODE_LEGAL = {")
    for fop in sorted(src["fp_block"]["ops"], key=lambda o: o["code"]):
        L.append(f"    0x{fop['code']:02X}: dict(")
        L.append(f"        legal_dtypes={sorted(fop['legal_dtypes'])!r},")
        L.append(f"        legal_acc={sorted(fop['legal_acc'])!r},")
        L.append(f"        legal_rnd={sorted(fop['legal_rnd'])!r},")
        L.append("    ),")
    L.append("}")
    L.append("")
    return "\n".join(L)


def emit_specfrag(src, src_sha):
    L = [SPDX_MD,
         "<!-- GENERATED by scripts/gen_isa_tables.py from isa/wt64v1_isa.json -->",
         f"<!-- sha256={src_sha} — DO NOT EDIT -->", "",
         "# WT64v1 opcode / legality tables (generated)", "",
         "| Op | Mnemonic | asm required | asm forbidden | XOR | opb | imm16 | RTL shape | 설명 |",
         "|---|---|---|---|---|---|---|---|---|"]
    for op in sorted(src["opcodes"], key=lambda o: o["code"]):
        a, r = op["asm_legality"], op["rtl_legality"]
        req = ",".join(a["required"]) or "—"
        forb = ",".join(a["forbidden"]) or "—"
        rtl_bits = "+".join(
            [k[4:] for k in ("req_port", "req_mem", "req_subscript", "req_opref", "req_imm16") if r[k]] +
            [f"!{k[7:]}" for k in ("forbid_subscript", "forbid_mem", "forbid_imm_any", "forbid_opref") if r[k]]
        ) or "—"
        L.append(f"| 0x{op['code']:02X} | {op['mnemonic']} | {req} | {forb} | "
                 f"{'✓' if a['allow_imm_xor_opref'] else ''} | "
                 f"{'✓' if a['require_opb_flag'] else ''} | "
                 f"{'✓' if a['require_imm16'] else ''} | {rtl_bits} | {op['desc']} |")
    if src["fp_block"]["ops"]:
        L.append("")
        L.append("## 0x70-0x7F mode-byte legality (fp block)")
        L.append("")
        L.append("| Op | Mnemonic | legal dtype | legal acc | legal rnd |")
        L.append("|---|---|---|---|---|")
        for fop in sorted(src["fp_block"]["ops"], key=lambda o: o["code"]):
            L.append(f"| 0x{fop['code']:02X} | {fop['mnemonic']} | "
                     f"{fop['legal_dtypes']} | {fop['legal_acc']} | {fop['legal_rnd']} |")
    return "\n".join(L) + "\n"


def _wrap(text, width):
    words, lines, cur = text.split(), [], ""
    for w in words:
        if cur and len(cur) + 1 + len(w) > width:
            lines.append(cur)
            cur = w
        else:
            cur = f"{cur} {w}" if cur else w
    if cur:
        lines.append(cur)
    return lines


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------

def render_all():
    raw = SOURCE.read_bytes()
    src = json.loads(raw.decode())
    validate(src)
    sha = hashlib.sha256(raw).hexdigest()
    return {
        "eh_codes":  emit_eh_codes(src, sha),
        "case_body": emit_case_body(src, sha),
        "wires":     emit_wires(src, sha),
        "pytables":  emit_pytables(src, sha),
        "specfrag":  emit_specfrag(src, sha),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", nargs="?", default="generate",
                    choices=["generate"])
    ap.add_argument("--check", action="store_true",
                    help="regenerate and byte-diff against committed artifacts")
    args = ap.parse_args()

    rendered = render_all()

    if args.check:
        stale = []
        for key, content in rendered.items():
            path = ARTIFACTS[key]
            existing = path.read_text() if path.exists() else ""
            if existing != content:
                diff = "".join(difflib.unified_diff(
                    existing.splitlines(keepends=True),
                    content.splitlines(keepends=True),
                    fromfile=str(path), tofile=f"{path} (regenerated)"))
                stale.append((path, diff))
        if stale:
            for path, diff in stale:
                print(f"STALE: {path}", file=sys.stderr)
                print(diff, file=sys.stderr)
            return 1
        print("gen_isa_tables: OK — all generated artifacts fresh.")
        return 0

    for key, content in rendered.items():
        path = ARTIFACTS[key]
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        print(f"wrote {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
