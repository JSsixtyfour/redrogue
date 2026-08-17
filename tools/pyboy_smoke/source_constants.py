from __future__ import annotations

from pathlib import Path
import re


CONST_RE = re.compile(r"^const\s+([A-Za-z0-9_]+)(?:\s*,.*)?$")


def _integer_expression(expression: str) -> int:
    converted = re.sub(r"\$([0-9a-fA-F]+)", r"0x\1", expression.strip())
    if not re.fullmatch(r"[0-9a-fA-FxX()+\-\s]+", converted):
        raise ValueError(f"Unsupported integer expression: {expression!r}")
    return int(eval(converted, {"__builtins__": {}}, {}))


def parse_rgbds_constants(path: Path) -> dict[str, int]:
    """Resolve the const/const_next/const_skip subset used by event_constants.asm."""
    current = 0
    constants: dict[str, int] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.split(";", 1)[0].strip()
        if not line:
            continue
        if line.startswith("const_def"):
            expression = line[len("const_def") :].strip()
            current = _integer_expression(expression) if expression else 0
            continue
        if line.startswith("const_next"):
            current = _integer_expression(line[len("const_next") :])
            continue
        if line.startswith("const_skip"):
            expression = line[len("const_skip") :].strip()
            current += _integer_expression(expression) if expression else 1
            continue
        match = CONST_RE.match(line)
        if match:
            constants[match.group(1)] = current
            current += 1
    return constants
