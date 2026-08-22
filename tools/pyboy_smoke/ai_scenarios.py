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
    for raw in document["scenarios"]:
        scenarios.append(
            AIScenario(
                name=str(raw["name"]),
                player=tuple(mon(value) for value in raw["player"]),
                enemy=tuple(mon(value) for value in raw["enemy"]),
                trainer_class=trainers[str(raw["trainer_class"])],
                ai_tier=int(raw["ai_tier"]),
                expect=dict(raw.get("expect", {})),
            )
        )
    return scenarios
