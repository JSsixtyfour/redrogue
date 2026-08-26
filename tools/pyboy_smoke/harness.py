from __future__ import annotations

import hashlib
import io
import json
import logging
import os
from pathlib import Path
import re
from datetime import datetime, timezone
import warnings

logging.disable(logging.WARNING)
warnings.filterwarnings("ignore", message="Using SDL2 binaries from pysdl2-dll.*")

from pyboy import PyBoy


class SymbolTable:
    """Parse RGBDS address symbols while ignoring non-address constant lines."""

    ADDRESS_RE = re.compile(
        r"^(?P<bank>[0-9a-fA-F]{2}):(?P<address>[0-9a-fA-F]{4})\s+(?P<label>\S+)$"
    )

    def __init__(self, path: Path):
        self.path = path
        self._symbols: dict[str, tuple[int, int]] = {}
        self._by_bank: dict[int, list[tuple[int, str]]] = {}
        for line in path.read_text(encoding="utf-8").splitlines():
            match = self.ADDRESS_RE.match(line.strip())
            if match:
                label = match.group("label")
                bank = int(match.group("bank"), 16)
                address = int(match.group("address"), 16)
                self._symbols[label] = (bank, address)
                self._by_bank.setdefault(bank, []).append((address, label))
        for entries in self._by_bank.values():
            entries.sort()

    def get(self, label: str) -> tuple[int, int]:
        try:
            return self._symbols[label]
        except KeyError as error:
            raise KeyError(f"{label!r} is missing from {self.path}") from error

    def bank(self, label: str) -> int:
        return self.get(label)[0]

    def address(self, label: str) -> int:
        return self.get(label)[1]

    def nearest(self, bank: int, address: int) -> str | None:
        candidates = self._by_bank.get(bank, ())
        nearest = None
        for symbol_address, label in candidates:
            if symbol_address > address:
                break
            nearest = (symbol_address, label)
        if nearest is None:
            return None
        symbol_address, label = nearest
        offset = address - symbol_address
        return label if offset == 0 else f"{label}+${offset:x}"


