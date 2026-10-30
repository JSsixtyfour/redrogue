"""Existing text-handler teaching fixture -> duplicate refusal -> cold Continue."""
import json
from pathlib import Path
import unittest
from unittest.mock import patch

import autoplay
import save_reload
from harness import RedRogueHarness
from purchase_scenario import evidence
import test_bridge_teach_known_move as teacher
from test_trade_identity_chain import party


def close_text(h):
    for _ in range(40):
        if not h.read8('wFontLoaded') & 1:
            break
        h.tap('b', 2); h.tick(8)
    return not h.read8('wFontLoaded') & 1 and save_reload.settle(h)


def run_chain(test, *, cgb):
    root=Path(__file__).resolve().parents[2]
    output=Path(__file__).parent/'artifacts'/f"teaching_identity_chain_{'cgb' if cgb else 'dmg'}"
    output.mkdir(parents=True,exist_ok=True)
    h=RedRogueHarness(root,output,cgb_mode=cgb);test.addCleanup(h.close)
    test.harness=h
    teacher.BridgeTeachKnownMoveTest.prepare_teacher(test)
    target=teacher.SLOT
    test.assertEqual(test.moves_at,h.address('wPartyMon2Moves'))
    # Same empty-slot construction as the accepted teaching control; clear
    # corresponding PP too so the initial fixture is internally coherent.
    for index in range(1,4):
        h.write8('wPartyMon2Moves',0,index);h.write8('wPartyMon2PP',0,index)
    before=party(h)
    first=teacher.BridgeTeachKnownMoveTest.moves(test)[0]
    move=next(teacher.MOVES[name] for name in ('TACKLE','SURF') if teacher.MOVES[name]!=first)
    flags=teacher.BridgeTeachKnownMoveTest.teach(test,move)
    test.assertTrue(flags & teacher.CARRY)
    test.assertTrue(close_text(h),'teaching did not restore settled overworld control')
    taught=party(h)
    test.assertEqual(taught['species'],before['species'])
    test.assertEqual(taught['ot'],before['ot']);test.assertEqual(taught['names'],before['names'])
    moves_offset=h.address('wPartyMon2Moves')-h.address('wPartyMon2Species')
    pp_offset=h.address('wPartyMon2PP')-h.address('wPartyMon2Species')
    allowed={moves_offset+1,pp_offset+1}
    for slot,(old,new) in enumerate(zip(before['mons'],taught['mons'])):
        for offset,(was,now) in enumerate(zip(old,new)):
            if slot!=target or offset not in allowed:test.assertEqual(now,was,(slot,offset))
    test.assertEqual(taught['mons'][target][moves_offset+1],move)
    test.assertGreater(taught['mons'][target][pp_offset+1]&0x3f,0)
    evidence(h,output,'taught')
    flags=teacher.BridgeTeachKnownMoveTest.teach(test,move)
    test.assertFalse(flags & teacher.CARRY)
    test.assertTrue(close_text(h),'duplicate refusal did not restore control')
    refused=party(h);test.assertEqual(refused,taught)
    test.assertEqual(teacher.BridgeTeachKnownMoveTest.moves(test).count(move),1)
    save_reload.save_now(h);sram=save_reload.sram_image(h);(output/'saved.sav').write_bytes(sram)
    with patch.object(autoplay,'ROM',autoplay.DEBUG_ROM):boot=save_reload.Reboot(sram,cgb_mode=cgb)
    test.addCleanup(boot.close);boot.load()
    test.assertEqual(boot.status,2);test.assertTrue(boot.overworld)
    restored=party(boot.h);test.assertEqual(restored,taught)
    agent=autoplay.AutoplayAgent(boot.h,seed=7);start=agent.position()
    warps={(x,y) for y,x,_,_ in boot.h.warp_entries()}
    moves=[(direction,target) for direction,target in agent.read_grid().moves(*start)
           if target not in agent.obstacles() and target not in warps]
    test.assertTrue(moves);test.assertTrue(agent.walk(moves[0][0]));test.assertNotEqual(agent.position(),start)
    test.assertEqual(party(boot.h),taught)
    test.assertFalse(h.hook_errors);test.assertFalse(boot.h.hook_errors)
    evidence(boot.h,output,'continued')
    with (output/'continued.state').open('wb') as stream:boot.h.save_state(stream)
    (output/'chain.json').write_text(json.dumps({'hardware_mode':h.hardware_mode,'rom_sha256':h.rom_sha256,
        'sym_sha256':h.sym_sha256,'target_slot':target,'move':move,'before':before,'taught':taught,
        'refused':refused,'restored':restored,'post_initial_party_fixture_writes':[],
        'fixture':'existing text_asm handler swap for both teach calls; initial empty move/PP slots',
        'save':'existing writer at settled overworld; SRAM-only cold Continue',
        'movement':{'from':start,'to':agent.position()}},indent=2))


class TeachingIdentityChainTest(unittest.TestCase):
    def test_teach_refuse_duplicate_then_cold_continue(self):
        run_chain(self,cgb=False)
