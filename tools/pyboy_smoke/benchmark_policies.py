"""Deterministic player policies for run_ai_benchmark.py (AI_BACKLOG L3).

The benchmark used to drive the player with only `first_slot` and `best_power`
(highest base power). A CPU that beats those has not necessarily become harder
for a human (AI_NEXT_STAGE_PROPOSAL_CODEX.md section 6), so this module adds:

- type_aware:    the move with the highest expected damage (Gen 1 formula on the
                 live stats, STAB, the ROM's own type chart, accuracy, hit count,
                 fixed-damage rules, two-turn and self-KO moves discounted);
- status_first:  a reliable sleep/paralysis/poison move while the enemy has no
                 status and no Substitute, else type_aware;
- setup_first:   an Attack/Special/Speed boost while healthy and below +2, else
                 type_aware;
- type_switcher: type_aware, but switches out when the enemy's best move KOs the
                 active mon and a living reserve survives it and matches up
                 better. Reads the enemy's real moveset (a benchmark opponent,
                 not a fair-play human model) and never switches two turns in a
                 row, so it cannot ping-pong.

Every policy is a pure function of a state snapshot (read_state) and the rules
parsed from source (load_rules), so each can be unit-tested without a ROM.
Ties always break toward the lower slot.
"""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import re

from source_constants import parse_rgbds_constants

POLICIES = ("best_power", "first_slot", "type_aware", "status_first",
            "setup_first", "type_switcher")
SWITCHING_POLICIES = ("type_switcher",)

STAT_NEUTRAL = 7  # stat-mod bytes run 1..13
SLP_MASK = 0x07
MULTIPLIERS = {"SUPER_EFFECTIVE": 2.0, "NOT_VERY_EFFECTIVE": 0.5, "NO_EFFECT": 0.0}


@dataclass(frozen=True)
class Move:
    effect: int
    power: int
    type: int
    accuracy: int  # percent


@dataclass
class Rules:
    moves: dict[int, Move]
    chart: dict[tuple[int, int], float]
    effects: dict[str, int]
    move_ids: dict[str, int]
    types: dict[str, int]

    def effect(self, name: str) -> int:
        return self.effects[name]


def load_rules(root: Path) -> Rules:
    effects = parse_rgbds_constants(root / "constants/move_effect_constants.asm")
    move_ids = parse_rgbds_constants(root / "constants/move_constants.asm")
    types = parse_rgbds_constants(root / "constants/type_constants.asm")
    moves: dict[int, Move] = {}
    move_id = 1
    for raw in (root / "data/moves/moves.asm").read_text(encoding="utf-8").splitlines():
        line = raw.split(";", 1)[0].strip()
        if not line.startswith("move "):
            continue
        fields = [f.strip() for f in line[len("move "):].split(",")]
        moves[move_id] = Move(effects[fields[1]], int(fields[2], 0), types[fields[3]],
                              int(fields[4], 0))
        move_id += 1
    chart: dict[tuple[int, int], float] = {}
    attacker = None
    for raw in (root / "data/types/type_matchups.asm").read_text(encoding="utf-8").splitlines():
        line = raw.split(";", 1)[0].strip()
        group = re.match(r"type_group\s+(\w+)", line)
        if group:
            attacker = types[group.group(1)]
            continue
        row = re.match(r"db\s+(\w+),\s*(\w+)$", line)
        if row and attacker is not None and row.group(2) in MULTIPLIERS:
            chart[(attacker, types[row.group(1)])] = MULTIPLIERS[row.group(2)]
    return Rules(moves, chart, effects, move_ids, types)


# --- State ------------------------------------------------------------------

@dataclass
class Mon:
    types: tuple[int, int]
    level: int
    hp: int
    max_hp: int
    attack: int
    defense: int
    speed: int
    special: int
    status: int
    moves: tuple[int, ...]
    pp: tuple[int, ...] = (0, 0, 0, 0)
    stat_mods: tuple[int, ...] = (STAT_NEUTRAL,) * 6
    substitute: bool = False
    reflect: bool = False
    light_screen: bool = False


@dataclass
class State:
    player: Mon
    enemy: Mon
    party: list[Mon]  # the player's party, in slot order (active included)
    active_slot: int


def _word(h, label: str) -> int:
    hi, lo = h.read_bytes(label, 2)
    return hi << 8 | lo


