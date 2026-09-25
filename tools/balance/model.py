"""Red Rogue balance model: Monte-Carlo simulation of whole runs, offline.

Every rule here mirrors a named routine in the ROM; the routine is cited next
to the function that copies it. Tables and knobs come from parse.py, never from
literals in this file, so `--set KNOB=VALUE` answers "what if" without a build.

What the player does is a POLICY (Config), not a guess about the ROM: which
optional doors they take, which mon takes the KOs. The player is assumed to win
every battle; how hard that is gets measured separately (Phase 3).

Usage:
  python tools/balance/model.py --runs 2000 --difficulty normal --exp-all 0
  python tools/balance/model.py --set GYM_R5_BASE=35 --set WILD_BUDGET_BASE=14
  python tools/balance/model.py --runs 200 --selfcheck
"""

from __future__ import annotations

import argparse
import random
import statistics
import sys
from dataclasses import dataclass, field, replace
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import parse  # noqa: E402
from parse import EVOLVE_ITEM, EVOLVE_TRADE, GameData  # noqa: E402

MAX_LEVEL = 100
DIFFICULTIES = ("normal", "easy", "very_easy", "hard", "very_hard")   # DIFFICULTY_* order
KANTO_LEADERS = ("Brock", "Misty", "LtSurge", "Erika", "Koga", "Blaine", "Sabrina", "Giovanni")
KANTO_E4 = ("Lorelei", "Bruno", "Agatha", "Lance")
STAGE_EVENTS = (  # StageEventTrainerTable order; (class, pool)
    ("JESSIE_JAMES", "POOL_JESSIE_JAMES"),
    ("PSYCHIC_TR", "POOL_PSYCHIC"),
    ("BURGLAR", "POOL_BURGLAR"),
    ("NURSE_JOY", "POOL_JOY"),
    ("OFFICER_JENNY", "POOL_JENNY"),
)
STARTERS = ("CHARMANDER", "SQUIRTLE", "BULBASAUR")
GROWTH_CURVES = ("GROWTH_MEDIUM_FAST", "GROWTH_MEDIUM_SLOW", "GROWTH_FAST", "GROWTH_SLOW")
PARTY_GEN_MAX_RETRIES = 8
AMULET_COIN_PCT = (10, 15, 20)


def class_name(camel: str) -> str:
    """Record label -> trainer class constant: LtSurge -> LT_SURGE, KogaE4 -> KOGA_E4."""
    out = ""
    for i, ch in enumerate(camel):
        if i and (ch.isupper() or (ch.isdigit() and not camel[i - 1].isdigit())):
            out += "_"
        out += ch.upper()
    return out


def bcd(value: int) -> int:
    """A BCD knob ($3000) as the decimal amount it displays (3000)."""
    return int(f"{value:x}")


# =============================================================================
# Config
# =============================================================================

@dataclass
class Config:
    difficulty: str = "normal"
    exp_all: int | None = 0          # None = not in the bag; 0-3 = key-item tier
    groups: tuple[str, ...] = ("KANTO",)
    take_wild: float = 0.5           # chance the player picks an optional wild-area door
    take_miniboss: float = 1.0       # chance the player picks the mini-boss door
    fight_stage_event: float = 1.0   # chance the player fights an armed stage event
    wild_steps: int = 250            # PLACEHOLDER until measure_wild_paths.py (Phase 3)
    policy: str = "carry"            # carry: the starter takes every KO; rotate: KOs spread
    amulet_coin: int = 0             # 0 = none, 1-3 = tier
    champion: str = "RIVAL3"
    reward_joins: int = 1            # reward mons that join per stage (bench)


# =============================================================================
# ROM mirrors: levels
# =============================================================================

def apply_difficulty(level: int, difficulty: str) -> int:
    """RogueApplyDifficulty (func_enc_gen.asm)."""
    if difficulty == "normal":
        return level
    delta = level // (5 if difficulty.startswith("very") else 10)
    if difficulty.endswith("easy"):
        v = level - delta
        return v if v > 0 else 1
    return min(level + delta, MAX_LEVEL)


def evolve_by_level(g: GameData, cfg: Config, species: str, level: int, rng: random.Random) -> str:
    """EvolveMonByLevel (func_enc_gen.asm), including the Eevee roll and the
    species-group gate (RogueIsSpeciesEvolutionAllowed)."""
    while True:
        for method, min_level, target in g.species[species].evos:
            if method in (EVOLVE_ITEM, EVOLVE_TRADE) and level < 35:
                continue
            if species == "EEVEE":
                r = rng.randrange(16)
                return "EEVEE" if r < 3 else "FLAREON" if r < 7 else "VAPOREON" if r < 11 else "JOLTEON"
            if level < min_level:
                continue
            cls = parse.classify(g.rarity, target)
            if cls is not None and cls[0] not in cfg.groups:
                continue
            species = target
            break
        else:
            return species


