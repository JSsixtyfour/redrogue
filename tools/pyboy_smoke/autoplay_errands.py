"""Directed autoplay errands (FOLLOWUPS #87).

`--errands pc,rental,lobby,roompc` (or `all`) sends the agent to features a
natural run never operates: the bridge-room PC, the rental official, the
lobby's rolled NPCs and the Dorm's Room PC. Each enabled errand fires once per
run, at its first eligible visit, and drives its menus with real presses only.
Without the flag nothing here runs and no random stream is drawn, so default
runs stay frame-identical.

An errand is (a goal the overworld walks to, a menu script answered one press
at a time). It ends when the overworld polls again. The party and current box
are snapshotted at the start and compared at the end against the errand's
contract; a violation is reported as an anomaly, never a crash. A failing
errand ends the errand, not the run.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

ERRAND_KINDS = ("pc", "rental", "lobby", "roompc")
BOXMON_STRUCT_LENGTH = 0x21
PARTYMON_STRUCT_LENGTH = 0x2C
NAME_LENGTH = 11
ERRAND_BUDGET = 400  # presses before the errand backs out with B


def parse_errands(text: str | None) -> frozenset[str]:
    """`pc,rental` -> {"pc", "rental"}; `all` -> every kind; None/'' -> none."""
    if not text:
        return frozenset()
    kinds = {part.strip() for part in text.split(",") if part.strip()}
    if "all" in kinds:
        return frozenset(ERRAND_KINDS)
    unknown = kinds - set(ERRAND_KINDS)
    if unknown:
        raise ValueError(f"unknown errand kind(s) {sorted(unknown)}; choose from {ERRAND_KINDS} or all")
    return frozenset(kinds)


def bridge_pc_tiles(root: Path) -> dict[str, list[tuple[int, int]]]:
    """Map constant name -> the tiles of its OpenBridgeBillsPC hidden events.

    Read from data/events/hidden_events.asm: the X,Y of each entry is the tile
    the player faces, standing at (X, Y+1) facing up. The first entry at a
    coordinate wins in the game, so later duplicates are dropped here too."""
    tiles: dict[str, list[tuple[int, int]]] = {}
    seen: dict[str, set[tuple[int, int]]] = {}
    current = None
    entry = re.compile(r"^\s*hidden_(?:event|text_predef)\s+(\d+),\s*(\d+),\s*(\w+)")
    for line in (root / "data/events/hidden_events.asm").read_text(encoding="utf-8").splitlines():
        line = line.split(";", 1)[0]
        header = re.match(r"^\s*hidden_events_for\s+(\w+)", line)
        if header:
            current = header.group(1)
            continue
        match = entry.match(line)
        if not match or current is None:
            continue
        x, y, routine = int(match.group(1)), int(match.group(2)), match.group(3)
        if (x, y) in seen.setdefault(current, set()):
            continue
        seen[current].add((x, y))
        if routine == "OpenBridgeBillsPC":
            tiles.setdefault(current, []).append((x, y))
    return tiles


def map_text_id(root: Path, script: str, name: str) -> int:
    """A map's TEXT_* value: its row in that script's def_text_pointers table (from 1)."""
    source = (root / script).read_text(encoding="utf-8")
    table = source.split("def_text_pointers", 1)[1]
    return re.findall(r"^\s*dw_const\s+\w+,\s*(TEXT_\w+)", table, re.M).index(name) + 1


def roster_identity(h) -> dict[str, object]:
    """The party and current box as order-free multisets of whole mon records
    (struct + nickname), plus their counts. Deposit-then-withdraw and swaps
    leave this unchanged; a lost, duplicated or altered mon does not."""
    def records(count_label, mons_label, struct_length, nicks_label, capacity):
        count = h.read8(count_label)
        if count > capacity:
            return count, ("<count out of range>",)
        if not count:
            return 0, ()  # PyBoy refuses a zero-length read
        mons = h.read_bytes(mons_label, struct_length * count)
        nicks = h.read_bytes(nicks_label, NAME_LENGTH * count)
        return count, tuple(sorted(
            bytes(mons[i * struct_length:(i + 1) * struct_length]) + bytes(nicks[i * NAME_LENGTH:(i + 1) * NAME_LENGTH])
            for i in range(count)))
    party_count, party = records("wPartyCount", "wPartyMons", PARTYMON_STRUCT_LENGTH, "wPartyMonNicks", 6)
    box_count, box = records("wBoxCount", "wBoxMons", BOXMON_STRUCT_LENGTH, "wBoxMonNicks", 20)
    return {"party_count": party_count, "party": party, "box_count": box_count, "box": box}


def combined_mons(identity: dict[str, object]) -> tuple[bytes, ...]:
    """Party + box records reduced to the shared box_struct prefix and the
    nickname, so a mon moved between party and box still matches itself."""
    def core(record: bytes, struct_length: int) -> bytes:
        # box_struct is the party struct's first $21 bytes. Byte 3 (box level)
        # is rewritten from the party level on deposit, so it is left out.
        return record[:3] + record[4:BOXMON_STRUCT_LENGTH] + record[struct_length:]
    mons = [core(r, PARTYMON_STRUCT_LENGTH) for r in identity["party"] if isinstance(r, bytes)]
    mons += [core(r, BOXMON_STRUCT_LENGTH) for r in identity["box"] if isinstance(r, bytes)]
    return tuple(sorted(mons))


@dataclass
class DirectedErrand:
    """One errand in progress. Subclasses set `kind` and answer `button`."""

    kind: str
    run_index: int
    start_frame: int
    before: dict[str, object]
    attempt: int = 0  # this run's attempt number (an errand may run ATTEMPTS times)
    target: str = ""  # which target, for an errand kind with several (lobby NPCs)
    presses: int = 0
    notes: list[str] = field(default_factory=list)
    reached: set[str] = field(default_factory=set)  # milestones, for the report

    ATTEMPTS = 1  # times per run
    BUDGET = ERRAND_BUDGET

    def __post_init__(self):  # the dataclass __init__ calls a subclass's only if the base has one
        pass

    def begin(self, agent) -> None:
        """Called once the errand exists, in the overworld, before its first press."""

    def extra_violations(self, agent) -> list[str]:
        """Contract checks beyond the roster, run when the errand ends."""
        return []

    def button(self, agent) -> str:
        raise NotImplementedError

    def next_button(self, agent) -> str:
        self.presses += 1
        if self.presses > self.BUDGET:
            self.reached.add("budget_exhausted")
            return "b"
        return self.button(agent)

    def contract_violations(self, after: dict[str, object]) -> list[str]:
        """Default contract: no mon gained, lost or changed, wherever it sits."""
        problems = []
        if after["party_count"] < 1:
            problems.append("party is empty")
        if combined_mons(after) != combined_mons(self.before):
            problems.append("party+box mon records changed "
                            f"(party {self.before['party_count']}->{after['party_count']}, "
                            f"box {self.before['box_count']}->{after['box_count']})")
        return problems


# Bill's PC (engine/pokemon/bills_pc.asm): hCurrentMenuItem 0-5 are party
# rows, 6-25 the 5x4 box grid. Mirrors MoveBillsPCCursor{Up,Down,Left,Right}.
PARTY_LENGTH = 6
BOX_COLUMNS = 5
MONS_PER_BOX = 20
PARTY_SUBMENU = {"swap": 0, "deposit": 1, "stats": 2}  # .partyActionMenu
BOX_SUBMENU = {"swap": 0, "withdraw": 1, "stats": 2}  # .noPendingSwap (RELEASE=3 is never chosen)


def bills_pc_moves(item: int, party_count: int) -> dict[str, int]:
    """Where each d-pad press takes the Bill's PC cursor from `item`."""
    moves = {}
    if item < PARTY_LENGTH:
        if item > 0:
            moves["up"] = item - 1
        if item + 1 < party_count:
            moves["down"] = item + 1
        if item < 4:  # BillsPCBoxRowStartMenuItems
            moves["right"] = PARTY_LENGTH + BOX_COLUMNS * item
        return moves
    slot = item - PARTY_LENGTH
    row, column = divmod(slot, BOX_COLUMNS)
    if slot >= BOX_COLUMNS:
        moves["up"] = item - BOX_COLUMNS
    if slot < MONS_PER_BOX - BOX_COLUMNS:
        moves["down"] = item + BOX_COLUMNS
    moves["left"] = item - 1 if column else min(row, party_count - 1)
    if column < BOX_COLUMNS - 1:
        moves["right"] = item + 1
    return moves


