from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path

from source_constants import parse_rgbds_constants, parse_trainer_constants


@dataclass(frozen=True)
class ScenarioMon:
    species: int
    level: int
    moves: tuple[int, ...]

    def as_fixture(self) -> dict[str, object]:
        return {"species": self.species, "level": self.level, "moves": list(self.moves)}


@dataclass(frozen=True)
class AIScenario:
    name: str
    player: tuple[ScenarioMon, ...]
    enemy: tuple[ScenarioMon, ...]
    trainer_class: int
    ai_tier: int
    expect: dict[str, object]
    phase: str
    heuristic: str
    case: str
    tags: tuple[str, ...]
    required_cases: tuple[str, ...]


VALID_CASES = {"positive", "negative", "boundary", "regression"}


def validate_scenario_metadata(raw: dict[str, object]) -> None:
    for field in ("name", "phase", "heuristic", "case"):
        if not isinstance(raw.get(field), str) or not str(raw[field]).strip():
            raise ValueError(f"scenario {field!r} must be a non-empty string")
    if raw["case"] not in VALID_CASES:
        raise ValueError(f"scenario case {raw['case']!r} is not one of {sorted(VALID_CASES)}")
    tags = raw.get("tags", [])
    required = raw.get("required_cases", [])
    if not isinstance(tags, list) or not all(isinstance(tag, str) and tag for tag in tags):
        raise ValueError("scenario tags must be a list of non-empty strings")
    if not isinstance(required, list) or not all(case in VALID_CASES for case in required):
        raise ValueError("required_cases contains an unsupported case")


def build_coverage_report(scenarios: list[AIScenario]) -> dict[str, object]:
    groups: dict[str, dict[str, object]] = {}
    for scenario in scenarios:
        key = f"{scenario.phase}:{scenario.heuristic}"
        group = groups.setdefault(
            key,
            {"phase": scenario.phase, "heuristic": scenario.heuristic,
             "cases": set(), "required_cases": set(), "scenarios": [], "tags": set()},
        )
        group["cases"].add(scenario.case)
        group["required_cases"].update(scenario.required_cases)
        group["scenarios"].append(scenario.name)
        group["tags"].update(scenario.tags)
    output = {}
    for key, group in groups.items():
        missing = group["required_cases"] - group["cases"]
        output[key] = {
            "phase": group["phase"],
            "heuristic": group["heuristic"],
            "cases": sorted(group["cases"]),
            "required_cases": sorted(group["required_cases"]),
            "missing_cases": sorted(missing),
            "scenarios": sorted(group["scenarios"]),
            "tags": sorted(group["tags"]),
        }
    return {"heuristics": output, "scenario_count": len(scenarios)}


def validate_scenario_coverage(scenarios: list[AIScenario]) -> dict[str, object]:
    report = build_coverage_report(scenarios)
    missing = {
        key: value["missing_cases"]
        for key, value in report["heuristics"].items()
        if value["missing_cases"]
    }
    if missing:
        raise ValueError(f"scenario coverage requirements are incomplete: {missing}")
    return report


def load_scenarios(path: Path, repo_root: Path) -> list[AIScenario]:
    """Load named ASM constants into compact SRAM-ready scenario fixtures."""
    species = parse_rgbds_constants(repo_root / "constants" / "pokemon_constants.asm")
    moves = parse_rgbds_constants(repo_root / "constants" / "move_constants.asm")
    trainers = parse_trainer_constants(repo_root / "constants" / "trainer_constants.asm")
    document = json.loads(path.read_text(encoding="utf-8"))

    def mon(raw: dict[str, object]) -> ScenarioMon:
        return ScenarioMon(
            species=species[str(raw["species"])],
            level=int(raw["level"]),
            moves=tuple(moves[str(move)] for move in raw["moves"]),
        )

    scenarios = []
    names = set()
    for raw in document["scenarios"]:
        validate_scenario_metadata(raw)
        if raw["name"] in names:
            raise ValueError(f"duplicate scenario name: {raw['name']}")
        names.add(raw["name"])
        scenarios.append(
            AIScenario(
                name=str(raw["name"]),
                player=tuple(mon(value) for value in raw["player"]),
                enemy=tuple(mon(value) for value in raw["enemy"]),
                trainer_class=trainers[str(raw["trainer_class"])],
                ai_tier=int(raw["ai_tier"]),
                expect=dict(raw.get("expect", {})),
                phase=str(raw["phase"]),
                heuristic=str(raw["heuristic"]),
                case=str(raw["case"]),
                tags=tuple(str(value) for value in raw.get("tags", [])),
                required_cases=tuple(str(value) for value in raw.get("required_cases", [])),
            )
        )
    validate_scenario_coverage(scenarios)
    return scenarios
