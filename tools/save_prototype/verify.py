"""Execute the isolated ROM primitives and replay their actual SRAM write trace.

This is a main-record experiment, not a production save migration or gameplay
Continue acceptance test. The host seeds an already-initialized format fixture.
"""
import argparse
import io
import json
from pathlib import Path
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/pyboy_smoke'))
from harness import RedRogueHarness
from model_save_handoff import Layout, chosen, gather, mapped_writes
from model_save_metadata import DONE, encode


def dump(h):
    result = bytearray()
    for bank in range(4):
        h.pyboy.memory[0] = 10
        h.pyboy.memory[0x4000] = bank
        result.extend(h.pyboy.memory[0xA000:0xC000])
    h.pyboy.memory[0] = 0
    return result


def install(h, raw):
    for bank in range(4):
        h.pyboy.memory[0] = 10
        h.pyboy.memory[0x4000] = bank
        h.pyboy.memory[0xA000:0xC000] = list(raw[bank * 8192:(bank + 1) * 8192])
    h.pyboy.memory[0] = 0


def regions(h):
    return [('wPlayerName', 11), ('wMainDataStart', h.address('wMainDataEnd') - h.address('wMainDataStart')),
            ('wSpriteDataStart', h.address('wSpriteDataEnd') - h.address('wSpriteDataStart')),
            ('wPartyDataStart', h.address('wPartyDataEnd') - h.address('wPartyDataStart')),
            ('wBoxDataStart', h.address('wBoxDataEnd') - h.address('wBoxDataStart')),
            ('hTileAnimations', 1), ('hCurMap', 1)]


def read_payload(h):
    return bytes(value for label, size in regions(h) for value in h.read_bytes(label, size))


def write_payload(h, payload):
    offset = 0
    for label, size in regions(h):
        address = h.address(label)
        h.pyboy.memory[address:address + size] = list(payload[offset:offset + size])
        offset += size
    assert offset == 3800


def seed(raw, layout, payload, active, generation=7, sequence=10, slot=0):
    raw = raw.copy()
    payload = bytearray(payload)
    payload[layout.current_offset] = active | 0x80
    for address, value in mapped_writes(layout.main(slot, active), layout.seal_main(generation, payload)):
        raw[address] = value
    raw[layout.main(1 - slot, active)[-1]] = 0
    for address in layout.selector:
        raw[address] = 0
    for address, value in zip(layout.selector[:18], encode(sequence, DONE, generation, (active << 1) | slot, 0)):
        raw[address] = value
    for addresses, values in ((layout.save_header, layout.new_header), (layout.descriptor, layout.format_record)):
        for address, value in zip(addresses, values):
            raw[address] = value
    return raw, bytes(payload)


def trace_hooks(h):
    state = {'enabled': False, 'bank': 0, 'writes': [], 'start': 0, 'end': 0,
             'capture_counts': set(), 'snapshots': {}}
    def bank(_):
        state['bank'] = h.pyboy.register_file.A
    h.register_hook('PSBankSelect', bank)
    def write(register):
        def capture(_):
            if not state['enabled']:
                return
            cpu = h.pyboy.register_file
            address = cpu.HL if register == 'HL' else (cpu.D << 8) | cpu.E
            if 0xA000 <= address < 0xC000:
                state['writes'].append((state['bank'] * 8192 + address - 0xA000, cpu.A))
                completed = len(state['writes']) - 1  # hook fires before this store
                if completed in state['capture_counts']:
                    state['snapshots'][completed] = dump(h)
                    # Resume the observed ROM store with precisely its SRAM bank
                    # and enable state restored after the read-only snapshot.
                    h.pyboy.memory[0] = 10
                    h.pyboy.memory[0x4000] = state['bank']
        return capture
    for label in ('invalidateMain', 'checksum', 'commitMain', 'invalidateSelector'):
        h.register_hook('PSSave.' + label, write('HL'))
    h.register_hook('PSSave.commitSelector', write('DE'))
    for label in ('tailWrite', 'write0', 'write1', 'write2', 'write3'):
        h.register_hook('PSCopySum.' + label, write('DE'))
    bank_num, address = h.symbols.get('CopyData')
    h._register_at((bank_num, address + 1), write('DE'))
    h.register_hook('PSSave', lambda _: state.update(start=h.cycle_count()))
    h.register_hook('PSSave.invalidateMain', lambda _: state.update(selection_done=h.cycle_count()))
    h.register_hook('PSSave.finishMain', lambda _: state.update(payload_done=h.cycle_count()))
    h.register_hook('PSClose', lambda _: state.update(end=h.cycle_count()))
    return state