def bills_pc_route(start: int, target: int, party_count: int) -> str | None:
    """First press of a shortest cursor path, or None when already there."""
    if start == target:
        return None
    frontier, first = [start], {start: None}
    while frontier:
        nxt = []
        for item in frontier:
            for button, step in bills_pc_moves(item, party_count).items():
                if step not in first:
                    first[step] = first[item] or button
                    if step == target:
                        return first[step]
                    nxt.append(step)
        frontier = nxt
    return None


def bills_pc_tasks(party_count: int, box_count: int) -> list[tuple[str, list[tuple]]]:
    """The Bill's PC errand's work, in order, for this roster. Every task
    leaves the roster as it found it (swaps are done twice). Never RELEASE."""
    p, n = party_count, box_count
    tasks = []
    if p >= 2 and n < MONS_PER_BOX:
        last = p - 1
        tasks.append(("deposit", [("cursor", last), ("a",), ("sub", PARTY_SUBMENU["deposit"])]))
        tasks.append(("withdraw", [("cursor", PARTY_LENGTH + n), ("a",), ("sub", BOX_SUBMENU["withdraw"])]))
    tasks.append(("party_stats", [("cursor", 0), ("a",), ("sub", PARTY_SUBMENU["stats"])]))
    if p >= 2:
        swap = [("cursor", 0), ("a",), ("sub", PARTY_SUBMENU["swap"]), ("cursor", 1), ("a",)]
        tasks.append(("swap_party", swap + swap))
    if n >= 1:
        cross = [("cursor", p - 1), ("a",), ("sub", PARTY_SUBMENU["swap"]), ("cursor", PARTY_LENGTH), ("a",)]
        tasks.append(("swap_party_box", cross + cross))
        tasks.append(("box_stats", [("cursor", PARTY_LENGTH), ("a",), ("sub", BOX_SUBMENU["stats"])]))
    if n >= 2:
        swap = [("cursor", PARTY_LENGTH), ("a",), ("sub", BOX_SUBMENU["swap"]), ("cursor", PARTY_LENGTH + 1), ("a",)]
        tasks.append(("swap_box", swap + swap))
    return tasks


