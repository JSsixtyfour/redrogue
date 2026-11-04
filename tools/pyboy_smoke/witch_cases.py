"""The witch matrix, one function per row of WITCH_AUTOPLAY_SOL_PLAN_2026-11-04.md.

Expected numbers come from WITCH_AUTOPLAY_EXPECTATIONS_2026-11-04.md, written from
the source before any of these ran. A case states what it must observe, on each
branch, and proves it reached the event: see Run.must_reach.
"""
from __future__ import annotations

from autoplay import ROOT
from source_constants import parse_map_constants
from witch_autoplay import RAM, Case, Context, Mon, Run, bcd

MAPS = parse_map_constants(ROOT / "constants/map_constants.asm")


def lifecycle_settlement(run: Run, *, prize: int, before: list[int]) -> None:
    """After the zone: the promised bit and nothing else, on accept; no change on
    decline; the bargain closed either way; the player still in control."""
    bit = prize - 1
    expected = list(before)
    if run.branch == "accept" and run.accepted_at_entry:
        expected[bit // 8] |= 1 << (bit % 8)
    run.check("earned bytes after settlement", expected, run.earned)
    run.check("accepted flag cleared by the lobby", False, run.accepted)
    run.control_check("after settlement")


def talk_and_verify(run: Run, quote: str | None = None) -> list[int]:
    """The offer, the quote and the branch's effect on the bargain, before any stage."""
    before = run.earned
    party = run.party_snapshot()
    run.talk()
    said = list(run.agent.transcript)  # a copy: the transcript keeps growing
    run.require("witch dialogue reached", bool(said), said)
    if quote is not None:
        run.require(f"quote shows {quote!r}", run.transcript_has(quote), said)
    run.check("accepted flag matches the answer", run.branch == "accept", run.accepted)
    run.check("earned bytes untouched by the talk", before, run.earned)
    run.check("party untouched by the talk", party, run.party_snapshot())
    run.accepted_at_entry = run.accepted
    return before


# ---- 3 No battle money -------------------------------------------------------

def c03(run: Run) -> None:
    h = run.h
    wins: list[dict[str, int]] = []

    def before_modifiers(_context) -> None:
        wins.append({"base": bcd(h.read_bytes("wAmountMoneyWon", 3)), "wallet_before": run.money})

    def wallet_add(_context) -> None:
        # MoneyForWinningText's AddBCD has not run yet: what the player is told.
        if wins and "told" not in wins[-1]:
            wins[-1]["told"] = bcd(h.read_bytes("wAmountMoneyWon", 3))

    h.register_hook("WitchApplyMoneyEffects", before_modifiers)
    h.register_hook("WitchApplyMoneyEffects.checkBridgeMoney", wallet_add)
    before = talk_and_verify(run, "No money from")
    start_wallet = run.money
    run.play_zone()
    run.must_reach("a paying trainer beaten", any(w["base"] for w in wins))
    run.notes.append(f"wins {wins}")
    for win in wins:
        told = win.get("told", -1)
        run.check("payout after the challenge", 0 if run.branch == "accept" else win["base"], told)
    expected_gain = sum(w["told"] for w in wins)
    run.check("wallet moved only by the payouts", expected_gain, run.money - start_wallet)
    lifecycle_settlement(run, prize=run.case.prize, before=before)


# ---- 7 Party limit -----------------------------------------------------------

def c07(run: Run, *, door: int = 0, size_over_limit: int = 0) -> None:
    h = run.h
    limit = h.read8("wPartyLimit")
    checks = h.hook_flag("WitchCheckPartyLimit")
    run.must_reach("party fixture matches the requested size",
                   h.read8("wPartyCount") == limit + size_over_limit)
    run.agent.forced_door = door
    before = talk_and_verify(run, f"with at most {limit}")
    transcript_before = len(run.agent.transcript)
    start_map = h.read8("hCurMap")

    def left_lobby() -> bool:
        return h.read8("hCurMap") != start_map

    frames = h.pyboy.frame_count + 8000
    while not left_lobby() and h.pyboy.frame_count < frames:
        run.agent.step()
    run.must_reach("a lobby stage door was taken", left_lobby())
    run.check("party check ran once at the door", 1, checks["count"])
    failed = any("CHALLENGE FAILED" in line for line in run.agent.transcript[transcript_before:])
    broke = run.branch == "accept" and size_over_limit > 0
    run.check("failure text shown", broke, failed)
    if broke:
        run.require(f"failure text quotes {limit}", run.transcript_has(f"than {limit}"),
                    list(run.agent.transcript[transcript_before:]))
    run.check("bargain state after the door", run.branch == "accept" and not broke, run.accepted)
    run.accepted_at_entry = run.accepted
    # Gain a Pokemon after a legal entry is covered by the stage reward below when
    # one is offered; the settlement still has to be correct either way.
    party_at_entry = h.read8("wPartyCount")
    run.play_zone()
    run.notes.append(f"party {party_at_entry} at entry, {h.read8('wPartyCount')} at settlement")
    lifecycle_settlement(run, prize=run.case.prize, before=before)


def _c07_legal(run: Run) -> None:
    c07(run, size_over_limit=0)


def _c07_broken(run: Run) -> None:
    c07(run, size_over_limit=1)


def _c07_broken_door2(run: Run) -> None:
    c07(run, door=1, size_over_limit=1)


# ---- 13 Gambler's Paradise -------------------------------------------------------

def c13(run: Run, *, door: int = 0) -> None:
    h = run.h
    doors_before = [h.read8("wLobbyDoor1StageMap"), h.read8("wLobbyDoor2StageMap")]
    run.agent.forced_door = door
    before = talk_and_verify(run, "PARADISE")
    doors = [h.read8("wLobbyDoor1StageMap"), h.read8("wLobbyDoor2StageMap")]
    corner = MAPS["GAME_CORNER"]
    run.check("doors after the answer", [corner, corner] if run.branch == "accept" else doors_before, doors)
    won = h.hook_flag("TrainerBattleVictory")
    # Only a sight-line battle runs table row 1, a talk-started one skips to row 2.
    # Row 1 repeats every frame while the trainer walks up, and the zone goes on past
    # Game Corner, so count distinct trainers on this map, not hook firings.
    spotted: set[int] = set()
    corner_battles: list[int] = []

    def row_one(_context) -> None:
        if h.read8("hCurMap") == corner:
            # Not hSpriteIndex, which the sprite loop reuses during the walk-up.
            spotted.add(h.read8("wTrainerHeaderFlagBit"))

    def battle(_context) -> None:
        if h.read8("hCurMap") == corner:
            corner_battles.append(h.read8("hSpriteIndex"))

    h.register_hook("DisplayEnemyTrainerTextAndStartBattle", row_one)
    h.register_hook("StartTrainerBattle", battle)
    run.play_zone()
    run.must_reach("a trainer beaten in the zone", won["count"] > 0)
    run.notes.append(f"Gamblers that spotted the player {sorted(spotted)}, Game Corner battles {corner_battles}")
    if run.branch == "accept":
        run.must_reach("a Gambler spotted the player", bool(spotted))
        run.require("every sight-line battle has a Gambler slot", spotted <= {2, 3, 4, 5}, sorted(spotted))
        run.check("each Gambler fought once", sorted(set(corner_battles)), sorted(corner_battles))
    lifecycle_settlement(run, prize=run.case.prize, before=before)


def _c13_door2(run: Run) -> None:
    c13(run, door=1)


# ---- Prize 3 Money: the shape for a permanent prize. Earn it, then use it next zone. -

def p03(run: Run) -> None:
    h = run.h
    wins: list[dict[str, int]] = []

    def base(_context) -> None:
        wins.append({"base": bcd(h.read_bytes("wAmountMoneyWon", 3))})

    def after_prize(_context) -> None:
        if wins:
            wins[-1]["told"] = bcd(h.read_bytes("wAmountMoneyWon", 3))

    h.register_hook("WitchApplyMoneyEffects", base)
    h.register_hook("WitchApplyMoneyEffects.checkBridgeMoney", after_prize)
    before = talk_and_verify(run)
    run.play_zone()
    zone1 = list(wins)
    wins.clear()
    for win in zone1:
        run.check("no benefit before settlement", win["base"], win["told"])
    lifecycle_settlement(run, prize=run.case.prize, before=before)
    start_wallet = run.money
    run.play_zone()
    run.must_reach("a paying trainer beaten after settlement", any(w["base"] for w in wins))
    run.notes.append(f"zone 2 wins {wins}")
    owned = run.branch == "accept"
    for win in wins:
        run.check("payout through the consumer", win["base"] + win["base"] // 10 if owned else win["base"],
                  win["told"])
    run.check("wallet delta equals the payouts", sum(w["told"] for w in wins), run.money - start_wallet)
    run.control_check("after the prize's zone")


# ---- Prize 5 Crits: the shape for a boundary draw replayed at its consumer. -------

def _ror3(value: int) -> int:
    return ((value >> 3) | (value << 5)) & 0xFF  # CriticalHitTest does rlc a x3


def p05(run: Run) -> None:
    h = run.h
    before = talk_and_verify(run)
    run.play_zone()
    lifecycle_settlement(run, prize=run.case.prize, before=before)

    rolls: list[dict[str, int]] = []
    pending: list[dict[str, int]] = []

    def base_threshold(_context) -> None:
        pending[:] = [{"whose": h.read8("hWhoseTurn"), "base": h.pyboy.register_file.E}]

    def replay(_context) -> None:
        if not pending:
            return
        registers = h.pyboy.register_file
        row = pending[0]
        row["adjusted"] = registers.B
        # Alternate the two sides. The unmodified threshold sits inside the window
        # the prize adds; the adjusted threshold is the first roll past it.
        row["roll"] = row["base"] if len(rolls) % 2 == 0 else row["adjusted"]
        registers.A = _ror3(row["roll"])
        rolls.append(row)
        pending.clear()

    def damage(_context) -> None:
        if rolls and "crit" not in rolls[-1]:
            rolls[-1]["crit"] = h.read8("wCriticalHitOrOHKO")

    menus = {"held": 0}

    def hold_the_enemy_up(_context) -> None:
        # Enemy control: it must live long enough to attack, so a roll lands on its
        # turn too. Status-only movesets take a while; the cap keeps a battle finite.
        if any(row["whose"] for row in rolls) or menus["held"] >= 40:
            return
        menus["held"] += 1
        h.write8("wEnemyMonHP", 3)
        h.write8("wEnemyMonMaxHP", 3)

    h.register_hook("BridgeAdjustCriticalThreshold", base_threshold)
    run.hook_after_call("CriticalHitTest.rollCrit", "BattleRandom", replay)
    h.register_hook("CalculateDamage", damage)
    h.register_hook("DisplayBattleMenu", hold_the_enemy_up)
    run.log_intervention("replay", draw="crit roll alternates unmodified threshold / adjusted threshold",
                         where="CriticalHitTest.rollCrit")
    run.log_intervention("setup", enemy="HP held at 768+ until the enemy has rolled once, at most 40 menus")
    run.play_zone()
    run.notes.append(f"rolls {rolls[:12]}")
    player = [r for r in rolls if not r["whose"] and "crit" in r and r["base"] >= 4]
    enemy = [r for r in rolls if r["whose"] and "crit" in r]
    window = [r for r in player if r["roll"] == r["base"]]
    past = [r for r in player if r["roll"] == r["adjusted"]]
    run.must_reach("a player roll inside the window", bool(window))
    run.must_reach("a player roll past the threshold", bool(past))
    run.must_reach("an enemy control roll", bool(enemy))
    owned = run.branch == "accept"
    for row in player:
        expected = min(255, row["base"] + row["base"] // 4) if owned else row["base"]
        run.check("player threshold", expected, row["adjusted"])
    for row in window:
        run.check("roll at the old threshold crits only with the prize", 1 if owned else 0, row["crit"])
    for row in past:
        run.check("roll at the threshold itself does not crit", 0, row["crit"])
    for row in enemy:
        run.check("enemy threshold unchanged", row["base"], row["adjusted"])
        run.check("the prize never helps the enemy", 0, row["crit"])
    run.control_check("after the prize's zone")


# ---- 12 Recoil: the shape for forcing moves and measuring per-turn HP deltas. ------

def c12(run: Run) -> None:
    h = run.h
    turns: list[dict[str, int]] = []
    recoils: list[dict[str, int]] = []
    menu_count = {"n": 0}

    def choose(agent) -> int:
        menu_count["n"] += 1
        return 1 if menu_count["n"] % 3 == 1 else 0  # a status move, then damaging ones

    def post_move(_context) -> None:
        turns.append({"damage": bcd2(h, "wDamage"), "state": h.read8("wBridgeRepeatState"),
                      "hp": bcd2(h, "wBattleMonHP"), "enemy_hp": bcd2(h, "wEnemyMonHP"),
                      "move": h.read8("wPlayerSelectedMove")})

    def self_damage(_context) -> None:
        registers = h.pyboy.register_file
        recoils.append({"amount": registers.B << 8 | registers.C, "hp": bcd2(h, "wBattleMonHP")})

    def after_damage(_context) -> None:
        recoils[-1]["after"] = bcd2(h, "wBattleMonHP")

    run.agent.move_policy = choose
    h.register_hook("HandlePostPlayerMoveWitchEffects", post_move)
    h.register_hook("ApplyWitchSelfDamage", self_damage)
    h.register_hook("ApplyWitchSelfDamage.updateBar", after_damage)
    before = talk_and_verify(run, "Every hit you")
    run.play_zone()
    run.notes.append(f"turns {turns[:8]}")
    damaging = [t for t in turns if t["damage"]]
    harmless = [t for t in turns if not t["damage"]]
    run.must_reach("a damaging move used", bool(damaging))
    run.must_reach("a status move used", bool(harmless))
    if run.branch == "accept":
        run.check("one recoil per damaging move", len(damaging), len(recoils))
        for turn, recoil in zip(damaging, recoils):
            run.check("recoil is a quarter of the damage, minimum 1", max(1, turn["damage"] // 4), recoil["amount"])
            run.check("HP fell by the recoil", max(0, recoil["hp"] - recoil["amount"]), recoil["after"])
    else:
        run.check("no recoil when declined", [], recoils)
    lifecycle_settlement(run, prize=run.case.prize, before=before)


def bcd2(h, label: str) -> int:
    """A big-endian 2-byte binary value (the name is historical to this file's reads)."""
    return h.read8(label) << 8 | h.read8(label, 1)


# ---- Save and Continue: the shape for persistence through a real save. ------------

def s01(run: Run) -> None:
    before = talk_and_verify(run)
    saved, loaded = run.save_and_continue()
    run.notes.append(f"saved {saved}")
    run.check("bargain state survives Save and CONTINUE", saved, loaded)
    run.check("accepted flag matches the answer after CONTINUE", run.branch == "accept", run.accepted)
    run.control_check("after CONTINUE")
    run.play_zone()
    lifecycle_settlement(run, prize=run.case.prize, before=before)


def _selftest_fail(run: Run) -> None:
    """Must end gameplay_fail with a full bundle: proves failure capture works."""
    talk_and_verify(run)
    run.check("deliberately wrong expectation", "this cannot match", run.earned)


def _selftest_not_reached(run: Run) -> None:
    """Must end not_reached: an event that never happens is uncovered, not passed."""
    talk_and_verify(run)
    run.must_reach("an event that cannot occur", False)


C = RAM
PILOT_PRIZE = C["PRIZE_MONEY"]
# Round 3's route: the quote is 3, large enough to hold a useful strong party.
ROUND3 = 2 * C.get("ROUND_BATTLES", 8) + 1


def party(size: int) -> tuple[Mon, ...]:
    species = ("TAUROS", "ALAKAZAM", "RHYDON", "ARCANINE", "GYARADOS", "JOLTEON")
    return tuple(Mon(name) for name in species[:size])


CASES = {case.id: case for case in (
    Case("C03", "No battle money", C["CHALLENGE_NO_MONEY"], PILOT_PRIZE, c03,
         Context(battle_count=1, gym_next=False)),
    Case("C07L", "Party limit, exactly the quote, door 1", C["CHALLENGE_PARTY_LIMIT"], C["PRIZE_RARITY_ITEM"],
         _c07_legal, Context(battle_count=ROUND3, gym_next=False, party=party(3))),
    Case("C07B1", "Party limit, one extra, door 1", C["CHALLENGE_PARTY_LIMIT"], C["PRIZE_RARITY_ITEM"],
         _c07_broken, Context(battle_count=ROUND3, gym_next=False, party=party(4))),
    Case("C07B2", "Party limit, one extra, door 2", C["CHALLENGE_PARTY_LIMIT"], C["PRIZE_RARITY_ITEM"],
         _c07_broken_door2, Context(battle_count=ROUND3, gym_next=False, party=party(4))),
    Case("C13D1", "Gambler's Paradise, door 1", C["CHALLENGE_GAMBLERS_PARADISE"], C["PRIZE_RARITY_ITEM"], c13,
         Context(battle_count=33, gym_next=False, badges=0x0F)),
    Case("C13D2", "Gambler's Paradise, door 2", C["CHALLENGE_GAMBLERS_PARADISE"], C["PRIZE_RARITY_ITEM"], _c13_door2,
         Context(battle_count=33, gym_next=False, badges=0x0F)),
    Case("C12", "Recoil on every hit", C["CHALLENGE_RECOIL_ATTACKS"], C["PRIZE_RARITY_ITEM"], c12,
         Context(battle_count=1, gym_next=False, party=(
             Mon("TAUROS", moves=("STOMP", "GROWL", "HEADBUTT"), pp=(20, 40, 15)),
             Mon("ALAKAZAM", moves=("PSYBEAM", "GROWL", "HEADBUTT"), pp=(20, 40, 15))))),
    Case("P03", "Prize: money, earned then used", C["CHALLENGE_SLOWED_POKEMON"], C["PRIZE_MONEY"], p03,
         Context(battle_count=1, gym_next=False)),
    Case("P05", "Prize: crit threshold, boundary replay", C["CHALLENGE_SLOWED_POKEMON"], C["PRIZE_CRIT_BOOST"], p05,
         Context(battle_count=1, gym_next=False)),
    Case("S01", "Save and CONTINUE right after the offer", C["CHALLENGE_NO_MONEY"], C["PRIZE_MONEY"], s01,
         Context(battle_count=1, gym_next=False)),
    Case("SELFFAIL", "Self-test: a failing check must produce a bundle", C["CHALLENGE_NO_MONEY"], PILOT_PRIZE,
         _selftest_fail, Context(battle_count=1, gym_next=False)),
    Case("SELFNR", "Self-test: an unreached event must not pass", C["CHALLENGE_NO_MONEY"], PILOT_PRIZE,
         _selftest_not_reached, Context(battle_count=1, gym_next=False)),
)}

# Runner self-tests, excluded from a default campaign and from the gate.
SELF_TESTS = ("SELFFAIL", "SELFNR")
MATRIX = tuple(case_id for case_id in CASES if case_id not in SELF_TESTS)
