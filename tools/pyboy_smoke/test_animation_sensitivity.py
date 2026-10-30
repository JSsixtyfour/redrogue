"""REDUCED includes OFF and suppresses battle text-window shaking."""

import io
import tempfile
from pathlib import Path

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants
from test_smoke import HarnessTestCase, REPO_ROOT, ARTIFACTS
from test_evolution_flow import EvolutionFlowFixture
from test_move_tutor_prices import run_entry


class AnimationSensitivityTest(HarnessTestCase):
    def startup(self, ram_path=None):
        if "StartupSensitivityChoice.ready" not in self.harness.symbols._symbols:
            self.skipTest("The pre-intro Sensitivity screen is shelved")
        cgb_mode = self.harness.hardware_mode == "CGB"
        self.harness.close()
        self.harness = RedRogueHarness(REPO_ROOT, ARTIFACTS, ram_path=ram_path,
                                      startup_sensitivity=None, cgb_mode=cgb_mode)
        h = self.harness
        ready = h.hook_flag("StartupSensitivityChoice.ready")
        h.wait_until(lambda: ready["count"], "steady startup choice", 600)
        h.tick(5, render=True)
        ARTIFACTS.mkdir(parents=True, exist_ok=True)
        suffix = "_cgb" if cgb_mode else ""
        h.pyboy.screen.image.save(ARTIFACTS / f"sensitivity_startup{suffix}.png")
        return h

    def test_startup_a_enables_sensitivity_without_intro_or_title(self):
        h = self.startup()
        intro = h.hook_flag("PlayIntro")
        title = h.hook_flag("DisplayTitleScreen")
        menu = h.hook_flag("MainMenu.mainMenuLoop")
        h.tap("a")
        h.wait_until(lambda: menu["count"], "Sensitivity main menu", 600)
        self.assertEqual(intro["count"], 0)
        self.assertEqual(title["count"], 0)
        self.assertTrue(h.read8("wOptions3") & 0x10)
        self.assertTrue(h.read8("wOptions") & 0x80)

    def test_startup_b_keeps_normal_intro(self):
        h = self.startup()
        intro = h.hook_flag("PlayIntro")
        h.tap("b")
        h.wait_until(lambda: intro["count"], "ordinary intro", 600)
        self.assertFalse(h.read8("wOptions3") & 0x10)

    def test_startup_choice_survives_loading_an_off_save(self):
        from test_save_header import dump_sram
        h = self.harness
        h.boot_to_lobby()
        h.write8("wOptions3", h.read8("wOptions3") & ~0x10)
        h.write8("wOptions", h.read8("wOptions") | 0x80)
        h.call_routine("SaveGameData")
        image = dump_sram(h)
        with tempfile.TemporaryDirectory() as directory:
            ram = Path(directory) / "ordinary.sav"
            ram.write_bytes(image)
            h = self.startup(ram)
            loaded = h.hook_flag("TryLoadSaveFile")
            menu = h.hook_flag("MainMenu.mainMenuLoop")
            h.tap("a")
            h.wait_until(lambda: menu["count"], "saved main menu", 600)
            self.assertGreater(loaded["count"], 0)
            self.assertTrue(h.read8("wOptions3") & 0x10)
            self.assertTrue(h.read8("wOptions") & 0x80)

    def test_new_game_defaults_keep_sensitivity(self):
        h = self.harness
        h.boot_fight2(seed=1)
        h.write8("wOptions3", 0x10)
        h.call_routine("InitOptions_")
        self.assertTrue(h.read8("wOptions3") & 0x10)
        self.assertTrue(h.read8("wOptions") & 0x80)

    def test_startup_choice_survives_direct_loss_recovery(self):
        from test_save_header import dump_sram
        h = self.harness
        h.boot_to_lobby()
        h.write8("wStatusFlags6", h.read8("wStatusFlags6") & ~0x82)
        h.write8("wRentalState", 0)
        h.write8("wOptions3", h.read8("wOptions3") & ~0x10)
        h.call_routine("LossRecoveryDiscard")
        h.call_routine("LossRecoveryPrepare")
        with tempfile.TemporaryDirectory() as directory:
            ram = Path(directory) / "recovery.sav"
            ram.write_bytes(dump_sram(h))
            h = self.startup(ram)
            entered = h.hook_flag("SpecialEnterMap")
            h.tap("a")
            h.wait_until(lambda: entered["count"], "Sensitivity loss recovery", 900)
            self.assertTrue(h.read8("wOptions3") & 0x10)
            self.assertTrue(h.read8("wOptions") & 0x80)

    def test_sensitivity_skips_blink_evolution_and_heal_effect_bodies(self):
        h = self.harness
        h.boot_fight2(seed=1)
        baseline = io.BytesIO()
        h.save_state(baseline)
        for routine, body in (("AnimationBlinkMon", "AnimationHideMonPic"),
                              ("Evolution_BackAndForthAnim", "Evolution_ChangeMonPic"),
                              ("FlashSprite8Times", "FlashSprite8Times.loop")):
            with self.subTest(routine=routine):
                h.load_state(baseline)
                h.park_before_hijack()
                h.write8("wOptions3", h.read8("wOptions3") | 0x10)
                entered = h.hook_flag(body)
                h.call_routine(routine)
                self.assertEqual(entered["count"], 0)

    def test_sensitivity_keeps_dialogue_arrow_visible(self):
        h = self.harness
        h.boot_fight2(seed=1)
        cell = h.address("wTileMap") + 18 + 16 * 20
        def setup(h):
            h.write8("wOptions3", h.read8("wOptions3") | 0x10)
            h.pyboy.memory[cell] = 0xEE
            h.write8("hDownArrowBlinkCount1", 1)
            h.write8("hDownArrowBlinkCount2", 1)
        # Observe the return before the abandoned battle redraws the tilemap.
        result = run_entry(h, "HandleDownArrowBlinkTiming", registers={"HL": cell}, setup=setup,
                           capture=lambda h: {"tile": h.pyboy.memory[cell],
                               "counts": [h.read8("hDownArrowBlinkCount1"), h.read8("hDownArrowBlinkCount2")]})
        self.assertEqual(result["tile"], 0xEE)
        self.assertEqual(result["counts"], [1, 1])

    def run_live(self, routine, setup=None, limit=1800, entry="JoypadLowSensitivity"):
        """Borrow one real menu-input call, preserving its return and interrupts."""
        h = self.harness
        armed = [True]
        finished = [False]
        bank, address = h.symbols.get(routine)
        def enter(_):
            if not armed[0]:
                finished[0] = True
                return
            armed[0] = False
            if setup:
                setup()
            rf = h.pyboy.register_file
            # Bankswitch returns to the genuine input call we intercepted.
            rf.SP -= 2
            target = h.address(entry)
            h.pyboy.memory[rf.SP] = target & 0xFF
            h.pyboy.memory[rf.SP + 1] = target >> 8
            rf.B, rf.HL = bank, address
            rf.PC = h.address("Bankswitch")
        h.register_hook(entry, enter)
        try:
            h.wait_until(lambda: finished[0], f"live {routine} return", limit)
        finally:
            h.unregister_hook(entry, enter)

    def test_steady_transition_fades_and_returns_without_pattern_or_flash(self):
        h = self.harness
        h.boot_fight2(seed=1)
        h.write8("wOptions3", h.read8("wOptions3") | 0x10)
        patterns = h.hook_flag("LoadBattleTransitionTile")
        flashes = h.hook_flag("BattleTransition_FlashScreen_")
        fade = h.hook_flag("GBFadeOutToBlack_")
        self.run_live("BattleTransition")
        self.assertGreater(fade["count"], 0)
        self.assertEqual(patterns["count"], 0)
        self.assertEqual(flashes["count"], 0)
        self.assertEqual(h.read8("hAutoBGTransferEnabled"), 0)
        self.assertEqual(h.pyboy.memory[0xFF47], 0xFF)

    def test_elevator_retains_completion_with_a_fixed_camera(self):
        h = self.harness
        h.boot_to_lobby()
        h.write8("wOptions3", h.read8("wOptions3") | 0x10)
        camera = h.read8("hSCY")
        samples = []
        h.register_hook("ShakeElevator.steady", lambda _:
                        samples.append(h.read8("hSCY")))
        cleanup = h.hook_flag("PlayDefaultMusic")
        self.run_live("ShakeElevator", entry="JoypadOverworld")
        self.assertEqual(len(samples), 100)
        self.assertEqual(set(samples), {camera})
        self.assertGreater(cleanup["count"], 0)

    def test_party_icon_wait_yields_without_altering_oam(self):
        h = self.harness
        h.boot_fight2(seed=1)
        h.write8("wOptions3", h.read8("wOptions3") | 0x10)
        motion = h.hook_flag("GetAnimationSpeed.motion")
        before = h.read_bytes("wShadowOAM", 160)
        self.run_live("AnimatePartyMon")
        self.assertEqual(motion["count"], 0)
        self.assertEqual(h.read_bytes("wShadowOAM", 160), before)

    def test_slot_payout_keeps_coins_without_palette_flashing(self):
        h = self.harness
        h.boot_fight2(seed=1)
        h.write8("wOptions3", h.read8("wOptions3") | 0x10)
        h.write8("wPayoutCoins", 0)
        h.write8("wPayoutCoins", 3, 1)
        h.write8("wPlayerCoins", 0)
        h.write8("wPlayerCoins", 0, 1)
        h.write8("wSlotMachineWinningSymbol", 0)
        palettes = []
        h.register_hook("SlotMachine_PayCoinsToPlayer.skip1", lambda _:
                        palettes.append(h.pyboy.memory[0xFF48]))
        self.run_live("SlotMachine_PayCoinsToPlayer")
        self.assertEqual(h.read_bytes("wPayoutCoins", 2), [0, 0])
        self.assertEqual(h.read_bytes("wPlayerCoins", 2), [0, 3])
        self.assertEqual(len(set(palettes)), 1)

    def test_sensitivity_label_fits_and_is_fully_erased(self):
        h = self.harness
        h.boot_fight2(seed=1)
        cell = h.address("wTileMap") + 2 * 20 + 8
        for options, extra, label in ((0x80, 0x10, "OptTextAnimSensitivity"),
                                      (0, 0, "OptTextAnimOn"),
                                      (0x80, 0, "OptTextAnimOff")):
            with self.subTest(label=label):
                def setup(h):
                    h.write8("wOptions", options)
                    h.write8("wOptions3", extra)
                    h.pyboy.memory[cell - 1] = 0x7F
                    h.pyboy.memory[cell + 11] = 0x7F
                bank, address = h.symbols.get(label)
                expected = list(h.pyboy.memory[bank, address:address + 11])
                result = run_entry(h, "OptDrawBattleAnim", registers={"HL": cell}, setup=setup,
                    capture=lambda h: {"tiles": list(h.pyboy.memory[cell:cell + 11]),
                        "guards": [h.pyboy.memory[cell - 1], h.pyboy.memory[cell + 11]]})
                self.assertEqual(result["tiles"], expected)
                self.assertEqual(result["guards"], [0x7F, 0x7F])

    def test_rotation_and_legacy_reduced_preserve_other_options(self):
        h = self.harness
        h.boot_fight2(seed=1)
        baseline = io.BytesIO()
        h.save_state(baseline)
        # ON, OFF, REDUCED, and the older REDUCED encoding.
        for options, extra, index in ((0, 0, 0), (0x80, 0, 1),
                                      (0x80, 0x10, 2), (0, 0x10, 2)):
            for direction in (1, -1):
                with self.subTest(index=index, direction=direction, legacy=options == 0):
                    h.load_state(baseline)
                    h.park_before_hijack()
                    h.write8("wOptions", options | 0x43)
                    h.write8("wOptions3", extra | 0x2B)
                    h.call_routine("OptBattleAnimIndex")
                    self.assertEqual(h.last_call_registers["A"], index)
                    h.write8("hJoy5", 0x10 if direction == 1 else 0x20)
                    h.call_routine("OptCycleBattleAnim")
                    target = (index + direction) % 3
                    self.assertEqual(h.read8("wOptions"), 0x43 | (0x80 if target else 0))
                    self.assertEqual(h.read8("wOptions3"), 0x2B | (0x10 if target == 2 else 0))

    def test_reduced_blocks_text_window_and_hud_shakes(self):
        h = self.harness
        h.boot_fight2(seed=1)
        baseline = io.BytesIO()
        h.save_state(baseline)
        predef_body = h.hook_flag("GetPredefRegisters")
        slow_body = h.hook_flag("AnimationShakeScreenHorizontallySlow")
        hud_body = h.hook_flag("ShakeEnemyHUD_WritePlayerMonPicOAM")
        for routine in ("PredefShakeScreenVertically", "PredefShakeScreenHorizontally",
                        "ShakeScreenHorizontallySlowCommon", "AnimationShakeEnemyHUD"):
            with self.subTest(routine=routine):
                h.load_state(baseline)
                h.park_before_hijack()
                h.write8("wOptions3", h.read8("wOptions3") | 0x10)
                counts = [flag["count"] for flag in (predef_body, slow_body, hud_body)]
                window = tuple(h.pyboy.memory[a] for a in (0xFF4A, 0xFF4B))
                h.call_routine(routine)
                self.assertEqual([flag["count"] for flag in (predef_body, slow_body, hud_body)], counts)
                self.assertEqual(tuple(h.pyboy.memory[a] for a in (0xFF4A, 0xFF4B)), window)

    def test_reduced_uses_off_path_during_real_battle(self):
        h = self.harness
        h.boot_fight2(seed=1)
        baseline = io.BytesIO()
        h.save_state(baseline)
        disabled = h.hook_flag("MoveAnimation.animationsDisabled")
        played = h.hook_flag("PlayAnimation")
        for off_bit in (0, 0x80):
            with self.subTest(legacy=off_bit == 0):
                h.load_state(baseline)
                h.write8("wOptions", (h.read8("wOptions") & 0x7F) | off_bit)
                h.write8("wOptions3", h.read8("wOptions3") | 0x10)
                before_disabled, before_played = disabled["count"], played["count"]
                for _ in range(180):
                    h.tap("a", 1)
                    if disabled["count"] > before_disabled:
                        break
                self.assertGreater(disabled["count"], before_disabled)
                self.assertEqual(played["count"], before_played)

    def test_legacy_reduced_keeps_off_substitute_setup(self):
        h = self.harness
        h.boot_fight2(seed=1)
        moves = parse_rgbds_constants(REPO_ROOT / "constants/move_constants.asm")
        # The enemy FIGHT 2 rolls follows VBlank-time RNG, so its moves drift with engine
        # timing (an Arbok's Wrap kept the player from ever acting). Pin it to Splash.
        for i in range(4):
            h.write8("wEnemyMonMoves", moves["SPLASH"] if i == 0 else 0, offset=i)
            h.write8("wEnemyMonPP", 30 if i == 0 else 0, offset=i)
        h.write8("wEnemySelectedMove", moves["SPLASH"])  # the AI picks before the menu opens
        h.write8("wBattleMonMoves", moves["SUBSTITUTE"])
        h.write8("wBattleMonPP", 10)
        h.write8("wOptions", h.read8("wOptions") & 0x7F)
        h.write8("wOptions3", h.read8("wOptions3") | 0x10)
        disabled = h.hook_flag("SubstituteEffect_.animationDisabled")
        substitute = h.hook_flag("AnimationSubstitute")
        for _ in range(300):
            h.tap("a", 1)
            if substitute["count"]:
                break
        self.assertGreater(disabled["count"], 0)
        self.assertGreater(substitute["count"], 0)


class SensitivityEvolutionTest(EvolutionFlowFixture, HarnessTestCase):
    def enable(self):
        h = self.harness
        h.register_hook("EvolveMon", lambda _:
                        h.write8("wOptions3", h.read8("wOptions3") | 0x10))
        return h.hook_flag("Evolution_ChangeMonPic")

    def test_evolutions_reveal_once_and_restore_battle(self):
        changes = self.enable()
        self.run_evolution()
        self.assertEqual(changes["count"], 2)  # one active, one bench

    def test_cancel_keeps_original_picture_and_restores_battle(self):
        changes = self.enable()
        self.run_evolution(cancel=True)
        self.assertEqual(changes["count"], 1)  # active cancelled; bench evolves once
