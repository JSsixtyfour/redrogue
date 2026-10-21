"""Team judgment for the stronger player (autoplay --player strong): which
reward and which bridge gift to take, on merit instead of at random.

An offered mon is worth its base stat total (form-aware: a form has its own
record in data/pokemon/forms/) plus a bonus for each type the party cannot yet
hit super-effectively that its own types can (STAB coverage). Every reward in
one batch arrives at the same level (the round's reward level), so level does
not separate them. A reward trade (slot 0 while BIT_ROGUE_TRADE_ACTIVE) costs
the mon given away, so its value is the offer's minus the given mon's.

Gifts are read from ROM: the giver's list (BridgeGiverMapTable /
BridgeGiverLists, as GetGiverListBase does) and the 7-byte gift_entry at each
offered index (wGift1-3). Their kinds get rough values on the same scale as a
mon: a mon gift as a reward; a move (taught or as a TM) by its power, more if
a party mon gets STAB from it; anything else a middling constant. These are
judgment calls, chosen to be measured (run_autoplay --player strong), not
tuned values.
"""
from __future__ import annotations

import re
from pathlib import Path

from source_constants import parse_rgbds_constants

COVERAGE_BONUS = 15     # per type newly hit super-effectively
EFFECT_VALUE = 380      # a gift that is neither a mon nor a move: middling
MOVE_VALUE_BASE = 250   # a damaging move, before power and STAB
NON_DAMAGING_MOVE = 230
ITEM_VALUE = 200        # an item that is not a TM
GIFT_ENTRY_SIZE = 7
GIFT_KINDS = ("MON", "ITEM", "TEACH_MOVE", "SPECIAL", "MON_EVOLVE", "GLOBAL_EFFECT", "SELECTED_EFFECT")
BIT_ROGUE_TRADE_ACTIVE = 2


def _record(text: str) -> tuple[int, tuple[str, str]] | None:
    stats = re.search(r"^\s*db\s+(\d+),\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+)\s*$", text, re.M)
    types = re.search(r"^\s*db\s+([A-Z_]+),\s*([A-Z_]+)\s*;\s*type", text, re.M)
    if not (stats and types):
        return None
    return sum(int(v) for v in stats.groups()), (types.group(1), types.group(2))


