"""Prepared party -> real PC grid deposit/withdraw -> SRAM-only Continue."""
import json
from pathlib import Path
import unittest
from unittest.mock import patch

import autoplay
from harness import RedRogueHarness
import save_reload
from source_constants import parse_map_constants, parse_rgbds_constants
from test_trade_identity_chain import party

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).parent / 'artifacts' / 'pc_identity_chain'


class PCIdentityChainTest(unittest.TestCase):
    cgb = False

    def setUp(self):
        self.output = ARTIFACTS / ('cgb' if self.cgb else 'dmg') / self._testMethodName
        self.output.mkdir(parents=True, exist_ok=True)
        self.h = RedRogueHarness(ROOT, self.output, cgb_mode=self.cgb)
        self.addCleanup(self.h.close)
        self.phase = None
        self.h.register_hook('BillsPC_.inputLoop', lambda _: setattr(self, 'phase', 'grid'))
        self.h.register_hook('HandleMenuInput', lambda _: setattr(self, 'phase', 'menu'))
        self.h.register_hook('JoypadOverworld', lambda _: setattr(self, 'phase', 'world'))
        maps = parse_map_constants(ROOT/'constants/map_constants.asm')
        target = maps['VIRIDIAN_POKECENTER']
        self.h.boot_debug1(maps['SILPH_CO_DORM'])
        # Prepared destination only: enter through a normal engine warp, as
        # the shared harness does for configured stage fixtures.
        self.h.write8('wWarpEntries', 0, offset=6)
        self.h.write8('wWarpEntries', target, offset=7)
        for _ in range(3): self.step('right')
        for _ in range(6):
            if self.h.read8('hCurMap') == target: break
            self.press('down', 40)
        self.h.wait_until(lambda: self.h.read8('hCurMap') == target, 'configured PC map', 600)
        self.h.tick(120)

    def press(self, button, settle=20):
        self.h.tap(button, 4)
        self.h.tick(settle)

    def step(self, button):
        self.press(button, 30)

    def open_pc(self):
        # Use the existing terrain/sprite pathfinder, not fixed walk timing.
        self.assertEqual((self.h.read8('wXCoord'), self.h.read8('wYCoord')), (3, 7))
        agent = autoplay.AutoplayAgent(self.h, seed=7)
        for _ in range(60):
            if agent.position() == (13, 4): break
            path = autoplay.world.find_path(agent.read_grid(), agent.position(),
                {(13, 4)}, agent.obstacles())
            if not path:
                self.h.pyboy.tick(1, render=True)
                self.h.pyboy.screen.image.save(self.output/'navigation.png')
                (self.output/'navigation.json').write_text(json.dumps({'position':agent.position(),
                    'tiles':agent.read_grid().tiles,'sprites':agent.sprites()}))
            self.assertTrue(path, 'no legal route to PC')
            agent.walk(path[0])
        self.assertEqual((self.h.read8('wXCoord'), self.h.read8('wYCoord')), (13, 4))
        self.step('up')
        self.phase = None
        for _ in range(30):
            if self.phase == 'grid': break
            self.press('a')
        self.assertEqual(self.phase, 'grid', 'PC grid did not open')

    def grid_action(self):
        self.phase = None
        self.press('a')
        self.assertEqual(self.phase, 'menu', 'selected mon submenu did not open')
        self.press('down')  # SWAP -> DEPOSIT/WITHDRAW
        self.press('a')
        for _ in range(20):
            if self.phase == 'grid': break
            self.press('a')
        self.assertEqual(self.phase, 'grid', 'transaction did not return to grid')

    def test_deposit_withdraw_identity_survives_cold_continue(self):
        self.run_identity_chain(save_while_boxed=False)

    def test_boxed_identity_survives_continue_before_withdrawal(self):
        self.run_identity_chain(save_while_boxed=True)

    def reopen_boxed_save(self, expected_party, stored, owner, nickname):
        for _ in range(20):
            if self.phase == 'world': break
            self.press('b')
        self.assertEqual(self.phase, 'world')
        self.assertTrue(save_reload.settle(self.h))
        save_reload.save_now(self.h)
        sram = save_reload.sram_image(self.h)
        (self.output/'boxed.sav').write_bytes(sram)
        with patch.object(autoplay, 'ROM', autoplay.DEBUG_ROM):
            boot = save_reload.Reboot(sram, cgb_mode=self.cgb)
        self.addCleanup(boot.close)
        boot.load()
        self.assertEqual(boot.status, 2)
        self.assertTrue(boot.overworld)
        self.assertEqual(party(boot.h), expected_party)
        self.assertEqual(boot.h.read8('wBoxCount'), 1)
        self.assertEqual(boot.h.read_bytes('wBoxSpecies', 2), [stored[0], 255])
        self.assertEqual(boot.h.read_bytes('wBoxMons', 33), stored)
        self.assertEqual(boot.h.read_bytes('wBoxMonOT', 11), owner)
        self.assertEqual(boot.h.read_bytes('wBoxMonNicks', 11), nickname)
        self.assertFalse(self.h.hook_errors)
        self.h = boot.h
        self.h.register_hook('BillsPC_.inputLoop', lambda _: setattr(self, 'phase', 'grid'))
        self.h.register_hook('HandleMenuInput', lambda _: setattr(self, 'phase', 'menu'))
        self.h.register_hook('JoypadOverworld', lambda _: setattr(self, 'phase', 'world'))
        self.press('up', 30)
        self.phase = None
        for _ in range(30):
            if self.phase == 'grid': break
            self.press('a')
        self.assertEqual(self.phase, 'grid', 'occupied-box PC did not reopen')
        self.assertEqual(self.h.read8('hCurrentMenuItem'), 0)

    def run_identity_chain(self, *, save_while_boxed):
        h = self.h
        # Debug1 supplies EXEGGUTOR in slot0. Prepare its supported Alolan
        # form and a nonzero PP-Up encoding before opening the PC.
        species = parse_rgbds_constants(ROOT/'constants/pokemon_constants.asm')
        types = parse_rgbds_constants(ROOT/'constants/type_constants.asm')
        self.assertEqual(h.read8('wPartyMon1Species'), species['EXEGGUTOR'])
        h.write8('wPartyMon1CatchRate', (h.read8('wPartyMon1CatchRate') & 0x9F) | 0x20)
        h.write8('wPartyMon1Type2', types['DRAGON'])
        h.write8('wPartyMon1PP', h.read8('wPartyMon1PP') | 0x80)
        before = party(h)
        self.assertGreaterEqual(before['count'], 2)
        # Empty current box is explicit fixture setup, before any PC input.
        h.write8('wBoxCount', 0)
        h.write8('wBoxSpecies', 255)
        self.open_pc()
        self.assertEqual(h.read8('hCurrentMenuItem'), 0)
        self.grid_action()
        deposited = party(h)
        self.assertEqual(deposited['count'], before['count'] - 1)
        self.assertEqual(deposited['species'], before['species'][1:])
        for field in ('mons', 'ot', 'names'):
            self.assertEqual(deposited[field], before[field][1:], field)
        self.assertEqual(h.read8('wBoxCount'), 1)
        self.assertEqual(h.read8('wBoxSpecies'), before['species'][0])
        stored = before['mons'][0][:33]
        stored[3] = before['mons'][0][33]  # box level is populated on deposit
        self.assertEqual(h.read_bytes('wBoxMons', 33), stored)
        self.assertEqual(h.read_bytes('wBoxMonOT', 11), before['ot'][0])
        self.assertEqual(h.read_bytes('wBoxMonNicks', 11), before['names'][0])
        if save_while_boxed:
            self.reopen_boxed_save(deposited, stored, before['ot'][0], before['names'][0])
            h = self.h
        self.press('right')  # party row0 -> box slot0
        self.assertEqual(h.read8('hCurrentMenuItem'), 6)
        self.grid_action()
        withdrawn = party(h)
        self.assertEqual(withdrawn['count'], before['count'])
        self.assertEqual(withdrawn['species'],
            before['species'][1:-1] + before['species'][:1] + [255])
        self.assertEqual(h.read8('wBoxCount'), 0)
        for field in ('ot', 'names'):
            self.assertEqual(withdrawn[field], before[field][1:] + before[field][:1], field)
        self.assertEqual(withdrawn['mons'][:-1], before['mons'][1:])
        # Stored 33-byte identity includes species, form bits, moves/PP, DVs,
        # OT ID and stat experience. Party-only stats are rebuilt on withdrawal.
        self.assertEqual(withdrawn['mons'][-1][:33], stored)
        for _ in range(20):
            if self.phase == 'world': break
            self.press('b')
        self.assertEqual(self.phase, 'world')
        self.assertTrue(save_reload.settle(h))
        save_reload.save_now(h)
        sram = save_reload.sram_image(h)
        (self.output/'saved.sav').write_bytes(sram)
        with patch.object(autoplay, 'ROM', autoplay.DEBUG_ROM):
            boot = save_reload.Reboot(sram, cgb_mode=self.cgb)
        self.addCleanup(boot.close)
        boot.load()
        self.assertEqual(boot.status, 2)
        self.assertTrue(boot.overworld)
        self.assertEqual(party(boot.h), withdrawn)
        self.assertEqual(boot.h.read8('wBoxCount'), 0)
        # Reopen through the actual PC interaction at the saved position.
        boot.h.tap('up', 4)
        boot.h.tick(30)
        entered = boot.h.hook_flag('BillsPC_.inputLoop')
        for _ in range(30):
            if entered['count']: break
            boot.h.tap('a', 4)
            boot.h.tick(20)
        self.assertGreater(entered['count'], 0, 'PC did not reopen after Continue')
        self.assertEqual(party(boot.h), withdrawn)
        with (self.output/'reopened.state').open('wb') as stream:
            boot.h.save_state(stream)
        self.assertFalse(h.hook_errors)
        self.assertFalse(boot.h.hook_errors)
        (self.output/'result.json').write_text(json.dumps({'before':before,
            'deposited':deposited,'withdrawn':withdrawn,'restored':party(boot.h),
            'boxed':stored,'hardware_mode':h.hardware_mode,
            'cold_continue_while_boxed':save_while_boxed,
            'fixture':'configured destination warp, initial form/type/PP-Up bytes and empty current box',
            'post_open_fixture_writes':[],
            'rom_sha256':h.rom_sha256,'sym_sha256':h.sym_sha256}, indent=2))


class CGBPCIdentityChainTest(PCIdentityChainTest):
    cgb = True


if __name__ == '__main__':
    unittest.main()