class BridgePCErrand(DirectedErrand):
    """A bridge room's PC: BILL's PC, then each of bills_pc_tasks, then out.

    Context comes from who polls the joypad (agent.last_wait_caller, recorded
    only while an errand runs): the box grid polls from BillsPC_.inputLoop,
    its SWAP/DEPOSIT/STATS boxes and the PC main menu from HandleMenuInput
    (which one: agent.last_menu_caller), anything else is text, answered A.
    A task whose screen does not appear within a few presses is skipped and
    noted, so a refused action (box full, last mon) cannot trap the errand."""

    MISMATCH_LIMIT = 6

    def __post_init__(self):
        self.entered_bills = False
        self.tasks: list[tuple[str, list[tuple]]] | None = None
        self.task_index = 0
        self.step_index = 0
        self.mismatches = 0

    def context(self, agent) -> str:
        waiter = agent.last_wait_caller
        if waiter.startswith("BillsPC_.inputLoop"):
            return "grid"
        if waiter.startswith("HandleMenuInput"):
            caller = agent.last_menu_caller
            if caller.startswith("PCMainMenu"):
                return "pc_menu"
            if caller.startswith("BillsPC_"):
                return "submenu"
        return "text"

    def skip_task(self, why: str) -> None:
        self.notes.append(f"{self.tasks[self.task_index][0]}: {why}")
        self.task_index += 1
        self.step_index = 0
        self.mismatches = 0

    def button(self, agent) -> str:
        where = self.context(agent)
        cursor = agent.h.read8("hCurrentMenuItem")
        if where == "text":
            return "a"
        if where == "pc_menu":
            self.reached.add("pc_main_menu")
            if self.entered_bills:
                return "b"  # LOG OFF
            if cursor:
                return "up"
            self.entered_bills = True
            return "a"  # BILL's PC is the first row
        if self.tasks is None:
            if where != "grid":
                return "b"
            self.reached.add("grid")
            self.tasks = bills_pc_tasks(agent.h.read8("wPartyCount"), agent.h.read8("wBoxCount"))
        while self.task_index < len(self.tasks):
            name, steps = self.tasks[self.task_index]
            if self.step_index >= len(steps):
                self.reached.add(name)
                self.task_index += 1
                self.step_index = 0
                self.mismatches = 0
                continue
            step = steps[self.step_index]
            wanted = "submenu" if step[0] == "sub" else "grid"
            if where != wanted:
                self.mismatches += 1
                if self.mismatches > self.MISMATCH_LIMIT:
                    self.skip_task(f"expected {wanted} at step {self.step_index}, saw {where}")
                    return "b"  # back to the grid
                return "b" if where == "submenu" else "a"
            self.mismatches = 0
            if step[0] == "cursor":
                route = bills_pc_route(cursor, step[1], agent.h.read8("wPartyCount"))
                if route is None:
                    self.step_index += 1
                    continue
                return route
            if step[0] == "a":
                self.step_index += 1
                return "a"
            # ("sub", row): pick that row of the SWAP/DEPOSIT/STATS box.
            if cursor == step[1]:
                self.step_index += 1
                return "a"
            return "down" if cursor < step[1] else "up"
        return "b"  # all done: cancel any pending SWAP, then leave the grid


