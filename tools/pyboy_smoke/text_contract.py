from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import re


SEGMENT_RE = re.compile(r'^\s*(text|line|cont)\s+"([^"]*)"')
LABEL_RE = re.compile(r"^([A-Za-z0-9_\.]+)::?$")


def text_blocks(path: Path) -> dict[str, list[str]]:
    blocks: dict[str, list[str]] = {}
    current_label: str | None = None
    for line in path.read_text(encoding="utf-8").splitlines():
        label = LABEL_RE.match(line.strip())
        if label:
            current_label = label.group(1)
            blocks.setdefault(current_label, [])
            continue
        segment = SEGMENT_RE.match(line)
        if segment and current_label is not None:
            blocks[current_label].append(segment.group(2))
    return blocks


def literal_width(text: str) -> int:
    """Return visible width for literal text without variable-width substitutions."""
    if "<" in text or "@" in text:
        raise ValueError(f"dynamic text needs an explicit width contract: {text!r}")
    return len(text)


def overlong_segments(path: Path, maximum: int = 17) -> list[tuple[str, str, int]]:
    failures: list[tuple[str, str, int]] = []
    for label, segments in text_blocks(path).items():
        for segment in segments:
            width = literal_width(segment)
            if width > maximum:
                failures.append((label, segment, width))
    return failures


@dataclass(frozen=True)
class EndBattleContract:
    path: Path
    label: str
    trainer_class: str


def rendered_end_battle_width(contract: EndBattleContract) -> int:
    blocks = text_blocks(contract.path)
    segments = blocks.get(contract.label)
    if not segments:
        raise AssertionError(f"No literal text found for {contract.label} in {contract.path}")
    return len(contract.trainer_class) + 2 + literal_width(segments[0])