class RedRogueHarness:
    TARGET_ROUTE = 0x79  # UNDERGROUND_PATH_WEST_EAST
    LOBBY_MAP = 0xAE  # INDIGO_PLATEAU_LOBBY
    WARP_NO_RETURN = 0xFD
    GIOVANNI_TYPE_BITS = 0x20
    FIGHT2_SPEC_MAGIC = 0xD2
    AI_LAYER_NAMES = (
        "REDUNDANT", "BASIC", "TYPES", "SETUP", "SMART",
        "DAMAGE", "THREAT", "PLAN", "RISKY",
    )

    def __init__(
        self,
        repo_root: Path,
        artifacts_dir: Path,
        *,
        sound_emulated: bool = False,
        ram_path: Path | None = None,
        cgb_mode: bool = False,
    ):
        self.repo_root = repo_root.resolve()
        self.rom_path = self.repo_root / "pokeblue_debug.gbc"
        self.sym_path = self.repo_root / "pokeblue_debug.sym"
        if not self.rom_path.is_file() or not self.sym_path.is_file():
            raise FileNotFoundError(
                "pokeblue_debug.gbc and pokeblue_debug.sym are required; run `make blue_debug`"
            )
        self.symbols = SymbolTable(self.sym_path)
        rom_data = bytearray(self.rom_path.read_bytes())
        self.rom_sha256 = hashlib.sha256(rom_data).hexdigest()
        self.sym_sha256 = hashlib.sha256(self.sym_path.read_bytes()).hexdigest()
        self._validate_rom_and_symbols(rom_data)
        self._recent_hooks: list[dict[str, object]] = []
        self._registered_hooks: list[tuple[int, int]] = []
        self._hook_callbacks: dict[tuple[int, int], list[object]] = {}
        self.hardware_mode = "CGB" if cgb_mode else "DMG"
        expected_mode = os.environ.get("REDROGUE_PYBOY_EXPECTED_MODE")
        if expected_mode is not None and expected_mode != self.hardware_mode:
            raise ValueError(
                f"test is classified {expected_mode} but requested {self.hardware_mode} mode"
            )

        # PyBoy's cgb=False only declines to force CGB mode. It does not force
        # DMG mode when byte $0143 advertises a CGB-compatible cartridge. The
        # default regression harness therefore uses an in-memory DMG header
        # mirror; opt-in CGB tests retain the authoritative ROM header.
        if not cgb_mode:
            rom_data[0x143] = 0
            header_checksum = 0
            for value in rom_data[0x134:0x14D]:
                header_checksum = (header_checksum - value - 1) & 0xFF
            rom_data[0x14D] = header_checksum
            global_checksum = (
                sum(rom_data) - rom_data[0x14E] - rom_data[0x14F]
            ) & 0xFFFF
            rom_data[0x14E] = global_checksum >> 8
            rom_data[0x14F] = global_checksum & 0xFF
        self._rom_file = io.BytesIO(rom_data)
        self.artifacts_dir = artifacts_dir.resolve()
        options = {
            "window": "null",
            "sound_emulated": sound_emulated,
            "log_level": "CRITICAL",
            "cgb": cgb_mode,
        }
        if ram_path is None:
            self.pyboy = PyBoy(self._rom_file, **options)
        else:
            with ram_path.resolve().open("rb") as ram_file:
                self.pyboy = PyBoy(
                    self._rom_file, ram_file=ram_file, **options
                )

    def _validate_rom_and_symbols(self, rom_data: bytearray) -> None:
        """Reject obviously stale or structurally incompatible build artifacts."""
        if len(rom_data) == 0 or len(rom_data) % 0x4000:
            raise ValueError(f"invalid ROM size: {len(rom_data)} bytes")
        rom_banks = len(rom_data) // 0x4000
        required = ("Bankswitch", "DebugMenu", "MainInBattleLoop")
        for label in required:
            bank, address = self.symbols.get(label)
            if bank >= rom_banks:
                raise ValueError(
                    f"{self.sym_path.name} places {label} in bank ${bank:02x}, "
                    f"outside the {rom_banks}-bank ROM"
                )
            if bank == 0 and address >= 0x4000:
                raise ValueError(f"invalid ROM0 symbol address for {label}: ${address:04x}")
            if bank and not 0x4000 <= address < 0x8000:
                raise ValueError(f"invalid ROMX symbol address for {label}: ${address:04x}")
        self.symbols.get("wPartySpecies")
        # make writes the ROM after the symbol file. A newer symbol file is a
        # strong indication that these artifacts came from different builds.
        if self.sym_path.stat().st_mtime > self.rom_path.stat().st_mtime + 2:
            raise ValueError(
                f"{self.sym_path.name} is newer than {self.rom_path.name}; "
                "rebuild pokeblue_debug.gbc before running PyBoy"
            )

    def close(self) -> None:
        for bank, address in reversed(self._registered_hooks):
            self.pyboy.hook_deregister(bank, address)
        self._registered_hooks.clear()
        self._hook_callbacks.clear()
        self.pyboy.stop(save=False)

    def register_hook(self, label: str, callback) -> None:
        bank, address = self.symbols.get(label)
        key = (bank, address)
        if key in self._hook_callbacks:
            self._hook_callbacks[key].append(callback)
            return
        self._hook_callbacks[key] = [callback]

        def dispatch(context, hook_key=key) -> None:
            for registered_callback in tuple(self._hook_callbacks[hook_key]):
                registered_callback(context)

        self.pyboy.hook_register(bank, address, dispatch, None)
        self._registered_hooks.append(key)

    def address(self, label: str) -> int:
        return self.symbols.address(label)

    def read8(self, label: str, offset: int = 0) -> int:
        return self.pyboy.memory[self.address(label) + offset]

    def write8(self, label: str, value: int, offset: int = 0) -> None:
        self.pyboy.memory[self.address(label) + offset] = value & 0xFF

    def plant_sentinels(self, values: dict[str, int]) -> dict[str, int]:
        """Write named borrowed-state sentinels and return the expected snapshot."""
        expected = {label: value & 0xFF for label, value in values.items()}
        for label, value in expected.items():
            self.write8(label, value)
        return expected

    def assert_sentinels(self, expected: dict[str, int]) -> None:
        """Fail with every borrowed byte that was not restored by a routine."""
        changed = {
            label: {"expected": value, "actual": self.read8(label)}
            for label, value in expected.items()
            if self.read8(label) != value
        }
        if changed:
            raise AssertionError(f"borrowed state was not restored: {changed}")

    def read_bytes(self, label: str, length: int, offset: int = 0) -> list[int]:
        start = self.address(label) + offset
        return list(self.pyboy.memory[start : start + length])

    def read_sram_bytes(self, label: str, length: int, bank: int = 1) -> list[int]:
        start = self.address(label)
        self.pyboy.memory[0x0000] = 0x0A
        self.pyboy.memory[0x4000] = bank
        values = list(self.pyboy.memory[start : start + length])
        self.pyboy.memory[0x0000] = 0
        return values

    def write_sram_bytes(self, label: str, values, bank: int = 1) -> None:
        start = self.address(label)
        self.pyboy.memory[0x0000] = 0x0A
        self.pyboy.memory[0x4000] = bank
        for offset, value in enumerate(values):
            self.pyboy.memory[start + offset] = value & 0xFF
        self.pyboy.memory[0x0000] = 0

    def save_state(self, file_object) -> None:
        """Save a deterministic trial baseline to an open binary file."""
        self.pyboy.save_state(file_object)

    def load_state(self, file_object) -> None:
        """Restore a trial baseline from an open binary file."""
        file_object.seek(0)
        self.pyboy.load_state(file_object)

    def tick(self, frames: int = 1, *, render: bool = False) -> None:
        for _ in range(frames):
            self.pyboy.tick(render=render)

    def cycle_count(self) -> int:
        """Return PyBoy's current CPU-cycle counter for performance telemetry."""
        counter = getattr(self.pyboy, "_cycles", None)
        if not callable(counter):
            raise RuntimeError("this PyBoy build does not expose the _cycles() counter")
        return int(counter())

    def tap(self, button: str, frames: int = 2) -> None:
        self.pyboy.button_press(button)
        self.tick(frames)
        self.pyboy.button_release(button)
        self.tick(frames)

    def move_tile(self, direction: str) -> None:
        # Deliberately a single short press: holding longer walks TWO tiles and
        # breaks the procedural-stage tests. Door entry needs a longer hold than
        # this, but that belongs in enter_stage_door1, not here.
        self.pyboy.button_press(direction)
        self.tick(20)
        self.pyboy.button_release(direction)
        self.tick(4)

    def wait_until(self, predicate, description: str, limit: int = 2400) -> int:
        for frame in range(limit):
            self.pyboy.tick(render=False)
            if predicate():
                return frame
        raise AssertionError(
            f"Timed out waiting for {description} after {limit} frames: "
            f"{json.dumps(self.diagnostic_state(), sort_keys=True)}"
        )

    def hook_flag(self, label: str, action=None) -> dict[str, int]:
        state = {"count": 0}

        def callback(_context) -> None:
            state["count"] += 1
            self._record_hook(label)
            if action is not None:
                action()

        self.register_hook(label, callback)
        return state

    def _record_hook(self, label: str) -> None:
        self._recent_hooks.append(
            {"label": label, "frame": self.pyboy.frame_count, "pc": self.pyboy.register_file.PC}
        )
        del self._recent_hooks[:-16]

    def hook_ai_scores(self) -> list[dict[str, object]]:
        """Capture scores plus the move ultimately selected for each AI decision."""
        records: list[dict[str, object]] = []
        pending: dict[str, object] = {
            "active": False,
            "record": None,
            "layer_snapshots": [],
            "enabled_layers": set(),
        }

        def begin(_context) -> None:
            pending["active"] = True
            pending["record"] = None
            pending["layer_snapshots"] = []
            pending["enabled_layers"] = set()

        def layer_start(_context) -> None:
            if not pending["active"]:
                return
            layer = self.pyboy.register_file.B
            if layer >= len(self.AI_LAYER_NAMES):
                return
            pending["layer_snapshots"].append(
                {"layer": layer, "scores": self.read_bytes("wBuffer", 4)}
            )

        def layer_return(_context) -> None:
            if not pending["active"]:
                return
            # The dispatcher pushed BC before jumping to the layer. At the
            # shared return seam, saved C/B are the next two stack bytes.
            stack_pointer = self.pyboy.register_file.SP
            layer = self.pyboy.memory[(stack_pointer + 1) & 0xFFFF]
            if layer < len(self.AI_LAYER_NAMES):
                pending["enabled_layers"].add(layer)

        def capture(_context) -> None:
            if not pending["active"]:
                return
            scores = self.read_bytes("wBuffer", 4)
            moves = self.read_bytes("wEnemyMonMoves", 4)
            legal_scores = [score for score, move in zip(scores, moves) if move]
            best_score = min(legal_scores)
            eligible_slots = [
                slot
                for slot, (score, move) in enumerate(zip(scores, moves))
                if move and score == best_score
            ]
            tier = max(0, self.read8("wAITier") - 1)
            snapshots = list(pending["layer_snapshots"])
            layer_trace = []
            for index, snapshot in enumerate(snapshots):
                before = snapshot["scores"]
                after = snapshots[index + 1]["scores"] if index + 1 < len(snapshots) else scores
                layer = snapshot["layer"]
                layer_trace.append(
                    {
                        "layer": self.AI_LAYER_NAMES[layer],
                        "enabled": layer in pending["enabled_layers"],
                        "before": before,
                        "after": after,
                        "delta": [new - old for old, new in zip(before, after)],
                    }
                )
            records.append(
                {
                    "scores": scores,
                    "moves": moves,
                    "eligible_slots": eligible_slots,
                    "tier": tier,
                    "layer_trace": layer_trace,
                    "frame": self.pyboy.frame_count,
                }
            )
            if len(eligible_slots) == 1:
                records[-1]["selected_slot"] = eligible_slots[0]
            pending["record"] = len(records) - 1

        def selected(_context) -> None:
            record_index = pending["record"]
            if record_index is None:
                return
            records[int(record_index)].update(
                {
                    "selected_slot": self.read8("wEnemyMoveListIndex"),
                    "selected_move": self.pyboy.register_file.A,
                }
            )
            pending["active"] = False
            pending["record"] = None

        for label, callback in (
            ("AIEnemyTrainerChooseMoves", begin),
            ("AIEnemyTrainerChooseMoves.nextLayer", layer_start),
            ("AIEnemyTrainerChooseMoves.layerReturn", layer_return),
            ("AIEnemyTrainerChooseMoves.loopFindMinimumEntries", capture),
            ("MainInBattleLoop.noLinkBattle", selected),
        ):
            self.register_hook(label, callback)
        return records

    def hook_enemy_send_out(self) -> list[dict[str, object]]:
        """Trace replacement selection through EnemySendOut's real farcall path."""
        records: list[dict[str, object]] = []
        pending: dict[str, object] = {}

        def begin(_context) -> None:
            pending.clear()
            pending.update(
                {
                    "frame": self.pyboy.frame_count,
                    "previous_slot": self.read8("wEnemyMonPartyPos"),
                }
            )

        def ranked(_context) -> None:
            pending.update(
                {
                    "best_score": self.read8("wBuffer", 18),
                    "ranked_slot": self.read8("wBuffer", 19),
                }
            )

        def selected(_context) -> None:
            pending["selected_slot"] = self.read8("hWhichPokemon")
            records.append(dict(pending))

        self.register_hook("EnemySendOutFirstMon.next", begin)
        self.register_hook("AISelectSendOut.done", ranked)
        self.register_hook("EnemySendOutFirstMon.next3", selected)
        return records

    def hook_turn_telemetry(self) -> list[dict[str, object]]:
        """Record battle state and CPU cycles at each turn and action seam."""
        records: list[dict[str, object]] = []

        def current() -> dict[str, object] | None:
            return records[-1] if records else None

        def begin(_context) -> None:
            if records and "end_cycle" not in records[-1]:
                records[-1]["end_cycle"] = self.cycle_count()
            records.append(
                {
                    "turn": len(records) + 1,
                    "frame": self.pyboy.frame_count,
                    "start_cycle": self.cycle_count(),
                    "player_hp": self.read_bytes("wBattleMonHP", 2),
                    "enemy_hp": self.read_bytes("wEnemyMonHP", 2),
                    "player_slot": self.read8("wPlayerMonNumber"),
                    "enemy_slot": self.read8("wEnemyMonPartyPos"),
                }
            )

        def choices(_context) -> None:
            record = current()
            if record is not None:
                record["player_move"] = self.read8("wTestBattlePlayerSelectedMove")
                record["enemy_move"] = self.read8("wEnemySelectedMove")

        def player_action(_context) -> None:
            record = current()
            if record is not None:
                record["player_acted"] = True

        def enemy_action(_context) -> None:
            record = current()
            if record is not None:
                record["enemy_acted"] = True

        def finish(_context) -> None:
            record = current()
            if record is not None and "end_cycle" not in record:
                record["end_cycle"] = self.cycle_count()

        for label, callback in (
            ("MainInBattleLoop", begin),
            ("MainInBattleLoop.noLinkBattle", choices),
            ("ExecutePlayerMove", player_action),
            ("ExecuteEnemyMove", enemy_action),
            ("TrainerBattleVictory", finish),
            ("HandlePlayerBlackOut", finish),
        ):
            self.register_hook(label, callback)
        return records

    def inject_fight2_spec(
        self,
        player: list[dict[str, object]],
        enemy: list[dict[str, object]],
        *,
        trainer_class: int,
        ai_tier: int,
    ) -> None:
        """Write a declarative FIGHT 2 team fixture into debug SRAM."""
        if not 1 <= len(player) <= 6 or not 1 <= len(enemy) <= 6:
            raise ValueError("FIGHT 2 scenarios require 1-6 mons on each side")
        if not 0 <= ai_tier <= 3:
            raise ValueError("AI tier must be 0-3")

        def encode_mon(mon: dict[str, object]) -> list[int]:
            moves = list(mon["moves"])
            if len(moves) > 4:
                raise ValueError("A scenario mon may have at most four moves")
            moves.extend([0] * (4 - len(moves)))
            species = int(mon["species"])
            level = int(mon["level"])
            if not 1 <= species <= 255 or not 1 <= level <= 100:
                raise ValueError("Scenario species and level are out of range")
            return [species, level, *(int(move) for move in moves)]

        entries = player + ([{"species": 1, "level": 1, "moves": []}] * (6 - len(player)))
        entries += enemy + ([{"species": 1, "level": 1, "moves": []}] * (6 - len(enemy)))
        payload = [
            self.FIGHT2_SPEC_MAGIC,
            len(player),
            len(enemy),
            trainer_class,
            ai_tier + 1,
        ]
        for mon in entries:
            payload.extend(encode_mon(mon))
        self.write_sram_bytes("sDebugFight2Spec", payload)

    def boot_debug1(self, destination_map: int) -> None:
        debug_menu = self.hook_flag("DebugMenu")

        self.tick(240)
        self.pyboy.button_press("select")
        for _ in range(300):
            self.tap("start", 1)
            if debug_menu["count"]:
                break
        self.pyboy.button_release("select")
        if not debug_menu["count"]:
            raise AssertionError("DebugMenu was not reached")

        self.tick(30)
        self.tap("down")
        self.tap("down")
        self.tap("a")
        self.wait_until(
            lambda: self.read8("hCurMap") == destination_map,
            "the Debug 1 destination",
            2400,
        )
        self.tick(180)

    def boot_fight2(self, seed: int = 1) -> None:
        if not 1 <= seed <= 99:
            raise ValueError("FIGHT 2 seed must be in the range 1-99")
        debug_menu = self.hook_flag("DebugMenu")
        quantity_menu = self.hook_flag("DisplayChooseQuantityMenu")
        battle_ready = self.hook_flag("MainInBattleLoop")

        self.tick(240)
        self.pyboy.button_press("select")
        for _ in range(300):
            self.tap("start", 1)
            if debug_menu["count"]:
                break
        self.pyboy.button_release("select")
        if not debug_menu["count"]:
            raise AssertionError("DebugMenu was not reached")

        self.tick(30)
        self.tap("down")
        self.tap("a")
        self.wait_until(
            lambda: quantity_menu["count"] >= 1,
            "the FIGHT 2 seed prompt",
            600,
        )
        for _ in range(100):
            current = self.read8("wItemQuantity")
            if current == seed:
                break
            self.tap("up" if current < seed else "down")
        else:
            raise AssertionError(f"Could not select FIGHT 2 seed {seed}")
        self.tap("a")
        for _ in range(300):
            self.tap("a", 1)
            self.tick(15)
            if battle_ready["count"]:
                break
        if not battle_ready["count"]:
            raise AssertionError(
                "FIGHT 2 did not reach the live battle loop: "
                f"{json.dumps(self.diagnostic_state(), sort_keys=True)}"
            )

    def boot_to_lobby(self, battle_count: int = 11, ai_tier: int | None = None) -> None:
        if ai_tier is not None and not 0 <= ai_tier <= 3:
            raise ValueError("AI tier must be 0-3 or None for automatic")
        debug_menu = self.hook_flag("DebugMenu")
        quantity_menu = self.hook_flag("DisplayChooseQuantityMenu")

        self.tick(240)
        self.pyboy.button_press("select")
        for _ in range(300):
            self.tap("start", 1)
            if debug_menu["count"]:
                break
        self.pyboy.button_release("select")
        if not debug_menu["count"]:
            raise AssertionError("DebugMenu was not reached")

        self.tick(30)
        self.tap("down")
        self.tap("down")
        self.tap("down")
        self.tap("a")
        self.wait_until(
            lambda: quantity_menu["count"] >= 1,
            "the Debug 2 battle-count prompt",
            600,
        )

        for _ in range(100):
            current = self.read8("wItemQuantity")
            if current == battle_count:
                break
            self.tap("up" if current < battle_count else "down")
        else:
            raise AssertionError(f"Could not select battle count {battle_count}")

        self.tap("a")
        self.wait_until(
            lambda: quantity_menu["count"] >= 2,
            "the Debug 2 AI-tier prompt",
            600,
        )
        tier_quantity = 1 if ai_tier is None else ai_tier + 2
        for _ in range(6):
            current = self.read8("wItemQuantity")
            if current == tier_quantity:
                break
            self.tap("up" if current < tier_quantity else "down")
        else:
            raise AssertionError(f"Could not select AI tier {ai_tier}")
        self.tap("a")
        self.wait_until(
            lambda: quantity_menu["count"] >= 3,
            "the Debug 2 Door 1 prompt",
            600,
        )
        self.tap("a")
        self.wait_until(
            lambda: quantity_menu["count"] >= 4,
            "the Debug 2 Door 2 prompt",
            600,
        )
        self.tap("a")

        def lobby_ready() -> bool:
            return (
                self.read8("wLobbyDoor1StageMap") != 0
                and self.read8("wSpritePlayerStateData1", 4) != 0
            )

        for _ in range(300):
            self.tap("a", 1)
            if lobby_ready():
                break
        if not lobby_ready():
            raise AssertionError("Lobby entry event did not complete")
        if self.read8("hCurMap") != self.LOBBY_MAP:
            raise AssertionError(
                f"Expected lobby map ${self.LOBBY_MAP:02x}, got ${self.read8('hCurMap'):02x}"
            )

    def enter_route_door1(self, *, giovanni: bool = False) -> None:
        self.enter_stage_door1(
            self.TARGET_ROUTE,
            description="Underground Path West-East",
            giovanni=giovanni,
        )

    def enter_stage_door1(
        self, map_id: int, *, description: str, giovanni: bool = False
    ) -> None:
        self.write8("wLobbyDoor1StageMap", map_id)
        self.write8("wWarpEntries", map_id, offset=3)

        flags = self.read8("wRogueFlagsBitfield") & 0x0F
        if giovanni:
            flags |= self.GIOVANNI_TYPE_BITS
        self.write8("wRogueFlagsBitfield", flags)
        self.tick(4)
        self.move_tile("up")
        # Step back down onto the warp tile. A warp fires *while the direction is
        # still held*, as the step lands, and how long that takes depends on the
        # boot phase - so a fixed press length is not safe here. This was a
        # hardcoded move_tile("down") until 2026-08-20, when adding the CGB VRAM
        # bank 1 clear to ClearVram shifted init timing and silently broke all 23
        # navigation assertions, while the real build was verified fine on BGB
        # (lobby door -> Rocket B1F -> trainer battle). Measured then: a 20, 24 or
        # 30 frame press never warped; 40 always did. Retry rather than trust any
        # single number, so the next timing shift does not resurrect this.
        for _ in range(6):
            self.pyboy.button_press("down")
            self.tick(40)
            self.pyboy.button_release("down")
            self.tick(6)
            if self.read8("hCurMap") == map_id:
                break
        self.wait_until(
            lambda: self.read8("hCurMap") == map_id,
            f"{description} entry",
            1200,
        )
        self.tick(180)

    def set_event(self, event: int) -> None:
        address = self.address("wEventFlags") + event // 8
        self.pyboy.memory[address] |= 1 << (event % 8)

    def event_is_set(self, event: int) -> bool:
        address = self.address("wEventFlags") + event // 8
        return bool(self.pyboy.memory[address] & (1 << (event % 8)))

    def call_routine(self, label: str, limit: int = 12000) -> None:
        """Call a ROM routine through the engine's bank trampoline."""
        bank, address = self.symbols.get(label)
        register_names = ("A", "B", "C", "D", "E", "F", "HL", "PC", "SP")
        saved_registers = {
            name: getattr(self.pyboy.register_file, name) for name in register_names
        }
        saved_bank = self.read8("hLoadedROMBank")
        return_bank = 0
        return_address = 0x3FFF
        completed = {"value": False}

        def returned(_context) -> None:
            if saved_registers["PC"] >= 0x4000:
                self.pyboy.memory[0x2000] = saved_bank
                self.write8("hLoadedROMBank", saved_bank)
            for name, value in saved_registers.items():
                setattr(self.pyboy.register_file, name, value)
            completed["value"] = True

        self.pyboy.hook_register(return_bank, return_address, returned, None)
        try:
            stack_pointer = (self.pyboy.register_file.SP - 2) & 0xFFFF
            self.pyboy.memory[stack_pointer] = return_address & 0xFF
            self.pyboy.memory[stack_pointer + 1] = return_address >> 8
            self.pyboy.register_file.SP = stack_pointer
            if address >= 0x4000:
                self.pyboy.register_file.B = bank
                self.pyboy.register_file.HL = address
                self.pyboy.register_file.PC = self.address("Bankswitch")
            else:
                self.pyboy.register_file.PC = address
            self.wait_until(lambda: completed["value"], label, limit)
        finally:
            self.pyboy.hook_deregister(return_bank, return_address)

    def probe_routine_until(self, label: str, predicate, limit: int = 12000) -> None:
        """Enter a real routine path, capture a seam, then restore emulator state."""
        baseline = io.BytesIO()
        self.save_state(baseline)
        bank, address = self.symbols.get(label)
        return_address = 0x3FFF
        try:
            stack_pointer = (self.pyboy.register_file.SP - 2) & 0xFFFF
            self.pyboy.memory[stack_pointer] = return_address & 0xFF
            self.pyboy.memory[stack_pointer + 1] = return_address >> 8
            self.pyboy.register_file.SP = stack_pointer
            if address >= 0x4000:
                self.pyboy.register_file.B = bank
                self.pyboy.register_file.HL = address
                self.pyboy.register_file.PC = self.address("Bankswitch")
            else:
                self.pyboy.register_file.PC = address
            self.wait_until(predicate, f"{label} probe seam", limit)
        finally:
            self.load_state(baseline)

    def preload_and_enter_wild_area(self, map_id: int, description: str) -> None:
        self.write8("wLobbyDoor1StageMap", map_id)
        self.write8("wWarpEntries", map_id, offset=3)
        self.call_routine("ProcPreloadAssignedWildArea", limit=60000)
        self.move_tile("up")
        self.move_tile("down")
        self.wait_until(
            lambda: self.read8("hCurMap") == map_id,
            f"{description} entry",
            2400,
        )
        self.tick(180)

    def sprite_positions(self, count: int) -> list[list[int]]:
        y_start = self.address("wSprite01StateData2MapY")
        x_start = self.address("wSprite01StateData2MapX")
        return [
            [
                self.pyboy.memory[y_start + index * 16] - 4,
                self.pyboy.memory[x_start + index * 16] - 4,
            ]
            for index in range(count)
        ]

    def warp_entries(self) -> list[list[int]]:
        count = self.read8("wNumberOfWarps")
        raw = self.read_bytes("wWarpEntries", count * 4)
        return [raw[index : index + 4] for index in range(0, len(raw), 4)]

    def diagnostic_state(self) -> dict[str, object]:
        safe = lambda label, offset=0: self.read8(label, offset)
        warp_count = safe("wNumberOfWarps")
        diagnostic_warps: object
        if 1 <= warp_count <= 32:
            diagnostic_warps = self.warp_entries()
        elif warp_count == 0:
            diagnostic_warps = []
        else:
            diagnostic_warps = {"invalid_count": warp_count}
        registers = self.pyboy.register_file
        pc = registers.PC
        loaded_bank = safe("hLoadedROMBank")
        pc_bank = 0 if pc < 0x4000 else loaded_bank
        stack = [self.pyboy.memory[(registers.SP + offset) & 0xFFFF] for offset in range(16)]
        return {
            "rom_sha256": self.rom_sha256,
            "sym_sha256": self.sym_sha256,
            "hardware_mode": self.hardware_mode,
            "frame": self.pyboy.frame_count,
            "cpu": {
                "pc": pc,
                "sp": registers.SP,
                "a": registers.A,
                "b": registers.B,
                "c": registers.C,
                "d": registers.D,
                "e": registers.E,
                "f": registers.F,
                "hl": registers.HL,
                "rom_bank": loaded_bank,
                "location": self.symbols.nearest(pc_bank, pc),
                "stack": stack,
            },
            "recent_hooks": list(self._recent_hooks),
            "map": safe("hCurMap"),
            "position": [safe("wXCoord"), safe("wYCoord")],
            "battle_count": safe("wBattleCount"),
            "rogue_flags": safe("wRogueFlagsBitfield"),
            "route_script": safe("wUndergroundPathRoute5CurScript"),
            "sprite_count": safe("wNumSprites"),
            "warps": diagnostic_warps,
            "sprite_extra": self.read_bytes("wMapSpriteExtraData", 20),
            "rng_state": [
                safe("hRandomAdd"),
                safe("hRandomSub"),
                safe("hRandomLast"),
                safe("hRandomLast", 1),
            ],
            "player_party": self.read_bytes("wPartySpecies", safe("wPartyCount") + 1),
            "enemy_party": self.read_bytes(
                "wEnemyPartySpecies", safe("wEnemyPartyCount") + 1
            ),
            "key_item_flags": self.read_sram_bytes("sKeyItemsBitfield", 4),
        }

    def write_failure_artifacts(self, test_name: str) -> tuple[Path, Path]:
        self.artifacts_dir.mkdir(parents=True, exist_ok=True)
        safe_name = re.sub(r"[^A-Za-z0-9_.-]+", "_", test_name)
        image_path = self.artifacts_dir / f"{safe_name}.png"
        state_path = self.artifacts_dir / f"{safe_name}.json"
        self.pyboy.tick(render=True)
        self.pyboy.screen.image.save(image_path)
        state_path.write_text(
            json.dumps(self.diagnostic_state(), indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        self._update_artifact_index(test_name, image_path, state_path)
        return image_path, state_path

    def _update_artifact_index(
        self, test_name: str, image_path: Path, state_path: Path
    ) -> None:
        index_path = self.artifacts_dir / "index.json"
        try:
            index = json.loads(index_path.read_text(encoding="utf-8"))
        except (FileNotFoundError, json.JSONDecodeError):
            index = {"schema_version": 1, "failures": {}}
        index["failures"][test_name] = {
            "recorded_at": datetime.now(timezone.utc).isoformat(),
            "hardware_mode": self.hardware_mode,
            "frame": self.pyboy.frame_count,
            "rom_sha256": self.rom_sha256,
            "sym_sha256": self.sym_sha256,
            "screenshot": image_path.name,
            "state": state_path.name,
        }
        temporary = index_path.with_suffix(".tmp")
        temporary.write_text(
            json.dumps(index, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        temporary.replace(index_path)
