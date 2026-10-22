"""Measure experimental PSSave via real START > SAVE with live interrupts."""
import argparse
import io
import json
from pathlib import Path

from verify import RedRogueHarness, Layout, dump, install, seed, write_payload, gather, chosen

FRAME_MS = 70224 / 4194304 * 1000


def profile(repo, output):
    result = {'scope': 'main-record experiment, real save-menu caller, interrupts enabled', 'modes': []}
    for mode in ('DMG', 'CGB single', 'CGB double'):
        h = RedRogueHarness(repo, output, cgb_mode=mode != 'DMG')
        try:
            h.boot_to_lobby()
            if mode == 'CGB single':
                h.write8('wOptions2', h.read8('wOptions2') & 0x7F)
            h.tick(30)
            start = h.cycle_count()
            h.tick(60)
            units = (h.cycle_count() - start) / 60
            h.park_before_hijack()
            h.call_routine('SaveGameData')  # ordinary schema-11 fixture producer
            raw = dump(h)
            layout = Layout('sum8', descriptor=True, shared_marker=True)
            payload = gather(raw, layout.payload_map)
            baseline = io.BytesIO()
            h.save_state(baseline)
            samples, active, returns = [], {}, set()
            def returned(_):
                if active and h.pyboy.register_file.SP == active['sp'] + 2:
                    elapsed = h.cycle_count() - active['start']
                    samples.append({'milliseconds': elapsed / units * FRAME_MS,
                                    'selection_ms': (active['selected'] - active['start']) / units * FRAME_MS,
                                    'payload_ms': (active['payload'] - active['selected']) / units * FRAME_MS,
                                    'publication_ms': (h.cycle_count() - active['payload']) / units * FRAME_MS,
                                    'vblanks': active['vblanks'], 'key1': active['key1'], 'slot': active['slot'], 'phase': active['phase'], 'active_box': active['active_box']})
                    active.clear()
            def entered(_):
                assert not active
                sp = h.pyboy.register_file.SP
                address = h.pyboy.memory[sp] | h.pyboy.memory[sp + 1] << 8
                bank = h.read8('hLoadedROMBank') if address >= 0x4000 else 0
                key = (bank, address)
                if key not in returns:
                    h._register_at(key, returned)
                    returns.add(key)
                active.update(start=h.cycle_count(), sp=sp, vblanks=0,
                              key1=h.pyboy.memory[0xFF4D] if mode != 'DMG' else None,
                              slot=trial_slot, phase=trial_phase, active_box=trial_active)
            h.register_hook('PSSave', entered)
            h.register_hook('PSSave.invalidateMain', lambda _: active.update(selected=h.cycle_count()) if active else None)
            h.register_hook('PSSave.finishMain', lambda _: active.update(payload=h.cycle_count()) if active else None)
            h.register_hook('VBlank', lambda _: active.update(vblanks=active['vblanks'] + 1) if active else None)
            for trial_active in (0, 11):
                for trial_slot, trial_phase in ((s, p) for s in (0, 1) for p in (0, 3)):
                    h.load_state(baseline)
                    memory, incoming = seed(raw, layout, payload, trial_active, slot=trial_slot)
                    install(h, memory)
                    write_payload(h, incoming)
                    h.tick(trial_phase)
                    count = len(samples)
                    h.write8('wBattleAndStartSavedMenuItem', 4)
                    h.tap('start', 6)
                    for _ in range(350):
                        h.tap('a', 3)
                        if len(samples) > count:
                            break
                    assert len(samples) == count + 1, (mode, trial_slot, h.diagnostic_state())
                    assert h.read8('wPSResult') == 0
                    committed = chosen(dump(h), layout)
                    assert committed[:3] == (8, 1 - trial_slot, trial_active)
                    assert samples[-1]['vblanks'] > 0
                    if mode != 'DMG':
                        assert samples[-1]['key1'] & 0x80 == (0x80 if mode == 'CGB double' else 0)
                    assert not h.hook_errors, h.hook_errors
            result['modes'].append({'mode': mode, 'counter_units_per_frame': units, 'samples': samples})
        finally:
            h.close()
    result['target_ms'] = 50
    result['passed'] = all(sample['milliseconds'] <= 50 for row in result['modes'] for sample in row['samples'])
    (output / 'live_profile.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('repo', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    profile(args.repo.resolve(), args.output.resolve())
