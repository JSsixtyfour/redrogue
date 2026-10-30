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
            'flags': h.read_sram_bytes('sKeyItemsBitfield', 4),
            'tiers': h.read_sram_bytes('sKeyItemTiers', 4)}


def run_chain(test, *, cgb):
    output = Path(__file__).parent / 'artifacts' / f"credit_service_chain_{'cgb' if cgb else 'dmg'}"
    output.mkdir(parents=True, exist_ok=True)
    h = credit_store.CreditStoreLiveTest.live(test, 'exact', cgb=cgb, output=output/'purchase')
    purchased = state(h)
    test.assertEqual(purchased['coins'], [0, 0])
    test.assertTrue(save_reload.settle(h), 'purchase did not restore save-ready control')
    # Reuse the existing actual save writer and fresh-emulator cold Continue.
    # This is an explicit writer-invoked save, not START-menu save acceptance.
    save_reload.save_now(h)
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
            'save':'existing SaveGameData writer invoked at settled overworld; SRAM-only fresh boot',
            'post_load_fixture_writes':[],'purchase':purchased,'restored':restored,'upgrade_refused':refused,
            'phases':['purchase_with_real_input','writer_save','cold_continue','walk_to_upgrade_vendor',
                      'refused_upgrade_with_real_input','legal_movement_restored']}
    (output/'chain.json').write_text(json.dumps(record,indent=2))


class CreditServiceChainTest(unittest.TestCase):
    def test_purchase_cold_continue_then_upgrade_refusal(self):
        run_chain(self,cgb=False)