class RentalErrand(DirectedErrand):
    """The rental official (lobby, or the Forest Rest House): the first
    attempt of a run answers the offer NO, the second YES (RentalInteraction:
    offer text, then a YES/NO box over the money box). Text-only outcomes
    (unavailable, already used, party/box full, no money) end the errand
    without a choice; the report's `reached` says which happened."""

    ATTEMPTS = 2

    def button(self, agent) -> str:
        if agent.last_wait_caller.startswith("HandleMenuInput"):
            self.reached.add("offer")
            want = 1 if self.attempt == 0 else 0  # NO, then YES
            cursor = agent.h.read8("hCurrentMenuItem")
            if cursor != want:
                return "down" if cursor < want else "up"
            self.reached.add("declined" if want else "accepted")
            return "a"
        return "a"

    def contract_violations(self, after: dict[str, object]) -> list[str]:
        return gain_violations(self, after, "accepted" in self.reached)


def gain_violations(errand: DirectedErrand, after: dict[str, object], may_gain: bool) -> list[str]:
    """Contract for an errand that may add one mon (a rental, a purchase):
    nothing owned is lost or altered, and at most one mon arrives, only
    after a YES."""
    from collections import Counter
    before, now = Counter(combined_mons(errand.before)), Counter(combined_mons(after))
    lost, gained = before - now, now - before
    problems = []
    if lost:
        problems.append(f"{sum(lost.values())} owned mon record(s) lost or changed")
    if gained:
        errand.reached.add("delivered")
        if not may_gain:
            problems.append("a mon arrived without a YES")
        if sum(gained.values()) > 1:
            problems.append(f"{sum(gained.values())} mons arrived at once")
    return problems


class ForestRentalErrand(RentalErrand):
    """The Forest Rest House's rental official: its own schedule, so the
    lobby's two attempts never use up the forest's (the rest house has
    ProceduralForestRestHouse_Script and its own RentalInteraction caller)."""


def routine_of(label: str) -> str:
    """'RoomPC.descTableSet+$3' -> 'RoomPC'."""
    return label.split("+", 1)[0].split(".", 1)[0]


def choose(agent) -> str:
    """A on a menu row, forgetting which menu that was. The menu hook sits on
    HandleMenuInput, but a party menu enters through HandleMenuInput_
    (HandlePartyMenuInput) and leaves last_menu_caller as it was, so a stale
    caller would make the party menu look like the box just answered. A menu
    that does not refresh the caller now reads as unknown, and gets B."""
    agent.last_menu_caller = ""
    return "a"