def scale_trainer_evolution(g: GameData, cfg: Config, species: str, level: int, rng: random.Random) -> str:
    """ScaleTrainer_evolution: evolve against a biased-down level (L - L/4, or
    L - L/8 from level 30)."""
    bias = level >> (3 if level >= 30 else 2)
    return evolve_by_level(g, cfg, species, level - bias, rng)


def rival_starter_evolve(g: GameData, species: str, level: int) -> str:
    """RivalStarterEvolve: up to two plain level steps, no bias, no Eevee."""
    if species == "EEVEE":
        return species
    for _ in range(2):
        nxt = next((t for m, lv, t in g.species[species].evos if m == parse.EVOLVE_LEVEL and level >= lv), None)
        if nxt is None:
            break
        species = nxt
    return species


# =============================================================================
# ROM mirrors: species rolls
# =============================================================================

def roll_tier_species(g: GameData, cfg: Config, tier: int, rng: random.Random) -> str:
    """RogueRollGroupForTier + RogueRollSpeciesInList: uniform over the union
    of the active groups' base forms at this tier; Kanto pokeball fallback."""
    union = [s for grp in cfg.groups for s in g.rarity[grp][tier].base]
    if not union:
        union = g.rarity["KANTO"][0].base
    return rng.choice(union)


def get_rand_mon(g: GameData, cfg: Config, b_class: int, rng: random.Random) -> str:
    """GetRandMon: b = 4 pokeball .. 1 masterball -> tier 4 - b. Base form only."""
    return roll_tier_species(g, cfg, 4 - b_class, rng)


def pc_roll_mon_class(round_idx: int, bump: int, rng: random.Random) -> int:
    """PCRollMonClass: 1 pokeball .. 4 masterball, biased by round."""
    shift = min(round_idx * 8 + bump, 255)
    eff = min(rng.randrange(256) + shift, 255)
    return 1 if eff < 205 else 2 if eff < 243 else 3 if eff < 253 else 4


def select_from_tier_evolved(g: GameData, cfg: Config, cls: int, level: int, rng: random.Random) -> str:
    """RogueSelectFromTier: roll a base form at class tier, then EvolveMonByLevel
    (no bias). The ownership re-roll is ignored: it changes which species, not
    the tier, and the model does not track the player's box."""
    return evolve_by_level(g, cfg, roll_tier_species(g, cfg, cls - 1, rng), level, rng)


# =============================================================================
# Battles
# =============================================================================

@dataclass
class Battle:
    kind: str                 # route, route_final, gym_trainer, gym_final, leader, miniboss,
                              # wild, wild_boss, stage_event, victory_road, e4, champion, oak_rival
    count: int                # wBattleCount while it is fought
    mons: list[tuple[str, int]]
    trainer: bool
    money_base: int = 0       # 0 = pays nothing

    @property
    def money_level(self) -> int:
        return self.mons[-1][1]


def roster_battle(g: GameData, cfg: Config, count: int, rng: random.Random) -> Battle:
    """GetRandRoster: route (mod 1-5) or gym-trainer (mod 6-9) roster."""
    idx = min(count, 89) // 10
    rem = min(count, 89) % 10
    block = (g.tables.route if rem < 6 else g.tables.gym)[idx]
    final = rem in (5, 9)
    base = block.min_level + (block.final_bonus if final else 0)
    counts = block.final_counts if final else block.counts
    mons = []
    for class_slot, n in enumerate(counts):          # pokeball first; b = 4 .. 1
        for _ in range(n):
            sp = get_rand_mon(g, cfg, 4 - class_slot, rng)
            lv = apply_difficulty(base + (rng.randrange(block.level_range) if block.level_range else 0), cfg.difficulty)
            mons.append((scale_trainer_evolution(g, cfg, sp, lv, rng), lv))
    kind = ("route_final" if rem == 5 else "route") if rem < 6 else ("gym_final" if rem == 9 else "gym_trainer")
    return Battle(kind, count, mons, True, g.knobs["MONEY_BASE_TRAINER"])


def draw_pool(g: GameData, cfg: Config, pool: str, level: int, used: list[str], allow_uber: bool,
              rng: random.Random, no_rival: str | None = None) -> str:
    """PartyGenRollFromPool + PartyGenPoolCandidateOk: NO_DUPES on the FIELDED
    species, uber filter, bounded retries (the last draw stands), then
    ScaleTrainer_evolution."""
    runs = g.pools[pool]
    eligible = [s for grp in parse.GROUPS if grp in cfg.groups for s in runs[grp]]
    if not eligible:
        eligible = runs["KANTO"][:1]
    draw = eligible[0]
    for _ in range(PARTY_GEN_MAX_RETRIES):
        draw = rng.choice(eligible)
        fielded = draw if draw == "EEVEE" else scale_trainer_evolution(g, cfg, draw, level, random.Random(0))
        cls = parse.classify(g.rarity, draw)
        if fielded in used or (not allow_uber and cls and cls[1] == parse.TIER_UBER) or draw == no_rival:
            continue
        break
    return scale_trainer_evolution(g, cfg, draw, level, rng)


