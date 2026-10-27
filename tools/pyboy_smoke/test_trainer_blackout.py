"""Real trainer loss -> run reset -> special warp -> controllable Dorm.

Only HP/KO Defiance are forced at the first live battle-loop entry. All
faint handling, battle cleanup, map scripts and warps execute normally.
"""
import re
import unittest
from test_smoke import HarnessTestCase, REPO_ROOT
from source_constants import parse_map_constants, parse_rgbds_constants, parse_trainer_constants


def loss_label_parts():
    """{origin id: (creator text, name text)} from the generated label tables."""
    text = (REPO_ROOT / 'data/trainers/movesets.asm').read_text(encoding='utf-8')
    creators = dict(re.findall(r'^\.creator(\d+): db "(.*)@"', text, re.M))
    names = dict(re.findall(r'^\.name(\d+): db "(.*)@"', text, re.M))
    return {int(o): (creators[c], names[n])
            for c, n, o in re.findall(r'^\tdb (\d+), (\d+) ; (\d+):', text, re.M)}


def letters(text):
    """Letters only, one space between runs: the box's ligature/punctuation tiles drop out."""
    return ' '.join(re.sub(r"<CONT>|'[stdlvrm]|[^A-Za-z]", ' ', text).split())


def box_letters(h):
    """The battle text box (tilemap rows 12-17), decoded the same way."""
    out = []
    for tile in h.read_bytes('wTileMap', 20 * 18)[20 * 12:]:
        if 0x80 <= tile <= 0x99:
            out.append(chr(ord('A') + tile - 0x80))
        elif 0xA0 <= tile <= 0xB9:
            out.append(chr(ord('a') + tile - 0xA0))
        else:
            out.append(' ')
    return ' '.join(''.join(out).split())