# Lobby NPCs (scripts/IndigoPlateauLobby.asm), in visit order. The four NPCs
# are rolled per visit by PCPsychicSetup; the door signs are bg events.
LOBBY_TARGETS = {
    "psychic": "TEXT_PC_PSYCHIC",
    "salesman": "TEXT_PC_POKEMON_SALESMAN",
    "trader": "TEXT_PC_TRADER_SUPER_NERD",
    "tutor": "TEXT_PC_MOVE_TUTOR",
    "sign1": "TEXT_PC_DOOR1_SIGN",
    "sign2": "TEXT_PC_DOOR2_SIGN",
}
YES, NO = 0, 1  # YesNoChoice rows


class LobbyNPCErrand(DirectedErrand):
    """One lobby NPC or door sign, each at most once per run.

    The NPCs all ask through YesNoChoice (a DisplayTwoOptionMenu box over the
    money box). The first box gets this target's answer: the psychic YES
    (reveals the next leader for money), the salesman NO on a session's first
    run and YES after (buys one mon), the trader NO (a YES trades a mon away),
    the tutor YES and then B at its party menu (no move taught). Any later
    YES/NO box (a nickname offer) gets NO, and any other menu gets B, so no
    menu this errand does not know can pick a mon. Signs are text only."""

    ATTEMPTS = len(LOBBY_TARGETS)

    def __post_init__(self):
        self.answered = False

    def first_answer(self) -> int:
        if self.target == "salesman":
            return YES if self.run_index > 1 else NO
        return {"psychic": YES, "tutor": YES}.get(self.target, NO)

    def button(self, agent) -> str:
        if not agent.last_wait_caller.startswith("HandleMenuInput"):
            return "a"
        if getattr(agent, "party_menu_waiting", False):  # HandlePartyMenuInput's own hook
            self.reached.add("party_menu")
            agent.party_menu_waiting = False  # answered here, as menu_goal_step would
            return "b"
        if routine_of(agent.last_menu_caller) != "DisplayTwoOptionMenu":
            self.reached.add(f"menu:{routine_of(agent.last_menu_caller) or 'unknown'}")
            return "b"
        want = NO if self.answered else self.first_answer()
        cursor = agent.h.read8("hCurrentMenuItem")
        if cursor != want:
            return "down" if cursor < want else "up"
        if not self.answered:
            self.reached.add("accepted" if want == YES else "declined")
            self.answered = True
        else:
            self.reached.add("later_no")
        return choose(agent)

    def contract_violations(self, after: dict[str, object]) -> list[str]:
        return gain_violations(self, after, self.target == "salesman" and "accepted" in self.reached)


# Room PC (custom_functions/room_pc.asm). Top rows: KEY ITEMS 0, FURNITURE 1,
# DECORATIONS 2, RECORDS 3, TOGGLES 4 when Johto or the Time Warp is active,
# then LOG OFF at wMaxMenuItem. FURNITURE and DECORATIONS each handle one
# row and return to the top menu, so each pick is its own visit.
ROOM_TOGGLES_ROW, ROOM_LOG_OFF = 4, "log_off"
ROOM_VISITS = (  # (name, top row, submenu row, pick key)
    ("key_items", 0, None, None),
    ("furniture_pc", 1, 0, "f_pc"),
    ("furniture_top", 1, 1, "f_top"),
    ("furniture_middle", 1, 2, "f_mid"),
    ("furniture_bottom", 1, 3, "f_bot"),
    ("decor_bedside", 2, 4, "d0"),
    ("decor_bottom", 2, 3, "d1"),
    ("decor_top", 2, 1, "d2"),
    ("decor_middle", 2, 2, "d3"),  # spot 1 of the spot picker, if the table has one
    ("decor_pc", 2, 0, "d6"),  # likewise for a LONG DESK
    ("records", 3, None, None),
    ("toggles", ROOM_TOGGLES_ROW, None, None),
    (ROOM_LOG_OFF, None, None, None),
)
ROOM_PICK_VENDOR = {"f_top": "RoomVendorTopIds", "f_mid": "RoomVendorMiddleIds", "f_pc": "RoomVendorDeskIds",
                    "f_bot": "RoomVendorPlantIds"}  # d* keys: RoomVendorPalsIds
ROOM_RECORDS_ROWS = (0, 1)  # RUN TIMES, FURTHEST RUNS (the HoF viewer and SPECIAL FORMS are left alone)
ROOM_VISIT_PRESS_LIMIT = 120