def spec_battle(g: GameData, cfg: Config, kind: str, count: int, n: int, base: int, step: int, pool: str,
                ace: str | None, allow_uber: bool, money_base: int, rng: random.Random,
                rival_starter: str | None = None) -> Battle:
    """RogueBuildParty: level = base + slot * step (clamped, then modifiers);
    pinned ace is not evolved, except the rival starter placeholder."""
    mons: list[tuple[str, int]] = []
    for slot in range(n):
        lv = apply_difficulty(max(1, min(base + slot * step, MAX_LEVEL)), cfg.difficulty)
        if slot == n - 1 and ace == "RIVAL_STARTER_PLACEHOLDER":
            sp = rival_starter_evolve(g, rival_starter, lv)
        elif slot == n - 1 and ace:
            sp = ace
        else:
            sp = draw_pool(g, cfg, pool, lv, [m for m, _ in mons], allow_uber, rng,
                           no_rival=rival_starter if ace == "RIVAL_STARTER_PLACEHOLDER" else None)
        mons.append((sp, lv))
    return Battle(kind, count, mons, True, money_base)


def leader_battle(g: GameData, cfg: Config, leader: parse.LeaderRecord, rnd: int, rng: random.Random) -> Battle:
    """InitGymBattle + gym_team_spec. Round 1 variant A is authored data in the
    ROM (the wTrainerNo 1 hole); modelled here as variant B, same levels."""
    k = g.knobs
    n, base, step = k[f"GYM_R{rnd}_MONS"], k[f"GYM_R{rnd}_BASE"], k[f"GYM_R{rnd}_STEP"]
    var = rng.randrange(3)
    ace = None
    if var == 0 and rnd > 1:
        ace = leader.ace_a_early if rnd <= 3 else leader.ace_a_late
    elif var == 2:
        ace = leader.ace_c_early if rnd <= 3 else leader.ace_c_late
    allow_uber = rnd >= 7 and "ALLOW_UBER" in leader.late_flags
    return spec_battle(g, cfg, "leader", 10 * rnd, n, base, step, leader.pool, ace, allow_uber,
                       g.money[class_name(leader.name)], rng)


