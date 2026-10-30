"""Full-move cancellation -> retry/replacement -> cold Continue, using real menu goals."""
import json
from pathlib import Path
import unittest
from unittest.mock import patch

import autoplay
import save_reload
from harness import RedRogueHarness
from purchase_scenario import evidence
import test_bridge_teach_known_move as teacher
from test_teaching_identity_chain import close_text
from test_trade_identity_chain import party


def run_chain(test, *, cgb, cancellation, output=None):
    root=Path(__file__).resolve().parents[2]
    output=Path(output) if output is not None else Path(__file__).parent/'artifacts'/f"teaching_full_{cancellation}_{'cgb' if cgb else 'dmg'}"
    output.mkdir(parents=True,exist_ok=True)
    h=RedRogueHarness(root,output,cgb_mode=cgb);test.addCleanup(h.close);test.harness=h
    teacher.BridgeTeachKnownMoveTest.prepare_teacher(test)
    initial=[teacher.MOVES[name] for name in ('TACKLE','GROWL','TAIL_WHIP','QUICK_ATTACK')]
    for index,move in enumerate(initial):
        h.write8('wPartyMon2Moves',move,index)
        h.write8('wPartyMon2PP',[0xc1,0x82,0x43,4][index],index)
    before=party(h);agent=autoplay.AutoplayAgent(h,seed=7);attempts=[]
    with (output/'initial.state').open('wb') as stream:h.save_state(stream)
    def attempt(kind):
        observed={'kind':kind,'offer':0,'forget':0,'abandon':0}
        def goal(label,caller,button='a',target=0,fresh=False):
            entered=h.pyboy.frame_count
            agent.set_menu_goal(label,lambda: agent.last_menu_caller.startswith(caller)
                and (agent.menu_frame>entered if fresh else agent.menu_frame>=entered),target,
                lambda: agent.line_button(h.read8('hCurrentMenuItem'),target),button=button,chaos=())
        def offer(_):
            observed['offer']+=1
            goal('full_offer_'+kind,'DisplayTwoOptionMenu',button='b' if kind=='decline' else 'a',fresh=True)
        def abandon(_):
            observed['abandon']+=1
            goal('full_abandon_'+kind,'DisplayTwoOptionMenu',fresh=True)
        def menu(_):
            if agent.last_menu_caller.startswith('TryingToLearn'):
                observed['forget']+=1
                goal('full_forget_'+kind,'TryingToLearn',button='b' if kind=='cancel_forget' else 'a',target=2)
        hooks=(('TryingToLearn',offer),('AbandonLearning',abandon),('HandleMenuInput',menu))
        for label,callback in hooks:h.register_hook(label,callback)
        try:
            flags=teacher.BridgeTeachKnownMoveTest.teach(test,teacher.MOVES['SURF'],
                                                       input_policy=lambda _:agent.ui_step())
        finally:
            for label,callback in hooks:h.unregister_hook(label,callback)
        test.assertTrue(close_text(h));test.assertEqual(observed['offer'],1)
        test.assertEqual(observed['forget'],int(kind!='decline'))
        test.assertEqual(observed['abandon'],int(kind!='replace'))
        attempts.append(observed)
        return flags
    flags=attempt(cancellation);test.assertFalse(flags&teacher.CARRY)
    cancelled=party(h);test.assertEqual(cancelled,before)
    evidence(h,output,'cancelled')
    # Retry on exactly the same party; no move/PP reset between attempts.
    flags=attempt('replace');test.assertTrue(flags&teacher.CARRY)
    replaced=party(h);expected=json.loads(json.dumps(before))
    move_offset=h.address('wPartyMon2Moves')-h.address('wPartyMon2Species')
    pp_offset=h.address('wPartyMon2PP')-h.address('wPartyMon2Species')
    expected['mons'][teacher.SLOT][move_offset+2]=teacher.MOVES['SURF']
    expected['mons'][teacher.SLOT][pp_offset+2]=15  # authored SURF base PP; PP Ups reset
    test.assertEqual(replaced,expected)
    test.assertGreaterEqual(agent.menu_stats['full_forget_replace']['moves'],2)
    evidence(h,output,'replaced')
    save_reload.save_now(h);sram=save_reload.sram_image(h);(output/'saved.sav').write_bytes(sram)
    with patch.object(autoplay,'ROM',autoplay.DEBUG_ROM):boot=save_reload.Reboot(sram,cgb_mode=cgb)
    test.addCleanup(boot.close);boot.load()
    test.assertEqual(boot.status,2);test.assertTrue(boot.overworld)
    walker=autoplay.AutoplayAgent(boot.h,seed=7);start=walker.position()
    warps={(x,y) for y,x,_,_ in boot.h.warp_entries()}
    legal=[(direction,target) for direction,target in walker.read_grid().moves(*start)
           if target not in walker.obstacles() and target not in warps]
    test.assertTrue(legal);test.assertTrue(walker.walk(legal[0][0]));test.assertNotEqual(walker.position(),start)
    test.assertEqual(party(boot.h),replaced)
    test.assertFalse(agent.checks.anomalies,agent.checks.anomalies)
    test.assertFalse(h.hook_errors);test.assertFalse(boot.h.hook_errors)
    evidence(boot.h,output,'continued')
    with (output/'continued.state').open('wb') as stream:boot.h.save_state(stream)
    (output/'chain.json').write_text(json.dumps({'hardware_mode':h.hardware_mode,'rom_sha256':h.rom_sha256,
        'sym_sha256':h.sym_sha256,'fixture':'existing text-handler dispatch; four explicit moves/PP at start only',
        'post_initial_party_fixture_writes':[],'attempts':attempts,'inputs':agent.report.inputs,
        'movement':{'from':start,'to':walker.position()},
        'menu_stats':agent.menu_stats,'before':before,'cancelled':cancelled,'replaced':replaced,
        'restored':party(boot.h),'save':'writer invoked at settled overworld; SRAM-only cold Continue'},indent=2))


class TeachingFullMenuTest(unittest.TestCase):
    def test_decline_then_retry_replacement(self):
        run_chain(self,cgb=False,cancellation='decline')

    def test_cancel_forget_then_retry_replacement(self):
        run_chain(self,cgb=False,cancellation='cancel_forget')
