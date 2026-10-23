"""CGB autoplay mode propagation and visible BG palette sanity checks."""
from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import autoplay
import autoplay_branch
import autoplay_checks
import autoplay_screen
import nightly
import run_autoplay
import save_reload
from test_smoke import ARTIFACTS, REPO_ROOT


class PaletteHelpersTest(unittest.TestCase):
    def test_reads_known_rgb15_row_without_changing_bgpi(self) -> None:
        class Memory:
            def __init__(self) -> None:
                self.index = 0xB5
                self.bytes = [0] * 64

            def __getitem__(self, address: int) -> int:
                if address == 0xFF68:
                    return self.index
                if address == 0xFF69:
                    return self.bytes[self.index & 0x3F]
                raise KeyError(address)

            def __setitem__(self, address: int, value: int) -> None:
                if address == 0xFF68:
                    self.index = value
                elif address == 0xFF69:
                    self.bytes[self.index & 0x3F] = value
                    if self.index & 0x80:
                        self.index = (self.index & 0x80) | ((self.index + 1) & 0x3F)
                else:
                    raise KeyError(address)

        memory = Memory()
        known = (0x7FFF, 0x56B5, 0x294A, 0x0000)
        for i, color in enumerate(known):
            memory.bytes[16 + i * 2] = color & 0xFF
            memory.bytes[17 + i * 2] = color >> 8

        self.assertEqual(autoplay_screen.read_cgb_bg_palette(memory, 2), known)
        self.assertEqual(memory.index, 0xB5)

    def test_visible_palette_allows_grayscale_and_distinct_uniform_rows(self) -> None:
        grayscale = (0x7FFF, 0x56B5, 0x294A, 0x0000)
        self.assertTrue(autoplay_screen.visible_palette_rows_are_sane([grayscale]))
        self.assertTrue(autoplay_screen.visible_palette_rows_are_sane([(0x001F,) * 4,
                                                                       (0x7C00,) * 4]))
        self.assertFalse(autoplay_screen.visible_palette_rows_are_sane([(0x1234,) * 4,
                                                                        (0x1234,) * 4]))

    def test_uniform_fade_mapping_covers_all_four_shades(self) -> None:
        for value in (0x00, 0x55, 0xAA, 0xFF):
            with self.subTest(value=value):
                self.assertTrue(autoplay_screen.uniform_dmg_palette_mapping(value))
        self.assertFalse(autoplay_screen.uniform_dmg_palette_mapping(0xE4))


class CGBModePropagationTest(unittest.TestCase):
    def test_cgb_flags_are_opt_in_and_artifacts_do_not_collide(self) -> None:
        self.assertFalse(autoplay.build_parser().parse_args([]).cgb)
        self.assertTrue(autoplay.build_parser().parse_args(["--cgb"]).cgb)
        self.assertFalse(run_autoplay.build_parser().parse_args([]).cgb)
        self.assertTrue(run_autoplay.build_parser().parse_args(["--cgb"]).cgb)
        self.assertNotEqual(
            autoplay.stem(7, rom=autoplay.DEBUG_ROM, cgb_mode=False),
            autoplay.stem(7, rom=autoplay.DEBUG_ROM, cgb_mode=True),
        )

    def test_branch_and_save_emulators_receive_cgb_mode(self) -> None:
        class FakeHarness:
            calls: list[dict[str, object]] = []

            def __init__(self, *_args, **kwargs) -> None:
                self.calls.append(kwargs)
                self.hardware_mode = "CGB" if kwargs.get("cgb_mode") else "DMG"

            def close(self) -> None:
                pass

        FakeHarness.calls = []
        with patch.object(autoplay_branch, "RedRogueHarness", FakeHarness), \
                patch.object(autoplay_branch, "BranchDriver", return_value=object()):
            result = autoplay_branch.run_snapshots(1, [], branches=1, frames=10,
                                                   cgb_mode=True)
        self.assertTrue(FakeHarness.calls[-1]["cgb_mode"])
        self.assertEqual(result["hardware_mode"], "CGB")

        FakeHarness.calls = []
        with patch.object(save_reload, "RedRogueHarness", FakeHarness), \
                patch.object(save_reload.autoplay_branch, "BranchDriver", return_value=object()):
            save_reload.run_save_checks(1, [], cgb_mode=True)
        self.assertEqual([call.get("cgb_mode") for call in FakeHarness.calls], [True, True])

    def test_nightly_cgb_suite_exercises_branch_save_and_coverage_paths(self) -> None:
        command, _timeout, keep = nightly.SUITES["cgb"]
        self.assertIn("--cgb", command)
        self.assertIn("--branches", command)
        self.assertIn("--save-checks", command)
        self.assertIn("--coverage", command)
        self.assertIn("autoplay_summary_cgb.json", keep)
        for flag in nightly.QUICK["cgb"]:
            self.assertIn(flag, command)

    def test_coverage_summary_path_resets_to_the_requested_mode(self) -> None:
        self.assertEqual(run_autoplay.coverage_summary_path(True),
                         autoplay.ARTIFACTS / "coverage_summary_cgb.json")
        self.assertEqual(run_autoplay.coverage_summary_path(False),
                         autoplay.ARTIFACTS / "coverage_summary.json")