def _battle_mon(h, side: str) -> Mon:
    p = "wBattleMon" if side == "player" else "wEnemyMon"
    status_label = "wPlayerBattleStatus" if side == "player" else "wEnemyBattleStatus"
    mods_label = "wPlayerMonStatMods" if side == "player" else "wEnemyMonStatMods"
    status2 = h.read8(status_label + "2")
    status3 = h.read8(status_label + "3")
    return Mon(
        types=(h.read8(p + "Type1"), h.read8(p + "Type2")),
        level=h.read8(p + "Level"),
        hp=_word(h, p + "HP"), max_hp=_word(h, p + "MaxHP"),
        attack=_word(h, p + "Attack"), defense=_word(h, p + "Defense"),
        speed=_word(h, p + "Speed"), special=_word(h, p + "Special"),
        status=h.read8(p + "Status"),
        moves=tuple(h.read_bytes(p + "Moves", 4)),
        pp=tuple(h.read_bytes(p + "PP", 4)),
        stat_mods=tuple(h.read_bytes(mods_label, 6)),
        substitute=bool(status2 & (1 << 4)),   # HAS_SUBSTITUTE_UP
        light_screen=bool(status3 & (1 << 1)),  # HAS_LIGHT_SCREEN_UP
        reflect=bool(status3 & (1 << 2)),       # HAS_REFLECT_UP
    )


def _party_mon(h, slot: int) -> Mon:
    base = h.address("wPartyMon1")
    stride = h.address("wPartyMon2") - base
    mem = h.pyboy.memory

    def at(label: str, n: int = 1) -> list[int]:
        offset = h.address(label) - base + slot * stride
        return [mem[base + offset + i] for i in range(n)]

    def word(label: str) -> int:
        hi, lo = at(label, 2)
        return hi << 8 | lo

    return Mon(
        types=tuple(at("wPartyMon1Type1", 2)), level=at("wPartyMon1Level")[0],
        hp=word("wPartyMon1HP"), max_hp=word("wPartyMon1MaxHP"),
        attack=word("wPartyMon1Attack"), defense=word("wPartyMon1Defense"),
        speed=word("wPartyMon1Speed"), special=word("wPartyMon1Special"),
        status=at("wPartyMon1Status")[0], moves=tuple(at("wPartyMon1Moves", 4)),
        pp=tuple(at("wPartyMon1PP", 4)),
    )


def read_state(h) -> State:
    count = h.read8("wPartyCount")
    return State(_battle_mon(h, "player"), _battle_mon(h, "enemy"),
                 [_party_mon(h, slot) for slot in range(count)], h.read8("wPlayerMonNumber"))


# --- Evaluation ---------------------------------------------------------------

def type_multiplier(rules: Rules, move_type: int, defender: Mon) -> float:
    result = 1.0
    for t in dict.fromkeys(defender.types):  # a mono-type mon lists its type twice
        result *= rules.chart.get((move_type, t), 1.0)
    return result


