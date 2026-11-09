"""Configured purchase -> cold Continue -> independent upgrade refusal chain."""
import json
from pathlib import Path
import unittest
from unittest.mock import patch

import autoplay
import save_reload
from purchase_scenario import snapshot
import test_credit_store as credit_store


def state(h):
    return {**snapshot(h), 'coins': h.read_bytes('wPlayerCoins', 2),
            'progress': h.read_bytes('wGameProgressFlags', h.address('wGameProgressFlagsEnd') - h.address('wGameProgressFlags')),
            'flags': h.read_sram_bytes('sKeyItemsBitfield', 4),
            'tiers': h.read_sram_bytes('sKeyItemTiers', 4)}


def run_chain(test, *, cgb, output=None):
    output = Path(output) if output is not None else Path(__file__).parent / 'artifacts' / f"credit_service_chain_{'cgb' if cgb else 'dmg'}"
    output.mkdir(parents=True, exist_ok=True)
    h = credit_store.CreditStoreLiveTest.live(test, 'exact', cgb=cgb, output=output/'purchase')
    purchased = state(h)
    test.assertEqual(purchased['coins'], [0, 0])
    test.assertTrue(save_reload.settle(h), 'purchase did not restore save-ready control')
    # No explicit save: the purchase must commit its own funds and progression.
    sram = save_reload.sram_image(h)
    (output/'saved.sav').write_bytes(sram)
    with patch.object(autoplay, 'ROM', autoplay.DEBUG_ROM):
        boot = save_reload.Reboot(sram, cgb_mode=cgb)
    test.addCleanup(boot.close)
    boot.load()
    test.assertEqual(boot.status, 2)
    test.assertTrue(boot.overworld, 'cold Continue did not restore player control')
    restored = state(boot.h)
    test.assertEqual(restored, purchased, 'purchase identity/accounting changed during cold load')
    # No ownership/tier/funds injection after reload. Walk to the other vendor
    # using the same live driver, with the naturally exhausted balance intact.
    credit_store.CreditStoreLiveTest.live(test, 'upgrade_insufficient', cgb=cgb, output=output/'upgrade',
                             harness=boot.h, initialize=False, funds_override=0)
    refused = state(boot.h)
    test.assertEqual(refused, purchased, 'unaffordable upgrade changed persistent transaction state')
    record={'hardware_mode':h.hardware_mode,'rom_sha256':h.rom_sha256,'sym_sha256':h.sym_sha256,
            'fixture':'existing arrival retarget, owned/tier reset and11credits at first purchase only',
            'save':'purchase autosave only; SRAM-only fresh boot',
            'post_load_fixture_writes':[],'purchase':purchased,'restored':restored,'upgrade_refused':refused,
            'phases':['purchase_with_real_input','cold_continue','walk_to_upgrade_vendor',
                      'refused_upgrade_with_real_input','legal_movement_restored']}
    (output/'chain.json').write_text(json.dumps(record,indent=2))


class CreditServiceChainTest(unittest.TestCase):
    def test_room_purchase_reset_inside_vendor_saves_debit_and_progress(self, cgb=False):
        h = credit_store.CreditStoreLiveTest.live(self, 'exact', cgb=cgb)
        self.assertTrue(save_reload.settle(h))
        agent = h.credit_test_agent
        target = (6, 3)
        for _ in range(30):
            if agent.position() == target:
                break
            path = credit_store.world.find_path(agent.read_grid(), agent.position(), {target}, agent.obstacles())
            self.assertTrue(path)
            agent.walk(path[0])
        self.assertEqual(agent.position(), target)
        agent.press('up', 2, 20)
        h.write_sram_bytes('sRoomOwned', [0, 0, 0, 0])
        h.write8('wPlayerCoins', 0)
        h.write8('wPlayerCoins', 0x20, 1)
        h.write8('wBattleCount', 23)  # newer progression than the prior item save
        transactions = []
        committed = h.hook_flag('CreditPurchaseSave', lambda: transactions.append({
            'piece': h.read8('wBuffer', 9),
            'owned': h.read_sram_bytes('sRoomOwned', 4),
            'ext': h.read_sram_bytes('sRoomOwnedExt', 4)}))
        for _ in range(80):
            agent.press('a', 2, 12)
            if committed['count']:
                break
        self.assertEqual(committed['count'], 1)
        h.tick(30)
        self.assertEqual(h.read_bytes('wPlayerCoins', 2), [0, 0x10])
        self.assertEqual(h.read_sram_bytes('sRoomOwned', 4), [1, 0, 0, 0], transactions)
        with patch.object(autoplay, 'ROM', autoplay.DEBUG_ROM):
            boot = save_reload.Reboot(save_reload.sram_image(h), cgb_mode=cgb)
        self.addCleanup(boot.close)
        boot.load()
        self.assertEqual(boot.status, 2)
        self.assertTrue(boot.overworld)
        self.assertEqual(boot.h.read_bytes('wPlayerCoins', 2), [0, 0x10])
        self.assertEqual(boot.h.read_sram_bytes('sRoomOwned', 4), [1, 0, 0, 0])
        self.assertEqual(boot.h.read8('wBattleCount'), 23)

    def test_purchase_cold_continue_then_upgrade_refusal(self):
        run_chain(self,cgb=False)

    def test_upgrades_and_pc_purchase_cold_continue_without_manual_save(self):
        for case in ('full_active', 'upgrade_exact', 'upgrade_final', 'upgrade_pc'):
            with self.subTest(case=case):
                h = credit_store.CreditStoreLiveTest.live(self, case, cgb=False)
                purchased = state(h)
                with patch.object(autoplay, 'ROM', autoplay.DEBUG_ROM):
                    boot = save_reload.Reboot(save_reload.sram_image(h))
                self.addCleanup(boot.close)
                boot.load()
                self.assertEqual(boot.status, 2)
                self.assertTrue(boot.overworld)
                self.assertEqual(state(boot.h), purchased)