class BlackoutFixture:
    def check_checkpoint_cold_continue(self, *, cgb=False):
        from test_save_header import ColdBoot, dump_sram
        from test_loss_recovery import CgbColdBoot
        boot = (CgbColdBoot if cgb else ColdBoot)(dump_sram(self.harness))
        try:
            self.assertEqual(boot.to_menu(), 2)
            boot.continue_game()
            maps = parse_map_constants(REPO_ROOT / 'constants/map_constants.asm')
            self.assertEqual(boot.h.read8('hCurMap'), maps['SILPH_CO_DORM'])
            self.assertEqual(boot.h.read8('wPartyCount'), 0)
            self.assertEqual(boot.h.read_bytes('wPlayerCoins', 2), [0x12, 0x34])
            self.assertEqual((boot.h.read8('wXCoord'), boot.h.read8('wYCoord')), (1, 7))
        finally:
            boot.close()

    def run_loss(self, *, leader=False, unvisited_hub=False, normal_save=False,
                 force_origin=None):
        """force_origin: overwrite the winning slot's wEnemyMoveOrigins entry as
        PrintLossOrigin starts; returns the text box seen at each .placePart
        entry and at .placed (all [] when not forced)."""
        h = self.harness
        maps = parse_map_constants(REPO_ROOT / 'constants/map_constants.asm')
        stride = h.address('wPartyMon2HP') - h.address('wPartyMon1HP')
        h.boot_to_lobby()
        if normal_save:
            h.write8('wStatusFlags6', h.read8('wStatusFlags6') & ~0x82)
        saves = h.hook_flag('SaveGameData')
        committed = h.hook_flag('LossRecoveryFinish.retire')
        h.enter_stage_door1(maps['PEWTER_GYM'], description='Brock gym')
        if unvisited_hub:
            # New games have not necessarily entered the Lobby, which used to
            # be the only place that established the Dorm blackout target.
            h.write8('wLastBlackoutMap', maps['PALLET_TOWN'])
        if leader:
            events = parse_rgbds_constants(REPO_ROOT / 'constants/event_constants.asm')
            for i in range(3):
                event = events[f'EVENT_BEAT_PEWTER_GYM_TRAINER_{i}']
                addr = h.address('wEventFlags') + event // 8
                h.pyboy.memory[addr] |= 1 << (event % 8)
        trace = []
        def record(label):
            trace.append((label, h.read8('hCurMap'), h.read8('wLastBlackoutMap'),
                          h.read8('wPartyCount'), h.read8('wBattleResult')))
        for label in ('HandlePlayerBlackOut', 'HandleBlackOut',
                      'ResetStatusAndHalveMoneyOnBlackout', 'HealParty',
                      'PrepareForSpecialWarp', 'SpecialEnterMap', 'CrashScreen'):
            h.register_hook(label, lambda _, label=label: record(label))
        fainted = []
        def faint(_):
            if fainted:
                return
            fainted.append(h.read8('wCurOpponent'))
            h.write8('wKODefianceUsages', 0)
            h.write8('wBattleMonHP', 0)
            h.write8('wBattleMonHP', 0, 1)
            for i in range(h.read8('wPartyCount')):
                h.write8('wPartyMon1HP', 0, i * stride)
                h.write8('wPartyMon1HP', 0, i * stride + 1)
        h.register_hook('MainInBattleLoop', faint)
        # Run-end persistence: Credits (wPlayerCoins, BCD) survive the reset,
        # the pending tally reaches the Dorm popup, and the Oak's Lab objects
        # a previous run hid come back. Seeded right before the loss.
        # (toggle_constants.asm's trailing hex comments are stale; parse.)
        toggles = parse_rgbds_constants(REPO_ROOT / 'constants/toggle_constants.asm')
        lab_toggles = [toggles[f'TOGGLE_ROGUE_STARTER_POKEBALL_{i}'] for i in (1, 2, 3)]
        lab_toggles.append(toggles['TOGGLE_OAKS_LAB_RIVAL'])
        h.write8('wPlayerCoins', 0x12)
        h.write8('wPlayerCoins', 0x34, 1)
        h.write8('wCreditsEarnedThisRun', 3)
        toggle_base = h.address('wToggleableObjectFlags')
        for bit in lab_toggles:
            h.pyboy.memory[toggle_base + bit // 8] |= 1 << (bit % 8)
        popup_tally = []
        h.register_hook('RogueCreditPopupCheck',
                        lambda _: popup_tally.append(h.read8('wCreditsEarnedThisRun')))
        # The tally alone proved nothing: the box was drawn only into WRAM with
        # the BG transfer off, so it never reached the screen. Read what the
        # window actually shows right before the popup restores the area.
        popup_screen = []
        def popup_restore(_):
            if popup_tally and not popup_screen:
                row = 0x9c00 + 2 * 32 + 2
                popup_screen.append((h.read8('hWY'),
                                     bytes(h.pyboy.memory[row:row + 6])))
        h.register_hook('LoadScreenTileAreaFromBuffer3', popup_restore)
        # Loss message: at .gotCode, a = the LossOriginLabels index chosen.
        # Record it with what wEnemyMoveOrigins says for the mon that was out.
        loss_codes = []
        def loss_code(_):
            pos = h.read8('wEnemyMonPartyPos')
            loss_codes.append((h.pyboy.register_file.A, h.read8('hIsInBattle'), pos,
                               h.read8('wEnemyMoveOrigins', pos) if pos < 6 else None))
        h.register_hook('PrintLossOrigin.gotCode', loss_code)
        boxes = []
        if force_origin is not None:
            def force(_):
                pos = h.read8('wEnemyMonPartyPos')
                if pos < 6:
                    h.write8('wEnemyMoveOrigins', force_origin, pos)
            h.register_hook('PrintLossOrigin', force)
            for label in ('PrintLossOrigin.placePart', 'PrintLossOrigin.placed'):
                h.register_hook(label, lambda _: boxes.append(box_letters(h)))
        # The lower trainer sees (4,7); Brock is spoken to from (4,2).
        for _ in range(11 if leader else 7):
            h.move_tile('up')
            if leader and h.read8('wYCoord') == 2:
                h.tap('a', 4)
            for _ in range(20):
                h.tap('a', 2)
                h.tick(8)
                if fainted:
                    break
            if fainted:
                break
        self.assertTrue(fainted, h.diagnostic_state())
        for _ in range(250):
            h.tap('a', 2)
            h.tick(8)
            if (h.read8('hCurMap') == maps['SILPH_CO_DORM']
                    and h.read8('hJoyIgnore') == 0
                    and (not normal_save or committed['count'])):
                break
        if normal_save:
            self.assertEqual(committed['count'], 1)
            h.tick(120)  # finish the noninteractive completion notice
            self.assertEqual(saves['count'], 1)
        labels = [row[0] for row in trace]
        self.assertNotIn('CrashScreen', labels, trace)
        self.assertNotIn('HealParty', labels, trace)
        self.assertEqual(labels, ['HandlePlayerBlackOut', 'HandleBlackOut',
                                 'ResetStatusAndHalveMoneyOnBlackout',
                                 'PrepareForSpecialWarp', 'SpecialEnterMap'], trace)
        self.assertEqual(trace[0][-1], 1, trace)  # a genuine loss, not a debug win
        # "You were defeated by <label>" ran once, on the trainer path (not the
        # wild fallback), and printed the label recorded for the mon that won.
        self.assertEqual(len(loss_codes), 1, loss_codes)
        code, in_battle, pos, recorded = loss_codes[0]
        self.assertEqual(in_battle, 2, loss_codes)
        self.assertLess(pos, h.read8('wEnemyPartyCount') or 6, loss_codes)
        self.assertEqual(code, recorded, loss_codes)
        self.assertEqual(trace[-1][1:4], (maps['SILPH_CO_DORM'], maps['SILPH_CO_DORM'], 0), trace)
        self.assertEqual(h.read8('hCurMap'), maps['SILPH_CO_DORM'], h.diagnostic_state())
        self.assertEqual((h.read8('wXCoord'), h.read8('wYCoord')), (1, 7))
        self.assertEqual(h.read8('wPartyCount'), 0)
        self.assertEqual(h.read8('wPartySpecies'), 0xff)
        self.assertEqual(h.read8('wBattleCount'), 0)
        self.assertEqual(h.read8('hIsInBattle'), 0)
        self.assertEqual((h.read8('wPlayerCoins'), h.read8('wPlayerCoins', 1)), (0x12, 0x34))
        self.assertIn(3, popup_tally, popup_tally)
        h.tick(120)
        # "EARNED" in charmap tile ids, on an on-screen window.
        self.assertEqual(popup_screen, [(0, bytes([0x84, 0x80, 0x91, 0x8d, 0x84, 0x83]))],
                         popup_screen)
        for bit in lab_toggles:
            self.assertFalse(h.pyboy.memory[toggle_base + bit // 8] & (1 << (bit % 8)),
                             f"Oak's Lab toggle {bit:#x} still hidden after the run reset")
        self.assertEqual(h.read8('wCreditsEarnedThisRun'), 0)  # popup drew and consumed it
        self.assertEqual(h.read8('hCurMap'), maps['SILPH_CO_DORM'])
        h.move_tile('right')
        self.assertEqual((h.read8('wXCoord'), h.read8('wYCoord')), (2, 7))
        if leader:
            trainers = parse_trainer_constants(REPO_ROOT / 'constants/trainer_constants.asm')
            self.assertEqual(fainted, [trainers['BROCK']])
        return boxes


class TrainerBlackoutTest(BlackoutFixture, HarnessTestCase):
    def test_normal_trainer_loss_checkpoint_cold_continues(self):
        self.run_loss(normal_save=True)
        self.check_checkpoint_cold_continue()

    def test_normal_brock_loss_checkpoint_cold_continues(self):
        self.run_loss(leader=True, normal_save=True)
        self.check_checkpoint_cold_continue()

    def test_normal_loss_repairs_uninitialized_destination_and_saves(self):
        self.run_loss(unvisited_hub=True, normal_save=True)
        self.check_checkpoint_cold_continue()

    def test_blackout_before_first_hub_visit(self):
        self.run_loss(unvisited_hub=True)

    def test_regular_trainer_blackout(self):
        self.run_loss()

    def test_brock_blackout(self):
        self.run_loss(leader=True)

    def test_blackout_prints_creator_and_name_parts(self):
        # The hardest layout: a creator that wraps to two lines, then a
        # two-line name. Each part is its own PlaceString; the name opens with
        # <CONT>, so a lost cursor or a skipped scroll shows up in the box.
        parts = loss_label_parts()
        origin = next(o for o, (c, n) in sorted(parts.items())
                      if '<CONT>' in c and n.count('<CONT>') == 2)
        creator, name = parts[origin]
        boxes = self.run_loss(force_origin=origin)
        self.assertEqual(len(boxes), 3, boxes)  # placePart x2, then placed
        before, after_creator, after_name = boxes
        self.assertIn('You were defeated by', before)
        # Two lines show at a time: after the creator, both of its lines.
        self.assertIn(letters(creator), after_creator, (creator, boxes))
        # After the name, only its two lines remain (the creator scrolled off).
        self.assertTrue(after_name.endswith(letters(name)), (name, boxes))
        self.assertNotIn(letters(creator).split()[0], after_name, boxes)

    def test_blackout_prints_smogon_credit(self):
        # Phase 3 credits: "by Smogon's / <role or format> set." (creator on line 1).
        parts = loss_label_parts()
        origin = next(o for o, (c, n) in sorted(parts.items())
                      if letters(c) == 'Smogon' and n.count('<CONT>') == 1)
        creator, name = parts[origin]
        boxes = self.run_loss(force_origin=origin)
        self.assertEqual(len(boxes), 3, boxes)
        self.assertTrue(boxes[2].endswith(letters(name)), (name, boxes))
        self.assertIn('Smogon', boxes[2], boxes)  # a one-line name leaves the creator on screen

    def test_blackout_prints_stadium_rental_label(self):
        # A creator-less Stadium label added by Phase 3: the creator part places nothing
        # and the name carries the whole label.
        parts = loss_label_parts()
        origin = max(o for o, (c, n) in parts.items()
                     if c == '' and 'Rental' in n and n.count('<CONT>') == 1)
        creator, name = parts[origin]
        boxes = self.run_loss(force_origin=origin)
        self.assertEqual(len(boxes), 3, boxes)
        self.assertTrue(boxes[2].endswith(letters(name)), (name, boxes))


if __name__ == '__main__':
    unittest.main()