def expected_damage(rules: Rules, move_id: int, attacker: Mon, defender: Mon,
                    accuracy: bool = True) -> float:
    """Expected damage of one use at the top roll; accuracy=False scores a hit."""
    move = rules.moves.get(move_id)
    if not move_id or move is None:
        return 0.0
    hit = move.accuracy / 100 if accuracy else 1.0
    e = rules.effect
    ids = rules.move_ids
    if move.effect == e("OHKO_EFFECT"):
        return 0.0
    if move.effect == e("SPECIAL_DAMAGE_EFFECT"):
        fixed = {ids["SONICBOOM"]: 20, ids["DRAGON_RAGE"]: 40,
                 ids["PSYWAVE"]: attacker.level * 3 // 4}.get(move_id, attacker.level)
        return fixed * hit
    if move.effect == e("SUPER_FANG_EFFECT"):
        return max(1, defender.hp // 2) * hit
    if move.power <= 1:
        return 0.0
    if move.effect == e("DREAM_EATER_EFFECT") and not defender.status & SLP_MASK:
        return 0.0
    physical = move.type < rules.types["FIRE"]
    attack = attacker.attack if physical else attacker.special
    defense = defender.defense if physical else defender.special
    if (physical and defender.reflect) or (not physical and defender.light_screen):
        defense *= 2
    base = ((2 * attacker.level // 5 + 2) * move.power * attack // max(1, defense)) // 50 + 2
    stab = 1.5 if move.type in attacker.types else 1.0
    hits = 1.0
    if move.effect in (e("ATTACK_TWICE_EFFECT"), e("TWINEEDLE_EFFECT")):
        hits = 2.0
    elif move.effect in (e("TWO_TO_FIVE_ATTACKS_EFFECT"), e("EFFECT_1E")):
        hits = 3.0  # (2+2+2+3+3+3+4+5)/8
    damage = base * stab * type_multiplier(rules, move.type, defender) * hits
    damage *= hit
    if move.effect in (e("CHARGE_EFFECT"), e("FLY_EFFECT"), e("HYPER_BEAM_EFFECT")):
        damage /= 2  # two turns of action for one hit
    if move.effect == e("EXPLODE_EFFECT"):
        damage /= 4  # spends the mon
    return damage


def legal_slots(mon: Mon) -> list[int]:
    slots = [s for s, (m, pp) in enumerate(zip(mon.moves, mon.pp)) if m and pp & 0x3F]
    return slots or [0]


def best_attack(rules: Rules, attacker: Mon, defender: Mon,
                slots: list[int] | None = None) -> tuple[int, float]:
    slots = legal_slots(attacker) if slots is None else slots
    best = max(slots, key=lambda s: (expected_damage(rules, attacker.moves[s], attacker, defender), -s))
    return best, expected_damage(rules, attacker.moves[best], attacker, defender)


def enemy_best_damage(rules: Rules, enemy: Mon, target: Mon) -> float:
    """The enemy's best one-turn damage on target, ignoring accuracy and PP."""
    return max((expected_damage(rules, m, enemy, target, accuracy=False)
                for m in enemy.moves), default=0.0)


def status_slot(rules: Rules, state: State) -> int | None:
    enemy = state.enemy
    if enemy.status or enemy.substitute:
        return None
    e = rules.effect
    t = rules.types
    candidates = []
    for s in legal_slots(state.player):
        move = rules.moves.get(state.player.moves[s])
        if move is None or move.accuracy < 75:
            continue
        if move.effect == e("SLEEP_EFFECT"):
            rank = 0
        elif move.effect == e("PARALYZE_EFFECT"):
            if move.type == t["ELECTRIC"] and t["GROUND"] in enemy.types:
                continue
            rank = 1
        elif move.effect == e("POISON_EFFECT"):
            if t["POISON"] in enemy.types:
                continue
            rank = 2
        else:
            continue
        candidates.append((rank, -move.accuracy, s))
    return min(candidates)[2] if candidates else None


SETUP_STAT = {"ATTACK_UP1_EFFECT": 0, "ATTACK_UP2_EFFECT": 0, "SPEED_UP1_EFFECT": 2,
              "SPEED_UP2_EFFECT": 2, "SPECIAL_UP1_EFFECT": 3, "SPECIAL_UP2_EFFECT": 3}


def setup_slot(rules: Rules, state: State) -> int | None:
    player = state.player
    if player.hp * 2 < player.max_hp:
        return None
    by_effect = {rules.effect(name): stat for name, stat in SETUP_STAT.items()}
    for s in legal_slots(player):
        move = rules.moves.get(player.moves[s])
        stat = by_effect.get(move.effect) if move else None
        if stat is not None and player.stat_mods[stat] < STAT_NEUTRAL + 2:
            return s
    return None


def choose_slot(rules: Rules, state: State, policy: str) -> int:
    player = state.player
    legal = legal_slots(player)
    if policy == "first_slot":
        return legal[0]
    if policy == "best_power":
        return max(legal, key=lambda s: (rules.moves[player.moves[s]].power
                                         if player.moves[s] in rules.moves else 0, -s))
    if policy == "status_first":
        slot = status_slot(rules, state)
        if slot is not None:
            return slot
    if policy == "setup_first":
        slot = setup_slot(rules, state)
        if slot is not None:
            return slot
    if policy in ("type_aware", "status_first", "setup_first", "type_switcher"):
        return best_attack(rules, player, state.enemy, legal)[0]
    raise ValueError(f"unknown policy {policy}")


def matchup(rules: Rules, mon: Mon, enemy: Mon) -> float:
    """Share of the enemy's HP we remove per turn minus the share of ours it does."""
    ours = best_attack(rules, mon, enemy)[1] / max(1, enemy.hp)
    theirs = enemy_best_damage(rules, enemy, mon) / max(1, mon.hp)
    return ours - theirs


def choose_switch(rules: Rules, state: State, policy: str, switched_last_turn: bool) -> int | None:
    """Party slot to switch to at the battle menu, or None to fight."""
    if policy not in SWITCHING_POLICIES or switched_last_turn:
        return None
    active = state.player
    if enemy_best_damage(rules, state.enemy, active) < active.hp:
        return None  # not about to be KO'd
    best = None
    for slot, mon in enumerate(state.party):
        if slot == state.active_slot or not mon.hp:
            continue
        if enemy_best_damage(rules, state.enemy, mon) >= mon.hp:
            continue  # would die on entry
        score = matchup(rules, mon, state.enemy)
        if best is None or score > best[0]:
            best = (score, slot)
    if best is None or best[0] <= matchup(rules, active, state.enemy):
        return None
    return best[1]
