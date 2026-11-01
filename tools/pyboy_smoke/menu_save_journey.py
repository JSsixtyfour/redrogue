"""Real START > SAVE inputs and matching-ROM SRAM-only Continue evidence."""
import hashlib
import io
import json
from pathlib import Path

import save_reload
from source_constants import parse_rgbds_constants


def publication_clock_evidence(entry,ticks,written):
    """Explain publication by an exact tick chain, without timer-byte allowances."""
    expected=list(entry)
    problems=[]
    for tick in ticks:
        if tick['clock']!=expected or not tick['timer_enabled'] or expected[0]!=1:
            problems.append('publication tick predecessor or enable differs')
            break
        expected=save_reload.advance_run_clock(expected,1)
    if written!=expected:
        problems.append('copied clock differs from the complete publication tick chain')
    return {'status':'invalid' if problems else 'accounted','entry_clock':entry,
            'written_clock':written,'expected_clock':expected,'ticks':ticks,'problems':problems}


def save_with_inputs(test, h, agent, output):
    output = Path(output)
    output.mkdir(parents=True, exist_ok=True)
    test.assertTrue(save_reload.settle(h), 'no idle overworld before menu save')
    before = io.BytesIO()
    h.save_state(before)
    (output / 'before.state').write_bytes(before.getvalue())
    entered = {'menu': 0, 'writer': 0}
    saved = {}
    timer = []
    publication_ticks=[]
    consumed={}
    def menu(_):
        entered['menu'] += 1
    def writer(_):
        entered['writer'] += 1
        saved.update(save_reload.region_image(h))
        timer.append(save_reload.timer_observation(h, 'SaveGameData.entry'))
    copy_label = 'SaveGameData.copyMain' if 'SaveGameData.copyMain' in h.symbols._symbols else 'CopyMainSaveData'
    def copying(_):
        timer.append(save_reload.timer_observation(h, copy_label))
    def ticking(_):
        if entered['writer'] and len(consumed)<5:
            observation=save_reload.timer_observation(h,'RunTimerTick.entry')
            if observation['timer_enabled'] and observation['clock'][0]==1:
                publication_ticks.append(observation)
    clock_address=h.address('wRunTimerState')
    def reading(_):
        address=h.pyboy.register_file.HL
        if entered['writer'] and clock_address<=address<clock_address+5:
            consumed[address-clock_address]=h.pyboy.memory[address]
    hooks=[('SaveMenu',menu),('SaveGameData',writer),(copy_label,copying),('RunTimerTick',ticking)]
    # These are the five executable `ld a,[hli]` sites in the proven copier,
    # not data bytes. Validate the opcode against the matching built ROM.
    bank,batch=h.symbols.get('CopySaveDataAndSum.batch4')
    sites=[h.symbols.get('CopySaveDataAndSum.tail')]+[(bank,batch+i*5) for i in range(4)]
    for index,key in enumerate(sites):
        test.assertEqual(h.pyboy.memory[key[0],key[1]],0x2a,'save copier instruction changed')
        label=f'FixtureSaveClockRead{index}'
        h.symbols._symbols[label]=key
        hooks.append((label,reading))
    for label, callback in hooks:
        h.register_hook(label, callback)
    start = h.pyboy.frame_count
    first_input = len(agent.report.inputs)
    events=parse_rgbds_constants(h.repo_root/'constants/event_constants.asm')
    save_row=4 if h.event_is_set(events['EVENT_GOT_POKEDEX']) else 3
    try:
        agent.press('start', 4, 8)
        for _ in range(1500):
            if entered['writer'] and agent.mode() == 'overworld' and not h.read8('wWalkCounter'):
                break
            if h.pyboy.frame_count - agent.last_wait_frame > 2:
                h.tick(2)
                continue
            caller = agent.last_menu_caller
            cursor = h.read8('hCurrentMenuItem')
            if caller.startswith('RedisplayStartMenu'):
                if entered['menu']:
                    agent.press('b')
                else:
                    agent.press('a' if cursor == save_row else 'down' if cursor < save_row else 'up')
            elif caller.startswith('DisplayTwoOptionMenu'):
                agent.press('a' if cursor == 0 else 'up')
            else:
                agent.press('a')
        else:
            test.fail('START > SAVE did not return player control')
        test.assertEqual(entered, {'menu': 1, 'writer': 1})
        test.assertEqual(h.hook_errors, [])
        sram = save_reload.sram_image(h)
        test.assertEqual(set(consumed),set(range(5)),'run clock bytes were not observed at the copier')
        written=[consumed[i] for i in range(5)]
        clock_offset=clock_address-h.address('wMainDataStart')
        entry_clock=list(saved['main data'][clock_offset:clock_offset+5])
        publication=publication_clock_evidence(entry_clock,publication_ticks,written)
        test.assertEqual(publication['status'],'accounted',publication)
        test.assertEqual(save_reload.published_run_clock(h,sram),written)
        main=bytearray(saved['main data'])
        main[clock_offset:clock_offset+5]=bytes(written)
        saved['main data']=bytes(main)
        (output / 'saved.sav').write_bytes(sram)
        record = {'provenance': 'real START/menu-direction/confirmation inputs; no writer injection',
            'rom_sha256': h.rom_sha256, 'sym_sha256': h.sym_sha256,
            'frames': h.pyboy.frame_count - start, 'entry_counts': entered,
            'save_row':save_row,
            'publication_clock':publication,
            'comparison_policy':'exact copied clock plus complete observed publication/load tick chains',
            'inputs': agent.report.inputs[first_input:], 'timer': timer,
            'saved_regions_hex': {name: values.hex() for name, values in saved.items()},
            'sram_sha256': hashlib.sha256(sram).hexdigest()}
        (output / 'menu_save.json').write_text(json.dumps(record, indent=2) + '\n')
        return saved, sram
    finally:
        for label, callback in reversed(hooks):
            h.unregister_hook(label, callback)


def cold_continue(test, h, saved, sram, output, *, expected_depth):
    output = Path(output)
    output.mkdir(parents=True, exist_ok=True)
    boot = save_reload.Reboot(sram, cgb_mode=h.hardware_mode == 'CGB')
    try:
        boot.load()
        test.assertEqual(boot.h.rom_sha256, h.rom_sha256)
        test.assertEqual(boot.h.sym_sha256, h.sym_sha256)
        accounting = save_reload.account_saved_timer(h, saved, boot.loaded, sram, boot.active_timer_ticks) if boot.loaded else None
        diffs = save_reload.differences(h, saved, boot.loaded, accounted_timer=accounting) if boot.loaded else None
        record = {'status': boot.status, 'overworld': boot.overworld,
                  'expected_depth': expected_depth, 'depth': boot.h.read8('wEndlessDepth'),
                  'differences': diffs, 'timer': accounting, 'hook_errors': boot.h.hook_errors,
                  'rom_sha256': boot.h.rom_sha256, 'sym_sha256': boot.h.sym_sha256}
        (output / 'continue.json').write_text(json.dumps(record, indent=2) + '\n')
        test.assertEqual(boot.status, 2)
        test.assertTrue(boot.overworld)
        test.assertEqual(accounting['status'], 'accounted', accounting)
        test.assertEqual(diffs, [], diffs)
        test.assertEqual(record['depth'], expected_depth)
        test.assertEqual(boot.h.hook_errors, [])
        return boot
    except BaseException:
        boot.close()
        raise
