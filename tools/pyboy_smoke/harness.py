from __future__ import annotations

import hashlib
import json
import logging
from pathlib import Path
import re
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
        for line in path.read_text(encoding="utf-8").splitlines():
            match = self.ADDRESS_RE.match(line.strip())
            if match:
                self._symbols[match.group("label")] = (
                    int(match.group("bank"), 16),
                    int(match.group("address"), 16),
                )

    def get(self, label: str) -> tuple[int, int]:
        try:
            return self._symbols[label]
        except KeyError as error:
            raise KeyError(f"{label!r} is missing from {self.path}") from error

    def bank(self, label: str) -> int:
        return self.get(label)[0]

    def address(self, label: str) -> int:
        return self.get(label)[1]


class RedRogueHarness:
    TARGET_ROUTE = 0x79  # UNDERGROUND_PATH_WEST_EAST
    LOBBY_MAP = 0xAE  # INDIGO_PLATEAU_LOBBY
    WARP_NO_RETURN = 0xFD
    GIOVANNI_TYPE_BITS = 0x20

    def __init__(self, repo_root: Path, artifacts_dir: Path):
        self.repo_root = repo_root.resolve()
        self.rom_path = self.repo_root / "pokeblue_debug.gbc"
        self.sym_path = self.repo_root / "pokeblue_debug.sym"
        if not self.rom_path.is_file() or not self.sym_path.is_file():
            raise FileNotFoundError(
                "pokeblue_debug.gbc and pokeblue_debug.sym are required; run `make blue_debug`"
            )
        self.symbols = SymbolTable(self.sym_path)
        self.rom_sha256 = hashlib.sha256(self.rom_path.read_bytes()).hexdigest()
        self.artifacts_dir = artifacts_dir.resolve()
        self.pyboy = PyBoy(
            str(self.rom_path),
            window="null",
            sound_emulated=False,
            log_level="CRITICAL",
        )

    def close(self) -> None:
        self.pyboy.stop(save=False)

    def address(self, label: str) -> int:
        return self.symbols.address(label)

    def read8(self, label: str, offset: int = 0) -> int:
        return self.pyboy.memory[self.address(label) + offset]

    def write8(self, label: str, value: int, offset: int = 0) -> None:
        self.pyboy.memory[self.address(label) + offset] = value & 0xFF

    def read_bytes(self, label: str, length: int, offset: int = 0) -> list[int]:
        start = self.address(label) + offset
        return list(self.pyboy.memory[start : start + length])

    def tick(self, frames: int = 1, *, render: bool = False) -> None:
        for _ in range(frames):
            self.pyboy.tick(render=render)

    def tap(self, button: str, frames: int = 2) -> None:
        self.pyboy.button_press(button)
        self.tick(frames)
        self.pyboy.button_release(button)
        self.tick(frames)

    def move_tile(self, direction: str) -> None:
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

    def hook_flag(self, label: str) -> dict[str, int]:
        state = {"count": 0}

        def callback(_context) -> None:
            state["count"] += 1

        bank, address = self.symbols.get(label)
        self.pyboy.hook_register(bank, address, callback, None)
        return state

    def boot_to_lobby(self, battle_count: int = 11) -> None:
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
            "the Debug 2 Door 1 prompt",
            600,
        )
        self.tap("a")
        self.wait_until(
            lambda: quantity_menu["count"] >= 3,
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
        self.move_tile("down")
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
        return_bank = 0
        return_address = 0x3FFF
        idle_loop = 0xCFF0
        completed = {"value": False}

        def returned(_context) -> None:
            completed["value"] = True
            self.pyboy.register_file.PC = idle_loop

        self.pyboy.hook_register(return_bank, return_address, returned, None)
        try:
            self.pyboy.memory[idle_loop] = 0x18  # jr -2
            self.pyboy.memory[idle_loop + 1] = 0xFE
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
        return {
            "rom_sha256": self.rom_sha256,
            "frame": self.pyboy.frame_count,
            "map": safe("hCurMap"),
            "position": [safe("wXCoord"), safe("wYCoord")],
            "battle_count": safe("wBattleCount"),
            "rogue_flags": safe("wRogueFlagsBitfield"),
            "route_script": safe("wUndergroundPathRoute5CurScript"),
            "sprite_count": safe("wNumSprites"),
            "warps": diagnostic_warps,
            "sprite_extra": self.read_bytes("wMapSpriteExtraData", 20),
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
        return image_path, state_path