def cold_load(repo, raw, expected, output):
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / 'case.sav'
        path.write_bytes(raw)
        h = RedRogueHarness(repo, output, ram_path=path)
        try:
            # Deliberately use the independent primitive, before entering a game.
            # The production loader must continue to reject experimental schema 12.
            h.tick(240)
            h.park_before_hijack()
            before = dump(h)
            loaded_at_return = []
            h.register_hook('PSLoad.done', lambda _: loaded_at_return.append(read_payload(h)))
            h.call_routine('PSLoad')
            assert h.read8('wPSResult') == 0, h.diagnostic_state()
            assert len(loaded_at_return) == 1
            loaded = loaded_at_return[0]
            if loaded != expected:
                differences = [(i, a, b) for i, (a, b) in enumerate(zip(loaded, expected)) if a != b]
                (output / 'failed_cold.sav').write_bytes(raw)
                (output / 'failed_load.json').write_text(json.dumps({'differences': differences, 'expected': list(expected), 'loaded': list(loaded)}, indent=2))
                raise AssertionError(('cold payload mismatch', differences[:40], len(differences)))
            assert dump(h) == before, 'Main-only loader wrote SRAM'
            assert not h.hook_errors, h.hook_errors
        finally:
            h.close()


def verify(repo, output):
    output.mkdir(parents=True, exist_ok=True)
    layout = Layout('sum8', descriptor=True, shared_marker=True)
    h = RedRogueHarness(repo, output)
    results = {'scope': 'isolated main-record primitives; no production hooks or companion recovery',
               'cases': [], 'cuts': 0, 'torn_metadata_cases': 0, 'cold_loads': 0}
    try:
        h.boot_to_lobby()
        h.call_routine('SaveGameData')
        raw = dump(h)
        payload = gather(raw, layout.payload_map)
        parked = io.BytesIO()
        h.save_state(parked)
        tracing = trace_hooks(h)
        for active in range(12):
            h.load_state(parked)
            sequence = 0xFFFFFFFF if active == 11 else 10
            generation = 0xFFFFFFFF if active == 11 else 7
            memory, old_payload = seed(raw, layout, payload, active, generation, sequence)
            install(h, memory)
            write_payload(h, old_payload)
            for iteration in range(2):
                baseline = io.BytesIO()
                h.save_state(baseline)
                old = chosen(memory, layout)
                newer = bytearray(old[3][4:-2])
                newer[0] = 0x99 - iteration
                newer[11] ^= 1 << iteration
                # A byte from each serialized region, without changing lengths,
                # counts, active box, map identity or live WRAM control fields.
                for label in ('wMoney', 'wPartyMon1OT', 'wBoxMonNicks'):
                    if label in h.symbols._symbols:
                        offset = next((sum(size for _, size in regions(h)[:i]) + h.address(label) - h.address(start)
                                       for i, (start, size) in enumerate(regions(h))
                                       if h.address(start) <= h.address(label) < h.address(start) + size), None)
                        if offset is not None:
                            newer[offset] ^= 1
                write_payload(h, newer)
                tracing.update(enabled=True, writes=[], snapshots={},
                               capture_counts={1, 1900, 3806, 3807, 3808, 3825} if active in (0, 11) else set())
                h.call_routine('PSSave')
                tracing['enabled'] = False
                assert h.read8('wPSResult') == 0, (active, iteration, h.diagnostic_state())
                assert not h.hook_errors, h.hook_errors
                after = dump(h)
                selected = chosen(after, layout)
                assert selected[0] == (old[0] + 1) & 0xFFFFFFFF
                assert selected[1] == 1 - old[1] and selected[2] == active
                assert selected[3][4:-2] == newer
                trace = tracing['writes'].copy()
                assert len(trace) == 3826, len(trace)
                assert {address for address, _ in trace} <= set(layout.main(selected[1], active)) | set(layout.selector)
                projected = memory.copy()
                assert gather(projected, layout.main(old[1], active)) == old[3]
                for index, (address, value) in enumerate(trace):
                    projected[address] = value
                    current = chosen(projected, layout)
                    assert current[3][4:-2] in (old[3][4:-2], bytes(newer)), (active, iteration, index)
                    assert gather(projected, layout.main(old[1], active)) == old[3]
                    results['cuts'] += 1
                assert projected == after, 'Actual ROM writes differ from instrumented trace'
                # Every torn value at metadata/validity publications, replayed
                # from the actual ROM trace with the independent host decoder.
                replay = memory.copy()
                for index, (address, value) in enumerate(trace):
                    if address in layout.selector or index in (0, 3806):
                        saved = replay[address]
                        for torn in range(256):
                            replay[address] = torn
                            current = chosen(replay, layout)
                            assert current[3][4:-2] in (old[3][4:-2], bytes(newer)), (index, torn)
                            results['torn_metadata_cases'] += 1
                        replay[address] = saved
                    replay[address] = value
                # Real cold emulator reloads before/after publication boundaries.
                if active in (0, 11):
                    for count in (1, 1900, 3806, 3807, 3808, 3825, 3826):
                        cut = memory.copy()
                        for address, value in trace[:count]:
                            cut[address] = value
                        if count < 3826:
                            assert tracing['snapshots'][count] == cut, ('execution/replay mismatch', count)
                            cut = tracing['snapshots'][count]
                        else:
                            cut = after
                        (output / f'cut_{active}_{iteration}_{count}.sav').write_bytes(cut)
                        expected = chosen(cut, layout)[3][4:-2]
                        cold_load(repo, cut, expected, output)
                        results['cold_loads'] += 1
                results['cases'].append({'active': active, 'iteration': iteration, 'old_slot': old[1],
                                         'generation': selected[0], 'cycles': tracing['end'] - tracing['start'],
                                         'ms_single_speed': (tracing['end'] - tracing['start']) / 4194.304,
                                         'selection_ms': (tracing['selection_done'] - tracing['start']) / 4194.304,
                                         'payload_write_ms': (tracing['payload_done'] - tracing['selection_done']) / 4194.304,
                                         'publication_ms': (tracing['end'] - tracing['payload_done']) / 4194.304,
                                         'writes': len(trace)})
                (output / f'trace_{active}_{iteration}.json').write_text(json.dumps(trace))
                memory = after
                # Reload a full parked state between independent invocations.
                h.load_state(baseline)
                install(h, memory)
                write_payload(h, newer)
        # Format refusal is byte-exact and precedes destination/payload writes.
        refused_payloads = []
        h.register_hook('PSRefuse', lambda _: refused_payloads.append(read_payload(h)))
        for routine in ('PSSelect', 'PSSave', 'PSLoad'):
            h.load_state(parked)
            install(h, raw)  # genuine schema-11 save, not a prototype fixture
            before = dump(h)
            before_wram = read_payload(h)
            count = len(refused_payloads)
            h.call_routine(routine)
            assert h.read8('wPSResult') == 1
            assert dump(h) == before
            assert len(refused_payloads) == count + 1 and refused_payloads[-1] == before_wram
        results['legacy_refused_unchanged'] = True
        # Malformed sealed context, ambiguous sequences, bad main framing and
        # checksum damage must refuse before any destination/persistent write.
        good, good_payload = seed(raw, layout, payload, 0)
        malformed = []
        for name, address in [('descriptor', layout.descriptor[2]), ('main checksum', layout.main0[-2]),
                              ('main marker', layout.main0[-1]), ('generation', layout.main0[0]),
                              ('selector CRC', layout.selector[13])]:
            broken = good.copy()
            broken[address] ^= 1
            malformed.append((name, broken))
        for name, second_sequence in [('equal sequence', 10), ('half-range sequence', 10 + 0x80000000)]:
            broken = good.copy()
            for address, value in zip(layout.selector[18:], encode(second_sequence, DONE, 7, 0, 0)):
                broken[address] = value
            malformed.append((name, broken))
        for name, mode, count, undo in [('incomplete mode', 0, 0, 0), ('invalid active', DONE, 24, 0), ('undo live', DONE, 0, 1)]:
            broken = good.copy()
            for address, value in zip(layout.selector[:18], encode(10, mode, 7, count, undo)):
                broken[address] = value
            malformed.append((name, broken))
        for name, broken in malformed:
            for routine in ('PSSelect', 'PSSave', 'PSLoad'):
                h.load_state(parked)
                install(h, broken)
                write_payload(h, good_payload)
                before_wram = read_payload(h)
                count = len(refused_payloads)
                h.call_routine(routine)
                assert h.read8('wPSResult') == 1, (name, routine)
                assert dump(h) == broken, (name, routine, 'persistent write')
                assert len(refused_payloads) == count + 1 and refused_payloads[-1] == before_wram, (name, routine, 'destination write')
        results['malformed_refusals'] = len(malformed) * 3
        h.load_state(parked)
        install(h, good)
        write_payload(h, good_payload)
        h.write8('wCurrentBoxNum', 0x81)
        h.call_routine('PSSave')
        assert h.read8('wPSResult') == 1 and dump(h) == good
        results['active_change_refused'] = True
        results['latency_target_ms'] = 50
        results['latency_passed'] = all(case['ms_single_speed'] <= 50 for case in results['cases'])
        (output / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
        print(json.dumps(results, indent=2))
    finally:
        h.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('repo', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    verify(args.repo.resolve(), args.output.resolve())
