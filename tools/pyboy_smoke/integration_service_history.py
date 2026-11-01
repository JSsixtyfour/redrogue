"""Natural NEW GAME, three ended runs, deliberate clerk/nurse/clerk history.

Only the input policy changes. No inventory, money, party, run outcome, map,
NPC, or menu cursor is injected. Cold-save probes remain separate emulators.
"""
import json
from unittest.mock import patch
import unittest

import autoplay
from lifecycle_exposure import evaluate
from purchase_scenario import snapshot
from harness import RedRogueHarness
from menu_save_journey import cold_continue, save_with_inputs


class DirectedServiceAgent(autoplay.AutoplayAgent):
    def __init__(self,*args,**kwargs):
        super().__init__(*args,**kwargs)
        self.services=[]
        self.pending_service=None
        self.service_failures=[]
        self.h.register_hook('SubtractAmountPaidFromMoney',self.paid)
        self.h.register_hook('DisplayPokemartDialogue_.done',self.shop_closed)
        self.h.register_hook('AnimateHealingMachine',self.healed)

    def paid(self,_):
        if self.pending_service and self.pending_service['kind']=='clerk':
            self.pending_service['payments']+=1

    def shop_closed(self,_):
        if self.pending_service and self.pending_service['kind']=='clerk':
            self.pending_service['closed']=True

    def healed(self,_):
        if self.pending_service and self.pending_service['kind']=='nurse':
            self.pending_service['closed']=True

    def identity(self):
        return {'flags':self.h.read_sram_bytes('sKeyItemsBitfield',4),
                'tiers':self.h.read_sram_bytes('sKeyItemTiers',4),
                'credits':self.h.read_bytes('wPlayerCoins',2)}

    def goal_groups(self,grid):
        run=len(self.report.runs)+1
        if self.h.read8('hCurMap')==self.lobby_map and run<=3 and not any(row['run_index']==run for row in self.services):
            kind='nurse' if run==2 else 'clerk'
            slot=autoplay.LOBBY_NURSE_SLOT if kind=='nurse' else autoplay.LOBBY_CLERK_SLOT
            sprites=self.sprites()
            if slot in sprites:
                return [self.talk_goal(grid,{slot:sprites[slot]},kind)]
        return super().goal_groups(grid)

    def arrive(self,face,label):
        run=len(self.report.runs)+1
        if label.partition(':')[0] in ('clerk','nurse') and run<=3 and not any(row['run_index']==run for row in self.services):
            self.pending_service={'run_index':run,'kind':label.partition(':')[0],
                'before':snapshot(self.h),'identity_before':self.identity(),
                'counts_before':self.recovery_counts(),'payments':0,'closed':False,
                'chosen':None,'start_frame':self.h.pyboy.frame_count}
        super().arrive(face,label)

    def choose_purchase(self,stock):
        pending=self.pending_service
        if pending and pending['kind']=='clerk':
            if pending['payments']: return None
            quantity=1 if pending['run_index']==1 else 2
            options=[(self.price(item),i,item) for i,item in enumerate(stock)
                     if item in self.heal_amounts and 0<self.price(item)*quantity<=self.money()]
            if not options:
                self.service_failures.append({'run_index':pending['run_index'],'reason':'no affordable healing stock'})
                return None
            price,index,item=min(options)
            pending['chosen']={'item':item,'quantity':quantity,'unit_price':price}
            return index,quantity,item
        return super().choose_purchase(stock)

    def overworld_step(self):
        pending=self.pending_service
        if pending and pending['closed']:
            after=snapshot(self.h)
            issues=[]
            if self.identity()!=pending['identity_before']: issues.append('persistent ownership/tier/credit changed')
            if pending['kind']=='clerk':
                chosen=pending['chosen']
                if chosen is None or pending['payments']!=1:
                    issues.append('expected exactly one completed purchase')
                else:
                    expected=dict(pending['counts_before'])
                    expected[chosen['item']]=expected.get(chosen['item'],0)+chosen['quantity']
                    if self.recovery_counts()!=expected: issues.append('inventory delta differs from purchase')
                    if after['money']!=pending['before']['money']-chosen['unit_price']*chosen['quantity']:
                        issues.append('payment differs from purchase')
                if after['party']!=pending['before']['party']: issues.append('mart changed party')
            else:
                if after['money']!=pending['before']['money'] or after['items']!=pending['before']['items']:
                    issues.append('nurse changed money/items')
                if any(hp!=maximum for hp,maximum in self.party_hp()): issues.append('nurse did not fully heal party')
            pending.update(after=after,identity_after=self.identity(),issues=issues,
                           end_frame=self.h.pyboy.frame_count)
            self.services.append(pending)
            self.event('directed_service',service=pending)
            self.service_failures.extend(issues)
            self.pending_service=None
        super().overworld_step()


