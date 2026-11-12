"""The witch matrix, one function per row of WITCH_AUTOPLAY_SOL_PLAN_2026-11-04.md.

Expected numbers come from WITCH_AUTOPLAY_EXPECTATIONS_2026-11-04.md, written from
the source before any of these ran. A case states what it must observe, on each
branch, and proves it reached the event: see Run.must_reach.
"""
from __future__ import annotations

from autoplay import ROOT
from source_constants import parse_map_constants, parse_rgbds_constants, parse_trainer_class_indexes
from witch_autoplay import (ANSWERS, MON_PP, MOVES as MOVES_BY_NAME, PARTY_STRUCT, RAM, Case, Context, Mon, Run, bcd,
                            steer_offer)

MAPS = parse_map_constants(ROOT / "constants/map_constants.asm")
SPECIAL_TYPE = 0x14  # SPECIAL in constants/type_constants.asm: types from here up are special


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
    after = run.party_snapshot()
    if any(status & 0x08 for status in party["status"]):
        # A poisoned member loses HP on the walk to her; that is the walk, not the talk.
        party, after = dict(party, hp=None), dict(after, hp=None)
    run.check("party untouched by the talk", party, after)
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
    enemy_moves = h.hook_flag("ExecuteEnemyMove")
    player_moves = h.hook_flag("ExecutePlayerMove")

    def hold_the_enemy_up(_context) -> None:
        # Enemy control: it must live long enough to attack, so a roll lands on its
        # turn too. Status-only movesets take a while; the cap keeps a battle finite.
        if any(row["whose"] for row in rolls) or menus["held"] >= 150 or enemy_moves["count"] >= 8:
            return
        menus["held"] += 1
        h.write8("wEnemyMonHP", 0x0F)
        h.write8("wEnemyMonMaxHP", 0x0F)

    h.register_hook("BridgeAdjustCriticalThreshold", base_threshold)
    run.hook_after_call("CriticalHitTest.rollCrit", "BattleRandom", replay)
    h.register_hook("CalculateDamage", damage)
    h.register_hook("DisplayBattleMenu", hold_the_enemy_up)
    run.log_intervention("replay", draw="crit roll alternates unmodified threshold / adjusted threshold",
                         where="CriticalHitTest.rollCrit")
    run.log_intervention("setup", enemy="HP held at 3840+ until the enemy has rolled once, at most 150 menus or 8 enemy moves")
    run.play_zone()
    run.notes.append(f"menus held {menus['held']}, player moves {player_moves['count']}, "
                     f"enemy moves {enemy_moves['count']}")
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


# ---- Shared battle helpers ---------------------------------------------------------

def at_stage_door(run: Run, action) -> None:
    """Run `action` once, as the player leaves the lobby through a stage door. The
    nurse has already healed the party by then, so state staged earlier is lost."""
    h, lobby, done = run.h, run.agent.lobby_map, {"yes": False}

    def door(_context) -> None:
        if (not done["yes"] and h.read8("wWarpedFromWhichMap") == lobby
                and h.read8("wWarpedFromWhichWarp") in (2, 3)):
            done["yes"] = True
            action()

    h.register_hook("WitchCheckPartyLimit", door)


def hold_enemy(run: Run, *, menus_up: int = 6, refill_from: int | None = 1) -> dict[str, int]:
    """Keep the enemy alive for `menus_up` battle menus of each battle, then leave it
    at 1 HP. The active mon's HP is topped up at every menu so a long battle cannot
    black out. Counters: menus (this battle), battles. Always logged as setup."""
    h = run.h
    state = {"menus": 0, "battles": 0}

    def new_battle(_context) -> None:
        state["menus"] = 0
        state["battles"] += 1

    def menu(_context) -> None:
        state["menus"] += 1
        h.write8("wBattleMonHP", h.read8("wBattleMonMaxHP"))
        h.write8("wBattleMonHP", h.read8("wBattleMonMaxHP", 1), offset=1)
        if refill_from is not None and state["battles"] >= refill_from:
            for slot in range(4):
                if h.read8("wBattleMonMoves", slot):
                    h.write8("wBattleMonPP", 30, offset=slot)
        if state["menus"] <= menus_up:
            for label in ("wEnemyMonHP", "wEnemyMonMaxHP"):
                h.write8(label, 0x0F)
                h.write8(label, 0, offset=1)
        else:
            h.write8("wEnemyMonHP", 0)
            h.write8("wEnemyMonHP", 1, offset=1)

    h.register_hook("StartBattle", new_battle)
    h.register_hook("DisplayBattleMenu", menu)
    # When the enemy swaps mons the raised HP can outlive the old max for one menu: the
    # agent's battle check calls that an anomaly, but this hold made it.
    run.expected_anomaly_prefixes.append("enemy's active mon HP")
    run.log_intervention("setup", enemy=f"HP held at 3840 for {menus_up} menus of each battle, then 1",
                         player="active mon HP topped up at every menu"
                                + (f", battle PP refilled to 30 from battle {refill_from}" if refill_from else ""))
    return state


# ---- 14 Same move penalty ----------------------------------------------------------

def c14(run: Run) -> None:
    h = run.h
    pattern = [0, 0, 1, 0, 0, 2, 2, 1]          # A A B A A C C B
    state = hold_enemy(run, menus_up=len(pattern) + 1)
    run.agent.move_policy = lambda agent: pattern[(state["menus"] - 1) % len(pattern)]
    battles: dict[int, list[dict[str, object]]] = {}
    penalties = h.hook_flag("HandlePostPlayerMoveWitchEffects.sameMoveApply")

    def post(_context) -> None:
        row = {"state": h.read8("wBridgeRepeatState"), "move": h.read8("wPlayerSelectedMove"),
               "penalty_calls": penalties["count"], "menu": state["menus"]}
        battles.setdefault(state["battles"], []).append(row)

    h.register_hook("HandlePostPlayerMoveWitchEffects", post)
    run.log_intervention("setup", policy="move slots A A B A A C C B")
    before = talk_and_verify(run, "Repeat a move")
    run.play_zone()
    first = battles.get(1, [])
    run.notes.append(f"battle 1 {first}")
    run.must_reach("a battle of at least five turns", len(first) >= 5)
    # A row is captured on entry to the hook, before that turn's penalty applies, so the
    # turn's penalty is the count change seen by the next row.
    # The rule, on whatever the turns turned out to be: a repeat is the same move as the last
    # turn that acted. State 0 is a lost action (full paralysis, a flinch), which clears the
    # streak and draws no penalty.
    counts = [row["penalty_calls"] for row in first] + [None]
    previous = None
    repeated = 0
    for index, row in enumerate(first[:-1]):
        lost = row["state"] == 0
        repeat = not lost and row["move"] == previous
        repeated += repeat
        run.check(f"turn {index + 1}: repeat penalty", repeat and run.branch == "accept",
                  counts[index + 1] > row["penalty_calls"])
        if not lost:
            run.check(f"turn {index + 1}: repeat state", 2 if repeat else 1, row["state"])
        previous = None if lost else row["move"]
    run.must_reach("a repeated move", repeated > 0)
    if len(battles) >= 2:
        run.check("a fresh battle starts without a streak", False, battles[2][0]["state"] == 2)
    lifecycle_settlement(run, prize=run.case.prize, before=before)


# ---- 16 / 17 Typed recoil ----------------------------------------------------------

