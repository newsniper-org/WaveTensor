#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""v1.8.0a §23.9 — freshness lint for the single-source ISA tables.

Thin wrapper over `gen_isa_tables.py --check` (lint_* naming symmetry with
lint_frag_total_m1_held.py; same exit-code contract: 0 = fresh, 1 = stale
with unified diffs on stderr). Run manually or via `make lint`.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gen_isa_tables  # noqa: E402

if __name__ == "__main__":
    sys.argv = [sys.argv[0], "--check"]
    sys.exit(gen_isa_tables.main())