def room_vendor_ids(root: Path) -> dict[str, list[int]]:
    """RoomVendor*Ids tables (custom_functions/room_vendor.asm): a count byte,
    then the owned-bit piece id of list entries 1..count."""
    tables: dict[str, list[int]] = {}
    current, wanted = None, 0
    for line in (root / "custom_functions/room_vendor.asm").read_text(encoding="utf-8").splitlines():
        line = line.split(";", 1)[0].strip()
        label = re.match(r"^(RoomVendor\w+Ids):", line)
        if label:
            current, wanted = label.group(1), -1
            tables[current] = []
            continue
        if current is None or not line.startswith("db "):
            if current is not None and line:
                current = None
            continue
        values = [int(value) for value in re.findall(r"\b\d+\b", line[3:])]
        if wanted < 0:
            wanted, values = values[0], values[1:]
        tables[current].extend(values)
        if len(tables[current]) >= wanted:
            current = None
    return tables


def read_save_sram(h, label: str, length: int) -> list[int]:
    """Read save-bank SRAM, then put the mapper back where the game keeps it
    between accesses (RAM bank 0, RAM disabled; room_pc.asm's file header).
    The cartridge is MBC3, so the bank register touches RAM only."""
    memory, start = h.pyboy.memory, h.address(label)
    memory[0x0000] = 0x0A
    memory[0x4000] = 1
    try:
        return list(memory[start:start + length])
    finally:
        memory[0x4000] = 0
        memory[0x0000] = 0


def room_state(h) -> list[int]:
    """sRoomFurniture (2 bytes) then sRoomDecorSlots (8)."""
    return read_save_sram(h, "sRoomFurniture", 2) + read_save_sram(h, "sRoomDecorSlots", 8)


def room_current_choice(state: list[int], key: str) -> int:
    """The table index the room currently holds for a pick key (sram.asm)."""
    b0, b1 = state[0], state[1]
    if key == "f_top":
        return b0 & 0x0F
    if key == "f_mid":
        return (b0 >> 4) & 0x07
    if key == "f_pc":
        return b1 & 0x01
    if key == "f_bot":
        return 0 if not b0 & 0x80 else (2 if b1 & 0x02 else 1)
    return state[2 + int(key[1:])]  # dN: decoration slot N


def room_pick_row(choice: int, ids: list[int], owned: list[int]) -> int | None:
    """The visible row of table index `choice` in a filtered pick list
    (RoomPickRealIndex inverted): entry 0 always shows, entry k>0 shows when
    its piece id is owned. None when the choice is not shown."""
    def is_owned(piece: int) -> bool:
        return bool(owned[piece >> 3] >> (piece & 7) & 1)
    if choice == 0:
        return 0
    if choice > len(ids) or not is_owned(ids[choice - 1]):
        return None
    return 1 + sum(is_owned(piece) for piece in ids[:choice - 1])