def c1617(run: Run, mode: str) -> None:
    """Challenges 12 (mode any), 16 (physical) and 17 (special): one quarter-damage recoil
    for each damaging move of the matching class, none for status moves."""
    h = run.h
    state = hold_enemy(run, menus_up=9)
    run.agent.move_policy = lambda agent: (state["menus"] - 1) % 3     # STOMP, PSYBEAM, GROWL

    def sturdy() -> None:
        # Damage here runs to four digits, so a quarter-damage recoil outweighs a normal
        # HP bar. Give every member 999 HP at the stage door (the cap), so a long fight
        # is measured instead of ending in a blackout.
        for index in range(h.read8("wPartyCount")):
            base = index * PARTY_STRUCT
            for label, offset in (("wPartyMon1HP", base + 0), ("wPartyMon1MaxHP", base + 0)):
                h.write8(label, 999 >> 8, offset=offset)
                h.write8(label, 999 & 0xFF, offset=offset + 1)
        run.log_intervention("setup", party_hp="every member's HP and max HP set to 999 at the stage door")

    at_stage_door(run, sturdy)
    turns: list[dict[str, int]] = []
    recoils: list[int] = []

    def post(_context) -> None:
        turns.append({"type": h.read8("wPlayerMoveType"), "damage": bcd2(h, "wDamage"),
                      "state": h.read8("wBridgeRepeatState"), "recoils": len(recoils),
                      "enemy_hp": bcd2(h, "wEnemyMonHP"), "own_hp": bcd2(h, "wBattleMonHP"),
                      "missed": h.read8("wMoveMissed"), "move": h.read8("wPlayerSelectedMove"),
                      "power": h.read8("wPlayerMovePower")})

    def recoil(_context) -> None:
        registers = h.pyboy.register_file
        recoils.append(registers.B << 8 | registers.C)

    h.register_hook("HandlePostPlayerMoveWitchEffects", post)
    h.register_hook("ApplyWitchSelfDamage", recoil)
    before = talk_and_verify(run, {"any": "Every hit you", "special": "SPC moves", "physical": "ATK moves"}[mode])
    try:
        run.play_zone()
    finally:
        run.notes.append(f"turns {turns[:9]} recoils {recoils[:9]}")
    run.notes.append("compact turns (index, type, damage, recoil count before, enemy hp, move): "
                     + " ".join(f"{i+1}:{t['type']:02x}:{t['damage']}:{t['recoils']}:{t['enemy_hp']}:{t['move']}"
                                for i, t in enumerate(turns)))
    run.notes.append(f"recoil amounts {recoils}")
    # A status move leaves the previous hit's number in wDamage, so only a move with power
    # that dealt damage counts as damaging.
    for turn in turns:
        # wBridgeRepeatState is 0 when the player lost its action; wDamage is then the enemy's.
        turn["hit"] = bool(turn["power"] and turn["damage"] and not turn["missed"] and turn["state"])
        turn["struggle"] = turn["move"] == 255      # Struggle has its own recoil; out of scope here
    kinds = {t["type"] >= SPECIAL_TYPE for t in turns if t["hit"]}
    run.must_reach("a physical and a special damaging move landed", kinds == {True, False})
    run.must_reach("a status move used", any(not t["power"] for t in turns))
    last = 0
    # Each turn's recoil is recorded after its post hook, so compare with the next row.
    for index, turn in enumerate(turns):
        after = turns[index + 1]["recoils"] if index + 1 < len(turns) else len(recoils)
        gained = after - turn["recoils"]
        if turn["struggle"]:
            last += gained          # Struggle's recoil still lands in the list
            continue
        special = turn["type"] >= SPECIAL_TYPE
        charged = (turn["hit"] and run.branch == "accept"
                   and (mode == "any" or special == (mode == "special")))
        run.check(f"turn {index + 1} (type {turn['type']:02x}, damage {turn['damage']}): recoil count",
                  1 if charged else 0, gained)
        if charged:
            run.check(f"turn {index + 1}: recoil is damage / 4", max(1, turn["damage"] // 4), recoils[last])
        last += gained
    lifecycle_settlement(run, prize=run.case.prize, before=before)


def _c12(run: Run) -> None:
    c1617(run, "any")


def _c16(run: Run) -> None:
    c1617(run, "physical")


def _c17(run: Run) -> None:
    c1617(run, "special")


# ---- 18 Double PP ------------------------------------------------------------------

def c18(run: Run) -> None:
    h = run.h
    # Slot PP at the door: 3, 2 with a PP Up bit, 1. Policy: slot 0 twice, then 1, then 2.
    pattern = [0, 0, 1, 2]
    state = hold_enemy(run, menus_up=6, refill_from=2)
    run.agent.move_policy = lambda agent: (
        pattern[state["menus"] - 1] if state["battles"] == 1 and state["menus"] <= len(pattern) else 3)
    battle_pp: list[list[int]] = []
    party_pp: list[list[int]] = []
    enemy_pp: list[int] = []

    def stage() -> None:
        for slot, value in enumerate((3, 2 | 0x40, 1, 30)):
            h.write8("wPartyMon1", value, offset=MON_PP + slot)
        run.log_intervention("setup", pp=(3, "2 with a PP Up bit", 1, 30))

    def menu(_context) -> None:
        if state["battles"] == 1:
            battle_pp.append(h.read_bytes("wBattleMonPP", 4))
            party_pp.append([h.read8("wPartyMon1", MON_PP + s) for s in range(4)])
            enemy_pp.append(sum(v & 0x3F for v in h.read_bytes("wEnemyMonPP", 4)))

    h.register_hook("DisplayBattleMenu", menu)
    at_stage_door(run, stage)
    before = talk_and_verify(run, "cost 2 PP")
    run.play_zone()
    run.notes.append(f"battle PP at menus {battle_pp[:6]}, party PP {party_pp[:6]}, enemy {enemy_pp[:6]}")
    run.must_reach("four menus in the first battle", len(battle_pp) >= 5)
    step = 2 if run.branch == "accept" else 1
    for index, slot in enumerate(pattern):
        now, then = battle_pp[index], battle_pp[index + 1]
        spent = (now[slot] & 0x3F) - (then[slot] & 0x3F)
        run.check(f"turn {index + 1}, slot {slot}: PP spent from {now[slot] & 0x3F}", min(step, now[slot] & 0x3F), spent)
        run.check(f"turn {index + 1}: PP Up bits kept", now[slot] & 0xC0, then[slot] & 0xC0)
        run.check(f"turn {index + 1}: party PP matches battle PP", then, party_pp[index + 1])
        run.require(f"turn {index + 1}: enemy spends at most one PP", enemy_pp[index] - enemy_pp[index + 1] <= 1,
                    (enemy_pp[index], enemy_pp[index + 1]))
    lifecycle_settlement(run, prize=run.case.prize, before=before)


# ---- Rarity draws: 4, prizes 1 and 2 ----------------------------------------------

CLASS_TABLES = ("RewardClassWidths", "RewardClassWidthsDown", "StageRewardClassWidths", "ItemClassWidths")


def spread_widths(bonus: int, cumulative: list[int]) -> list[int]:
    """The class widths RollSpreadClass leaves after draining `bonus`, from home/rarity_class.asm."""
    widths = [cum - (cumulative[i - 1] if i else 0) for i, cum in enumerate(cumulative)]
    n, left, band, above = len(widths), bonus, 0, len(widths)
    while left and above:
        take = min(widths[band], left)
        widths[band] -= take
        left -= take
        share = take // above
        for j in range(1, above):
            widths[band + j] += share
        band += 1
        above -= 1
    return widths


def spread_class(roll: int, bonus: int, cumulative: list[int]) -> int:
    total = 0
    for index, width in enumerate(spread_widths(bonus, cumulative)):
        total += width
        if roll < total:
            return index + 1
    return len(cumulative) + 1


def class_probe(run: Run) -> tuple[list[dict[str, object]], dict[str, int]]:
    """Hook RollSpreadClass: record every call, replace its roll with the next boundary
    value, and record the class the ROM returns. Rows carry the caller, the table's name,
    the bonus and a `zone` tag the case advances."""
    h = run.h
    rows: list[dict[str, object]] = []
    zone = {"n": 1}
    tables = {h.symbols.get(name)[1]: name for name in CLASS_TABLES}

    def entry(_context) -> None:
        registers = h.pyboy.register_file
        sp, hl = registers.SP, registers.HL
        ret = h.pyboy.memory[sp] | h.pyboy.memory[sp + 1] << 8
        bank = 0 if ret < 0x4000 else h.read8("hLoadedROMBank")
        count = h.pyboy.memory[hl]
        cumulative = [h.pyboy.memory[hl + 1 + i] for i in range(count)]
        bonus = registers.B
        widths_cum = [sum(spread_widths(bonus, cumulative)[:i + 1]) for i in range(count)]
        candidates = sorted({0, 255} | {c - 1 for c in widths_cum if c} | {c for c in widths_cum if c < 256})
        roll = candidates[len(rows) % len(candidates)]
        rows.append({"zone": zone["n"], "caller": str(h.symbols.nearest(bank, ret)), "bonus": bonus,
                     "table": tables.get(hl, f"{hl:04x}"), "cumulative": cumulative, "natural_roll": registers.A,
                     "roll": roll,
                     # The other rarity sources live at this draw, so the prize's share can be isolated.
                     "miniboss": bool(h.read8("wRogueFlagsBitfield") & (1 << RAM["BIT_MINIBOSS_ACTIVE"])),
                     "gym_item_bonus": h.read8("wItemBonusRarity")})
        registers.A = roll

    def done(_context) -> None:
        rows[-1]["class"] = h.pyboy.register_file.C

    h.register_hook("RollSpreadClass", entry)
    h.register_hook("RollSpreadClass.done", done)
    run.log_intervention("replay", draw="class roll replaced by the next boundary value of its band table",
                         where="RollSpreadClass entry")
    return rows, zone


def check_class_rows(run: Run, rows: list[dict[str, object]]) -> None:
    for row in rows:
        if "class" in row:
            run.check(f"{row['table']} bonus {row['bonus']} roll {row['roll']}: class",
                      spread_class(row["roll"], row["bonus"], row["cumulative"]), row["class"])


def c04(run: Run) -> None:
    rows, zone = class_probe(run)
    before = talk_and_verify(run, "Worse luck")
    run.play_zone()
    mons = [r for r in rows if str(r["caller"]).startswith("Random_Pokemon_Selection")]
    run.notes.append(f"pokemon rows {mons[:6]}")
    run.must_reach("three reward draws in the zone", len(mons) >= 3)
    owned = bool(before[0] & 1)
    if run.branch == "accept":
        want = ("RewardClassWidths", 0) if owned else ("RewardClassWidthsDown", 51)
    else:
        want = ("StageRewardClassWidths", 51) if owned else ("RewardClassWidths", 0)
    for row in mons:
        run.check("ladder and bonus", want, (row["table"], row["bonus"]))
    check_class_rows(run, rows)
    lifecycle_settlement(run, prize=run.case.prize, before=before)


def rarity_prize(run: Run, source: str) -> None:
    rows, zone = class_probe(run)
    before = talk_and_verify(run)
    prefix = ("Random_Pokemon_Selection",) if source == "pokemon" else ("Random_Item_Selection", "item_")
    run.play_zone()
    first = [r for r in rows if r["zone"] == 1 and str(r["caller"]).startswith(prefix)]
    lifecycle_settlement(run, prize=run.case.prize, before=before)
    zone["n"] = 2
    for _ in range(5):  # the gym is skipped over: its leader adds its own item bonus
        run.play_zone()
        zone["n"] = 3
        second = [r for r in rows if r["zone"] == 3 and str(r["caller"]).startswith(prefix)]
        if second:
            break
    second = [r for r in rows if r["zone"] == 3 and str(r["caller"]).startswith(prefix)]
    run.notes.append(f"{source} zone 1 {first[:4]} zone 2 {second[:4]}")
    run.must_reach("draws in zone 1", bool(first))
    run.must_reach("draws in zone 2", bool(second))
    owned = run.branch == "accept"
    for row in first:
        run.check("zone 1: no bonus before settlement", 0, row["bonus"])
    for row in second:
        # Other live sources: the mini-boss's +51 (both kinds) and, for items, the gym bonus.
        others = 51 * row["miniboss"] + (row["gym_item_bonus"] if source == "item" else 0)
        run.check(f"zone 2: prize adds 51 on top of the other sources ({others})",
                  min(255, others + (51 if owned else 0)), row["bonus"])
    check_class_rows(run, rows)
    run.control_check("after the prize's zone")


def _p01(run: Run) -> None:
    rarity_prize(run, "pokemon")


def _p02(run: Run) -> None:
    rarity_prize(run, "item")


# ---- 1 and 2 No reward Pokemon, no random item ------------------------------------

TOGGLES = parse_rgbds_constants(ROOT / "constants/toggle_constants.asm")
EVENT_IDS = parse_rgbds_constants(ROOT / "constants/event_constants.asm")


def toggle_hidden(h, name: str) -> bool:
    index = TOGGLES[name]
    return bool(h.read8("wToggleableObjectFlags", index // 8) >> (index % 8) & 1)


def c0102(run: Run, *, balls: bool) -> None:
    h = run.h
    lobby = run.agent.lobby_map
    ball_names = ("TOGGLE_ROGUE_REWARD_POKEBALL_1", "TOGGLE_ROGUE_REWARD_POKEBALL_2",
                  "TOGGLE_ROGUE_REWARD_POKEBALL_3", "TOGGLE_ROGUE_TRADE_NPC")
    watched = ball_names if balls else ("TOGGLE_STAGE_RANDOM_ITEM",)
    zone = {"n": 1}
    samples: list[tuple[int, tuple[bool, ...]]] = []

    refreshes = h.hook_flag("RogueRefresh")
    visit = {"map": None, "base": 0}
    menus = h.hook_flag("RogueRewardMenu")

    def poll(_context) -> None:
        current = h.read8("hCurMap")
        if current == lobby:
            visit["map"] = None
            return
        if visit["map"] != current:
            visit["map"], visit["base"] = current, refreshes["count"]
        # Polls before the stage's own RogueRefresh show the previous stage's flags.
        if refreshes["count"] > visit["base"]:
            state = tuple(toggle_hidden(h, name) for name in ball_names + ("TOGGLE_STAGE_RANDOM_ITEM",))
            if not samples or samples[-1][:2] != (zone["n"], state):
                samples.append((zone["n"], state, refreshes["count"], current))

    h.register_hook("JoypadOverworld", poll)
    party_before = h.read8("wPartyCount")
    before = talk_and_verify(run, "hands out" if balls else "No item in")
    run.play_zone()
    party_after = h.read8("wPartyCount")
    zone1_menus = menus["count"]  # the next zone may offer a reward: it has no bargain
    lifecycle_settlement(run, prize=run.case.prize, before=before)
    zone["n"] = 2
    for _ in range(5):  # gyms and wild-area stages have no RogueRefresh: play on to a route that does
        run.play_zone()
        if any(s[0] == 2 for s in samples):
            break
    run.notes.append(f"samples (zone, hidden flags, RogueRefresh count, map) {samples}")
    names = ball_names + ("TOGGLE_STAGE_RANDOM_ITEM",)
    index = [names.index(n) for n in watched]
    zone1 = [s[1] for s in samples if s[0] == 1]
    zone2 = [s[1] for s in samples if s[0] == 2]
    run.must_reach("object samples in both zones", bool(zone1) and bool(zone2))
    if run.branch == "accept":
        run.check("every watched object hidden throughout zone 1", True,
                  all(all(s[i] for i in index) for s in zone1))
        if balls:
            run.notes.append(f"RogueRewardMenu opened {zone1_menus} time(s) in zone 1, {menus['count']} in all")
            run.check("no reward menu opens in the zone", 0, zone1_menus)
            run.check("no reward Pokemon gained", party_before, party_after)
            # These gate the all-trainers offer and re-talking the last trainer.
            for event in ("EVENT_ROGUE_POKEMON_OFFERED", "EVENT_GOT_ROGUE_POKEMON"):
                flag = EVENT_IDS[event]
                run.check(f"{event} closed for the zone", 1, h.read8("wEventFlags", flag // 8) >> (flag % 8) & 1)
    else:
        run.must_reach("an unhidden watched object in zone 1", any(not all(s[i] for i in index) for s in zone1))
        if balls:
            run.must_reach("a reward Pokemon gained when declined", party_after > party_before)
    shown = [any(not s[i] for s in zone2) for i in index]
    if balls:
        run.check("next zone shows the reward balls again", True, shown[1] and shown[2])
    else:
        run.check("next zone shows the random item again", [True], shown)
    run.control_check("after the second zone")


def _c01(run: Run) -> None:
    c0102(run, balls=True)


def _c02(run: Run) -> None:
    c0102(run, balls=False)


# ---- Prize 4 EXP -------------------------------------------------------------------

def _earn_then_use(run: Run, before: list[int], zones: int = 2) -> None:
    """Zone 1 earns the prize (settled by the lobby), then `zones` more zones use it."""
    run.play_zone()
    lifecycle_settlement(run, prize=run.case.prize, before=before)
    for _ in range(zones):
        run.play_zone()


def p04(run: Run) -> None:
    h = run.h
    rows: list[dict[str, int]] = []
    zone = {"n": 1}

    def after_boost(_context) -> None:
        base = h.read8("wEnemyMonBaseExp") * h.read8("wEnemyMonLevel") // 7
        rows.append({"zone": zone["n"], "base": base, "boosted": base + base // 2,
                     "final": h.read8("hQuotient", 2) << 8 | h.read8("hQuotient", 3),
                     "level": h.read8("wEnemyMonLevel")})

    h.register_hook("GainExperience.noWitchExpBoost", after_boost)
    before = talk_and_verify(run)
    run.play_zone()
    lifecycle_settlement(run, prize=run.case.prize, before=before)
    zone["n"] = 2
    run.play_zone()
    run.notes.append(f"rows {rows[:8]}")
    owned = run.branch == "accept"
    one = [r for r in rows if r["zone"] == 1]
    two = [r for r in rows if r["zone"] == 2]
    run.must_reach("EXP awarded in both zones", bool(one) and bool(two))
    for row in one:
        run.check("zone 1: trainer 1.5x only, no prize yet", row["boosted"], row["final"])
    for row in two:
        expected = min(0xFFFF, row["boosted"] + row["boosted"] // 10) if owned else row["boosted"]
        run.check(f"zone 2: +10% after the 1.5x (base {row['base']})", expected, row["final"])
    run.control_check("after the prize's zone")


# ---- Prize 6 Accuracy --------------------------------------------------------------

def p06(run: Run) -> None:
    h = run.h
    state = hold_enemy(run, menus_up=14)
    # Mostly Slam for the boundary rolls; every fifth Tackle, whose threshold meets the cap.
    run.agent.move_policy = lambda agent: (
        (1 if state["menus"] % 2 else 0) if state["menus"] > 14 else 2 if state["menus"] % 5 == 0 else 0)
    rows: list[dict[str, int]] = []
    pending: list[dict[str, int]] = []
    per_side = {0: 0, 1: 0}

    def base(_context) -> None:
        pending[:] = [{"whose": h.read8("hWhoseTurn"), "base": h.pyboy.register_file.B}]

    def replay(_context) -> None:
        if not pending:
            return
        registers = h.pyboy.register_file
        row = pending.pop()
        if state["menus"] > 14:
            return  # the hold is over: natural rolls, so the forced misses cannot stall the battle
        row["adjusted"] = registers.B
        # Each side cycles its own offsets, so the player meets every boundary in turn.
        row["roll"] = min(255, row["base"] + (0, 1, 26, 27)[per_side[row["whose"]] % 4])
        per_side[row["whose"]] += 1
        registers.A = row["roll"]
        rows.append(row)

    def landed(_context) -> None:
        if rows and "missed" not in rows[-1]:
            rows[-1]["missed"] = h.read8("wMoveMissed")

    h.register_hook("MoveHitTest.doAccuracyCheck", base)
    run.hook_after_call("MoveHitTest.doAccuracyCheck", "BattleRandom", replay)
    h.register_hook("HandlePostPlayerMoveWitchEffects", landed)
    run.log_intervention("replay", draw="accuracy roll = T, T+1, T+26, T+27 in turn", where="MoveHitTest.doAccuracyCheck")
    before = talk_and_verify(run)
    run.play_zone()
    lifecycle_settlement(run, prize=run.case.prize, before=before)
    for row in rows:
        row["zone"] = 1
    zone1_rows = len(rows)
    run.play_zone()
    run.notes.append(f"rows {rows[:10]}")
    owned = run.branch == "accept"
    player = [r for r in rows[zone1_rows:] if not r["whose"] and "missed" in r and r["base"] < 229]
    enemy = [r for r in rows[zone1_rows:] if r["whose"]]
    run.must_reach("player accuracy checks below the 255 cap in zone 2", len(player) >= 4)
    for row in player:
        threshold = min(255, row["base"] + 26) if owned else row["base"]
        run.check(f"player threshold (base {row['base']})", threshold, row["adjusted"])
        # cp b / jr z hit / jr nc miss: a roll equal to the threshold hits.
        run.check(f"roll {row['roll']} against {threshold}: miss", row["roll"] > threshold, bool(row["missed"]))
    for row in enemy:
        run.check("enemy threshold untouched", row["base"], row["adjusted"])
    capped = [r for r in rows[zone1_rows:] if not r["whose"] and r["base"] >= 230]
    run.must_reach("a player accuracy check that would pass 255", bool(capped))
    for row in capped:
        run.check(f"threshold {row['base']} stays in range", 255 if owned else row["base"], row["adjusted"])
    run.control_check("after the prize's zone")


# ---- Prize 7 Special ---------------------------------------------------------------

def p07(run: Run) -> None:
    h = run.h
    seen: list[dict[str, int]] = []
    state = {"battle": 0, "zone": 1}

    def new_battle(_context) -> None:
        state["battle"] += 1
        state["menus"] = 0

    def menu(_context) -> None:
        state["menus"] += 1
        if state["menus"] == 1:
            slot = h.read8("wPlayerMonNumber")
            party = h.read8("wPartyMon1", slot * PARTY_STRUCT + 42) << 8 | h.read8("wPartyMon1", slot * PARTY_STRUCT + 43)
            battle = h.read8("wBattleMonSpecial") << 8 | h.read8("wBattleMonSpecial", 1)
            seen.append({"zone": state["zone"], "slot": slot, "party": party, "battle": battle})

    def register() -> None:
        h.register_hook("StartBattle", new_battle)
        h.register_hook("DisplayBattleMenu", menu)

    register()
    before = talk_and_verify(run)
    run.play_zone()
    lifecycle_settlement(run, prize=run.case.prize, before=before)
    state["zone"] = 2
    run.play_zone()
    saved, loaded = run.save_and_continue()
    run.check("bargain state survives the save", saved["boosts"], loaded["boosts"])
    h = run.h
    register()
    state["zone"] = 3
    run.play_zone()
    run.notes.append(f"seen {seen[:10]}")
    owned = run.branch == "accept"
    for row in seen:
        if row["zone"] == 1 or not owned:
            expected = row["party"]
        else:
            expected = min(999, row["party"] + (row["party"] >> 3))
        run.check(f"zone {row['zone']} battle Special from party {row['party']}", expected, row["battle"])
    run.must_reach("battles in zones 2 and 3", {r["zone"] for r in seen} >= {2, 3})
    run.check("Special bit in the earned boosts", owned, bool(h.read8("wEarnedStatBoosts") & 0x08))
    run.control_check("after the prize's zone")


# ---- Prize 8 Resist super effective ------------------------------------------------

# One attacker type and a defender type it hits super effectively, and a resisting one.
SUPER_AGAINST = {"FIGHTING": "NORMAL", "FLYING": "GRASS", "POISON": "GRASS", "GROUND": "FIRE", "ROCK": "FIRE",
                 "BUG": "GRASS", "FIRE": "GRASS", "WATER": "FIRE", "GRASS": "WATER", "ELECTRIC": "WATER",
                 "PSYCHIC_TYPE": "FIGHTING", "ICE": "GRASS", "DRAGON": "DRAGON"}
RESISTS = {"FIRE": "WATER", "WATER": "WATER", "GRASS": "FIRE", "ELECTRIC": "GRASS", "ICE": "FIRE",
           "FIGHTING": "FLYING", "GROUND": "GRASS", "FLYING": "ROCK", "ROCK": "FIGHTING"}
TYPES = parse_rgbds_constants(ROOT / "constants/type_constants.asm")


def p08(run: Run) -> None:
    h = run.h
    hold_enemy(run, menus_up=10)
    rows: list[dict[str, object]] = []
    pending: list[dict[str, object]] = []

    live = {"enemy_move": False}

    def enemy_move(_context) -> None:
        live["enemy_move"] = True

    def next_menu(_context) -> None:
        live["enemy_move"] = False
        pending.clear()

    def entry(_context) -> None:
        # The AI's damage simulator reaches this exit too, and never calls RandomizeDamage.
        # Only a real enemy move is measured or poked.
        if not live["enemy_move"]:
            return
        move_type = h.read8("wEnemyMoveType")
        name = next((n for n, v in TYPES.items() if v == move_type), "")
        original = h.read_bytes("wBattleMonType", 2)
        variant = len(rows) % 4
        poke = None
        if variant in (1, 3) and name in SUPER_AGAINST:
            poke = [TYPES[SUPER_AGAINST[name]]] * 2
        elif variant == 2 and name in SUPER_AGAINST and name in RESISTS:
            poke = [TYPES[SUPER_AGAINST[name]], TYPES[RESISTS[name]]]
        if poke:
            h.write8("wBattleMonType", poke[0])
            h.write8("wBattleMonType", poke[1], offset=1)
        if poke:
            # Natural enemy damage here is 2 to 3, where a quarter truncates to nothing.
            h.write8("wDamage", 0)
            h.write8("wDamage", 1 if variant == 3 else 40, offset=1)
        pending[:] = [{"variant": variant, "poked": bool(poke), "type": name, "restore": original,
                       "pre": h.read8("wDamage") << 8 | h.read8("wDamage", 1)}]

    def scanned(_context) -> None:
        if pending:
            pending[0]["c"] = h.pyboy.register_file.C
            # The poked types exist only for this scan.
            h.write8("wBattleMonType", pending[0]["restore"][0])
            h.write8("wBattleMonType", pending[0]["restore"][1], offset=1)

    def after(_context) -> None:
        if not pending or not live["enemy_move"]:
            return
        row = pending.pop()
        row["post"] = h.read8("wDamage") << 8 | h.read8("wDamage", 1)
        rows.append(row)
        live["enemy_move"] = False

    h.register_hook("ExecuteEnemyMove", enemy_move)
    h.register_hook("DisplayBattleMenu", next_menu)
    h.register_hook("RogueWitchResistSuperEffective", entry)
    run.hook_after_call("RogueWitchResistSuperEffective", "TypeMatchupScan", scanned)
    h.register_hook("RandomizeDamage", after)
    run.log_intervention("setup", player_types="enemy hits cycle natural / super-effective / 2x-then-0.5x / damage 1, "
                         "types poked at the scan and restored after")
    before = talk_and_verify(run)
    run.play_zone()
    lifecycle_settlement(run, prize=run.case.prize, before=before)
    rows.clear()
    pending.clear()
    run.play_zone()
    run.notes.append(f"rows {rows[:10]}")
    owned = run.branch == "accept"
    run.must_reach("enemy hits measured after settlement", len(rows) >= 4)
    if owned:
        run.must_reach("a super-effective poke landed", any(r["poked"] and r.get("c", 0) > 20 for r in rows))
    for row in rows:
        reduced = owned and row.get("c", 0) > 20      # unowned: the routine returns before its scan
        expected = row["pre"] - row["pre"] // 4 if reduced else row["pre"]
        run.check(f"{row['type']} (scan {row.get('c')}, variant {row['variant']}): damage {row['pre']}",
                  expected, row["post"])
    for row in rows:
        if owned and row["variant"] == 2 and row["poked"]:
            run.check("2x then 0.5x is neutral", 20, row["c"])
        if owned and row["variant"] == 3 and row["poked"]:
            run.check("damage 1 stays 1", 1, row["post"])
    run.control_check("after the prize's zone")


# ---- 6 Increased rarity foes -------------------------------------------------------

def c06(run: Run) -> None:
    h = run.h
    rows: list[dict[str, int]] = []

    def pre(_context) -> None:
        # Boundary, accept only: the fourth roster slot is forced to the top class (1) once.
        if run.branch == "accept" and len(rows) == 3:
            run.log_intervention("poke", label="roster class b", value=1, natural=h.pyboy.register_file.B,
                                 where="GetRandMon.aceKnown")
            h.pyboy.register_file.B = 1
        rows.append({"pre": h.pyboy.register_file.B})

    def post(_context) -> None:
        rows[-1]["post"] = h.pyboy.register_file.B

    h.register_hook("GetRandMon.aceKnown", pre)
    h.register_hook("GetRandMon.noRarityBump", post)
    before = talk_and_verify(run, "rarer breeds")
    run.play_zone()
    run.notes.append(f"rows {rows[:12]}")
    run.must_reach("roster classes drawn in the zone", len(rows) >= 4)
    for index, row in enumerate(rows):
        bumped = run.branch == "accept" and row["pre"] >= 2
        run.check(f"class {row['pre']} after the challenge", row["pre"] - 1 if bumped else row["pre"], row["post"])
    if run.branch == "accept":
        run.check("class 1 cannot go rarer", 1, rows[3]["post"])
        run.must_reach("an ordinary class was lowered", any(r["pre"] >= 2 for r in rows))
    lifecycle_settlement(run, prize=run.case.prize, before=before)


# ---- Prize set: nine owned, ten owned, blackout ------------------------------------

def witch_visible(run: Run) -> bool:
    agent = run.agent
    return agent.witch_slot(agent.sprites()) is not None


def complete_set(run: Run) -> None:
    """Prize 10 is the only one missing. The real offer names it, and earning it
    through the lifecycle completes the set without touching the legendary bit."""
    before = talk_and_verify(run)
    run.check("the offer names the missing prize", run.case.prize, run.h.read8("wWitchPrize"))
    run.play_zone()
    lifecycle_settlement(run, prize=run.case.prize, before=before)
    if run.branch == "accept":
        run.check("all ten prize bits set, legendary bit untouched", [0xFF, 0x03], run.earned)
        run.check("with every prize earned she no longer appears", False, witch_visible(run))


def none_offered(run: Run) -> None:
    """All ten owned and no legendary bargain on offer: no challenge, no prize, no stall."""
    h = run.h
    run.check("no challenge rolled", 0, h.read8("wWitchChallenge"))
    run.check("no prize rolled", 0, h.read8("wWitchPrize"))
    run.check("no bargain pending", False, run.accepted)
    run.check("earned bytes unchanged", [0xFF, 0x03], run.earned)
    run.control_check("with nothing on offer")
    run.play_zone()
    run.check("earned bytes unchanged after a zone", [0xFF, 0x03], run.earned)


def blackout(run: Run) -> None:
    h, agent = run.h, run.agent
    before = talk_and_verify(run)
    forced = {"done": False}

    def faint(_context) -> None:
        # Leave the lead on 1 HP and everyone else fainted, with an enemy that cannot die,
        # so the party loses the fight through the game's own faint and blackout code.
        if not forced["done"]:
            forced["done"] = True
            for index in range(h.read8("wPartyCount")):
                poke_party_state(run, index, hp=1 if index == 0 else 0)
            h.write8("wBattleMonHP", 0)
            h.write8("wBattleMonHP", 1, offset=1)
            run.log_intervention("setup", forced="lead on 1 HP, others fainted, enemy HP held at 3840")
        for label in ("wEnemyMonHP", "wEnemyMonMaxHP"):
            h.write8(label, 0x0F)
            h.write8(label, 0, offset=1)

    run.expected_anomaly_prefixes.append("enemy's active mon HP")

    h.register_hook("DisplayBattleMenu", faint)
    run.check("precondition: prizes earned before the run ends", run.case.context.earned, tuple(run.earned))
    agent.run(stages=agent.report.stages_cleared + 1, max_frames=run.case.max_frames)
    run.raise_on_hook_error()
    run.must_reach("a blackout happened", agent.report.blackouts > 0)
    run.wait_playable()
    run.check("earned bits wiped by the blackout", [0, 0], run.earned)
    run.check("accepted flag wiped", False, run.accepted)
    run.control_check("in the new run")


# ---- 15 No healing outside battle --------------------------------------------------

def c15(run: Run) -> None:
    from autoplay import AutoplayAgent
    h, agent = run.h, run.agent
    lobby = agent.lobby_map
    blocks = h.hook_flag("RogueWitchBlockHealing")
    uses = h.hook_flag("ItemUseMedicine")
    before = talk_and_verify(run, "No medicine")
    limit = h.pyboy.frame_count + 6000
    while h.read8("hCurMap") == lobby and h.pyboy.frame_count < limit:
        agent.step()
    run.must_reach("a stage was entered", h.read8("hCurMap") != lobby)
    run.wait_playable()
    # Stage a hurt lead and a potion in the Recovery pocket, then drive START > ITEM
    # ourselves: the agent's own heal plan is switched off under this challenge.
    item = min(agent.heal_amounts, key=lambda i: agent.heal_amounts[i])
    slot = agent.recovery_table.index(item)
    h.write8("wRecoveryItemCounts", 3, offset=slot)
    maximum = h.read8("wPartyMon1MaxHP") << 8 | h.read8("wPartyMon1MaxHP", 1)
    poke_party_state(run, 0, hp=maximum // 5)
    run.log_intervention("setup", recovery_item=item, count=3, lead_hp=maximum // 5)
    hp_before = bcd2(h, "wPartyMon1HP")
    count_before = agent.recovery_counts().get(item, 0)
    agent.plan = AutoplayAgent.choose_heal(agent)
    run.must_reach("a heal plan for the staged potion", agent.plan is not None)
    end = h.pyboy.frame_count + 4000
    while agent.plan is not None and h.pyboy.frame_count < end:
        agent.step()                  # until the errand's menus have closed (the agent clears the plan)
    agent.plan = None
    hp_after = bcd2(h, "wPartyMon1HP")
    count_after = agent.recovery_counts().get(item, 0)
    run.notes.append(f"item {item} count {count_before}->{count_after}, hp {hp_before}->{hp_after}, "
                     f"block checks {blocks['count']}, medicine uses {uses['count']}")
    run.must_reach("the item use reached ItemUseMedicine", uses["count"] > 0)
    if run.branch == "accept":
        run.check("the refusal ran", True, blocks["count"] > 0)
        run.check("the potion was not consumed", count_before, count_after)
        run.check("the lead's HP did not change", hp_before, hp_after)
    else:
        run.require("declined: the lead's HP rose", hp_after > hp_before, (hp_before, hp_after))
    run.control_check("after the item menus")
    run.play_zone()
    lifecycle_settlement(run, prize=run.case.prize, before=before)


# ---- 8 Slowed Pokemon --------------------------------------------------------------

QUICK_MOVES = ("QUICK_ATTACK", "COUNTER")
# Percent of the stat at each stage 1..13 (7 = neutral), as StatModifierRatios.
STAGE_RATIO = {1: 25, 2: 28, 3: 33, 4: 40, 5: 50, 6: 66, 7: 100, 8: 150, 9: 200, 10: 250, 11: 300, 12: 350, 13: 400}


def c08(run: Run) -> None:
    h = run.h
    state = hold_enemy(run, menus_up=16)
    turns: list[dict[str, object]] = []
    zone = {"n": 1}
    priority = {MOVES_BY_NAME[m] for m in QUICK_MOVES}

    halves = h.hook_flag("HalvePlayerSpeedIfSluggish")
    applies = h.hook_flag("ApplySingleEarnedStatBoost")
    effects: list[tuple[int, int, int]] = []

    def stat_effect(_context) -> None:
        # Entry to the routine that should put the halving back after a stage change.
        effects.append((h.read8("hWhoseTurn"), h.read8("wPlayerMoveEffect"), h.read8("wEnemyMoveEffect")))

    h.register_hook("ApplySingleEarnedStatBoost", stat_effect)

    def menu(_context) -> None:
        slot = h.read8("wPlayerMonNumber")
        party = h.read8("wPartyMon1", slot * PARTY_STRUCT + 40) << 8 | h.read8("wPartyMon1", slot * PARTY_STRUCT + 41)
        battle = h.read8("wBattleMonSpeed") << 8 | h.read8("wBattleMonSpeed", 1)
        variant = len(turns) % 4
        # Enemy Speed relative to the player's: just under full, under half, a tie, above full.
        target = {0: party - 1, 1: party // 2 - 1, 2: battle, 3: party + 1}[variant]
        h.write8("wEnemyMonSpeed", target >> 8)
        h.write8("wEnemyMonSpeed", target & 0xFF, offset=1)
        turns.append({"zone": zone["n"], "party": party, "battle": battle, "variant": variant, "enemy": target,
                      "order": [], "menus": state["menus"], "stage": h.read8("wPlayerMonSpeedMod"),
                      "status": h.read8("wBattleMonStatus"), "halve_calls": halves["count"],
                      "apply_calls": applies["count"],
                      "unmodified": h.read8("wPlayerMonUnmodifiedSpeed") << 8 | h.read8("wPlayerMonUnmodifiedSpeed", 1)})

    def first(who):
        def hook(_context) -> None:
            if turns and len(turns[-1]["order"]) < 2:
                turns[-1]["order"].append(who)
                turns[-1].setdefault("moves", (h.read8("wPlayerSelectedMove"), h.read8("wEnemySelectedMove")))
        return hook

    h.register_hook("DisplayBattleMenu", menu)
    h.register_hook("ExecutePlayerMove", first("P"))
    h.register_hook("ExecuteEnemyMove", first("E"))
    run.log_intervention("setup", enemy_speed="set at every menu to party-1, party/2-1, the player's battle Speed, party+1")
    before = talk_and_verify(run, "half SPEED")
    run.play_zone()
    lifecycle_settlement(run, prize=run.case.prize, before=before)
    zone["n"] = 2
    run.play_zone()
    run.notes.append(f"turns {turns[:8]}")
    owned_bargain = run.branch == "accept"
    one = [t for t in turns if t["zone"] == 1 and len(t["order"]) == 2 and not (set(t.get("moves", ())) & priority)]
    run.must_reach("complete turns in the bargained zone", len(one) >= 8)
    def staged(turn) -> int:
        """The stat the game should hold: the party's Speed through the stage ratio (a
        paralysis quarter is applied in the same place, so a paralysed turn is skipped)."""
        return max(1, turn["party"] * STAGE_RATIO[turn["stage"]] // 100)

    plain = [t for t in one if not t["status"] & 0x40]       # not paralysed
    for turn in plain:
        expected = max(1, staged(turn) // 2) if owned_bargain else staged(turn)
        run.check(f"battle Speed {turn['battle']} (party {turn['party']}, stage {turn['stage']}, "
                  f"halve calls so far {turn['halve_calls']})", expected, turn["battle"])
    for turn in one:
        enemy = turn["enemy"]
        if enemy == turn["battle"] or set(turn.get("moves", ())) & priority:
            continue  # a tie is random, checked below
        run.check(f"turn order, player {turn['battle']} against enemy {enemy}",
                  "P" if turn["battle"] > enemy else "E", turn["order"][0])
    ties = [t["order"][0] for t in one if t["enemy"] == t["battle"]]
    run.notes.append(f"tie outcomes {ties}")
    run.notes.append(f"ApplySingleEarnedStatBoost entries (whose turn, player effect, enemy effect): {effects[:6]}")
    run.must_reach("tie turns", len(ties) >= 4)
    later = [t for t in turns if t["zone"] == 2 and not t["status"] & 0x40]
    run.must_reach("battles in the next zone", bool(later))
    for turn in later:
        run.check(f"next zone: Speed is the party's through stage {turn['stage']}", staged(turn), turn["battle"])
    run.control_check("after the zone")


def speed_after_stage_change(unmodified: int, stage: int, *, sluggish: bool, boosted: bool, paralysed: bool) -> int:
    """Execution's order after a Speed stage change (AIPredictSpeedAtStage mirrors it)."""
    value = max(1, min(999, unmodified * STAGE_RATIO[stage] // 100))
    if sluggish:
        value = max(1, value // 2)
    if boosted:
        value = min(999, value + value // 8)
    return max(1, value // 4) if paralysed else value


def c08s(run: Run) -> None:
    """Stage moves, paralysis, the earned Speed boost, Haze and Transform all stack with
    the halving. Enemy moves stay natural: String Shot and the like land on the same
    formula, and each step retries until its own effect shows in the battle state."""
    h = run.h
    hold_enemy(run, menus_up=30)
    sluggish = run.branch == "accept"
    state = {"step": 0, "tries": 0, "stage": 7, "copied": None}
    reached: list[str] = []

    def word(label: str) -> int:
        return h.read8(label) << 8 | h.read8(label, 1)

    def use(move: str) -> None:
        state["move"] = move
        for slot in range(4):
            h.write8("wBattleMonMoves", MOVES_BY_NAME[move], offset=slot)
            h.write8("wBattleMonPP", 30, offset=slot)

    def paralyse() -> None:
        # What the paralysis effect does: the status bit and a quarter of live Speed.
        speed = max(1, word("wBattleMonSpeed") // 4)
        h.write8("wBattleMonStatus", 1 << 6)
        h.write8("wBattleMonSpeed", speed >> 8)
        h.write8("wBattleMonSpeed", speed & 0xFF, offset=1)

    def copied(_context) -> None:
        if h.read8("hWhoseTurn") == 0:
            state["copied"] = word("wEnemyMonSpeed")

    def menu(_context) -> None:
        step, stage = state["step"], h.read8("wPlayerMonSpeedMod")
        if step >= 5:
            return
        # A new battle reloads the moves from the party, and a step can land on a battle's
        # last menu. A Transform that landed has moves of its own, the enemy's.
        if state.get("move") and not h.read8("wPlayerBattleStatus3") >> 3 & 1:
            use(state["move"])
        paralysed = bool(h.read8("wBattleMonStatus") & 1 << 6)
        speed, unmodified = word("wBattleMonSpeed"), word("wPlayerMonUnmodifiedSpeed")
        staged = speed_after_stage_change(unmodified, stage, sluggish=sluggish, boosted=True, paralysed=paralysed)
        state["tries"] += 1
        if state["tries"] > 12:
            state["step"] = 5
            use("TACKLE")
            return
        if step == 0:
            use("AGILITY")
        elif step in (1, 2) and stage > state["stage"]:
            run.check(f"Agility{' while paralysed' if step == 2 else ''}: stage {stage}, unmodified {unmodified}",
                      staged, speed)
            reached.append("agility paralysed" if step == 2 else "agility")
            if step == 1:
                paralyse()
                use("AGILITY")
            else:
                use("HAZE")
        elif step == 3 and stage == 7 and not paralysed and state["stage"] > 7:
            boosted = unmodified + unmodified // 8
            run.check(f"Haze: unmodified {unmodified}", max(1, boosted // 2) if sluggish else boosted, speed)
            reached.append("haze")
            paralyse()
            use("TRANSFORM")
        elif step == 4 and h.read8("wPlayerBattleStatus3") >> 3 & 1 and state["copied"] is not None:
            boosted = state["copied"] + state["copied"] // 8
            halved = max(1, boosted // 2) if sluggish else boosted
            expected = max(1, halved // 4) if paralysed else halved
            if stage != h.read8("wEnemyMonSpeedMod"):  # an enemy stat move landed after the copy
                expected = staged
            run.check(f"Transform: copied {state['copied']}, paralysed {paralysed}", expected, speed)
            reached.append("transform")
            use("TACKLE")
        else:
            state["stage"] = max(state["stage"], stage)
            return
        state["step"], state["tries"], state["stage"] = step + 1, 0, stage

    def boost() -> None:
        h.write8("wEarnedStatBoosts", h.read8("wEarnedStatBoosts") | 1 << 2)

    at_stage_door(run, boost)
    h.register_hook("TransformEffect_", copied)
    h.register_hook("DisplayBattleMenu", menu)
    run.log_intervention("setup", earned="Speed boost bit set at the stage door",
                         player="battle moves poked to Agility, Haze, Transform in turn; status poked to paralysis")
    before = talk_and_verify(run, "half SPEED")
    run.play_zone()
    lifecycle_settlement(run, prize=run.case.prize, before=before)
    run.notes.append(f"reached {reached}")
    for name in ("agility", "agility paralysed", "haze", "transform"):
        run.must_reach(f"{name} row", name in reached)
    run.control_check("after the zone")


# ---- 11 Legendary boss -------------------------------------------------------------

GYM_LINEUP = ("BROCK", "SABRINA", "ERIKA", "JASMINE", "CLAIR", "MISTY", "LT_SURGE", "KOGA")
LEGENDARY_SLOTS = (1, 2)  # Sabrina's and Erika's pools hold Mew, which the party lacks
BIT_UBER = RAM["BIT_WITCH_UBER_RECEIVED"]


def _c11_context(door1: int, door2: int, leader: str = "SABRINA", lead: str = "MEWTWO") -> Context:
    """`leader` stands in badge slot 1 (a LEGENDARY_SLOTS door); `lead` is the
    masterball-class mon the trade takes, and must be outside that leader's pool
    (LegendaryBossTable), or the leader would be owned out."""
    classes = parse_trainer_class_indexes(ROOT / "constants/trainer_constants.asm")
    lineup = tuple(leader if index == 1 else name for index, name in enumerate(GYM_LINEUP))
    return Context(battle_count=37, gym_next=True, badges=0xF0,
                   # The lead is the masterball-class mon the trade takes, and the
                   # agent picks the lead at a trade's party menu.
                   party=(Mon(lead), Mon("TAUROS"), Mon("ALAKAZAM"), Mon("ARCANINE")),
                   # Both gifts of the run already taken: at 4 badges a gift room can
                   # otherwise take both doors, which hides the witch.
                   pokes={"wGymChoice": 1 << RAM["BIT_GYM_CHOICE_LATCHED"] | door1 | door2 << 3,
                          "wLegendaryBossSpecies": 0, "wBridgeState": 2 << 6},
                   arrays={"wRunGymLineup": tuple(classes[name] for name in lineup)})


def _lobby_door_blocks(h) -> list[int]:
    """The two door blocks on the lobby's top wall: 8 open, 12 closed."""
    stride = h.read8("wCurMapWidth") + 6
    return [h.read8("wOverworldMap", offset=3 * stride + 3 + x) for x in (4, 5)]


def c11(run: Run, *, door: int, door1: int, door2: int, quote: str, trade: str = "yes") -> None:
    h = run.h
    species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
    legendaries = {species[name] for name in ("MEW", "MEWTWO", "CELEBI", "LUGIA", "HO_OH")}
    doors = (door1 in LEGENDARY_SLOTS, door2 in LEGENDARY_SLOTS)
    run.agent.forced_door = door
    before = talk_and_verify(run, quote)
    accepted = run.branch == "accept"
    closed = [12 if accepted and not doors[0] else 8, 12 if accepted and not doors[1] else 8]
    run.check("door blocks after the answer", closed, _lobby_door_blocks(h))

    aces: list[dict[str, int]] = []
    offers = h.hook_flag("OfferLegendaryTradeCommon")
    start = h.read8("hCurMap")

    def first_menu(_context) -> None:
        count = h.read8("wEnemyPartyCount")
        if h.read8("hCurMap") != start and h.read8("wCurOpponent"):
            row = {"class": h.read8("wTrainerClass"), "ace": h.read8("wEnemyPartySpecies", count - 1),
                   "recorded": h.read8("wLegendaryBossSpecies")}
            if not aces or aces[-1] != row:
                aces.append(row)

    def trade_prompt(_context) -> None:
        # The agent answers YES/NO menus through its witch hook while this flag is up.
        agent = run.agent
        agent.answers, agent.witch_talking = [trade], True
        agent.witch_talk_frame = h.pyboy.frame_count

    wanted: list[int] = []

    def give_the_wanted_mon(_context) -> None:
        # The agent aims at its lead here. The trade names any masterball-class mon.
        agent = run.agent
        if not offers["count"] or h.read8("hIsInBattle") or agent.menu_goal is None:
            return
        species_wanted = h.read8("wInGameTradeGiveMonSpecies")
        wanted.append(species_wanted)
        count = h.read8("wPartyCount")
        party_now = h.read_bytes("wPartySpecies", count)
        if species_wanted in party_now:
            agent.menu_goal.target = party_now.index(species_wanted)

    def top_up(_context) -> None:
        h.write8("wBattleMonHP", h.read8("wBattleMonMaxHP"))
        h.write8("wBattleMonHP", h.read8("wBattleMonMaxHP", 1), offset=1)

    run.log_intervention("setup", player="active mon HP topped up at every menu: this row tests the bargain, not the fight")
    h.register_hook("DisplayBattleMenu", first_menu)
    h.register_hook("DisplayBattleMenu", top_up)
    h.register_hook("OfferLegendaryTradeCommon", trade_prompt)
    h.register_hook("PartyMenuInit", give_the_wanted_mon)
    party_before = h.read_bytes("wPartySpecies", h.read8("wPartyCount"))
    run.play_zone()
    run.notes.append(f"aces {aces[:6]}; trade offers entered {offers['count']}; "
                     f"party {party_before} -> {h.read_bytes('wPartySpecies', h.read8('wPartyCount'))}")
    run.notes.append(f"answers left {run.agent.answers}, transcript tail {run.agent.transcript[-14:]}")
    run.must_reach("the leader's battle", bool(aces))
    leader = aces[-1]
    if accepted:
        run.require("the leader's ace is a legendary the party lacks",
                    leader["ace"] in legendaries and leader["ace"] not in party_before, leader)
        run.check("the trade byte names the ace", leader["ace"], leader["recorded"])
    else:
        run.require("no legendary ace when declined", leader["ace"] not in legendaries, leader)
        run.check("no trade byte when declined", 0, leader["recorded"])
    traded = accepted and trade == "yes"
    party = h.read_bytes("wPartySpecies", h.read8("wPartyCount"))
    if accepted:
        run.must_reach("the trade was offered", offers["count"] > 0)
    if traded:
        run.must_reach("the trade's party menu", bool(wanted))
        run.check("the masterball mon went in the trade", party_before.count(wanted[-1]) - 1, party.count(wanted[-1]))
    else:
        run.check("the party keeps its mons", party_before, party)
    run.check("the legendary arrived only on a completed trade", traded, leader["ace"] in party)
    expected = list(before)
    if traded:
        expected[1] |= 1 << BIT_UBER
    run.check("only the Uber bit may change", expected, run.earned)
    run.check("accepted flag cleared by the lobby", False, run.accepted)
    run.check("the trade byte is gone after settlement", 0, h.read8("wLegendaryBossSpecies"))
    run.control_check("after settlement")


def _c11l(run: Run) -> None:
    c11(run, door=0, door1=1, door2=0, quote="DOOR 1")


def _c11r(run: Run) -> None:
    c11(run, door=1, door1=0, door2=1, quote="DOOR 2")


def _c11b(run: Run) -> None:
    c11(run, door=1, door1=1, door2=2, quote="either door")  # text reworded 2026-11-09 (f9202856)


def _c11n(run: Run) -> None:
    c11(run, door=0, door1=1, door2=0, quote="DOOR 1", trade="no")


def _reenter_lobby_offer(run: Run, *, endless: int) -> int:
    """The witch's roll on a fresh gym-next lobby entry, steered at Challenge 11: the
    entry code is re-run the way every warp does. Returns what she settled on."""
    h = run.h
    h.write8("wEndlessDepth", endless)
    h.write8("wGymChoice", 1 << RAM["BIT_GYM_CHOICE_LATCHED"] | 2 | 3 << 3)  # Erika, Jasmine
    h.write8("wBridgeState", 2 << 6)
    h.write8("wRogueFlagsBitfield", h.read8("wRogueFlagsBitfield") | 1 << RAM["BIT_ROGUE_GYM_NEXT"])
    event = EVENT_IDS["EVENT_ENTER_ROOM"]
    h.write8("wEventFlags", h.read8("wEventFlags", event // 8) & ~(1 << event % 8) & 0xFF, offset=event // 8)
    setup = h.hook_flag("PCWitchSetup")
    polls = h.hook_flag("JoypadOverworld")
    h.wait_until(lambda: setup["count"] > 0, "lobby setup", 1200)
    polls["count"] = 0
    h.wait_until(lambda: polls["count"] > 2, "lobby input poll", 1200)
    return h.read8("wWitchChallenge")


def _c11m(run: Run) -> None:
    """One legendary received per run until Endless, read at the witch's own roll."""
    h = run.h
    c11(run, door=0, door1=1, door2=0, quote="DOOR 1")
    # Celebi keeps Erika a legendary door once Mew is owned, so only the limit can refuse.
    groups = parse_rgbds_constants(ROOT / "constants/rogue_species_groups.asm")
    h.write_sram_bytes("sRogueSpeciesGroupsEnabled",
                       [groups["GROUP_OVERRIDE_TAG"]
                        | sum(1 << groups[n] for n in ("BIT_GROUP_KANTO", "BIT_GROUP_JOHTO", "BIT_GROUP_WARP"))], bank=1)
    run.log_intervention("setup", species_groups="Kanto, Johto and Warp on; next lobby entry re-run, steered at 11",
                         endless_depth="poked to 0, then 1")
    steer_offer(h, C["CHALLENGE_LEGENDARY_BOSS"], 0)
    traded = run.branch == "accept"
    chosen = _reenter_lobby_offer(run, endless=0)
    run.notes.append(f"offer before Endless {chosen}")
    run.check("before Endless: 11 only if no legendary was received", not traded,
              chosen == C["CHALLENGE_LEGENDARY_BOSS"])
    chosen = _reenter_lobby_offer(run, endless=1)
    run.notes.append(f"offer in Endless {chosen}")
    run.check("in Endless: 11 is offered again", C["CHALLENGE_LEGENDARY_BOSS"], chosen)
    h.write8("wEndlessDepth", 0)


def c11d(run: Run, answer: str, quote: str = "DOOR 1") -> None:
    """Door Dice after any bargain: the warning, then YES breaks it and NO spends nothing."""
    from autoplay import AutoplayAgent
    h, agent = run.h, run.agent
    challenge = run.case.challenge
    before = talk_and_verify(run, quote)
    accepted = run.branch == "accept"
    h.write8("wDiceCharges", (h.read8("wDiceCharges") & 0b11111100) | 2)
    warned = h.hook_flag("DoorDiceBargainWarning")
    uses = {"n": 0}  # the plan retries while the lead stays hurt, as a press of the item would
    rolled = h.hook_flag("SelectAndPatchLobbyExit")

    def warning(_context) -> None:
        if accepted:
            agent.answers, agent.witch_talking = [answer], True
            agent.witch_talk_frame = h.pyboy.frame_count

    def use_the_dice(_context) -> None:
        # The heal plan reaches the same dispatch a Door Dice from the bag does.
        uses["n"] += 1
        h.pyboy.register_file.PC = h.address("ItemUseDoorDice")

    # Stage the agent's own START > ITEM drive; the medicine dispatch becomes the dice.
    item = min(agent.heal_amounts, key=lambda i: agent.heal_amounts[i])
    h.write8("wRecoveryItemCounts", 3, offset=agent.recovery_table.index(item))
    maximum = bcd2(h, "wPartyMon1MaxHP")
    poke_party_state(run, 0, hp=maximum // 5)
    run.log_intervention("replay", dispatch="ItemUseMedicine redirected to ItemUseDoorDice",
                         charges=2, recovery_item=item, lead_hp=maximum // 5)
    h.register_hook("DoorDiceBargainWarning", warning)
    h.register_hook("ItemUseMedicine", use_the_dice)
    charges = h.read8("wDiceCharges") & 3
    rolled_before = rolled["count"]
    agent.plan = AutoplayAgent.choose_heal(agent)
    run.must_reach("a plan to open the bag", agent.plan is not None)
    end = h.pyboy.frame_count + 4000
    while agent.plan is not None and h.pyboy.frame_count < end:
        agent.step()
    agent.plan = None
    run.must_reach("the Door Dice ran", warned["count"] > 0)
    keeps = accepted and answer == "no"
    run.check("the bargain after the dice", keeps, run.accepted)
    run.check("the challenge id after the dice",
              challenge if keeps else (0 if accepted else h.read8("wWitchChallenge")),
              h.read8("wWitchChallenge"))
    run.check("charges after the dice", charges if keeps else max(0, charges - uses["n"]), h.read8("wDiceCharges") & 3)
    run.check("the doors rerolled unless cancelled", not keeps, rolled["count"] > rolled_before)
    run.check("earned bytes unchanged", before, run.earned)
    run.check("the warning shows only with a bargain up", accepted, run.transcript_has("Rolling will"))
    run.control_check("after the dice")


def _c11k(run: Run) -> None:
    c11d(run, "no")


def _c11y(run: Run) -> None:
    c11d(run, "yes")


def _dice_no(run: Run) -> None:
    c11d(run, "no", quote="No money from")


def _dice_yes(run: Run) -> None:
    c11d(run, "yes", quote="No money from")


def gate_excluded(run: Run) -> None:
    """A gate refused the steered challenge: the draw looped past the steering and she
    offers another. Play her offer normally: the zone and the exit must still work."""
    h = run.h
    steers = [i for i in run.interventions if i["kind"] == "steer"]
    run.must_reach("the steered draw was refused", bool(steers) and steers[-1]["challenge_draws"] > 5)
    offered = h.read8("wWitchChallenge")
    run.notes.append(f"steered {run.case.challenge}, offered {offered}, draws {steers[-1]['challenge_draws']}")
    run.check("the excluded challenge is not on offer", True, offered != run.case.challenge)
    corner = MAPS["GAME_CORNER"]
    talk_and_verify(run)
    doors = [h.read8("wLobbyDoor1StageMap"), h.read8("wLobbyDoor2StageMap")]
    if offered != C["CHALLENGE_GAMBLERS_PARADISE"]:
        run.check("the doors are not the Game Corner", True, corner not in doors)

    def top_up(_context) -> None:
        h.write8("wBattleMonHP", h.read8("wBattleMonMaxHP"))
        h.write8("wBattleMonHP", h.read8("wBattleMonMaxHP", 1), offset=1)

    h.register_hook("DisplayBattleMenu", top_up)
    run.log_intervention("setup", player="active mon HP topped up at every menu")
    run.play_zone()
    run.check("accepted flag cleared by the lobby", False, run.accepted)
    run.control_check("the normal exit after settlement")


def c11w(run: Run) -> None:
    """The doors moved between her roll and the talk, leaving no legendary door: she
    withdraws, on either answer, and nothing downstream sees an offer."""
    h = run.h
    h.write8("wGymChoice", 1 << RAM["BIT_GYM_CHOICE_LATCHED"] | 0 | 3 << 3)
    run.log_intervention("setup", doors="repointed to two leaders without a legendary, as a Door Dice would")
    before = run.earned
    run.talk()
    said = list(run.agent.transcript)
    run.require("she withdraws", run.transcript_has("fates"), said)
    run.check("the offer is gone", 0, h.read8("wWitchChallenge"))
    run.check("no bargain struck", False, run.accepted)
    run.check("no question asked", ANSWERS[run.branch], tuple(run.agent.answers))
    run.check("earned bytes untouched", before, run.earned)
    run.control_check("after the withdrawal")


# ---- Transitions -------------------------------------------------------------------

GIFT_ROOMS = {MAPS[name] for name in (
    "COPYCATS_HOUSE_2F", "BILLS_HOUSE", "MR_FUJIS_HOUSE", "SS_ANNE_CAPTAINS_ROOM", "CINNABAR_LAB_FOSSIL_ROOM",
    "POKEMON_FAN_CLUB", "WARDENS_HOUSE", "VIRIDIAN_SCHOOL_HOUSE", "OLD_MANS_HOUSE", "CERULEAN_TRASHED_HOUSE",
    "REDS_HOUSE_1F", "IGAS_DOJO", "FLORAS_GROTTO", "OAKS_LAB")}


def witch_absent(run: Run, *, gift: bool) -> None:
    """Steered to appear, she still must not: the door or finale gate comes first."""
    h = run.h
    doors = {h.read8("wLobbyDoor1StageMap"), h.read8("wLobbyDoor2StageMap")}
    if gift:
        run.must_reach("a gift room took the doors", doors <= GIFT_ROOMS)
    else:
        run.must_reach("the Elite Four is next", not doors & GIFT_ROOMS)
    run.check("no challenge on offer", 0, h.read8("wWitchChallenge"))
    run.check("her sprite is hidden", True, toggle_hidden(h, "TOGGLE_PC_WITCH"))
    run.check("no bargain", False, run.accepted)
    run.notes.append(f"doors {sorted(doors)}")
    run.control_check("the lobby still plays")


def _witch_absent_gift(run: Run) -> None:
    witch_absent(run, gift=True)


def _witch_absent_elite(run: Run) -> None:
    witch_absent(run, gift=False)


def chain(run: Run) -> None:
    """Three different bargains in a row, on real lobby visits: Gamblers patches the doors
    on a route visit, a turn limit follows at the gym, then the Speed halving on a route.
    Nothing from an earlier bargain may leak into the next."""
    h, agent = run.h, run.agent
    corner = MAPS["GAME_CORNER"]
    accept = run.branch == "accept"
    drains = h.hook_flag("HandlePostPlayerMoveWitchEffects")
    run.log_intervention("setup", player="active mon HP topped up at every menu")

    def top_up(_context) -> None:
        h.write8("wBattleMonHP", h.read8("wBattleMonMaxHP"))
        h.write8("wBattleMonHP", h.read8("wBattleMonMaxHP", 1), offset=1)

    h.register_hook("DisplayBattleMenu", top_up)
    expected = run.earned

    def settle_expected(prize: int) -> None:
        if accept and prize:
            expected[(prize - 1) // 8] |= 1 << ((prize - 1) % 8)

    prize = h.read8("wWitchPrize")
    talk_and_verify(run, "PARADISE")
    if accept:
        run.check("Gamblers patched both doors", [corner, corner],
                  [h.read8("wLobbyDoor1StageMap"), h.read8("wLobbyDoor2StageMap")])
    steer_offer(h, C["CHALLENGE_TURN_LIMIT"], 0)
    run.play_zone()
    settle_expected(prize)
    run.check("first bargain settled", expected, run.earned)
    doors = [h.read8("wLobbyDoor1StageMap"), h.read8("wLobbyDoor2StageMap")]
    run.check("no door patch survives the zone", False, corner in doors)
    run.must_reach("she offers the second bargain", h.read8("wWitchChallenge") == C["CHALLENGE_TURN_LIMIT"])
    limit = h.read8("wBattleTurnLimit")
    prize = h.read8("wWitchPrize")
    agent.witch_pending, agent.witch_done, agent.answers = True, False, list(ANSWERS[run.branch])
    talk_and_verify(run, f"{limit}")
    steer_offer(h, C["CHALLENGE_SLOWED_POKEMON"], 0)
    run.play_zone()
    settle_expected(prize)
    run.check("second bargain settled", expected, run.earned)
    run.must_reach("she offers the third bargain", h.read8("wWitchChallenge") == C["CHALLENGE_SLOWED_POKEMON"])
    prize = h.read8("wWitchPrize")
    agent.witch_pending, agent.witch_done, agent.answers = True, False, list(ANSWERS[run.branch])
    talk_and_verify(run, "half SPEED")
    turns: list[tuple[int, int, int]] = []

    tainted = {"battle": False}

    def fresh(_context) -> None:
        tainted["battle"] = False

    def menu(_context) -> None:
        # Paralysis stacks on top, which C08S measures. It also stays on the party from
        # battle to battle, so cure it here; the Speed it quartered lasts this battle.
        if h.read8("wBattleMonStatus") & 1 << 6:
            run.log_intervention("setup", cured="paralysis, so the next battle shows plain Speed")
            h.write8("wBattleMonStatus", 0)
            for index in range(h.read8("wPartyCount")):
                h.write8("wPartyMon1Status", 0, offset=index * PARTY_STRUCT)
            tainted["battle"] = True
        if not tainted["battle"]:
            turns.append((bcd2(h, "wBattleMonSpeed"), bcd2(h, "wPlayerMonUnmodifiedSpeed"),
                          h.read8("wPlayerMonSpeedMod")))

    h.register_hook("StartBattle", fresh)
    h.register_hook("DisplayBattleMenu", menu)
    run.play_zone()
    settle_expected(prize)
    run.check("third bargain settled", expected, run.earned)
    plain = [t for t in turns if t[2] == 7]
    run.must_reach("turns at a neutral Speed stage", bool(plain))
    for speed, unmodified, _stage in plain[:12]:
        run.check("Speed carries only this bargain's halving",
                  max(1, unmodified // 2) if accept else unmodified, speed)
    run.notes.append(f"post-move hook calls {drains['count']}, turn limit quoted {limit}")
    run.control_check("after the chain")


def s02(run: Run) -> None:
    """Save and CONTINUE inside the bargained stage, then finish the zone."""
    h, agent = run.h, run.agent
    lobby = agent.lobby_map
    before = talk_and_verify(run)
    limit = h.pyboy.frame_count + 6000
    while h.read8("hCurMap") == lobby and h.pyboy.frame_count < limit:
        agent.step()
    run.must_reach("a stage was entered", h.read8("hCurMap") != lobby)
    stage = h.read8("hCurMap")
    # The entry walk is scripted and masks START: save only once it has ended.
    limit = h.pyboy.frame_count + 1500
    while (h.pyboy.frame_count < limit and
           (h.read8("hSimulatedJoypadStatesIndex") or h.read8("hJoyIgnore") or agent.mode() != "overworld")):
        agent.step()
    saved, loaded = run.save_and_continue()
    run.notes.append(f"saved {saved}")
    run.check("bargain state survives Save and CONTINUE", saved, loaded)
    run.check("CONTINUE returns to the stage", stage, run.h.read8("hCurMap"))
    run.check("accepted flag matches the answer", run.branch == "accept", run.accepted)
    run.play_zone()
    lifecycle_settlement(run, prize=run.case.prize, before=before)


def s03(run: Run) -> None:
    """Save and CONTINUE after settlement: the prize stays and is not granted twice."""
    before = talk_and_verify(run)
    run.play_zone()
    lifecycle_settlement(run, prize=run.case.prize, before=before)
    earned = run.earned
    saved, loaded = run.save_and_continue()
    run.notes.append(f"saved {saved}")
    run.check("bargain state survives Save and CONTINUE", saved, loaded)
    run.check("earned bytes survive", earned, run.earned)
    run.check("still settled after CONTINUE", False, run.accepted)
    run.control_check("after CONTINUE")


def s04(run: Run) -> None:
    """The Hall of Fame's Endless path settles a pending bargain before it clears the flags."""
    h = run.h
    before = talk_and_verify(run)
    expected = list(before)
    if run.branch == "accept":
        expected[(run.case.prize - 1) // 8] |= 1 << ((run.case.prize - 1) % 8)
    settles = h.hook_flag("WitchSettlePendingPrize")
    h.park_before_hijack()
    run.log_intervention("replay", routine="EndlessContinue called directly from the lobby state")
    h.call_routine("EndlessContinue", limit=120000)
    run.must_reach("the Endless path settled", settles["count"] > 0)
    run.check("earned bytes after the Endless settlement", expected, run.earned)
    run.check("accepted flag cleared", False, run.accepted)
    run.check("no challenge left", 0, h.read8("wWitchChallenge"))
    run.check("depth rose", 1, h.read8("wEndlessDepth"))


# ---- Row extras: recoil edges, lost actions, nurse, healing move ---------------------

def c12m(run: Run) -> None:
    """A multi-hit move recoils once from its last hit, a miss not at all, recoil can KO,
    and the replacement's status move carries no second recoil."""
    h, agent = run.h, run.agent
    moves = {name: MOVES_BY_NAME[name] for name in ("FURY_ATTACK", "THUNDER", "TACKLE", "GROWL")}
    plan = ["FURY_ATTACK", "THUNDER", "TACKLE", "GROWL"]
    state = hold_enemy(run, menus_up=len(plan) + 1)
    slot_of = {name: index for index, name in enumerate(moves)}
    agent.move_policy = lambda a: slot_of[plan[state["menus"] - 1]] if state["battles"] == 1 and state["menus"] <= len(plan) else slot_of["TACKLE"]
    rows: list[dict[str, int]] = []
    recoils: list[int] = []

    def sturdy() -> None:
        for index in range(h.read8("wPartyCount")):
            base = index * PARTY_STRUCT
            for label in ("wPartyMon1HP", "wPartyMon1MaxHP"):
                h.write8(label, 999 >> 8, offset=base)
                h.write8(label, 999 & 0xFF, offset=base + 1)
        run.log_intervention("setup", party_hp="every member's HP and max HP set to 999 at the stage door")

    def menu(_context) -> None:
        if state["battles"] != 1:
            return
        h.write8("wEnemyMonSpeed", 0)
        h.write8("wEnemyMonSpeed", 1, offset=1)      # the player moves first, so step 3's own recoil is the KO
        if state["menus"] == 3:
            h.write8("wBattleMonHP", 0)
            h.write8("wBattleMonHP", 1, offset=1)

    def post(_context) -> None:
        rows.append({"menu": state["menus"], "battle": state["battles"], "move": h.read8("wPlayerSelectedMove"),
                     "damage": bcd2(h, "wDamage"), "hits": h.read8("wPlayerNumHits"), "missed": h.read8("wMoveMissed"),
                     "state": h.read8("wBridgeRepeatState"), "recoils": len(recoils),
                     "slot": h.read8("wPlayerMonNumber")})

    def recoil(_context) -> None:
        registers = h.pyboy.register_file
        recoils.append(registers.B << 8 | registers.C)

    def force_miss(_context) -> None:
        if h.read8("hWhoseTurn") == 0 and state["battles"] == 1 and state["menus"] <= 3:
            h.pyboy.register_file.A = 0xFF if state["menus"] == 2 else 0

    at_stage_door(run, sturdy)
    h.register_hook("DisplayBattleMenu", menu)
    h.register_hook("HandlePostPlayerMoveWitchEffects", post)
    h.register_hook("ApplyWitchSelfDamage", recoil)
    run.hook_after_call("MoveHitTest.doAccuracyCheck", "BattleRandom", force_miss)
    run.log_intervention("replay", draw="accuracy roll forced: step 2's Thunder to 255, steps 1 and 3 to 0",
                         where="MoveHitTest.doAccuracyCheck")
    run.log_intervention("setup", steps=plan, step3_hp=1, enemy_speed=1)
    before = talk_and_verify(run, "Every hit you")
    run.play_zone()
    run.notes.append(f"rows {rows[:8]} recoils {recoils[:8]}")
    accept = run.branch == "accept"

    def row_for(menu_index: int) -> tuple[dict[str, int], int]:
        found = [i for i, r in enumerate(rows) if r["battle"] == 1 and r["menu"] == menu_index]
        run.must_reach(f"step {menu_index} ran", bool(found))
        i = found[-1]
        after = rows[i + 1]["recoils"] if i + 1 < len(rows) else len(recoils)
        return rows[i], after - rows[i]["recoils"]

    fury, gained = row_for(1)
    run.must_reach("Fury Attack landed more than once", fury["hits"] >= 0 and fury["damage"] > 0 and fury["state"] != 0)
    run.check("multi-hit: one recoil for the move", 1 if accept else 0, gained)
    if accept:
        run.check("multi-hit: the recoil is the last hit's quarter", max(1, fury["damage"] // 4), recoils[fury["recoils"]])
    miss, gained = row_for(2)
    run.check("the forced roll missed", 1, 1 if miss["missed"] else 0)
    run.check("a miss recoils nothing", 0, gained)
    ko, gained = row_for(3)
    run.check("step 3: recoil on the 1 HP mon", 1 if accept else 0, gained)
    replacement, gained = row_for(4)
    if accept:
        run.check("the recoil KO brought in a replacement", True, replacement["slot"] != ko["slot"])
    run.check("the replacement's status move recoils nothing", 0, gained)
    lifecycle_settlement(run, prize=run.case.prize, before=before)


def c14x(run: Run) -> None:
    """A lost action clears the streak; a switch starts a new one."""
    h, agent = run.h, run.agent
    # Steps: A, A (penalty), A with the action lost, A, A (penalty), switch, then A.
    state = hold_enemy(run, menus_up=8)
    switch_menu = 6
    lost_menu = 3
    agent.move_policy = lambda a: 0
    original = agent.break_stalemate

    def switch_once():
        # The agent's own hook runs before hold_enemy's count for this menu.
        if state["battles"] == 1 and state["menus"] + 1 == switch_menu:
            return 1
        return original()

    agent.break_stalemate = switch_once
    rows: list[dict[str, int]] = []
    penalties = h.hook_flag("HandlePostPlayerMoveWitchEffects.sameMoveApply")

    def lose_action(_context) -> None:
        if state["battles"] == 1 and state["menus"] == lost_menu:
            h.write8("wBattleMonStatus", 1 << 5)  # frozen, after the move was selected

    def post(_context) -> None:
        if state["battles"] != 1:
            return
        rows.append({"menu": state["menus"], "state": h.read8("wBridgeRepeatState"),
                     "penalties": penalties["count"], "slot": h.read8("wPlayerMonNumber")})
        if state["menus"] == lost_menu:
            h.write8("wBattleMonStatus", 0)

    def menu(_context) -> None:
        if state["battles"] == 1:
            h.write8("wEnemyMonSpeed", 0)
            h.write8("wEnemyMonSpeed", 1, offset=1)

    h.register_hook("DisplayBattleMenu", menu)
    h.register_hook("ExecutePlayerMove", lose_action)
    h.register_hook("HandlePostPlayerMoveWitchEffects", post)
    run.log_intervention("setup", steps="A A lost A A switch A", frozen_menu=lost_menu, enemy_speed=1)
    before = talk_and_verify(run, "Repeat a move")
    run.play_zone()
    run.notes.append(f"rows {rows[:9]}")
    by_menu = {row["menu"]: i for i, row in enumerate(rows)}

    def outcome(menu_index: int) -> tuple[int, bool]:
        run.must_reach(f"menu {menu_index} executed", menu_index in by_menu)
        i = by_menu[menu_index]
        after = rows[i + 1]["penalties"] if i + 1 < len(rows) else penalties["count"]
        return rows[i]["state"], after > rows[i]["penalties"]

    accept = run.branch == "accept"
    for menu_index, want_state, want_penalty in ((1, 1, False), (2, 2, True), (3, 0, False), (4, 1, False),
                                                 (5, 2, True), (7, 1, False)):
        got_state, got_penalty = outcome(menu_index)
        run.check(f"menu {menu_index}: repeat state", want_state, got_state)
        run.check(f"menu {menu_index}: penalty", want_penalty and accept, got_penalty)
    run.check("the switch changed the active mon", True, rows[by_menu[7]]["slot"] != rows[by_menu[5]]["slot"])
    lifecycle_settlement(run, prize=run.case.prize, before=before)


def c15x(run: Run) -> None:
    """Allowed under no-healing: the nurse before the door, and a healing move in battle."""
    h, agent = run.h, run.agent
    lobby = agent.lobby_map
    before = talk_and_verify(run, "No medicine")
    maximum = bcd2(h, "wPartyMon1MaxHP")
    poke_party_state(run, 0, hp=maximum // 5)
    run.log_intervention("setup", lead_hp=maximum // 5, moves="Recover, then Tackle")
    agent.healed_this_visit = False
    nurse = h.hook_flag("DisplayPokemonCenterDialogue_")
    limit = h.pyboy.frame_count + 6000
    while h.read8("hCurMap") == lobby and h.pyboy.frame_count < limit:
        agent.step()
    run.must_reach("a stage was entered", h.read8("hCurMap") != lobby)
    run.notes.append(f"nurse dialogue entries {nurse['count']}")
    run.check("the nurse healed the lead", maximum, bcd2(h, "wPartyMon1HP"))
    healed: list[tuple[int, int]] = []
    menus = {"n": 0}
    agent.move_policy = lambda a: 0 if menus["n"] == 1 else 1

    def menu(_context) -> None:
        menus["n"] += 1
        h.write8("wEnemyMonSpeed", 0)
        h.write8("wEnemyMonSpeed", 1, offset=1)
        if menus["n"] == 1:
            low = bcd2(h, "wBattleMonMaxHP") // 4
            h.write8("wBattleMonHP", low >> 8)
            h.write8("wBattleMonHP", low & 0xFF, offset=1)

    def post(_context) -> None:
        if menus["n"] == 1 and not healed:
            healed.append((bcd2(h, "wBattleMonHP"), bcd2(h, "wBattleMonMaxHP")))

    h.register_hook("DisplayBattleMenu", menu)
    h.register_hook("HandlePostPlayerMoveWitchEffects", post)
    run.play_zone()
    run.must_reach("Recover was used", bool(healed))
    run.notes.append(f"after Recover {healed}")
    run.require("Recover healed in battle", healed[0][0] > healed[0][1] // 4, healed[0])
    lifecycle_settlement(run, prize=run.case.prize, before=before)


def c15b(run: Run) -> None:
    """The in-battle allowance, called directly. The real battle ITEM list is one fixed
    list of key items (the pocket switch refuses it under BIT_BATTLE_ITEM_LIST), so no
    medicine can reach ItemUseMedicine in battle through the menu: the routine is the
    only way to exercise the allowance."""
    h = run.h
    talk_and_verify(run, "No medicine")
    allowed = h.hook_flag("RogueWitchBlockHealing.allow")
    h.park_before_hijack()
    saved = h.read8("hIsInBattle")
    outcomes: dict[str, int] = {}
    try:
        for label, in_battle in (("outside", 0), ("inside", 1)):
            h.write8("hIsInBattle", in_battle)
            before = allowed["count"]
            run.log_intervention("replay", routine=f"RogueWitchBlockHealing called with hIsInBattle={in_battle}")
            h.call_routine("RogueWitchBlockHealing")
            outcomes[label] = allowed["count"] - before
    finally:
        h.write8("hIsInBattle", saved)
    run.notes.append(f"allow-path hits {outcomes}")
    run.check("allowed in battle", 1, outcomes["inside"])
    run.check("outside battle", 0 if run.branch == "accept" else 1, outcomes["outside"])


def c18z(run: Run) -> None:
    """The next zone spends one PP per move again."""
    h = run.h
    before = talk_and_verify(run, "cost 2 PP")
    run.play_zone()
    lifecycle_settlement(run, prize=run.case.prize, before=before)
    rows: list[tuple[int, int]] = []
    start = {"pp": None}

    def turn(_context) -> None:
        start["pp"] = sum(v & 0x3F for v in h.read_bytes("wBattleMonPP", 4))

    def post(_context) -> None:
        if start["pp"] is not None and h.read8("wBridgeRepeatState"):
            rows.append((start["pp"], sum(v & 0x3F for v in h.read_bytes("wBattleMonPP", 4))))
        start["pp"] = None

    h.register_hook("ExecutePlayerMove", turn)
    h.register_hook("HandlePostPlayerMoveWitchEffects", post)
    run.play_zone()
    run.notes.append(f"next zone PP before/after {rows[:8]}")
    run.must_reach("moves in the next zone", bool(rows))
    for pp_before, pp_after in rows:
        run.check(f"one PP from {pp_before}", 1, pp_before - pp_after)
    run.control_check("after the next zone")


# ---- Forced stages: rows that need one particular map ---------------------------------

def force_stage(run: Run, name: str) -> int:
    """Both doors lead to `name`, the way a Door Dice or a door patch would point them."""
    h, stage = run.h, MAPS[name]
    for label in ("wLobbyDoor1StageMap", "wLobbyDoor2StageMap", "wRogueMap"):
        h.write8(label, stage)
    run.log_intervention("setup", doors=name)
    return stage


def top_up_every_menu(run: Run) -> None:
    h = run.h

    def top_up(_context) -> None:
        h.write8("wBattleMonHP", h.read8("wBattleMonMaxHP"))
        h.write8("wBattleMonHP", h.read8("wBattleMonMaxHP", 1), offset=1)

    h.register_hook("DisplayBattleMenu", top_up)
    run.log_intervention("setup", player="active mon HP topped up at every menu")


def c02d(run: Run) -> None:
    """The Fighting Dojo has its own item ball and its own check of Challenge 2."""
    h = run.h
    top_up_every_menu(run)
    before = talk_and_verify(run, "No item in")
    stage = force_stage(run, "FIGHTING_DOJO")
    hidden: list[bool] = []

    def poll(_context) -> None:
        if h.read8("hCurMap") == stage:
            hidden.append(toggle_hidden(h, "TOGGLE_FIGHTING_DOJO_RANDOM_ITEM"))

    h.register_hook("JoypadOverworld", poll)
    run.play_zone()
    run.must_reach("the Dojo was played", bool(hidden))
    run.notes.append(f"polls {len(hidden)}, hidden first {hidden[0]}, last {hidden[-1]}")
    if run.branch == "accept":
        run.check("the Dojo's ball is hidden once its script has run", True, all(hidden[1:]))
    else:
        run.check("the Dojo's ball starts visible", False, hidden[0])
    lifecycle_settlement(run, prize=run.case.prize, before=before)


def c11x(run: Run) -> None:
    """Into a leader with no legendary with the bargain up. The closed door normally stops
    this, so the open door is repointed: the map load itself must break the bargain."""
    h, agent = run.h, run.agent
    species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
    legendaries = {species[name] for name in ("MEW", "MEWTWO", "CELEBI", "LUGIA", "HO_OH")}
    top_up_every_menu(run)
    before = talk_and_verify(run, "DOOR 1")
    h.write8("wGymChoice", 1 << RAM["BIT_GYM_CHOICE_LATCHED"] | 0 | 1 << 3)
    h.write8("wLobbyDoor1StageMap", MAPS["PEWTER_GYM"])
    h.write8("wRogueMap", MAPS["PEWTER_GYM"])
    run.log_intervention("setup", doors="door 1 repointed to Brock after the bargain; door 2 holds the legendary")
    agent.forced_door = 0
    lobby = agent.lobby_map
    aces: list[int] = []

    def menu(_context) -> None:
        if h.read8("wCurOpponent"):
            aces.append(h.read8("wEnemyPartySpecies", h.read8("wEnemyPartyCount") - 1))

    h.register_hook("DisplayBattleMenu", menu)
    limit = h.pyboy.frame_count + 6000
    while h.read8("hCurMap") == lobby and h.pyboy.frame_count < limit:
        agent.step()
    run.must_reach("Brock's gym was entered", h.read8("hCurMap") == MAPS["PEWTER_GYM"])
    run.wait_playable()
    run.check("no bargain on entry", False, run.accepted)
    if run.branch == "accept":
        run.check("the challenge is gone on entry", 0, h.read8("wWitchChallenge"))
    run.play_zone()
    run.must_reach("battles in the gym", bool(aces))
    run.check("no legendary fielded", True, not set(aces) & legendaries)
    run.check("no trade byte", 0, h.read8("wLegendaryBossSpecies"))
    run.check("nothing granted", before, run.earned)
    run.control_check("after the wrong door")


def _money(run: Run, amount: int) -> None:
    digits = f"{amount:06d}"
    for i in range(3):
        run.h.write8("wPlayerMoney", int(digits[2 * i:2 * i + 2], 16), offset=i)


def p10x(run: Run, *, clerk_slot: int, boundary: bool) -> None:
    """Prize 10 at either lobby clerk; with `boundary`, the wallet holds exactly the
    discounted total, so only the prize can pay for it."""
    import autoplay
    h, agent = run.h, run.agent
    before = talk_and_verify(run)
    run.play_zone()
    lifecycle_settlement(run, prize=run.case.prize, before=before)
    rows: list[dict[str, int]] = []
    plan: dict[str, int] = {"n": 0}

    def pre(_context) -> None:
        rows.append({"quote": bcd(h.read_bytes("hMoney", 3))})

    def post(_context) -> None:
        if rows and "checked" not in rows[-1]:
            rows[-1]["checked"] = bcd(h.read_bytes("hMoney", 3))

    def shopping_list(stock: list[int]):
        plan["n"] += 1
        if plan["n"] > 1:
            return None
        index = 0
        if boundary:
            # ItemPrices has no row for TMs: take the first item that has one.
            priced = []
            for position, item in enumerate(stock):
                try:
                    priced.append((position, agent.price(item)))
                except ValueError:
                    continue
            if not priced:
                return None
            index, price = priced[0]
            total = price * 2
            plan["wallet"] = total - total // 10
        else:
            plan["wallet"] = 90000
        _money(run, plan["wallet"])
        run.log_intervention("setup", wallet=plan["wallet"])
        return (index, 2, stock[index])

    h.register_hook("RogueWitchDiscountBuyPrice", pre)
    h.register_hook("DisplayPokemartDialogue_.isThereEnoughMoney", post)
    agent.choose_purchase = shopping_list
    agent.shop, agent.shopped_this_visit = True, False
    saved = autoplay.LOBBY_CLERK_SLOT
    autoplay.LOBBY_CLERK_SLOT = clerk_slot
    end = h.pyboy.frame_count + 8000
    try:
        while "wallet" not in plan or (agent.plan is not None and h.pyboy.frame_count < end):
            agent.step()
            if h.pyboy.frame_count > end:
                break
    finally:
        autoplay.LOBBY_CLERK_SLOT = saved
    agent.plan = None
    run.must_reach("a purchase was attempted", "wallet" in plan and bool(rows))
    run.notes.append(f"plan {plan}, rows {rows}, wallet now {run.money}")
    owned = run.branch == "accept"
    quote = rows[0]["quote"]
    expected_total = quote - quote // 10 if owned else quote
    run.check("the total checked and quoted", expected_total, rows[0]["checked"])
    affordable = plan["wallet"] >= expected_total
    run.check("the wallet after the attempt", plan["wallet"] - expected_total if affordable else plan["wallet"], run.money)
    run.control_check("after the clerk")


def p10f(run: Run) -> None:
    """Prize 10 at a forest rest-house clerk, walked to through the real forest."""
    import unittest
    from test_forest_rest_house import ForestWalk, SITE_MASK, ROOT, house_sites
    from source_constants import parse_map_constants, parse_rgbds_constants
    h = run.h
    before = talk_and_verify(run)
    run.play_zone()
    lifecycle_settlement(run, prize=run.case.prize, before=before)

    class Walker(ForestWalk, unittest.TestCase):
        def __init__(self, harness) -> None:
            unittest.TestCase.__init__(self, "run")
            self.h = harness
            self.maps = parse_map_constants(ROOT / "constants/map_constants.asm")
            self.toggles = parse_rgbds_constants(ROOT / "constants/toggle_constants.asm")
            self.sites = house_sites()

    walker = Walker(h)
    forest, house = walker.maps["PROCEDURAL_FOREST"], walker.maps["PROCEDURAL_FOREST_REST_HOUSE"]
    h.write8("wStageEvent", 0)
    h.preload_and_enter_wild_area(forest, "forest")
    run.log_intervention("setup", entry="forest preloaded and entered from the lobby row", wallet=90000)
    for name in ("CLERK_HEALING", "CLERK_STOCK"):
        index = walker.toggles[f"TOGGLE_PFRESTHOUSE_{name}"]
        byte = h.read8("wToggleableObjectFlags", offset=index // 8)
        h.write8("wToggleableObjectFlags", byte & ~(1 << index % 8), offset=index // 8)
    for name in ("RENTAL_OFFICIAL", "SALESMAN"):
        walker.hide(f"TOGGLE_PFRESTHOUSE_{name}")
    site = (h.read_sram_bytes("sProcForestItemGot", 1, bank=0)[0] & SITE_MASK) - 1
    run.must_reach("a rest house in this forest", site >= 0)
    x, y = walker.sites[site]
    h.write8("wProcForestWildBudget", 0)
    walker.walk_to((2 * x + 1, 2 * y + 2))
    walker.press_until("up", house, "into the rest house")
    for move in ("up", "right", "right"):
        walker.step(move)
    _money(run, 90000)
    rows: list[dict[str, int]] = []

    def pre(_context) -> None:
        rows.append({"quote": bcd(h.read_bytes("hMoney", 3))})

    def post(_context) -> None:
        if rows and "checked" not in rows[-1]:
            rows[-1]["checked"] = bcd(h.read_bytes("hMoney", 3))

    h.register_hook("RogueWitchDiscountBuyPrice", pre)
    h.register_hook("DisplayPokemartDialogue_.isThereEnoughMoney", post)
    h.move_tile("right")          # blocked by the clerk: only turns
    h.tick(10)
    for _ in range(40):
        if rows and "checked" in rows[0]:
            break
        h.tap("a")
        h.tick(40)
    h.tick(120)
    run.notes.append(f"forest clerk rows {rows}, wallet now {run.money}")
    run.must_reach("a purchase was attempted at the forest clerk", bool(rows) and "checked" in rows[0])
    quote = rows[0]["quote"]
    expected_total = quote - quote // 10 if run.branch == "accept" else quote
    run.check("the total checked and quoted", expected_total, rows[0]["checked"])
    run.check("the wallet after the purchase", 90000 - expected_total, run.money)


def _p10b(run: Run) -> None:
    p10x(run, clerk_slot=2, boundary=True)


def _p10c(run: Run) -> None:
    p10x(run, clerk_slot=3, boundary=False)


def p04s(run: Run) -> None:
    """With EXP Share on, every recipient gets the +10% from its own amount."""
    h = run.h
    h.write8("wOptions3", h.read8("wOptions3") | 1 << RAM["BIT_EXP_SHARE"])
    run.log_intervention("setup", option="EXP Share on")
    before = talk_and_verify(run)
    run.play_zone()
    lifecycle_settlement(run, prize=run.case.prize, before=before)
    wins = h.hook_flag("GainExperience")
    rows: list[dict[str, int]] = []

    def pending(_context) -> None:
        rows.append({"before": h.read8("hQuotient", 2) << 8 | h.read8("hQuotient", 3), "win": wins["count"]})

    def final(_context) -> None:
        if rows and "final" not in rows[-1]:
            rows[-1]["final"] = h.read8("hQuotient", 2) << 8 | h.read8("hQuotient", 3)

    h.register_hook("WitchBoostExp10Percent", pending)
    h.register_hook("GainExperience.noWitchExpBoost", final)
    finals = h.hook_flag("GainExperience.noWitchExpBoost")
    run.play_zone()
    run.notes.append(f"rows {rows[:8]}, wins {wins['count']}, recipients {finals['count']}")
    run.must_reach("EXP Share split a win between members", finals["count"] > wins["count"] > 0)
    if run.branch == "accept":
        run.check("every recipient reached the prize", finals["count"], len(rows))
        for row in rows:
            run.check(f"+10% from {row['before']}", min(0xFFFF, row["before"] + row["before"] // 10), row["final"])
    else:
        run.check("no prize when declined", [], rows)
    run.control_check("after the zone")


def gift_door(run: Run) -> None:
    """A Door Dice after a bargain lands on a gift room. A gift room returns straight to the
    lobby, so a bargain still up would pay a prize for nothing: rolling must end it first."""
    from autoplay import AutoplayAgent
    h, agent = run.h, run.agent
    before = talk_and_verify(run)
    h.write8("wDiceCharges", (h.read8("wDiceCharges") & 0b11111100) | 1)  # one roll: the plan retries while the lead is hurt
    fired = {"n": 0}

    def force_gift(_context) -> None:
        if not fired["n"]:
            fired["n"] = 1
            h.pyboy.register_file.PC = h.address("BridgeRollAndAssign.fire")

    def use_the_dice(_context) -> None:
        h.pyboy.register_file.PC = h.address("ItemUseDoorDice")

    def warning(_context) -> None:
        agent.answers, agent.witch_talking = ["yes"], True
        agent.witch_talk_frame = h.pyboy.frame_count

    h.register_hook("DoorDiceBargainWarning", warning)
    item = min(agent.heal_amounts, key=lambda i: agent.heal_amounts[i])
    h.write8("wRecoveryItemCounts", 1, offset=agent.recovery_table.index(item))
    maximum = bcd2(h, "wPartyMon1MaxHP")
    poke_party_state(run, 0, hp=maximum // 5)
    h.register_hook("BridgeRollAndAssign", force_gift)
    h.register_hook("ItemUseMedicine", use_the_dice)
    run.log_intervention("replay", dispatch="ItemUseMedicine redirected to ItemUseDoorDice",
                         draw="the gift-room roll forced to fire once")
    agent.plan = AutoplayAgent.choose_heal(agent)
    run.must_reach("a plan to open the bag", agent.plan is not None)
    end = h.pyboy.frame_count + 4000
    while agent.plan is not None and h.pyboy.frame_count < end:
        agent.step()
    agent.plan = None
    doors = {h.read8("wLobbyDoor1StageMap"), h.read8("wLobbyDoor2StageMap")}
    run.must_reach("the dice landed on gift rooms", doors <= GIFT_ROOMS)
    run.check("rolling ended any bargain", False, run.accepted)
    prize = run.case.prize - 1
    lobby = agent.lobby_map
    limit = h.pyboy.frame_count + 8000
    while h.read8("hCurMap") == lobby and h.pyboy.frame_count < limit:
        agent.step()
    run.must_reach("a gift room was entered", h.read8("hCurMap") in GIFT_ROOMS)
    limit = h.pyboy.frame_count + 30000
    while h.read8("hCurMap") != lobby and h.pyboy.frame_count < limit:
        agent.step()
    run.must_reach("back in the lobby", h.read8("hCurMap") == lobby)
    run.wait_playable()
    earned_prize = bool(run.earned[prize // 8] >> (prize % 8) & 1)
    run.notes.append(f"doors {sorted(doors)}, accepted now {run.accepted}, prize granted {earned_prize}, "
                     f"earned {before} -> {run.earned}")
    run.check("a gift room pays no prize", False, earned_prize)
    run.control_check("after the gift room")


def hall_of_fame(run: Run) -> None:
    """Elite Four, Champion and the Hall of Fame into Endless, played by the agent."""
    h, agent = run.h, run.agent
    top_up_every_menu(run)
    offers = h.hook_flag("EndlessOffer")
    continues = h.hook_flag("EndlessContinue")
    earned = run.earned
    end = h.pyboy.frame_count + run.case.max_frames

    def answer(_context) -> None:
        agent.answers, agent.witch_talking = ["yes"], True
        agent.witch_talk_frame = h.pyboy.frame_count

    h.register_hook("EndlessOffer", answer)
    maps: list[int] = []
    while not continues["count"] and h.pyboy.frame_count < end:
        agent.step()
        run.raise_on_hook_error()
        current = h.read8("hCurMap")
        if not maps or maps[-1] != current:
            maps.append(current)
    names = {value: name for name, value in MAPS.items()}
    run.notes.append(f"maps {[names.get(m, m) for m in maps]}, offers {offers['count']}")
    run.must_reach("the Endless offer", offers["count"] > 0)
    run.must_reach("Endless continued", continues["count"] > 0)
    run.wait_playable(20000)
    run.check("depth rose", 1, h.read8("wEndlessDepth"))
    run.check("earned bytes kept into Endless", earned, run.earned)
    run.check("no bargain carried over", False, run.accepted)
    run.check("no challenge carried over", 0, h.read8("wWitchChallenge"))
    run.control_check("the new circuit plays")


# ---- Prize 9 Multistrike -----------------------------------------------------------

def p09(run: Run) -> None:
    h = run.h
    state = hold_enemy(run, menus_up=12)
    run.agent.move_policy = lambda agent: (state["menus"] - 1) % 2   # FURY_ATTACK, DOUBLE_KICK
    rows: list[dict[str, int]] = []
    zone = {"n": 1}

    def hits(_context) -> None:
        rows.append({"zone": zone["n"], "whose": h.read8("hWhoseTurn"), "move": h.read8("wPlayerSelectedMove"),
                     "enemy_move": h.read8("wEnemySelectedMove"), "hits": h.pyboy.register_file.A})

    h.register_hook("TwoToFiveAttacksEffect.saveNumberOfHits", hits)
    before = talk_and_verify(run)
    run.play_zone()
    lifecycle_settlement(run, prize=run.case.prize, before=before)
    zone["n"] = 2
    run.play_zone()
    run.notes.append(f"rows {rows[:14]}")
    owned = run.branch == "accept"
    fury, kick = MOVES_BY_NAME["FURY_ATTACK"], MOVES_BY_NAME["DOUBLE_KICK"]
    player = [r for r in rows if not r["whose"]]
    fury_rows = [r for r in player if r["move"] == fury]
    kick_rows = [r for r in player if r["move"] == kick]
    for zone_number in (1, 2):
        run.must_reach(f"zone {zone_number}: 2 to 5 hit rolls", any(r["zone"] == zone_number for r in fury_rows))
    for row in fury_rows:
        boosted = owned and row["zone"] == 2
        run.check(f"zone {row['zone']} hit count {row['hits']}", True,
                  row["hits"] in ((4, 5) if boosted else (2, 3, 4, 5)))
    if not owned:
        run.must_reach("an unboosted 2 or 3 hit roll", any(r["hits"] < 4 for r in fury_rows))
    run.check("a fixed two-hit move stays at 2", [2] * len(kick_rows), [r["hits"] for r in kick_rows])
    run.check("enemy rolls are never forced to 4 or 5", True,
              all(r["hits"] in (2, 3, 4, 5) for r in rows if r["whose"]))
    run.control_check("after the prize's zone")


# ---- Prize 10 Shop discount --------------------------------------------------------

def p10(run: Run) -> None:
    h = run.h
    rows: list[dict[str, int]] = []
    zone = {"n": 1}

    def pre(_context) -> None:
        rows.append({"zone": zone["n"], "quote": bcd(h.read_bytes("hMoney", 3)), "wallet": run.money})

    def post(_context) -> None:
        if rows and "charge_quote" not in rows[-1]:
            rows[-1]["charge_quote"] = bcd(h.read_bytes("hMoney", 3))
            rows[-1]["wallet_at_check"] = run.money
        # The wallet now is the previous purchase's after-payment wallet.
        for earlier in rows[:-1]:
            earlier.setdefault("wallet_after", run.money)

    def poll(_context) -> None:
        for row in rows:
            if "charge_quote" in row:
                row.setdefault("wallet_after", run.money)

    h.register_hook("RogueWitchDiscountBuyPrice", pre)
    h.register_hook("DisplayPokemartDialogue_.isThereEnoughMoney", post)
    h.register_hook("JoypadOverworld", poll)
    before = talk_and_verify(run)
    run.play_zone()
    lifecycle_settlement(run, prize=run.case.prize, before=before)
    zone["n"] = 2
    # A fixed shopping list, so the purchase does not depend on what the bag already holds:
    # two of the first item on the clerk's list, then done.
    purchases = {"n": 0}

    def shopping_list(stock: list[int]):
        purchases["n"] += 1
        return (0, 2, stock[0]) if purchases["n"] == 1 else None

    run.agent.choose_purchase = shopping_list
    run.log_intervention("setup", shopping="buy 2 of the first item on the clerk's list, once")
    run.agent.shop = True
    run.agent.shopped_this_visit = False
    run.play_zone()
    run.notes.append(f"rows {rows[:6]}")
    owned = run.branch == "accept"
    bought = [r for r in rows if r["zone"] == 2 and "wallet_after" in r]
    run.must_reach("a purchase in the lobby after settlement", bool(bought))
    for row in bought:
        expected = row["quote"] - row["quote"] // 10 if owned else row["quote"]
        run.check(f"quote {row['quote']}: total shown, checked and charged", expected, row["charge_quote"])
        run.check("wallet charged exactly the checked total", row["charge_quote"], row["wallet"] - row["wallet_after"])
    run.control_check("after the prize's zone")


# ---- 5 Increased levels ------------------------------------------------------------

def level_bonus(level: int) -> int:
    """Expected result of RogueApplyWitchLevelBonus: +(L*26)>>8, minimum +1, saturating."""
    return min(255, level + max(1, (level * 26) >> 8))


def c05(run: Run) -> None:
    h = run.h
    rows: list[dict[str, int]] = []

    def entry(_context) -> None:
        row = {"in": h.read8("wCurEnemyLevel")}
        # Boundary inputs, accept only: 9 (the minimum applies), 10, and 250 (saturates).
        # The exit hook restores the natural result, so the battle is the real one.
        poke = {1: 9, 2: 10, 3: 250}.get(len(rows)) if run.branch == "accept" else None
        if poke is not None:
            row["natural"] = row["in"]
            row["in"] = poke
            h.write8("wCurEnemyLevel", poke)
            run.log_intervention("poke", label="wCurEnemyLevel", value=poke, natural=row["natural"],
                                 where="RogueApplyWitchLevelBonus entry")
        rows.append(row)

    def exit_(_context) -> None:
        registers = h.pyboy.register_file
        rows[-1]["out"] = registers.A
        if "natural" in rows[-1]:
            registers.A = level_bonus(rows[-1]["natural"])  # the real fight uses the real level

    h.register_hook("RogueApplyWitchLevelBonus", entry)
    h.register_hook("RogueApplyWitchLevelBonus.lvlBonusOk", exit_)
    before = talk_and_verify(run, "Foes will be")
    run.play_zone()
    run.notes.append(f"rows {rows[:8]}")
    run.must_reach("the level helper ran for enemies", len(rows) >= 4)
    if run.branch == "accept":
        for row in rows:
            run.check(f"level {row['in']} after the bonus", level_bonus(row["in"]), row.get("out"))
        run.must_reach("the 250 boundary was exercised", any(r["in"] == 250 for r in rows))
        run.check("250 saturates at 255", 255, next(r["out"] for r in rows if r["in"] == 250))
        run.check("9 gets the +1 minimum", 10, next(r["out"] for r in rows if r["in"] == 9))
    else:
        run.check("no level change when declined", [], [r for r in rows if "out" in r])
    lifecycle_settlement(run, prize=run.case.prize, before=before)


# ---- 9 All poisoned ----------------------------------------------------------------

STATUS_PSN, STATUS_BRN = 1 << 3, 1 << 4


def poke_party_state(run: Run, index: int, *, status: int | None = None, hp: int | None = None) -> None:
    h, base = run.h, index * PARTY_STRUCT
    if status is not None:
        h.write8("wPartyMon1Status", status, offset=base)
    if hp is not None:
        h.write8("wPartyMon1HP", hp >> 8, offset=base)
        h.write8("wPartyMon1HP", hp & 0xFF, offset=base + 1)
    run.log_intervention("setup", party_index=index, status=status, hp=hp)


def party_statuses(h) -> list[int]:
    return [h.read8("wPartyMon1Status", i * PARTY_STRUCT) for i in range(h.read8("wPartyCount"))]


def c09(run: Run) -> None:
    h = run.h
    before = talk_and_verify(run, "poisoned")
    lobby = run.agent.lobby_map
    samples: list[dict[str, object]] = []
    cured = {"done": False}
    zone = {"calls": 0, "start": None}

    def at_door(_context) -> None:
        # The nurse has healed everyone by the time the player leaves, so the
        # already-statused and fainted members are staged at the door itself.
        stage_door = h.read8("wWarpedFromWhichMap") == lobby and h.read8("wWarpedFromWhichWarp") in (2, 3)
        if stage_door and zone["start"] is None:
            poke_party_state(run, 2, status=STATUS_BRN)   # already statused: must be skipped
            poke_party_state(run, 3, hp=0)                # fainted: must be skipped
            zone["start"] = party_statuses(h)

    def entry(_context) -> None:
        if h.read8("hCurMap") == lobby:
            return
        zone["calls"] += 1
        # Third call of the zone: cure a healthy member by hand, then the routine runs.
        if zone["calls"] == 3 and not cured["done"] and run.branch == "accept":
            cured["done"] = True
            poke_party_state(run, 0, status=0)

    def poll(_context) -> None:
        if h.read8("hCurMap") != lobby:
            samples.append({"calls": zone["calls"], "status": party_statuses(h)})

    h.register_hook("WitchCheckPartyLimit", at_door)
    h.register_hook("WitchReapplyPoison", entry)
    h.register_hook("JoypadOverworld", poll)
    run.play_zone()
    start = zone["start"]
    run.notes.append(f"start {start}, first samples {samples[:6]}")
    run.must_reach("the door staging ran", start is not None)
    run.must_reach("overworld samples in the zone", len(samples) >= 6)
    run.must_reach("poison routine ran in the zone", zone["calls"] >= 3)
    stages = [s for s in samples if s["calls"] >= 1]
    run.must_reach("a sample after the first poison poll", bool(stages))
    first = stages[0]["status"]
    if run.branch == "accept":
        run.check("healthy members poisoned, statused and fainted skipped",
                  [STATUS_PSN, STATUS_PSN, STATUS_BRN, 0], first[:4])
        run.must_reach("the cure was applied", cured["done"])
        after_cure = [s for s in samples if s["calls"] >= 4]
        run.must_reach("a sample after the cure", bool(after_cure))
        run.check("a cured member is poisoned again at the next step", STATUS_PSN, after_cure[0]["status"][0])
    else:
        run.check("declined: nothing poisoned", start, first[:4])
    cured["done"] = True
    lifecycle_settlement(run, prize=run.case.prize, before=before)
    # Next zone: the bargain is closed, so a healthy party stays clean.
    samples.clear()
    cured["done"] = True
    run.play_zone()
    run.must_reach("samples in the next zone", len(samples) >= 4)
    run.check("next zone: no member poisoned by the witch", False,
              any(s["status"][0] & STATUS_PSN for s in samples[:4]))


# ---- 10 Turn limit -----------------------------------------------------------------

def c10(run: Run) -> None:
    h = run.h
    entries: list[dict[str, int]] = []
    battle = {"menus": 0, "inits": 0, "zero_at_init": []}

    def start(_context) -> None:
        battle["starting"] = True

    def init(_context) -> None:
        # The witch's offer text computes the limit here too, with no battle to start.
        if not battle.pop("starting", False):
            return
        battle["menus"] = 0
        battle["inits"] += 1
        battle["zero_at_init"].append(h.read8("wBattleTurnCount"))

    def hold(_context) -> None:
        # Keep the enemy alive past the limit, then let it die. Logged as setup.
        battle["menus"] += 1
        # Player HP is topped up each menu so a long battle cannot black out. The drain
        # checks read the HP bar's old and new values, not a delta against this HP.
        h.write8("wBattleMonHP", h.read8("wBattleMonMaxHP"))
        h.write8("wBattleMonHP", h.read8("wBattleMonMaxHP", 1), offset=1)
        if battle["menus"] <= h.read8("wBattleTurnLimit") + 2:
            for label in ("wEnemyMonHP", "wEnemyMonMaxHP"):
                h.write8(label, 0x0F)
                h.write8(label, 0, offset=1)
        else:
            h.write8("wEnemyMonHP", 0)
            h.write8("wEnemyMonHP", 1, offset=1)

    def drain_entry(_context) -> None:
        entries.append({"pre": h.read8("wBattleTurnCount"), "limit": h.read8("wBattleTurnLimit"),
                        "max_hp": bcd2(h, "wBattleMonMaxHP"), "battle": battle["inits"]})

    def drained(_context) -> None:
        entries[-1]["drain"] = h.read8("wHPBarOldHP") + (h.read8("wHPBarOldHP", 1) << 8) \
            - h.read8("wHPBarNewHP") - (h.read8("wHPBarNewHP", 1) << 8)
        entries[-1]["post"] = h.read8("wBattleTurnCount")

    h.register_hook("WitchInitTurnLimit", start)
    h.register_hook("WitchComputeTurnLimit", init)
    h.register_hook("DisplayBattleMenu", hold)
    h.register_hook("HandleTurnLimitDrain", drain_entry)
    h.register_hook("HandleTurnLimitDrain.noOverkill", drained)
    run.log_intervention("setup", enemy="HP held at 3840+ until two menus past the limit, then 1, each battle",
                         player="active mon HP topped up at every menu")
    limit = h.read8("wBattleTurnLimit")
    before = talk_and_verify(run, f"After {limit} turns")
    run.play_zone()
    run.notes.append(f"limit {limit}, entries {entries[:14]}")
    run.must_reach("battles ran the drain hook", len(entries) >= limit)
    if run.branch == "accept":
        run.must_reach("a battle reached the limit", any("drain" in e for e in entries))
        run.check("every battle's counter starts at 0", [0] * len(battle["zero_at_init"]),
                  battle["zero_at_init"])
        for e in entries:
            run.check(f"limit in force (battle {e['battle']}, pre {e['pre']})", limit, e["limit"])
            run.check(f"drain happens exactly when the counter reaches the limit (pre {e['pre']})",
                      e["pre"] + 1 >= limit, "drain" in e)
            if "drain" in e:
                run.check("drain is max HP / 16, minimum 1", max(1, e["max_hp"] // 16), e["drain"])
        first = next(e for e in entries if "drain" in e)
        run.notes.append(f"first drain ended turn {first['post']} (quoted limit {limit})")
        run.check("first drain ends turn X, the quoted limit", limit, first["post"])
    else:
        run.check("declined: no drain", [], [e for e in entries if "drain" in e])
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
    Case("C12", "Recoil on every hit", C["CHALLENGE_RECOIL_ATTACKS"], C["PRIZE_RARITY_ITEM"], _c12,
         Context(battle_count=1, gym_next=False, party=(
             Mon("TAUROS", moves=("STOMP", "PSYBEAM", "GROWL"), pp=(20, 20, 40)), Mon("ALAKAZAM")))),
    Case("C12L", "Recoil on every hit, the original status-move fixture", C["CHALLENGE_RECOIL_ATTACKS"],
         C["PRIZE_RARITY_ITEM"], c12,
         Context(battle_count=1, gym_next=False, party=(
             Mon("TAUROS", moves=("STOMP", "GROWL", "HEADBUTT"), pp=(20, 40, 15)),
             Mon("ALAKAZAM", moves=("PSYBEAM", "GROWL", "HEADBUTT"), pp=(20, 40, 15))))),
    Case("P03", "Prize: money, earned then used", C["CHALLENGE_SLOWED_POKEMON"], C["PRIZE_MONEY"], p03,
         Context(battle_count=1, gym_next=False)),
    Case("P05", "Prize: crit threshold, boundary replay", C["CHALLENGE_SLOWED_POKEMON"], C["PRIZE_CRIT_BOOST"], p05,
         Context(battle_count=1, gym_next=False)),
    Case("C05", "Increased levels, route", C["CHALLENGE_INCREASED_LEVELS"], C["PRIZE_RARITY_ITEM"], c05,
         Context(battle_count=1, gym_next=False)),
    Case("C05G", "Increased levels, gym and leader", C["CHALLENGE_INCREASED_LEVELS"], C["PRIZE_RARITY_ITEM"], c05,
         Context(battle_count=8, gym_next=True)),
    Case("C09", "All poisoned, route", C["CHALLENGE_ALL_POISONED"], C["PRIZE_RARITY_ITEM"], c09,
         Context(battle_count=1, gym_next=False, party=party(4))),
    Case("C10A", "Turn limit, round 0", C["CHALLENGE_TURN_LIMIT"], C["PRIZE_RARITY_ITEM"], c10,
         Context(battle_count=1, gym_next=False)),
    Case("C10B", "Turn limit, round 2", C["CHALLENGE_TURN_LIMIT"], C["PRIZE_RARITY_ITEM"], c10,
         Context(battle_count=ROUND3, gym_next=False)),
    Case("C14", "Same move penalty", C["CHALLENGE_SAME_MOVE_PENALTY"], C["PRIZE_RARITY_ITEM"], c14,
         Context(battle_count=1, gym_next=False, party=(
             Mon("TAUROS", moves=("STOMP", "HEADBUTT", "TACKLE"), pp=(20, 15, 35)), Mon("ALAKAZAM")))),
    Case("C16", "Physical recoil", C["CHALLENGE_RECOIL_PHYSICAL"], C["PRIZE_RARITY_ITEM"], _c16,
         Context(battle_count=1, gym_next=False, party=(
             Mon("TAUROS", moves=("STOMP", "PSYBEAM", "GROWL"), pp=(20, 20, 40)), Mon("ALAKAZAM")))),
    Case("C17", "Special recoil", C["CHALLENGE_RECOIL_SPECIAL"], C["PRIZE_RARITY_ITEM"], _c17,
         Context(battle_count=1, gym_next=False, party=(
             Mon("TAUROS", moves=("STOMP", "PSYBEAM", "GROWL"), pp=(20, 20, 40)), Mon("ALAKAZAM")))),
    Case("C18", "Double PP", C["CHALLENGE_DOUBLE_PP"], C["PRIZE_RARITY_ITEM"], c18,
         Context(battle_count=1, gym_next=False, party=(
             Mon("TAUROS", moves=("STOMP", "HEADBUTT", "TACKLE", "SCRATCH"), pp=(20, 15, 35, 35)), Mon("ALAKAZAM")))),
    Case("C01", "No reward Pokemon", C["CHALLENGE_NO_REWARD_POKEMON"], C["PRIZE_MONEY"], _c01,
         Context(battle_count=1, gym_next=False)),
    Case("C02", "No random item", C["CHALLENGE_NO_RANDOM_ITEM"], C["PRIZE_MONEY"], _c02,
         Context(battle_count=1, gym_next=False)),
    Case("C04", "Reduced rarity", C["CHALLENGE_REDUCED_RARITY"], C["PRIZE_MONEY"], c04,
         Context(battle_count=1, gym_next=False)),
    Case("C04P", "Reduced rarity with prize 1 owned", C["CHALLENGE_REDUCED_RARITY"], C["PRIZE_MONEY"], c04,
         Context(battle_count=1, gym_next=False, earned=(0x01, 0x00))),
    Case("P01", "Prize: reward Pokemon rarity", C["CHALLENGE_NO_MONEY"], C["PRIZE_RARITY_POKEMON"], _p01,
         Context(battle_count=1, gym_next=False, party=party(4))),
    Case("P02", "Prize: random item rarity", C["CHALLENGE_NO_MONEY"], C["PRIZE_RARITY_ITEM"], _p02,
         Context(battle_count=1, gym_next=False, party=party(4))),
    Case("P04", "Prize: EXP +10%", C["CHALLENGE_NO_MONEY"], C["PRIZE_EXP_BOOST"], p04,
         Context(battle_count=1, gym_next=False, party=(Mon("TAUROS", level=50), Mon("ALAKAZAM", level=50)))),
    Case("P06", "Prize: accuracy +26, boundary replay", C["CHALLENGE_NO_MONEY"], C["PRIZE_ACC_BOOST"], p06,
         Context(battle_count=1, gym_next=False, party=(
             Mon("TAUROS", moves=("SLAM", "THUNDER", "TACKLE"), pp=(20, 10, 35)), Mon("ALAKAZAM")))),
    Case("P07", "Prize: Special +12.5%", C["CHALLENGE_NO_MONEY"], C["PRIZE_SPECIAL_BOOST"], p07,
         Context(battle_count=1, gym_next=False)),
    Case("P08", "Prize: resist super effective", C["CHALLENGE_NO_MONEY"], C["PRIZE_RESIST_SUPER"], p08,
         Context(battle_count=1, gym_next=False)),
    Case("P10N", "Nine prizes owned, the tenth completes the set", C["CHALLENGE_NO_MONEY"], C["PRIZE_CHEAP_ITEMS"],
         complete_set, Context(battle_count=1, gym_next=False, earned=(0xFF, 0x01))),
    Case("P10A", "All ten owned, nothing on offer", 0, 0, none_offered,
         Context(battle_count=1, gym_next=False, earned=(0xFF, 0x03))),
    Case("BLK", "Blackout wipes bargain and prizes", C["CHALLENGE_NO_MONEY"], C["PRIZE_CRIT_BOOST"], blackout,
         Context(battle_count=1, gym_next=False, earned=(0x0F, 0x00))),
    Case("C07GL", "Party limit at a gym, exactly the quote", C["CHALLENGE_PARTY_LIMIT"], C["PRIZE_RARITY_ITEM"],
         _c07_legal, Context(battle_count=8, gym_next=True, party=party(2))),
    Case("C07GB", "Party limit at a gym, one extra", C["CHALLENGE_PARTY_LIMIT"], C["PRIZE_RARITY_ITEM"],
         _c07_broken, Context(battle_count=8, gym_next=True, party=party(3))),
    Case("C15", "No healing outside battle", C["CHALLENGE_NO_HEALING"], C["PRIZE_MONEY"], c15,
         Context(battle_count=1, gym_next=False)),
    Case("C06", "Increased rarity foes", C["CHALLENGE_INCREASED_RARITY_FOES"], C["PRIZE_MONEY"], c06,
         Context(battle_count=ROUND3, gym_next=False)),
    Case("C08", "Slowed Pokemon", C["CHALLENGE_SLOWED_POKEMON"], C["PRIZE_MONEY"], c08,
         Context(battle_count=1, gym_next=False, party=(
             Mon("TAUROS", moves=("TACKLE", "SCRATCH", "POUND"), pp=(35, 35, 35)), Mon("ALAKAZAM")))),
    Case("C08S", "Speed effects stack with Slowed Pokemon", C["CHALLENGE_SLOWED_POKEMON"], C["PRIZE_MONEY"], c08s,
         Context(battle_count=1, gym_next=False, party=(
             Mon("TAUROS", moves=("TACKLE", "SCRATCH", "POUND"), pp=(35, 35, 35)), Mon("ALAKAZAM")))),
    Case("C11L", "Legendary boss, door 1", C["CHALLENGE_LEGENDARY_BOSS"], 0, _c11l, _c11_context(1, 0)),
    Case("C11R", "Legendary boss, door 2", C["CHALLENGE_LEGENDARY_BOSS"], 0, _c11r, _c11_context(0, 1)),
    Case("C11B", "Legendary boss, either door", C["CHALLENGE_LEGENDARY_BOSS"], 0, _c11b, _c11_context(1, 2)),
    Case("C11N", "Legendary boss, trade refused", C["CHALLENGE_LEGENDARY_BOSS"], 0, _c11n, _c11_context(1, 0)),
    Case("C11W", "Legendary boss, she withdraws", C["CHALLENGE_LEGENDARY_BOSS"], 0, c11w, _c11_context(1, 0)),
    Case("C11M", "Legendary limit, one per run until Endless", C["CHALLENGE_LEGENDARY_BOSS"], 0, _c11m,
         _c11_context(1, 0)),
    Case("C11K", "Legendary boss, Door Dice cancelled", C["CHALLENGE_LEGENDARY_BOSS"], 0, _c11k, _c11_context(1, 0)),
    Case("C11Y", "Legendary boss, Door Dice rolled", C["CHALLENGE_LEGENDARY_BOSS"], 0, _c11y, _c11_context(1, 0)),
    Case("C13E", "Gamblers excluded early", C["CHALLENGE_GAMBLERS_PARADISE"], 0, gate_excluded,
         Context(battle_count=1, gym_next=False), gate_rejects=True),
    Case("C13G", "Gamblers excluded at a gym", C["CHALLENGE_GAMBLERS_PARADISE"], 0, gate_excluded,
         Context(battle_count=37, gym_next=True, badges=0xF0, party=(Mon("ALAKAZAM"), Mon("ARCANINE")),
                 pokes={"wBridgeState": 2 << 6}), gate_rejects=True),
    Case("C13F", "Gamblers excluded before Victory Road", C["CHALLENGE_GAMBLERS_PARADISE"], 0, gate_excluded,
         Context(battle_count=64, gym_next=False, badges=0xFF, party=party(6)),
         gate_rejects=True),
    Case("C01G", "No reward Pokemon excluded at a gym", C["CHALLENGE_NO_REWARD_POKEMON"], 0, gate_excluded,
         Context(battle_count=8, gym_next=True), gate_rejects=True),
    Case("C02G", "No random item excluded at a gym", C["CHALLENGE_NO_RANDOM_ITEM"], 0, gate_excluded,
         Context(battle_count=8, gym_next=True), gate_rejects=True),
    Case("C04G", "Reward rarity excluded at a gym", C["CHALLENGE_REDUCED_RARITY"], 0, gate_excluded,
         Context(battle_count=8, gym_next=True), gate_rejects=True),
    Case("W00G", "No witch when a gift room takes the doors", C["CHALLENGE_NO_MONEY"], 0, _witch_absent_gift,
         Context(battle_count=21, gym_next=True, badges=0b11), gate_hides=True),
    Case("W00E", "No witch once the Elite Four is next", C["CHALLENGE_NO_MONEY"], 0, _witch_absent_elite,
         Context(battle_count=71, gym_next=False, badges=0xFF, events=("EVENT_VICTORY_ROAD_CLEARED",)), gate_hides=True),
    Case("CHAIN", "Three different bargains in a row", C["CHALLENGE_GAMBLERS_PARADISE"], 0, chain,
         Context(battle_count=33, gym_next=False, badges=0x0F, party=(Mon("ALAKAZAM"), Mon("ARCANINE")),
                 pokes={"wBridgeState": 2 << 6})),
    Case("S02", "Save and CONTINUE inside the stage", C["CHALLENGE_NO_MONEY"], C["PRIZE_MONEY"], s02,
         Context(battle_count=1, gym_next=False)),
    Case("S03", "Save and CONTINUE after settlement", C["CHALLENGE_NO_MONEY"], C["PRIZE_MONEY"], s03,
         Context(battle_count=1, gym_next=False)),
    Case("S04", "Hall of Fame to Endless settlement", C["CHALLENGE_NO_MONEY"], C["PRIZE_MONEY"], s04,
         Context(battle_count=1, gym_next=False)),
    Case("C12M", "Recoil: multi-hit, miss, self-KO", C["CHALLENGE_RECOIL_ATTACKS"], C["PRIZE_RARITY_ITEM"], c12m,
         Context(battle_count=1, gym_next=False, party=(
             Mon("TAUROS", moves=("FURY_ATTACK", "THUNDER", "TACKLE", "GROWL"), pp=(20, 10, 35, 40)),
             Mon("ALAKAZAM", moves=("FURY_ATTACK", "THUNDER", "TACKLE", "GROWL"), pp=(20, 10, 35, 40))))),
    Case("C14X", "Same move: lost action and switch", C["CHALLENGE_SAME_MOVE_PENALTY"], C["PRIZE_RARITY_ITEM"], c14x,
         Context(battle_count=1, gym_next=False, party=(
             Mon("TAUROS", moves=("TACKLE", "STOMP"), pp=(35, 20)), Mon("ALAKAZAM", moves=("TACKLE", "PSYBEAM"), pp=(35, 20))))),
    Case("C15X", "No healing: nurse and a healing move", C["CHALLENGE_NO_HEALING"], C["PRIZE_RARITY_ITEM"], c15x,
         Context(battle_count=1, gym_next=False, party=(
             Mon("TAUROS", moves=("RECOVER", "TACKLE"), pp=(20, 35)), Mon("ALAKAZAM")))),
    Case("C15B", "No healing: the in-battle allowance", C["CHALLENGE_NO_HEALING"], C["PRIZE_RARITY_ITEM"], c15b,
         Context(battle_count=1, gym_next=False)),
    Case("C18Z", "Double PP: the next zone is back to one", C["CHALLENGE_DOUBLE_PP"], C["PRIZE_RARITY_ITEM"], c18z,
         Context(battle_count=1, gym_next=False)),
    Case("C02D", "No random item: the Fighting Dojo", C["CHALLENGE_NO_RANDOM_ITEM"], C["PRIZE_RARITY_ITEM"], c02d,
         Context(battle_count=1, gym_next=False)),
    Case("C11X", "Legendary boss, the wrong leader", C["CHALLENGE_LEGENDARY_BOSS"], 0, c11x, _c11_context(1, 0)),
    # FOLLOWUPS #87: every other leader's OfferLegendaryTrade<Leader> entry, through the
    # same real-input lifecycle as C11L (door 1). Lugia leads for Giovanni: his only
    # legendary is Mewtwo, so a Mewtwo lead would own him out.
    Case("C11BL", "Legendary boss, Blaine", C["CHALLENGE_LEGENDARY_BOSS"], 0, _c11l, _c11_context(1, 0, "BLAINE")),
    Case("C11GI", "Legendary boss, Giovanni (Armored Mewtwo)", C["CHALLENGE_LEGENDARY_BOSS"], 0, _c11l,
         _c11_context(1, 0, "GIOVANNI", lead="LUGIA")),
    Case("C11FA", "Legendary boss, Falkner", C["CHALLENGE_LEGENDARY_BOSS"], 0, _c11l, _c11_context(1, 0, "FALKNER")),
    Case("C11MO", "Legendary boss, Morty", C["CHALLENGE_LEGENDARY_BOSS"], 0, _c11l, _c11_context(1, 0, "MORTY")),
    Case("C11PR", "Legendary boss, Pryce", C["CHALLENGE_LEGENDARY_BOSS"], 0, _c11l, _c11_context(1, 0, "PRYCE")),
    Case("P10B", "Prize 10: the wallet holds only the discounted total", C["CHALLENGE_NO_MONEY"], C["PRIZE_CHEAP_ITEMS"],
         _p10b, Context(battle_count=1, gym_next=False, money=5000)),
    Case("P10C", "Prize 10: the second clerk", C["CHALLENGE_NO_MONEY"], C["PRIZE_CHEAP_ITEMS"],
         _p10c, Context(battle_count=1, gym_next=False, money=5000)),
    Case("P10F", "Prize 10: a forest rest-house clerk", C["CHALLENGE_NO_MONEY"], C["PRIZE_CHEAP_ITEMS"], p10f,
         Context(battle_count=1, gym_next=False, money=5000)),
    Case("P04S", "Prize 4 with EXP Share", C["CHALLENGE_NO_MONEY"], C["PRIZE_EXP_BOOST"], p04s,
         Context(battle_count=1, gym_next=False, party=(Mon("TAUROS", level=50), Mon("ALAKAZAM", level=50)))),
    Case("DICEN", "Any bargain: Door Dice cancelled", C["CHALLENGE_NO_MONEY"], C["PRIZE_MONEY"], _dice_no,
         Context(battle_count=1, gym_next=False)),
    Case("DICEY", "Any bargain: Door Dice rolled", C["CHALLENGE_NO_MONEY"], C["PRIZE_MONEY"], _dice_yes,
         Context(battle_count=1, gym_next=False)),
    Case("GIFT", "A Door Dice sends a bargain to a gift room", C["CHALLENGE_NO_MONEY"], C["PRIZE_MONEY"], gift_door,
         Context(battle_count=13, gym_next=True, badges=0b1)),
    Case("HOF", "Elite Four, Hall of Fame, Endless", C["CHALLENGE_NO_MONEY"], 0, hall_of_fame,
         Context(battle_count=71, gym_next=False, badges=0xFF, party=party(6),
                 events=("EVENT_VICTORY_ROAD_CLEARED", "EVENT_AI_DEFEATED")), gate_hides=True, max_frames=500_000),
    Case("P09", "Prize: multistrike", C["CHALLENGE_NO_MONEY"], C["PRIZE_MULTISTRIKE"], p09,
         Context(battle_count=1, gym_next=False, party=(
             Mon("TAUROS", moves=("FURY_ATTACK", "DOUBLE_KICK", "TACKLE"), pp=(20, 30, 35)), Mon("ALAKAZAM")))),
    Case("P10", "Prize: shop discount", C["CHALLENGE_NO_MONEY"], C["PRIZE_CHEAP_ITEMS"], p10,
         Context(battle_count=1, gym_next=False, money=5000)),
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