def miniboss_battle(g: GameData, cfg: Config, who: str, count: int, rival_starter: str, rng: random.Random,
                    kind: str = "miniboss") -> Battle:
    """BuildMiniBossTeam: every mon gets its own MiniBossSetLevel roll; fill mons
    come from MiniBossRollFillMon (base forms, never evolved)."""
    row = g.tables.miniboss[min(count, 89) // 10]
    teams = g.miniboss_teams["RivalMiniBossData" if who == "RIVAL" else "GiovanniMiniBossData"]
    team = teams[0] if who == "RIVAL" else rng.choice(teams)

    def level() -> int:
        lv = min(row.min_level + (rng.randrange(row.level_range) if row.level_range else 0), MAX_LEVEL)
        return apply_difficulty(lv, cfg.difficulty)

    mons = []
    for tok in team:
        if tok.startswith("FILL:"):
            for _ in range(int(tok.split(":")[1])):
                lv = level()
                b = row.base_class
                if rng.randrange(256) < row.rare_chance and b >= 2:
                    b -= 1
                mons.append((get_rand_mon(g, cfg, b, rng), lv))
        elif tok == "RIVAL_STARTER_PLACEHOLDER":
            lv = level()
            mons.append((rival_starter_evolve(g, rival_starter, lv), lv))
        else:
            mons.append((tok, level()))
    base = g.money["RIVAL_MINIBOSS" if who == "RIVAL" else "GIOVANNI_MINIBOSS"]
    return Battle(kind, count, mons, True, base)


def e4_battle(g: GameData, cfg: Config, member: parse.E4Record, count: int, rng: random.Random) -> Battle:
    """InitElite4Battle + e4_team_spec: tier from wBattleCount 86-89."""
    tier = min(max(count - 86, 0), 3) + 1
    var = rng.randrange(3)
    ace = member.ace_a if var == 0 else member.ace_c if var == 2 else None
    return spec_battle(g, cfg, "e4", count, 6, g.knobs["E4_BASE_LEVEL"] + tier, g.knobs["E4_LEVEL_STEP"],
                       member.pool, ace, False, g.money[class_name(member.name)], rng)


def stage_event_battle(g: GameData, cfg: Config, count: int, rng: random.Random) -> Battle:
    """StageEventRoll picks a type; stage_event_team_spec builds it."""
    cls, pool = rng.choice(STAGE_EVENTS)
    r = min(count, 89) // 10 + 1
    k = g.knobs
    return spec_battle(g, cfg, "stage_event", count, k[f"STAGE_EVENT_R{r}_MONS"], k[f"STAGE_EVENT_R{r}_BASE"],
                       k["STAGE_EVENT_LEVEL_STEP"], pool, None, False, g.money[cls], rng)


def wild_battle(g: GameData, cfg: Config, count: int, rng: random.Random) -> Battle:
    """PCRollWildEncounter: PCGetWildLevel + class roll, no difficulty modifier."""
    idx = min(count, 89) // 10
    lv = g.tables.wild[idx] + rng.randrange(3)
    sp = select_from_tier_evolved(g, cfg, pc_roll_mon_class(idx, 0, rng), lv, rng)
    return Battle("wild", count, [(sp, lv)], False)


def wild_boss_battle(g: GameData, cfg: Config, count: int, rng: random.Random) -> Battle:
    """PCRollBoss: PCGetBossLevel + a class roll bumped by 60."""
    idx = min(count, 89) // 10
    lv = g.tables.wild_boss[idx]
    sp = select_from_tier_evolved(g, cfg, pc_roll_mon_class(idx, 60, rng), lv, rng)
    return Battle("wild_boss", count, [(sp, lv)], False)


# =============================================================================
# ROM mirrors: EXP, money, levels
# =============================================================================

def exp_for_ko(g: GameData, base_exp: int, level: int, trainer: bool) -> int:
    """GainExperience: base * L / 7, then BoostExp (x1.5, saturating) for a
    trainer battle, or for every battle when WILD_EXP_MATCHES_TRAINER."""
    e = base_exp * level // 7
    if trainer or g.knobs["WILD_EXP_MATCHES_TRAINER"]:
        e = min(e + e // 2, 0xFFFF)
    return e


def exp_all_base(base_exp: int, tier: int) -> int:
    """FaintEnemyPokemon's EXP All reduction: value - value >> (tier + 1); tier 3 = full."""
    return base_exp if tier == 3 else base_exp - (base_exp >> (tier + 1))


def money_for(g: GameData, battle: Battle, amulet_tier: int) -> int:
    """ReadTrainer .FinishUp: base x level of the last mon, + Amulet Coin %."""
    if not battle.money_base:
        return 0
    lv = battle.money_level
    if amulet_tier:
        lv += lv * AMULET_COIN_PCT[amulet_tier - 1] // 100
    return battle.money_base * lv


def exp_at_level(curve: tuple[int, int, int, int, int], n: int) -> int:
    """CalcExperience: a/b * n^3 + c * n^2 + d * n - e (integer, a*n^3 // b)."""
    a, b, c, d, e = curve
    return a * n ** 3 // b + c * n * n + d * n - e


def level_from_exp(curve: tuple[int, int, int, int, int], exp: int) -> int:
    """CalcLevelFromExperience: the highest d >= 1 with exp(d) <= exp."""
    lv = 1
    while lv < MAX_LEVEL and exp_at_level(curve, lv + 1) <= exp:
        lv += 1
    return lv


def reward_level(g: GameData, count: int) -> int:
    """GetRewardMonLevel, stage caller: the gym block of the current round,
    min + range/2, clamped to [REWARD_LEVEL_FLOOR, REWARD_LEVEL_CAP]."""
    block = g.tables.gym[min(count, 89) // 10]
    lv = block.min_level + (block.level_range >> 1)
    return max(g.knobs["REWARD_LEVEL_FLOOR"], min(lv, g.knobs["REWARD_LEVEL_CAP"]))


# =============================================================================
# The run
# =============================================================================

@dataclass
class Member:
    join_level: int
    join_battle: int          # index into the run's battle list
    exp_gained: int = 0


@dataclass
class Checkpoint:
    rnd: int                  # 1-8 gyms, 9 = before the Elite Four, 10 = before the Champion
    label: str
    battle_index: int         # battles fought before this checkpoint
    enemy_ace_level: int
    ace_exp: int
    bench: list[tuple[int, int]]   # (join level, exp gained) for every non-ace member
    money: int


@dataclass
class Run:
    battles: list[Battle] = field(default_factory=list)
    checkpoints: list[Checkpoint] = field(default_factory=list)
    stages: list[str] = field(default_factory=list)
    offers: list[str] = field(default_factory=list)   # special kind offered per lobby visit


class Simulator:
    def __init__(self, g: GameData, cfg: Config, seed: int):
        self.g, self.cfg, self.rng = g, cfg, random.Random(seed)
        self.run = Run()
        self.members = [Member(5, 0)]           # the starter, flat level 5 in Oak's Lab
        self.money = bcd(g.knobs["START_MONEY"])
        self.rival_starter = self.rng.choice(STARTERS)
        self.count = 0
        self.ko_turn = 0

    # --- bookkeeping ---
    def fight(self, battle: Battle) -> None:
        g, cfg = self.g, self.cfg
        self.run.battles.append(battle)
        for sp, lv in battle.mons:
            base = g.species[sp].base_exp
            if cfg.policy == "rotate":
                fighter = self.ko_turn % len(self.members)
                self.ko_turn += 1
            else:
                fighter = 0
            if cfg.exp_all is None:
                self.members[fighter].exp_gained += exp_for_ko(g, base, lv, battle.trainer)
            else:
                share = exp_for_ko(g, exp_all_base(base, cfg.exp_all), lv, battle.trainer)
                self.members[fighter].exp_gained += share    # the fighter's own call
                for m in self.members:                        # then every party mon
                    m.exp_gained += share
        self.money += money_for(g, battle, cfg.amulet_coin)
        if battle.trainer and battle.kind not in ("stage_event",):
            self.count += 1

    def join(self, level: int) -> None:
        if len(self.members) < 6:
            self.members.append(Member(level, len(self.run.battles)))

    def checkpoint(self, rnd: int, label: str, enemy_ace: int) -> None:
        ace = self.members[0]
        self.run.checkpoints.append(Checkpoint(
            rnd, label, len(self.run.battles), enemy_ace, ace.exp_gained,
            [(m.join_level, m.exp_gained) for m in self.members[1:]], self.money))

    # --- stages ---
    def route(self, miniboss: str | None) -> None:
        for rem in range(1, 6):
            if rem == 5 and miniboss:
                self.fight(miniboss_battle(self.g, self.cfg, miniboss, self.count, self.rival_starter, self.rng))
            else:
                self.fight(roster_battle(self.g, self.cfg, self.count, self.rng))

    def wild_area(self, stage_event: bool) -> None:
        g, cfg, rng = self.g, self.cfg, self.rng
        k = g.knobs
        budget = min(255, k["WILD_BUDGET_BASE"] + self.count // k["WILD_BUDGET_DIVISOR"])
        encounters = sum(1 for _ in range(cfg.wild_steps) if rng.randrange(256) < k["WILD_AREA_ENCOUNTER_RATE"])
        for _ in range(min(budget, encounters)):
            self.fight(wild_battle(g, cfg, self.count, rng))
        if stage_event and rng.random() < cfg.fight_stage_event:
            self.fight(stage_event_battle(g, cfg, self.count, rng))
        boss = wild_boss_battle(g, cfg, self.count, rng)
        self.fight(boss)
        self.count += k["WILD_AREA_EXIT_BATTLES"]

    def simulate(self) -> Run:
        g, cfg, rng, k = self.g, self.cfg, self.rng, self.g.knobs
        c = g.constants
        leaders = [r for r in g.leaders if r.name in KANTO_LEADERS] if cfg.groups == ("KANTO",) else list(g.leaders)
        lineup = rng.sample(leaders, 8)

        # Oak's Lab: the rival's starter at 5, pays RIVAL1 money, count -> 1.
        self.fight(Battle("oak_rival", 0, [(self.rival_starter, apply_difficulty(5, cfg.difficulty))], True,
                          g.money["RIVAL1"]))

        mb_count = wa_count = since_special = 0
        wild_types_left = 4
        for rnd in range(1, 9):
            badges = rnd - 1
            kind = None
            if self.count >= c["MINIBOSS_FIRST_BATTLECOUNT"]:
                remaining = c["MINIBOSS_TOTAL_ROUTES"] - badges

                def forced(have: int, need: int) -> bool:
                    short = need - have
                    return short > 0 and remaining <= short

                mbf, waf = forced(mb_count, c["MINIBOSS_MIN_PER_RUN"]), forced(wa_count, c["WILD_AREA_MIN_PER_RUN"])
                if mbf and not waf:
                    kind = "miniboss"
                elif waf and not mbf:
                    kind = "wild_forced"
                elif mbf or since_special >= 3 or rng.randrange(256) < (since_special + 1) * 64:
                    kind = ("wild" if wa_count < mb_count else "miniboss" if wa_count > mb_count
                            else rng.choice(("miniboss", "wild")))
                if kind == "wild" and waf:
                    kind = "wild_forced"
                if kind is None:
                    since_special += 1
                else:
                    since_special = 0
                if kind and kind.startswith("wild"):
                    if wild_types_left == 0:
                        kind = None          # all four types offered; the pick fails open to a route
                    else:
                        wild_types_left -= 1
                        wa_count = min(wa_count + 1, 3)
                elif kind == "miniboss":
                    mb_count += 1

            self.run.offers.append(kind or "none")
            stage_event = kind is not None and kind.startswith("wild") and \
                rng.randrange(256) < k["STAGE_EVENT_CHANCE"]
            if kind == "wild_forced" or (kind == "wild" and rng.random() < cfg.take_wild):
                self.run.stages.append("wild")
                self.wild_area(stage_event)
            elif kind == "miniboss" and rng.random() < cfg.take_miniboss:
                self.run.stages.append("miniboss")
                self.route(rng.choice(("RIVAL", "GIOVANNI")))
            else:
                self.run.stages.append("route")
                self.route(None)
            for _ in range(cfg.reward_joins):
                self.join(reward_level(g, 10 * (rnd - 1) + 1))

            for _ in range(4):
                self.fight(roster_battle(g, cfg, self.count, rng))
            leader = leader_battle(g, cfg, lineup[rnd - 1], rnd, rng)
            self.checkpoint(rnd, lineup[rnd - 1].name, leader.mons[-1][1])
            self.fight(leader)

        # Victory Road: four roster trainers, then the static rival mini-boss.
        self.run.stages.append("victory_road")
        for _ in range(4):
            self.fight(roster_battle(g, cfg, self.count, rng))
        self.fight(miniboss_battle(g, cfg, "RIVAL", self.count, self.rival_starter, rng, "victory_road"))

        e4 = [r for r in g.e4 if r.name in KANTO_E4]
        rng.shuffle(e4)
        first = e4_battle(g, cfg, e4[0], self.count, rng)
        self.checkpoint(9, "Elite Four", first.mons[-1][1])
        self.fight(first)
        for member in e4[1:]:
            self.fight(e4_battle(g, cfg, member, self.count, rng))
        champ = spec_battle(g, cfg, "champion", self.count, 6, 60, 1, "POOL_RIVAL3",
                            "RIVAL_STARTER_PLACEHOLDER", False, g.money["RIVAL3"], rng, self.rival_starter)
        self.final_count = self.count
        self.checkpoint(10, "Champion", champ.mons[-1][1])
        self.fight(champ)
        return self.run


# =============================================================================
# Aggregation
# =============================================================================

def pct(values: list[float], p: float) -> float:
    s = sorted(values)
    return s[min(len(s) - 1, max(0, round(p * (len(s) - 1))))]


def ace_level(g: GameData, curve: str, ace_exp: int) -> int:
    rate = g.growth[curve]
    return level_from_exp(rate, exp_at_level(rate, 5) + ace_exp)


def team_average(g: GameData, curve: str, cp: Checkpoint) -> float:
    rate = g.growth[curve]
    levels = [ace_level(g, curve, cp.ace_exp)]
    levels += [level_from_exp(rate, exp_at_level(rate, lv) + gained) for lv, gained in cp.bench]
    return sum(levels) / len(levels)


def summarize(g: GameData, runs: list[Run]) -> list[dict]:
    """One row per checkpoint: enemy ace, player ace per growth curve (mean /
    p10 / p90), gap to the ace - 2 target, cumulative money."""
    rows = []
    for i in range(len(runs[0].checkpoints)):
        cps = [r.checkpoints[i] for r in runs]
        row = {
            "round": cps[0].rnd,
            "label": "Elite Four" if cps[0].rnd == 9 else "Champion" if cps[0].rnd == 10 else f"Gym {cps[0].rnd}",
            "battles": statistics.mean(cp.battle_index for cp in cps),
            "enemy_ace": statistics.mean(cp.enemy_ace_level for cp in cps),
            "money": statistics.mean(cp.money for cp in cps),
        }
        for curve in GROWTH_CURVES:
            lv = [ace_level(g, curve, cp.ace_exp) for cp in cps]
            short = curve.removeprefix("GROWTH_").lower()
            row[f"ace_{short}"] = statistics.mean(lv)
            row[f"ace_{short}_p10"] = pct(lv, 0.1)
            row[f"ace_{short}_p90"] = pct(lv, 0.9)
            row[f"team_{short}"] = statistics.mean(team_average(g, curve, cp) for cp in cps)
        row["gap_medium_slow"] = row["ace_medium_slow"] - (row["enemy_ace"] - 2)
        rows.append(row)
    return rows


def simulate(g: GameData, cfg: Config, n: int, seed: int = 1) -> list[Run]:
    return [Simulator(g, cfg, seed * 100003 + i).simulate() for i in range(n)]


def format_round_table(rows: list[dict], cfg: Config) -> str:
    head = (f"difficulty={cfg.difficulty} exp_all={cfg.exp_all} policy={cfg.policy} "
            f"take_wild={cfg.take_wild} groups={','.join(cfg.groups)}")
    lines = [head,
             "| checkpoint | battles | enemy ace | ace MedSlow (p10-p90) | ace MedFast | ace Fast | ace Slow "
             "| team MedSlow | gap vs ace-2 | money |",
             "|---|---|---|---|---|---|---|---|---|---|"]
    for r in rows:
        lines.append(
            f"| {r['label']} | {r['battles']:.0f} | {r['enemy_ace']:.1f} "
            f"| {r['ace_medium_slow']:.1f} ({r['ace_medium_slow_p10']}-{r['ace_medium_slow_p90']}) "
            f"| {r['ace_medium_fast']:.1f} | {r['ace_fast']:.1f} | {r['ace_slow']:.1f} "
            f"| {r['team_medium_slow']:.1f} | {r['gap_medium_slow']:+.1f} | {r['money']:,.0f} |")
    return "\n".join(lines)


# =============================================================================
# Self-check: hand-computed values the model must reproduce
# =============================================================================

def selfcheck(g: GameData, runs: int) -> list[str]:
    fails: list[str] = []

    def check(name: str, got, want) -> None:
        if got != want:
            fails.append(f"{name}: got {got!r}, want {want!r}")

    # Growth curves against Gen 1's published totals.
    check("MedSlow L5", exp_at_level(g.growth["GROWTH_MEDIUM_SLOW"], 5), 135)
    check("MedSlow L100", exp_at_level(g.growth["GROWTH_MEDIUM_SLOW"], 100), 1059860)
    check("MedFast L100", exp_at_level(g.growth["GROWTH_MEDIUM_FAST"], 100), 1000000)
    check("Fast L100", exp_at_level(g.growth["GROWTH_FAST"], 100), 800000)
    check("Slow L100", exp_at_level(g.growth["GROWTH_SLOW"], 100), 1250000)
    check("level_from_exp MedSlow 135", level_from_exp(g.growth["GROWTH_MEDIUM_SLOW"], 135), 5)
    check("level_from_exp MedSlow 134", level_from_exp(g.growth["GROWTH_MEDIUM_SLOW"], 134), 4)

    # EXP: Pidgey (55) at L3, trainer: 55*3//7 = 23, x1.5 -> 34.
    pidgey = g.species["PIDGEY"].base_exp
    check("Pidgey base exp", pidgey, 55)
    check("EXP Pidgey L3 trainer", exp_for_ko(g, pidgey, 3, True), 34)
    wild = exp_for_ko(g, pidgey, 3, False)
    check("EXP Pidgey L3 wild (knob)", wild, 34 if g.knobs["WILD_EXP_MATCHES_TRAINER"] else 23)
    check("EXP All tier 0 base 55", exp_all_base(55, 0), 28)
    check("EXP All tier 3 base 55", exp_all_base(55, 3), 55)

    # Difficulty: RogueApplyDifficulty on the round-1 leader ace (12 + 2 = 14).
    ace1 = g.knobs["GYM_R1_BASE"] + (g.knobs["GYM_R1_MONS"] - 1) * g.knobs["GYM_R1_STEP"]
    for diff, want in (("normal", ace1), ("easy", ace1 - ace1 // 10), ("very_easy", ace1 - ace1 // 5),
                       ("hard", ace1 + ace1 // 10), ("very_hard", ace1 + ace1 // 5)):
        check(f"difficulty {diff}", apply_difficulty(ace1, diff), want)
    check("difficulty floor", apply_difficulty(1, "very_easy"), 1)

    # Money: route trainer base x last level; Amulet Coin tier 3 (+20%).
    b = Battle("route", 1, [("PIDGEY", 4)], True, g.knobs["MONEY_BASE_TRAINER"])
    check("money route L4", money_for(g, b, 0), g.knobs["MONEY_BASE_TRAINER"] * 4)
    b = Battle("route", 1, [("PIDGEY", 10)], True, g.knobs["MONEY_BASE_TRAINER"])
    check("money amulet t3 L10", money_for(g, b, 3), g.knobs["MONEY_BASE_TRAINER"] * 12)
    check("wild pays nothing", money_for(g, Battle("wild", 1, [("PIDGEY", 5)], False), 0), 0)
    check("GIOVANNI leader base", g.money["GIOVANNI"], g.knobs["MONEY_BASE_LEADER_GIOVANNI"])
    check("BROCK leader base", g.money["BROCK"], g.knobs["MONEY_BASE_LEADER"])
    check("START_MONEY", bcd(g.knobs["START_MONEY"]), 3000)

    # Reward level: round 1 gym block min + range/2, floored at 5.
    blk = g.tables.gym[0]
    check("reward level r1", reward_level(g, 1),
          max(g.knobs["REWARD_LEVEL_FLOOR"], blk.min_level + blk.level_range // 2))

    # Evolution bias: Pidgey (evolves 18) at L20 -> biased 15 -> stays Pidgey;
    # at L24 -> biased 18 -> Pidgeotto.
    rng = random.Random(0)
    cfg = Config()
    check("bias L20 Pidgey", scale_trainer_evolution(g, cfg, "PIDGEY", 20, rng), "PIDGEY")
    check("bias L24 Pidgey", scale_trainer_evolution(g, cfg, "PIDGEY", 24, rng), "PIDGEOTTO")
    check("item evo below 35", evolve_by_level(g, cfg, "POLIWHIRL", 34, rng), "POLIWHIRL")
    check("item evo at 35", evolve_by_level(g, cfg, "POLIWHIRL", 35, rng), "POLIWRATH")

    # Structural invariants over a batch of real runs.
    for seed in range(runs):
        sim = Simulator(g, Config(), seed)
        run = sim.simulate()
        check("champion fought at count 90", sim.final_count, 90)
        n_wild = run.stages.count("wild")
        n_event = sum(bt.kind == "stage_event" for bt in run.battles)
        trainer = [bt for bt in run.battles if bt.trainer]
        check("trainer battles", len(trainer), 1 + 8 * 10 + 5 + 4 + 1 - 5 * n_wild + n_event)
        leaders = [bt for bt in run.battles if bt.kind == "leader"]
        check("leader counts", [bt.count for bt in leaders], [10 * r for r in range(1, 9)])
        for r, bt in enumerate(leaders, 1):
            want = g.knobs[f"GYM_R{r}_BASE"] + (g.knobs[f"GYM_R{r}_MONS"] - 1) * g.knobs[f"GYM_R{r}_STEP"]
            check(f"leader r{r} ace level", bt.mons[-1][1], want)
            check(f"leader r{r} size", len(bt.mons), g.knobs[f"GYM_R{r}_MONS"])
        check("e4 counts", [bt.count for bt in run.battles if bt.kind == "e4"], [86, 87, 88, 89])
        check("no specials on route 1", run.offers[0], "none")
        for bt in run.battles:
            if bt.kind in ("route", "route_final", "gym_trainer", "gym_final"):
                idx, rem = min(bt.count, 89) // 10, min(bt.count, 89) % 10
                blk = (g.tables.route if rem < 6 else g.tables.gym)[idx]
                lo = blk.min_level + (blk.final_bonus if rem in (5, 9) else 0)
                hi = lo + max(blk.level_range - 1, 0)
                if not all(lo <= lv <= hi for _, lv in bt.mons):
                    fails.append(f"roster levels out of band at count {bt.count}: {bt.mons} vs {lo}-{hi}")
                    break
        if fails:
            break

    # Reproducibility: same seed, same run.
    a = simulate(g, Config(), 1, seed=3)[0]
    b2 = simulate(g, Config(), 1, seed=3)[0]
    check("seeded reproducibility", [bt.mons for bt in a.battles], [bt.mons for bt in b2.battles])

    # SpecialKindForced counts OFFERS, not visits, and it cannot keep both
    # "min 2 per run" promises: a run reaching route 8 short one of EACH has both
    # forced on one visit, and .chooseKind's tie-break drops one. What does hold
    # is at least one of each kind.
    for run in simulate(g, Config(take_wild=0.0), runs, seed=11):
        wild = sum(o.startswith("wild") for o in run.offers)
        mini = run.offers.count("miniboss")
        if wild < 1 or mini < 1:
            fails.append(f"a run was offered no wild area or no mini-boss: {run.offers}")
            break
    return fails


# =============================================================================
# CLI
# =============================================================================

def apply_overrides(g: GameData, sets: list[str]) -> GameData:
    knobs = dict(g.knobs)
    for s in sets:
        key, _, value = s.partition("=")
        if key not in knobs:
            raise SystemExit(f"--set: unknown knob {key!r} (not a DEF in balance_constants.asm)")
        knobs[key] = parse._int(value)
    return replace(g, knobs=knobs)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--runs", type=int, default=1000)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--difficulty", choices=DIFFICULTIES, default="normal")
    ap.add_argument("--exp-all", default="0", help="off, or key-item tier 0-3")
    ap.add_argument("--policy", choices=("carry", "rotate"), default="carry")
    ap.add_argument("--take-wild", type=float, default=0.5)
    ap.add_argument("--take-miniboss", type=float, default=1.0)
    ap.add_argument("--wild-steps", type=int, default=250)
    ap.add_argument("--amulet-coin", type=int, default=0, choices=(0, 1, 2, 3))
    ap.add_argument("--groups", default="KANTO", help="comma list: KANTO,JOHTO,WARP")
    ap.add_argument("--set", action="append", default=[], metavar="KNOB=VALUE")
    ap.add_argument("--selfcheck", action="store_true")
    ap.add_argument("--trace", action="store_true", help="print one run's battles (seed --seed)")
    args = ap.parse_args(argv)

    g = apply_overrides(parse.load_all(), args.set)
    if args.selfcheck:
        fails = selfcheck(g, args.runs)
        for f in fails:
            print("FAIL", f)
        print(f"selfcheck: {'OK' if not fails else f'{len(fails)} failure(s)'}")
        if fails:
            return 1

    cfg = Config(
        difficulty=args.difficulty,
        exp_all=None if args.exp_all == "off" else int(args.exp_all),
        groups=tuple(x.strip().upper() for x in args.groups.split(",")),
        take_wild=args.take_wild,
        take_miniboss=args.take_miniboss,
        wild_steps=args.wild_steps,
        policy=args.policy,
        amulet_coin=args.amulet_coin,
    )
    if args.trace:
        sim = Simulator(g, cfg, args.seed * 100003)
        run = sim.simulate()
        print("stages:", " ".join(run.stages), "| rival starter:", sim.rival_starter)
        for bt in run.battles:
            mons = ", ".join(f"{sp} L{lv}" for sp, lv in bt.mons)
            print(f"  count {bt.count:3d} {bt.kind:12s} money {money_for(g, bt, cfg.amulet_coin):6d}  {mons}")
        return 0
    runs = simulate(g, cfg, args.runs, args.seed)
    print(format_round_table(summarize(g, runs), cfg))
    return 0


if __name__ == "__main__":
    sys.exit(main())