class RoomPCErrand(DirectedErrand):
    """The Dorm's Room PC: each ROOM_VISITS row once, then LOG OFF.

    Every FURNITURE/DECORATIONS pick list opens on row 0, not on the current
    choice, so a blind A would refurnish the room. The errand reads the room
    bytes at its start and moves the cursor to the row that shows the current
    choice (the filter's owned bits are the game's own snapshot in wBuffer +
    19..26), so each pick rewrites the value it found. The contract checks the
    room bytes are unchanged at the end. TOGGLES is opened and left with B
    (changing pools would change the run); KEY ITEMS likewise."""

    BUDGET = 1000

    def __post_init__(self):
        self.visit = 0
        self.entered = False
        self.visit_presses = 0
        self.records_row = 0
        self.room_before: list[int] | None = None

    def begin(self, agent) -> None:
        self.room_before = room_state(agent.h)

    def contract_violations(self, after: dict[str, object]) -> list[str]:
        # The Dorm between runs follows the rogue reset, which empties the
        # party, so the base contract's empty-party check does not apply.
        if combined_mons(after) != combined_mons(self.before):
            return ["party+box mon records changed"]
        return []

    def extra_violations(self, agent) -> list[str]:
        if self.room_before is None:
            return []
        after = room_state(agent.h)
        if after != self.room_before:
            return [f"room bytes changed {self.room_before} -> {after}"]
        return []

    def context(self, agent) -> str:
        if not agent.last_wait_caller.startswith("HandleMenuInput"):
            return "text"
        return {"RoomPC": "top", "RoomFurnitureMenu": "furniture", "RoomDecorationsMenu": "decorations",
                "RoomDrawPickList": "pick", "RoomRecordsMenu": "records"}.get(
                    routine_of(agent.last_menu_caller), "other")

    def skip(self, why: str) -> str:
        self.notes.append(f"{ROOM_VISITS[self.visit][0]}: {why}")
        self.visit_presses = -10_000  # counted as done, not reached, when the top menu returns
        return "b"

    def button(self, agent) -> str:
        where = self.context(agent)
        if where == "text":
            return "a"
        h = agent.h
        cursor = h.read8("hCurrentMenuItem")
        if where == "top":
            self.reached.add("top_menu")
            if self.entered:  # back from the visit just made
                if self.visit_presses >= 0:
                    self.reached.add(ROOM_VISITS[self.visit][0])
                self.visit += 1
                self.entered = False
                self.visit_presses = 0
                self.records_row = 0
            log_off = h.read8("wMaxMenuItem")
            while (self.visit < len(ROOM_VISITS) - 1 and ROOM_VISITS[self.visit][1] == ROOM_TOGGLES_ROW
                   and log_off <= ROOM_TOGGLES_ROW):
                self.visit += 1  # no TOGGLES row before Johto or the Time Warp
            name, row = ROOM_VISITS[min(self.visit, len(ROOM_VISITS) - 1)][:2]
            if name == ROOM_LOG_OFF:
                row = log_off
            if cursor != row:
                return "down" if cursor < row else "up"
            if name == ROOM_LOG_OFF:
                self.reached.add(ROOM_LOG_OFF)
            self.entered = True
            return choose(agent)
        self.visit_presses += 1
        if self.visit_presses > ROOM_VISIT_PRESS_LIMIT:
            return self.skip("press limit")
        name, _, sub_row, key = ROOM_VISITS[min(self.visit, len(ROOM_VISITS) - 1)]
        if where in ("furniture", "decorations"):
            if sub_row is None or (where == "furniture") != key.startswith("f"):
                return self.skip(f"unexpected {where} menu")
            if cursor != sub_row:
                return "down" if cursor < sub_row else "up"
            return choose(agent)
        if where == "pick":
            filtered = h.read8("wBuffer", 27) | h.read8("wBuffer", 28)
            if not filtered:  # a spot picker: SPOT 1
                self.reached.add("spot_picker")
                return choose(agent) if cursor == 0 else "up"
            if key is None or self.room_before is None:
                return self.skip("unexpected pick list")
            ids = agent.room_vendor_ids[ROOM_PICK_VENDOR.get(key, "RoomVendorPalsIds")]
            target = room_pick_row(room_current_choice(self.room_before, key), ids,
                                   h.read_bytes("wBuffer", 8, offset=19))
            if target is None:
                return self.skip("current choice not in the list")
            row = h.read8("wBuffer", 14) + cursor  # scroll offset + window row
            if row != target:
                return "down" if row < target else "up"
            self.reached.add(f"picked:{key}")
            return choose(agent)
        if where == "records":
            if self.records_row >= len(ROOM_RECORDS_ROWS):
                return "b"
            want = ROOM_RECORDS_ROWS[self.records_row]
            if cursor != want:
                return "down" if cursor < want else "up"
            self.records_row += 1
            self.reached.add(f"records:{want}")
            return choose(agent)
        return "b"  # PlayerPC (KEY ITEMS), TOGGLES, anything else: leave it unchanged


ERRAND_CLASSES = {"pc": BridgePCErrand, "rental": RentalErrand, "rental_forest": ForestRentalErrand,
                  "lobby": LobbyNPCErrand, "roompc": RoomPCErrand}
# Flag kinds that also enable internal kinds.
IMPLIED_KINDS = {"rental": ("rental_forest",)}


def expand_kinds(kinds: frozenset[str]) -> frozenset[str]:
    return frozenset(kinds).union(*(IMPLIED_KINDS.get(kind, ()) for kind in kinds))
