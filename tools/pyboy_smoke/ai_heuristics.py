"""Source-derived inventory of the trainer AI's heuristics (AI_BACKLOG L3).

The coverage manifest (ai_heuristic_manifest.json) must not be the only record
of what exists, or a heuristic left out of it would vanish from both the tests
and the coverage claims. So the inventory is parsed from the dispatch tables
that decide what can run:

- layer:        AIScoringPointers (trainer_ai.asm), one per scoring layer;
- smart:        AISmartEffectTable handlers (ai_smart.asm);
- redundant:    AIRedundantEffectTable handlers (ai_redundant.asm);
- plan:         AIPlanTable fitness/run pairs (ai_plans.asm);
- personality:  AISoftPersonalityPointers (trainer_ai.asm, Codex's track);
- item:         every `jp AIUse*` in trainer_ai.asm's class item routines;
- decision:     a curated list of switch, threat, fair-play, history and cache
                predicates that no table enumerates. Each must still exist as a
                label, so a rename or deletion fails the guard test.

Each entry also names the labels whose execution counts as reaching it (the
REDROGUE_AI_COVERAGE harness mode hooks them).
"""
from __future__ import annotations

from pathlib import Path
import re

DECISIONS = {
    # Switching (ai_switching.asm / ai_threat.asm)
    "AIShouldSwitch": "the switch decision and its triggers",
    "AISelectSendOut": "send-out ranking after a faint",
    "AIBestReserveSurvivesThreat": "B4 switch-in survival gate",
    "AISacrificeBeatsSwitch": "B5 sacrifice instead of a costly switch",
    "AIEnemyHasReliableFirstKO": "winning-action veto (switch) and B6 item veto",
    # Threat model
    "AIPlayerWouldKO": "one-decision KO answer (THREAT, RISKY, plans)",
    "AIHealWouldStillDie": "heal-move futility",
    "AIItemHealWouldStillDie": "heal-item futility (Checkpoint D)",
    # Fair play and history
    "AIGetPlayerMoveN": "believed player moveset (revealed + visible-type guess)",
    "AITrackSeenPlayerMove": "reveal tracking per party slot",
    "AITrackLastMove": "fresh-mon history reset at decision entry",
    "AITrackExecutedEnemyMove": "L1: history records the executed move",
    # Caches (FOLLOWUPS #48)
    "AIEstimateEnemyDamage": "one-decision enemy estimate cache",
    "AIRevalidateDecisionCaches": "player-first cache reuse",
}


def _table_entries(text: str, table: str, pattern: str) -> list[str]:
    lines = text.splitlines()
    start = next(i for i, line in enumerate(lines) if line.startswith(f"{table}:"))
    found = []
    for line in lines[start + 1:]:
        code = line.split(";", 1)[0].strip()
        if re.match(r"^[A-Za-z_]\w*:", code) or code.startswith("assert") or code == "db -1":
            break
        match = re.match(pattern, code)
        if match:
            found.append(match.group(1))
    return found


def _label_index(root: Path) -> dict[str, str]:
    """Every top-level label under engine/ -> "file:line", in one pass."""
    index: dict[str, str] = {}
    for path in sorted((root / "engine").rglob("*.asm")):
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            match = re.match(r"^([A-Za-z_]\w*)::?(\s|;|$)", line)
            if match:
                index.setdefault(match.group(1), f"{path.relative_to(root).as_posix()}:{number}")
    return index


def inventory(root: Path, with_source: bool = True) -> dict[str, dict[str, object]]:
    """with_source=False skips locating each label (a scan of every engine
    file), which is all the coverage hooks need."""
    ai = root / "engine/battle/ai"
    trainer_ai = (root / "engine/battle/trainer_ai.asm").read_text(encoding="utf-8")
    entries: dict[str, dict[str, object]] = {}
    index = _label_index(root) if with_source else {}

    def add(key: str, family: str, labels: list[str]) -> None:
        if key not in entries:
            entries[key] = {"family": family, "labels": labels}
            if with_source:
                if labels[0] not in index:
                    raise KeyError(f"label {labels[0]} not found under engine/")
                entries[key]["source"] = index[labels[0]]

    for label in _table_entries(trainer_ai, "AIScoringPointers", r"dw\s+(\w+)"):
        add(label, "layer", [label])
    smart = (ai / "ai_smart.asm").read_text(encoding="utf-8")
    for label in _table_entries(smart, "AISmartEffectTable", r"dbw\s+\w+,\s*(\w+)"):
        add(label, "smart", [label])
    redundant = (ai / "ai_redundant.asm").read_text(encoding="utf-8")
    for label in _table_entries(redundant, "AIRedundantEffectTable", r"dbw\s+\w+,\s*(\w+)"):
        add(label, "redundant", [label])
    plans = (ai / "ai_plans.asm").read_text(encoding="utf-8")
    for fit in _table_entries(plans, "AIPlanTable", r"ai_plan\s+[^,]+,\s*(\w+),\s*\w+"):
        name = fit.removeprefix("AIFit_")
        add(f"Plan_{name}", "plan", [fit, f"AIRun_{name}"])
    for label in _table_entries(trainer_ai, "AISoftPersonalityPointers", r"dw\s+(\w+)"):
        add(label, "personality", [label])
    for label in sorted(set(re.findall(r"^\s*jp\s+(?:c,\s*)?(AIUse\w+)", trainer_ai, re.M))):
        add(label, "item", [label])
    for label in DECISIONS:
        add(label, "decision", [label])
    return entries


_COVERAGE_LABELS: dict[Path, list[str]] = {}


def coverage_labels(root: Path) -> list[str]:
    if root not in _COVERAGE_LABELS:
        _COVERAGE_LABELS[root] = sorted({label for entry in inventory(root, False).values()
                                         for label in entry["labels"]})
    return _COVERAGE_LABELS[root]