class TeamJudge:
    def __init__(self, root: Path, harness, rules):
        self.h = harness
        self.rules = rules
        species = parse_rgbds_constants(root / "constants/pokemon_constants.asm")
        by_name: dict[str, tuple[int, tuple[int, int]]] = {}
        for path in (root / "data/pokemon/base_stats").glob("*.asm"):
            text = path.read_text(encoding="utf-8")
            dex = re.search(r"db\s+DEX_([A-Z0-9_]+)", text)
            record = _record(text)
            if dex and record:
                by_name[dex.group(1)] = (record[0], self._types(record[1]))
        self.base: dict[int, tuple[int, tuple[int, int]]] = {
            value: by_name[name] for name, value in species.items() if name in by_name and value}
        self.forms: dict[tuple[int, int], tuple[int, tuple[int, int]]] = {}
        for path in (root / "data/pokemon/forms").glob("*.asm"):
            text = path.read_text(encoding="utf-8")
            pair = re.search(r"form_record\s+(\w+),\s*(\d+)", text)
            record = _record(text)
            if pair and record and pair.group(1) in species:
                self.forms[(species[pair.group(1)], int(pair.group(2)))] = (record[0], self._types(record[1]))
        # TM/HM item -> its move. The add_hm/add_tm macros number the items in
        # source order from the const counter, which the constant parser does not
        # track; each list's first line carries its item id (`; $C4`, `; $C9`).
        moves = parse_rgbds_constants(root / "constants/move_constants.asm")
        text = (root / "constants/item_constants.asm").read_text(encoding="utf-8")
        self.tm_moves = {}
        for macro in ("add_hm", "add_tm"):
            lines = re.findall(rf"^\s*{macro}\s+(\w+)\s*(?:;\s*\$([0-9A-Fa-f]{{2}}))?", text, re.M)
            first = int(lines[0][1], 16)
            for i, (name, _) in enumerate(lines):
                if name in moves:
                    self.tm_moves[first + i] = moves[name]

    def _types(self, names: tuple[str, str]) -> tuple[int, int]:
        return tuple(self.rules.types[n] for n in names)

    # --------------------------------------------------------------- the party

    def party(self) -> list[tuple[int, tuple[int, int], tuple[int, ...]]]:
        """(species, types, moves) per party slot, from the live structs."""
        count = self.h.read8("wPartyCount")
        base = self.h.address("wPartyMon1")
        stride = self.h.address("wPartyMon2") - base
        mem = self.h.pyboy.memory
        types_at = self.h.address("wPartyMon1Type1") - base
        moves_at = self.h.address("wPartyMon1Moves") - base
        return [(mem[base + i * stride], (mem[base + i * stride + types_at], mem[base + i * stride + types_at + 1]),
                 tuple(mem[base + i * stride + moves_at + j] for j in range(4))) for i in range(count)]

    def _hits(self, attack_types) -> set[int]:
        """Defending types some attack type hits super-effectively."""
        return {defender for (attacker, defender), m in self.rules.chart.items()
                if attacker in attack_types and m > 1}

    # ------------------------------------------------------------------ values

    def mon_value(self, species: int, form: int = 0) -> float:
        bst, types = self.forms.get((species, form)) or self.base.get(species, (0, (0, 0)))
        if not bst:
            return 0.0
        have = self._hits({t for _, party_types, _ in self.party() for t in party_types})
        return bst + COVERAGE_BONUS * len(self._hits(set(types)) - have)

    def move_value(self, move: int) -> float:
        rule = self.rules.moves.get(move)
        if rule is None or not rule.power:
            return NON_DAMAGING_MOVE
        stab = any(rule.type in types for _, types, _ in self.party())
        return MOVE_VALUE_BASE + rule.power * (1.5 if stab else 1.0) * rule.accuracy / 100

    def reward_choice(self) -> int:
        """Index of the best reward offer (0-2), or 3 (NO THANKS) when the only
        thing on offer is a losing trade."""
        offers = [self.mon_value(s, f) for s, f in zip(self.h.read_bytes("wRoguePokemon1", 3),
                                                       self.h.read_bytes("wRoguePokemonForm1", 3))]
        if self.h.read8("wRogueFlagsBitfield") >> BIT_ROGUE_TRADE_ACTIVE & 1:
            offers[0] -= self.mon_value(self.h.read8("wroguenpctradegive"))
        best = max(range(len(offers)), key=lambda i: (offers[i], -i))
        return best if offers[best] > 0 else len(offers)

    # ------------------------------------------------------------------- gifts

    def _rom(self, bank: int, address: int) -> int:
        return self.h.pyboy.memory[bank, address] if address >= 0x4000 else self.h.pyboy.memory[0, address]

    def gift_entries(self) -> list[tuple[str, int]]:
        """(kind, param) for each offered gift, read from the giver's list in ROM."""
        bank, maps = self.h.symbols.get("BridgeGiverMapTable")
        _, lists = self.h.symbols.get("BridgeGiverLists")
        here = self.h.read8("hCurMap")
        giver = 0
        while self._rom(bank, maps + giver) != here:
            giver += 1
            if giver > 64:
                raise LookupError(f"map ${here:02X} is not a gift giver")
        table = self._rom(bank, lists + 2 * giver) | self._rom(bank, lists + 2 * giver + 1) << 8
        entries = []
        for index in self.h.read_bytes("wGift1", 3):
            entry = table + 1 + index * GIFT_ENTRY_SIZE  # past the count byte
            kind = self._rom(bank, entry)
            param = self._rom(bank, entry + 1) | self._rom(bank, entry + 2) << 8
            entries.append((GIFT_KINDS[kind] if kind < len(GIFT_KINDS) else f"kind {kind}", param))
        return entries

    def gift_value(self, kind: str, param: int) -> float:
        if kind == "MON":
            return self.mon_value(param & 0xFF)
        if kind == "MON_EVOLVE":
            return self.mon_value(param & 0xFF) + 60  # arrives evolved or evolving: worth a stage
        if kind == "TEACH_MOVE":
            return self.move_value(param & 0xFF)
        if kind == "ITEM":
            move = self.tm_moves.get(param & 0xFF)
            return self.move_value(move) if move else ITEM_VALUE
        return EFFECT_VALUE

    def gift_choice(self) -> int:
        values = [self.gift_value(kind, param) for kind, param in self.gift_entries()]
        return max(range(len(values)), key=lambda i: (values[i], -i))