class CGBMainWRAMReadinessTest(unittest.TestCase):
    def make_agent(self, *, hardware_mode: str, svbk: int):
        agent = object.__new__(autoplay.AutoplayAgent)
        memory = {0xFF70: svbk}
        ticks: list[int] = []
        agent.mem = memory
        agent.h = SimpleNamespace(
            hardware_mode=hardware_mode,
            pyboy=SimpleNamespace(frame_count=77),
            tick=lambda frames=1: ticks.append(frames),
        )
        return agent, ticks

    def test_only_cgb_banks_zero_and_one_are_ready(self) -> None:
        for svbk in range(8):
            with self.subTest(svbk=svbk):
                agent, _ = self.make_agent(hardware_mode="CGB", svbk=svbk)
                self.assertEqual(agent.game_world_reads_ready(), svbk in (0, 1))
        agent, _ = self.make_agent(hardware_mode="DMG", svbk=6)
        self.assertTrue(agent.game_world_reads_ready())

    def test_unsafe_step_ticks_once_without_reading_game_state(self) -> None:
        agent, ticks = self.make_agent(hardware_mode="CGB", svbk=2)
        agent.report = SimpleNamespace(steps=0)
        agent.cgb_wram_wait_frames = 0
        agent.track_battles = lambda: self.fail("must defer game-state reads while SVBK is unsafe")

        agent.step()

        self.assertEqual(agent.report.steps, 1)
        self.assertEqual(agent.cgb_wram_wait_frames, 1)
        self.assertEqual(ticks, [1])

    def test_progress_and_heartbeat_defer_world_reads(self) -> None:
        agent, _ = self.make_agent(hardware_mode="CGB", svbk=3)
        agent.h.read8 = lambda *_args: self.fail("unsafe D-bank read")
        agent.report = SimpleNamespace(events=[])
        agent.progress_marker = ("unchanged",)
        agent.last_progress_frame = 12
        agent.heartbeat = Path(tempfile.gettempdir()) / "followup81-cgb-heartbeat-test.json"

        agent.note_progress()
        agent.write_heartbeat()
        state = json.loads(agent.heartbeat.read_text(encoding="utf-8"))
        agent.heartbeat.unlink()

        self.assertEqual(agent.progress_marker, ("unchanged",))
        self.assertEqual(state["frame"], 77)
        self.assertIsNone(state["map"])
        self.assertIsNone(state["position"])
        self.assertEqual(state["mode"], "waiting for main WRAM bank")


class CGBStackCopyWindowTest(unittest.TestCase):
    def make_checks(self, *, saved_sp: int = 0xDFF0, hardware_mode: str = "CGB"):
        class FakeSymbols:
            def nearest(self, _bank: int, address: int) -> str:
                return f"${address:04X}"

        class FakeHarness:
            def __init__(self) -> None:
                self.hardware_mode = hardware_mode
                self.symbols = FakeSymbols()
                self.pyboy = SimpleNamespace(
                    register_file=SimpleNamespace(PC=0x560C, SP=0xC3F4),
                    frame_count=0,
                )

            def read8(self, label: str, offset: int = 0) -> int:
                if label == "hLoadedROMBank":
                    return 0x2C
                if label == "hSPTemp":
                    return (saved_sp >> 8) if offset == 0 else (saved_sp & 0xFF)
                raise KeyError(label)

        checks = object.__new__(autoplay_checks.GameChecks)
        checks.h = FakeHarness()
        checks.stack_top = 0xDFFF
        checks.stack_armed = True
        checks.lowest_sp = checks.stack_top
        checks.rom_banks = 512
        checks.crash = None
        checks.sp_trick_ranges = []
        checks.sp_copy_windows = [(0x2C, 0x5600, 0x566C, 0xC3A0, 0xC508)]
        return checks

    def test_map_copy_window_requires_matching_pc_source_and_saved_stack(self) -> None:
        checks = self.make_checks()
        self.assertTrue(checks._in_sp_trick(0x560C, 0xC3F4))
        self.assertFalse(checks._in_sp_trick(0x560C, 0xC510), "SP outside wTileMap must fail")
        self.assertFalse(checks._in_sp_trick(0x566C, 0xC3F4), "PC at the window end must fail")
        self.assertFalse(self.make_checks(saved_sp=0xC3F4)._in_sp_trick(0x560C, 0xC3F4),
                         "hSPTemp must preserve a real stack pointer")
        self.assertFalse(self.make_checks(hardware_mode="DMG")._in_sp_trick(0x560C, 0xC3F4))

    def test_bad_sp_during_copy_window_still_trips_crash_check(self) -> None:
        checks = self.make_checks()
        checks.h.pyboy.register_file.SP = 0xC510
        checks.after_step()
        self.assertEqual(checks.crash["kind"], "stack_out_of_range")

    def test_valid_source_pointer_inside_copy_window_is_accepted(self) -> None:
        checks = self.make_checks()
        checks.after_step()
        self.assertIsNone(checks.crash)


if __name__ == "__main__":
    unittest.main()