class DirectedServiceHistoryIntegrationTest(unittest.TestCase):
    def test_primary_cold_restarts_between_runs_and_inside_runs_two_and_three(self):
        output=autoplay.ARTIFACTS/'primary_service_restarts'
        output.mkdir(parents=True,exist_ok=True)
        resources=[]
        epochs=[]
        restarts=[]
        h=RedRogueHarness(autoplay.ROOT,output)
        resources.append(h)
        try:
            autoplay.boot_new_game(h,1,'NORMAL',False,None)
            agent=DirectedServiceAgent(h,seed=1,player='strong')
            def advance_until(predicate,label):
                start=h.pyboy.frame_count
                while not predicate() and h.pyboy.frame_count-start<200_000:
                    agent.step(); agent.checks.after_step(); agent.note_progress()
                    self.assertEqual(h.hook_errors,[])
                    self.assertIsNone(agent.checks.crash)
                    self.assertEqual(agent.checks.anomalies,[])
                self.assertTrue(predicate(),label)
            def restart(label):
                nonlocal h,agent
                case=output/label
                saved,sram=save_with_inputs(self,h,agent,case/'save')
                old=agent
                epochs.append({'label':label,'checks':old.checks.summary(),
                    'screen_checks':old.checks.screen.summary(),'anomalies':old.checks.anomalies,
                    'hook_errors':list(h.hook_errors),'last_frame':h.pyboy.frame_count,
                    'event_count':len(old.report.events)})
                boot=cold_continue(self,h,saved,sram,case/'continue',expected_depth=0)
                self.assertEqual(old.identity(),{'flags':boot.h.read_sram_bytes('sKeyItemsBitfield',4),
                    'tiers':boot.h.read_sram_bytes('sKeyItemTiers',4),
                    'credits':boot.h.read_bytes('wPlayerCoins',2)})
                resources.pop().close()
                resources.append(boot)
                h=boot.h
                agent=DirectedServiceAgent(h,seed=1,player='strong')
                agent.report=old.report
                agent.services=old.services
                agent.service_failures=old.service_failures
                agent.run_start={**old.run_start,'frame':h.pyboy.frame_count}
                agent.stage_map=old.stage_map
                agent.last_stage=old.last_stage
                agent.last_progress_frame=h.pyboy.frame_count
                agent.event('primary_cold_restart',checkpoint=label,emulator_epoch=len(epochs))
                restarts.append(label)
            agent.run(runs=1,max_frames=400_000)
            self.assertEqual(len(agent.report.runs),1)
            for run in (2,3):
                advance_until(lambda: h.read8('hCurMap')==agent.lobby_map and agent.mode()=='overworld',
                              f'run {run} input-ready lobby')
                restart(f'between_runs_before_{run}')
                advance_until(lambda: agent.stage_map is not None and agent.mode()=='overworld'
                    and h.read8('hCurMap') not in (agent.lobby_map,agent.reward_room),
                    f'run {run} input-ready first stage')
                restart(f'during_run_{run}')
                agent.run(runs=run,max_frames=400_000)
                self.assertEqual(len(agent.report.runs),run)
                self.assertEqual(h.hook_errors,[])
                self.assertIsNone(agent.checks.crash)
                self.assertEqual(agent.checks.anomalies,[])
            data=agent.report.to_json()
            data.update(build_identity={'gbc':h.rom_sha256,'sym':h.sym_sha256},
                provenance=__doc__,primary_restarts=restarts,epochs=epochs,
                frame_policy='frames are local to emulator epochs; restart events delimit input replay',
                final_checks=agent.checks.summary(),final_screen_checks=agent.checks.screen.summary())
            (output/'journey.json').write_text(json.dumps(data,indent=2)+'\n')
            self.assertEqual(len(restarts),4)
            self.assertEqual([(row['run_index'],row['kind']) for row in agent.services],
                             [(1,'clerk'),(2,'nurse'),(3,'clerk')])
            self.assertEqual(agent.service_failures,[])
            for row in agent.report.runs:
                self.assertGreaterEqual(row['stages_cleared'],1,row)
                self.assertGreaterEqual(row['battles_won'],1,row)
        finally:
            for resource in resources: resource.close()

    def test_three_natural_runs_clerk_nurse_clerk_with_exact_transaction_deltas(self):
        with patch.object(autoplay,'AutoplayAgent',DirectedServiceAgent):
            data=autoplay.play(1,new_game=True,runs=3,player='strong',difficulty='NORMAL',
                               save_checks=True,max_frames=1_500_000)
        path=autoplay.ARTIFACTS/'directed_service_history.json'
        path.write_text(json.dumps(data,indent=2)+'\n')
        self.assertEqual(evaluate(data)['gaps'],[],evaluate(data))
        services=[row['service'] for row in data['events'] if row['kind']=='directed_service']
        self.assertEqual([(row['run_index'],row['kind']) for row in services],
                         [(1,'clerk'),(2,'nurse'),(3,'clerk')])
        self.assertTrue(all(not row['issues'] for row in services),services)
        self.assertEqual(data['save_checks']['findings'],[])


if __name__=='__main__':
    unittest.main(verbosity=2)
