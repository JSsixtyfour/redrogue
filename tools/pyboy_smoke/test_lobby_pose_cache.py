"""Actual-assembly tests for the isolated lobby pose cache manager.

The fixture includes the current source directly and supplies only the three
staging/output symbols it references.  The cache state lives in synthetic
WRAM at C400, so this test does not depend on a game RAM declaration or on a
renderer integration that has not landed yet.
"""

from __future__ import annotations

import io
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


try:
    from pyboy import PyBoy
except ImportError:  # pragma: no cover - the smoke environment supplies PyBoy
    PyBoy = None  # type: ignore[assignment,misc]


REPO_ROOT = Path(__file__).resolve().parents[2]


class _LobbyPoseCacheRom:
    """Build and run the current cache-manager source in a tiny ROM."""

    # Mailbox and synthetic WRAM addresses.
    COMMAND = 0xC000
    COMPLETE = 0xC001
    RESULT_CARRY = 0xC002
    RESULT_A = 0xC003
    RESULT_B = 0xC004
    RESULT_C = 0xC005
    RESULT_D = 0xC006
    RESULT_E = 0xC007
    RESULT_H = 0xC008
    RESULT_L = 0xC009
    RESULT_LY = 0xC00A
    ARG_INDEX = 0xC00B
    ARG_PICTURE = 0xC00C
    ARG_POSE = 0xC00D
    ARG_OFFSET = 0xC00E
    TARGET_LINE = 0xC00F
    READY = 0xC010

    SHADOW_OAM = 0xC100
    STAGING = 0xC200
    OAM_SOURCE = 0xC300
    STATE = 0xC400
    STATE_SIZE = 21

    RESET = 1
    REQUEST = 2
    SET_HEALING = 3
    INVALIDATE = 4
    SELECT = 5
    PUBLISH = 6
    PUBLISH_AT_LINE = 7

    _FIXTURE = r'''
INCLUDE "includes.asm"

; These are test-only stand-ins for symbols supplied by the future caller.
DEF wShadowOAM EQU $C100
DEF wLobbyPoseStagingTiles EQU $C200
DEF wLobbyPoseStagingOAM EQU $C300
DEF wLobbyPoseStageSourceBank EQU $C350
DEF wLobbyPoseStageSourceAddress EQU $C351
DEF wLobbyPoseStageTileCount EQU $C353
DEF wLobbyPoseStagePoseFlags EQU $C354

; This cache fixture does not exercise LobbyPoseStageTiles. The dedicated
; staging fixture supplies the real bank-aware copier.
SECTION "Unused staging copier", ROM0[$180]
FarCopyData3::
    ret
DEF LOBBY_POSE_TEST_STATE EQU $C400

DEF MAIL_COMMAND EQU $C000
DEF MAIL_COMPLETE EQU $C001
DEF MAIL_RESULT_CARRY EQU $C002
DEF MAIL_RESULT_A EQU $C003
DEF MAIL_RESULT_B EQU $C004
DEF MAIL_RESULT_C EQU $C005
DEF MAIL_RESULT_D EQU $C006
DEF MAIL_RESULT_E EQU $C007
DEF MAIL_RESULT_H EQU $C008
DEF MAIL_RESULT_L EQU $C009
DEF MAIL_RESULT_LY EQU $C00A
DEF MAIL_ARG_INDEX EQU $C00B
DEF MAIL_ARG_PICTURE EQU $C00C
DEF MAIL_ARG_POSE EQU $C00D
DEF MAIL_ARG_OFFSET EQU $C00E
DEF MAIL_TARGET_LINE EQU $C00F
DEF MAIL_READY EQU $C010

SECTION "Lobby pose cache test entry", ROM0[$100]
    nop
    jp LobbyPoseCacheTestMain

SECTION "Lobby pose cache source", ROMX
DEF LOBBY_POSE_CORE_ONLY EQU 1
INCLUDE "engine/overworld/lobby_pose.asm"

SECTION "Lobby pose cache test dispatcher", ROMX
LobbyPoseCacheTestMain::
    di
    ld sp, $DFFF
    xor a
    ld [MAIL_COMMAND], a
    ld [MAIL_COMPLETE], a
    ld a, $5A
    ld [MAIL_READY], a
.wait
    ld a, [MAIL_COMMAND]
    and a
    jr z, .wait
    ld b, a
    xor a
    ld [MAIL_COMMAND], a
    ld a, b
    cp 1
    jp z, .reset
    cp 2
    jp z, .request
    cp 3
    jp z, .setHealing
    cp 4
    jp z, .invalidate
    cp 5
    jp z, .select
    cp 6
    jp z, .publish
    cp 7
    jp z, .publishAtLine
    ld a, $EE
    scf
    jp .report
.reset
    ld bc, $A1B2
    ld de, $C3D4
    ld hl, LOBBY_POSE_TEST_STATE
    call LobbyPoseCacheReset
    jp .report
.request
    ld a, [MAIL_ARG_INDEX]
    ld b, a
    ld a, [MAIL_ARG_PICTURE]
    ld d, a
    ld a, [MAIL_ARG_POSE]
    ld e, a
    ld a, [MAIL_ARG_OFFSET]
    ld c, a
    ld a, b
    ld hl, LOBBY_POSE_TEST_STATE
    call LobbyPoseCacheRequest
    jp .report
.setHealing
    ld a, [MAIL_ARG_INDEX]
    ld bc, $A1B2
    ld de, $C3D4
    ld hl, LOBBY_POSE_TEST_STATE
    call LobbyPoseCacheSetHealing
    jp .report
.invalidate
    ld a, [MAIL_ARG_INDEX]
    ld hl, LOBBY_POSE_TEST_STATE
    call LobbyPoseCacheInvalidate
    jp .report
.select
    ld hl, LOBBY_POSE_TEST_STATE
    call LobbyPoseCacheSelect
    jp .report
.publish
    ld a, [MAIL_ARG_INDEX]
    ld b, a
    ld a, [MAIL_ARG_PICTURE]
    ld d, a
    ld a, [MAIL_ARG_POSE]
    ld e, a
    ld a, [MAIL_ARG_OFFSET]
    ld c, a
    ld a, b
    ld hl, LOBBY_POSE_TEST_STATE
    call LobbyPoseCachePublish
    jp .report
.publishAtLine
.lineWait
    ldh a, [rLY]
    ld d, a
    ld a, [MAIL_TARGET_LINE]
    cp d
    jr nz, .lineWait
    ld a, [MAIL_ARG_INDEX]
    ld b, a
    ld a, [MAIL_ARG_PICTURE]
    ld d, a
    ld a, [MAIL_ARG_POSE]
    ld e, a
    ld a, [MAIL_ARG_OFFSET]
    ld c, a
    ld a, b
    ld hl, LOBBY_POSE_TEST_STATE
    call LobbyPoseCachePublish
    jp .report
.report
    ; Save the original A before using A to materialize the carry result.
    push af
    jr nc, .carryClear
    ld a, 1
    jr .storeCarry
.carryClear
    xor a
.storeCarry
    ld [MAIL_RESULT_CARRY], a
    pop af
    ld [MAIL_RESULT_A], a
    ld a, b
    ld [MAIL_RESULT_B], a
    ld a, c
    ld [MAIL_RESULT_C], a
    ld a, d
    ld [MAIL_RESULT_D], a
    ld a, e
    ld [MAIL_RESULT_E], a
    ld a, h
    ld [MAIL_RESULT_H], a
    ld a, l
    ld [MAIL_RESULT_L], a
    ldh a, [rLY]
    ld [MAIL_RESULT_LY], a
    ld a, 1
    ld [MAIL_COMPLETE], a
    jp .wait
'''

    def __init__(self, temp_dir: Path):
        if PyBoy is None:
            raise unittest.SkipTest("PyBoy is unavailable")
        for tool in ("rgbasm", "rgblink", "rgbfix"):
            if shutil.which(tool) is None:
                raise unittest.SkipTest(f"{tool} is unavailable")

        self.source = temp_dir / "lobby_pose_cache_fixture.asm"
        self.object = temp_dir / "lobby_pose_cache_fixture.o"
        self.rom_path = temp_dir / "lobby_pose_cache_fixture.gb"
        self.source.write_text(self._FIXTURE, encoding="utf-8")
        self._run(("rgbasm", "-Weverything", "-I", str(REPO_ROOT),
                   "-o", str(self.object), str(self.source)))
        self._run(("rgblink", "-o", str(self.rom_path), str(self.object)))
        self._run(("rgbfix", "-v", "-p", "0", str(self.rom_path)))
        self.pyboy = PyBoy(
            io.BytesIO(self.rom_path.read_bytes()),
            window="null",
            sound_emulated=False,
            cgb=False,
            log_level="CRITICAL",
        )
        self.pyboy.set_emulation_speed(0)
        self._wait_for_boot()

    @staticmethod
    def _run(command: tuple[str, ...]) -> None:
        result = subprocess.run(command, capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError(
                f"command failed ({result.returncode}): {' '.join(command)}\n"
                f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
            )

    def close(self) -> None:
        self.pyboy.stop(save=False)

    def _wait_for_boot(self) -> None:
        for _ in range(120):
            self.pyboy.tick(render=False)
            if self.read8(self.READY) == 0x5A:
                return
        raise AssertionError("lobby pose cache fixture did not reach mailbox loop")

    def read8(self, address: int) -> int:
        return self.pyboy.memory[address]

    def write8(self, address: int, value: int) -> None:
        self.pyboy.memory[address] = value & 0xFF

    def read_block(self, address: int, size: int) -> bytes:
        return bytes(self.read8(address + i) for i in range(size))

    def write_block(self, address: int, data: bytes) -> None:
        for offset, value in enumerate(data):
            self.write8(address + offset, value)

    def command(
        self,
        command: int,
        index: int = 0,
        picture: int = 0,
        pose: int = 0,
        offset: int = 0,
        target_line: int = 0,
    ) -> dict[str, int | bool]:
        self.write8(self.COMPLETE, 0)
        self.write8(self.ARG_INDEX, index)
        self.write8(self.ARG_PICTURE, picture)
        self.write8(self.ARG_POSE, pose)
        self.write8(self.ARG_OFFSET, offset)
        self.write8(self.TARGET_LINE, target_line)
        self.write8(self.COMMAND, command)
        for _ in range(240):
            self.pyboy.tick(render=False)
            if self.read8(self.COMPLETE):
                return {
                    "carry": bool(self.read8(self.RESULT_CARRY)),
                    "a": self.read8(self.RESULT_A),
                    "b": self.read8(self.RESULT_B),
                    "c": self.read8(self.RESULT_C),
                    "d": self.read8(self.RESULT_D),
                    "e": self.read8(self.RESULT_E),
                    "h": self.read8(self.RESULT_H),
                    "l": self.read8(self.RESULT_L),
                    "ly": self.read8(self.RESULT_LY),
                }
        raise AssertionError(f"lobby pose cache fixture timed out on command {command}")

    def reset(self) -> dict[str, int | bool]:
        return self.command(self.RESET)

    def request(self, index: int, picture: int, pose: int, offset: int):
        return self.command(self.REQUEST, index, picture, pose, offset)

    def set_healing(self, active: int):
        return self.command(self.SET_HEALING, active)

    def invalidate(self, index: int):
        return self.command(self.INVALIDATE, index)

    def select(self):
        return self.command(self.SELECT)

    def publish(self, index: int, picture: int, pose: int, offset: int,
                *, target_line: int | None = None):
        command = self.PUBLISH if target_line is None else self.PUBLISH_AT_LINE
        return self.command(command, index, picture, pose, offset,
                           0 if target_line is None else target_line)


class LobbyPoseCacheAssemblyTest(unittest.TestCase):
    fixture: _LobbyPoseCacheRom | None = None
    temp_dir: tempfile.TemporaryDirectory[str] | None = None

    @classmethod
    def setUpClass(cls) -> None:
        cls.temp_dir = tempfile.TemporaryDirectory(prefix="redrogue-lobby-cache-")
        try:
            cls.fixture = _LobbyPoseCacheRom(Path(cls.temp_dir.name))
        except Exception:
            cls.temp_dir.cleanup()
            cls.temp_dir = None
            raise

    @classmethod
    def tearDownClass(cls) -> None:
        if cls.fixture is not None:
            cls.fixture.close()
        if cls.temp_dir is not None:
            cls.temp_dir.cleanup()

    def setUp(self) -> None:
        assert self.fixture is not None
        f = self.fixture
        f.write8(0xFF40, 0x00)  # deterministic immediate commits
        f.write8(0xFF4F, 0x00)  # bank-0 VRAM is the commit precondition
        f.write_block(f.STATE, bytes((0x30 + i * 7) & 0xFF
                                     for i in range(f.STATE_SIZE)))
        for address in range(0x8000, 0x9000):
            f.write8(address, 0xD1)
        for address in range(f.SHADOW_OAM, f.SHADOW_OAM + 0xA0):
            f.write8(address, 0xD2)
        for address in range(0xFE00, 0xFEA0):
            f.write8(address, 0xD3)
        f.write_block(f.STAGING, bytes((0x40 + i) & 0xFF for i in range(64)))
        f.write_block(f.OAM_SOURCE, bytes((0x90 + i) & 0xFF for i in range(16)))

    def _reset(self) -> None:
        result = self.fixture.reset()  # type: ignore[union-attr]
        self.assertFalse(result["carry"])
        self.assertEqual((result["b"], result["c"], result["d"], result["e"],
                          result["h"], result["l"]),
                         (0xA1, 0xB2, 0xC3, 0xD4, 0xC4, 0x00))

    def _state(self) -> bytes:
        assert self.fixture is not None
        return self.fixture.read_block(self.fixture.STATE,
                                       self.fixture.STATE_SIZE)

    def _outputs(self) -> tuple[bytes, bytes, bytes]:
        assert self.fixture is not None
        f = self.fixture
        return (f.read_block(0x8000, 0x1000),
                f.read_block(f.SHADOW_OAM, 0xA0),
                f.read_block(0xFE00, 0xA0))

    def _assert_hl(self, result: dict[str, int | bool]) -> None:
        self.assertEqual((result["h"], result["l"]), (0xC4, 0x00))

    def _publish_descriptor(self, index: int, picture: int, pose: int,
                            offset: int) -> None:
        assert self.fixture is not None
        result = self.fixture.publish(index, picture, pose, offset)
        self.assertFalse(result["carry"])
        self._assert_hl(result)

    def _request_and_publish(self, index: int, picture: int, pose: int,
                             offset: int) -> None:
        assert self.fixture is not None
        result = self.fixture.request(index, picture, pose, offset)
        self.assertFalse(result["carry"])
        self._assert_hl(result)
        selected = self.fixture.select()
        self.assertFalse(selected["carry"])
        self._assert_hl(selected)
        self._publish_descriptor(index, picture, pose, offset)

    def test_reset_clears_exact_21_bytes_and_preserves_guards_and_registers(self):
        assert self.fixture is not None
        f = self.fixture
        before = self._state()
        guard_before = f.read_block(f.STATE - 0x10, 0x40)
        result = f.reset()
        self.assertFalse(result["carry"])
        self.assertEqual((result["a"], result["b"], result["c"], result["d"],
                          result["e"], result["h"], result["l"]),
                         (0, 0xA1, 0xB2, 0xC3, 0xD4, 0xC4, 0))
        self.assertEqual(f.read_block(f.STATE, 18), bytes([0xFF] * 18))
        self.assertEqual(f.read_block(f.STATE + 18, 3), bytes([0, 0, 0]))
        self.assertEqual(f.read_block(f.STATE - 0x10, 0x10),
                         guard_before[:0x10])
        self.assertEqual(f.read_block(f.STATE + f.STATE_SIZE, 0x1B),
                         guard_before[0x10 + f.STATE_SIZE:])
        self.assertNotEqual(before, self._state())

    def test_request_valid_invalid_and_rejection_is_atomic(self):
        assert self.fixture is not None
        f = self.fixture
        self._reset()
        for index, picture, pose, offset in (
            (0, 1, 0, 0x00), (1, 2, 4, 0x10), (2, 3, 0x28, 0x20),
        ):
            with self.subTest(valid=(index, picture, pose, offset)):
                result = f.request(index, picture, pose, offset)
                self.assertFalse(result["carry"])
                self._assert_hl(result)
                start = 3 * index
                state = self._state()
                self.assertEqual(state[start:start + 3],
                                 bytes((picture, pose, offset)))
                self.assertEqual(state[18] & (1 << index), 1 << index)

        for index, picture, pose, offset in (
            (3, 1, 0, 0), (0, 0, 0, 0), (0, 0xFF, 0, 0),
            (0, 1, 1, 0), (0, 1, 0x24, 0), (0, 1, 0, 1),
            (0, 1, 0, 0xA0), (0xFF, 1, 0, 0),
        ):
            with self.subTest(invalid=(index, picture, pose, offset)):
                before = self._state()
                result = f.request(index, picture, pose, offset)
                self.assertTrue(result["carry"])
                self._assert_hl(result)
                self.assertEqual(self._state(), before)

    def test_identical_committed_request_coalesces_without_dirtying(self):
        assert self.fixture is not None
        f = self.fixture
        self._reset()
        f.request(0, 0x21, 4, 0x10)
        self._publish_descriptor(0, 0x21, 4, 0x10)
        state = self._state()
        self.assertEqual(state[18:20], bytes((0, 1)))
        result = f.request(0, 0x21, 4, 0x10)
        self.assertFalse(result["carry"])
        self._assert_hl(result)
        self.assertEqual(self._state(), state)
        result = f.select()
        self.assertTrue(result["carry"])
        self._assert_hl(result)

    def test_replacement_changes_request_but_not_committed_descriptor(self):
        assert self.fixture is not None
        f = self.fixture
        self._reset()
        f.request(1, 0x21, 0, 0x10)
        self._publish_descriptor(1, 0x21, 0, 0x10)
        before = self._state()
        result = f.request(1, 0x22, 8, 0x20)
        self.assertFalse(result["carry"])
        self._assert_hl(result)
        state = self._state()
        self.assertEqual(state[3:6], bytes((0x22, 8, 0x20)))
        self.assertEqual(state[9:12], before[9:12])
        # The old committed bytes remain valid while the replacement waits
        # for its own publish; only the dirty bit changes.
        self.assertEqual(state[18:20], bytes((0x02, 0x02)))

    def test_select_returns_first_dirty_descriptor_and_physical_base(self):
        assert self.fixture is not None
        f = self.fixture
        self._reset()
        descriptors = ((0, 0x21, 0, 0x20), (1, 0x22, 4, 0x40),
                        (2, 0x23, 8, 0x60))
        for descriptor in descriptors:
            self.assertFalse(f.request(*descriptor)["carry"])
        for index, picture, pose, offset in descriptors:
            with self.subTest(index=index):
                result = f.select()
                self.assertFalse(result["carry"])
                self.assertEqual((result["a"], result["b"], result["c"],
                                  result["d"], result["e"]),
                                 (index, 0x6C + index * 4, offset, picture, pose))
                self._assert_hl(result)
                # Selection is non-consuming until Publish.
                self.assertEqual(f.select()["a"], index)
            self._publish_descriptor(index, picture, pose, offset)
        self.assertTrue(f.select()["carry"])

    def test_stale_publish_rejects_without_vram_oam_or_state_publication(self):
        assert self.fixture is not None
        f = self.fixture
        self._reset()
        self.assertFalse(f.request(0, 0x21, 0, 0x00)["carry"])
        selected = f.select()
        self.assertEqual((selected["a"], selected["d"], selected["e"],
                          selected["c"]), (0, 0x21, 0, 0))
        self.assertFalse(f.request(0, 0x22, 4, 0x10)["carry"])
        state_before = self._state()
        outputs_before = self._outputs()
        result = f.publish(0, 0x21, 0, 0x00)
        self.assertTrue(result["carry"])
        self._assert_hl(result)
        self.assertEqual(self._state(), state_before)
        self.assertEqual(self._outputs(), outputs_before)

    def test_late_lcd_commit_stays_dirty_and_retry_succeeds(self):
        assert self.fixture is not None
        f = self.fixture
        self._reset()
        self.assertFalse(f.request(0, 0x21, 0, 0x00)["carry"])
        state_before = self._state()
        outputs_before = self._outputs()
        f.write8(0xFF40, 0x80)
        result = f.publish(0, 0x21, 0, 0x00, target_line=0)
        self.assertTrue(result["carry"])
        self._assert_hl(result)
        self.assertEqual(self._state(), state_before)
        self.assertEqual(self._outputs(), outputs_before)
        f.write8(0xFF40, 0)
        result = f.publish(0, 0x21, 0, 0x00)
        self.assertFalse(result["carry"])
        self.assertEqual(self._state()[18:21], bytes((0, 1, 0)))

    def test_invalidate_one_and_all_dirty_latest_valid_requests_only(self):
        assert self.fixture is not None
        f = self.fixture
        self._reset()
        self._request_and_publish(0, 0x21, 0, 0x00)
        self._request_and_publish(1, 0x22, 4, 0x10)
        result = f.invalidate(0)
        self.assertFalse(result["carry"])
        self._assert_hl(result)
        self.assertEqual(self._state()[18:20], bytes((0x01, 0x02)))
        result = f.select()
        self.assertEqual((result["a"], result["c"]), (0, 0x00))
        self._publish_descriptor(0, 0x21, 0, 0x00)
        self.assertEqual(self._state()[18:20], bytes((0x00, 0x03)))
        result = f.invalidate(0xFF)
        self.assertFalse(result["carry"])
        self._assert_hl(result)
        self.assertEqual(self._state()[18:20], bytes((0x03, 0x00)))
        # Cache 2 was never requested and must remain clean/unoccupied.
        self.assertEqual(self._state()[6:9], bytes([0xFF] * 3))

    def test_picture_change_is_a_new_dirty_request_and_commits_new_key(self):
        assert self.fixture is not None
        f = self.fixture
        self._reset()
        self._request_and_publish(0, 0x21, 0, 0x00)
        before = self._state()
        self.assertFalse(f.request(0, 0x31, 8, 0x20)["carry"])
        state = self._state()
        self.assertEqual(state[0:3], bytes((0x31, 8, 0x20)))
        self.assertEqual(state[9:12], before[9:12])
        self.assertEqual(state[18:20], bytes((0x01, 0x01)))
        selected = f.select()
        self.assertEqual((selected["a"], selected["b"], selected["c"],
                          selected["d"], selected["e"]), (0, 0x6C, 0x20,
                                                            0x31, 8))
        self._publish_descriptor(0, 0x31, 8, 0x20)
        self.assertEqual(self._state()[9:12], bytes((0x31, 8, 0x20)))
        self.assertEqual(self._state()[18:20], bytes((0, 1)))

    def test_three_dirty_requests_serialize_in_index_order(self):
        assert self.fixture is not None
        f = self.fixture
        self._reset()
        descriptors = ((0, 0x21, 0, 0x10), (1, 0x22, 4, 0x30),
                        (2, 0x23, 8, 0x50))
        for descriptor in descriptors:
            self.assertFalse(f.request(*descriptor)["carry"])
        for index, picture, pose, offset in descriptors:
            result = f.select()
            self.assertFalse(result["carry"])
            self.assertEqual((result["a"], result["b"], result["c"],
                              result["d"], result["e"]),
                             (index, 0x6C + index * 4, offset, picture, pose))
            self._publish_descriptor(index, picture, pose, offset)
        self.assertTrue(f.select()["carry"])
        self.assertEqual(self._state()[18:20], bytes((0, 7)))

    def test_healing_defers_80_and_90_but_allows_earlier_offsets_then_releases(self):
        assert self.fixture is not None
        f = self.fixture
        self._reset()
        descriptors = ((0, 0x21, 0, 0x80), (1, 0x22, 4, 0x90),
                        (2, 0x23, 8, 0x70))
        for descriptor in descriptors:
            self.assertFalse(f.request(*descriptor)["carry"])
        result = f.set_healing(1)
        self.assertFalse(result["carry"])
        self.assertEqual((result["b"], result["c"], result["d"], result["e"]),
                         (0xA1, 0xB2, 0xC3, 0xD4))
        self._assert_hl(result)
        result = f.select()
        self.assertFalse(result["carry"])
        self.assertEqual((result["a"], result["c"]), (2, 0x70))
        self._publish_descriptor(2, 0x23, 8, 0x70)
        self.assertTrue(f.select()["carry"])
        result = f.set_healing(0)
        self.assertFalse(result["carry"])
        self.assertEqual((result["b"], result["c"], result["d"], result["e"]),
                         (0xA1, 0xB2, 0xC3, 0xD4))
        self._assert_hl(result)
        for index, picture, pose, offset in descriptors[:2]:
            result = f.select()
            self.assertEqual((result["a"], result["c"]), (index, offset))
            self._publish_descriptor(index, picture, pose, offset)
        self.assertTrue(f.select()["carry"])

    def test_full_reload_and_text_healing_overlay_recovery_uses_real_sprite_assets(self):
        assert self.fixture is not None
        f = self.fixture
        assets = (
            (REPO_ROOT / "gfx" / "sprites" / "channeler.2bpp", 0x21, 0),
            (REPO_ROOT / "gfx" / "sprites" / "super_nerd.2bpp", 0x22, 4),
            (REPO_ROOT / "gfx" / "sprites" / "gameboy_kid.2bpp", 0x23, 8),
        )
        for path, picture, pose in assets:
            self.assertTrue(path.exists(), path)
            self.assertGreaterEqual(len(path.read_bytes()), pose * 16 + 64)

        self._reset()
        descriptors = tuple((index, picture, pose, 0x10 * index)
                            for index, (_, picture, pose) in enumerate(assets))
        for index, picture, pose, offset in descriptors:
            self.assertFalse(f.request(index, picture, pose, offset)["carry"])
            data = assets[index][0].read_bytes()
            f.write_block(f.STAGING, data[pose * 16:pose * 16 + 64])
            quad = bytes(value for tile in range(4) for value in (
                48 + (tile // 2) * 8,
                40 + (tile % 2) * 8,
                0x6C + index * 4 + tile,
                0x10,
            ))
            f.write_block(f.OAM_SOURCE, quad)
            self._publish_descriptor(index, picture, pose, offset)

        # A full reload and the ordinary text/healing overlays can overwrite
        # the cache's old bytes.  Invalidation must make the latest requests
        # recoverable without touching either overlay range during republish.
        for address in range(0x8000, 0x9000):
            f.write8(address, 0xA5)
        font = bytes((i * 13) & 0xFF for i in range(0x800))
        healing = bytes([0xE7] * 48)
        f.write_block(0x8800, font)
        f.write_block(0x87C0, healing)
        self.assertFalse(f.invalidate(0xFF)["carry"])
        self.assertEqual(self._state()[18:20], bytes((0x07, 0x00)))

        for index, (path, picture, pose), descriptor in zip(
            range(3), assets, descriptors
        ):
            _, _, _, offset = descriptor
            result = f.select()
            self.assertEqual((result["a"], result["c"], result["d"],
                              result["e"]), (index, offset, picture, pose))
            data = path.read_bytes()
            staged = data[pose * 16:pose * 16 + 64]
            f.write_block(f.STAGING, staged)
            self._publish_descriptor(index, picture, pose, offset)
            self.assertEqual(f.read_block(0x8000 + (0x6C + index * 4) * 16, 64),
                             staged)

        self.assertEqual(f.read_block(0x8800, 0x800), font)
        self.assertEqual(f.read_block(0x87C0, 48), healing)
        self.assertEqual(self._state()[18:20], bytes((0, 7)))


if __name__ == "__main__":
    unittest.main(verbosity=2)
