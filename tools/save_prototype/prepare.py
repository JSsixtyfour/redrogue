"""Create the isolated executable main-record experiment from a built snapshot.

Usage: python tools/save_prototype/prepare.py BUILT_SOURCE_COPY
Never edits production main.asm or production RAM declarations.
"""
import argparse
from pathlib import Path
import re
import shutil
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/pyboy_smoke'))
from model_save_handoff import Layout


def spans(addresses):
    result = []
    for value in addresses:
        bank, address = divmod(value, 8192)
        address += 0xA000
        if result and result[-1][0] == bank and result[-1][1] + result[-1][2] == address:
            result[-1][2] += 1
        else:
            result.append([bank, address, 1])
    return result


def prepare(target):
    layout = Layout('sum8', descriptor=True, shared_marker=True)
    # The old model's mapping is usable only while every referenced SRAM/WRAM
    # address matches the newly built source snapshot.
    current = {}
    for line in (target / 'pokeblue_debug.sym').read_text().splitlines():
        match = re.match(r'([0-9a-f]+):([0-9a-f]+) (\S+)$', line)
        if match:
            current[match[3]] = (int(match[1], 16), int(match[2], 16))
    for name, value in layout.sym.items():
        if name.startswith(('w', 's', 'h')) and name in current and (0xA000 <= value[1] < 0xE000 or 0xFF80 <= value[1] < 0xFFFF):
            assert current[name] == value, (name, value, current[name])
    destination = target / 'tools/save_prototype'
    destination.mkdir(parents=True, exist_ok=True)
    core = (ROOT / 'tools/save_prototype/core.asm').read_text()
    core = core.replace('ld [rRAMB], a', 'call PSBankSelect')
    core += '\nPSBankSelect::\n\tld [rRAMB], a\n\tret\n'
    # Keep the already-proven fused writer's loop and byte order intact.
    donor = (target / 'engine/menus/save.asm').read_text()
    donor = donor.split('CopySaveDataAndSum:\n', 1)[1].split('\nCalcCheckSum:', 1)[0]
    donor = donor.replace('\tREPT 4\n\tld a, [hli]\n\tld [de], a\n\tinc de\n\tadd c\n\tld c, a\n\tENDR', ''.join(
        f'\tld a, [hli]\n.write{i}\n\tld [de], a\n\tinc de\n\tadd c\n\tld c, a\n' for i in range(4)))
    donor = donor.replace('.tail\n\tld a, [hli]\n\tld [de], a', '.tail\n\tld a, [hli]\n.tailWrite\n\tld [de], a')
    core += '\nPSCopySum:\n' + donor
    generated = []
    def emit(value):
        generated.append(value)
    def const(name, value):
        emit(f'DEF {name} EQU ${value:04x}')
    const('PS_PAYLOAD', 3800)
    const('PS_CURRENT_OFFSET', layout.current_offset)
    const('PS_SELECTOR', layout.selector[0] % 8192 + 0xA000)
    assert spans(layout.selector) == [[0, 0xBCB1, 36]]
    const('PS_FIXED_GENERATION', layout.main0[0] % 8192 + 0xA000)
    const('PS_SHADOW_GENERATION', layout.main1[0][0] % 8192 + 0xA000)
    const('PS_FIXED_MARKER', layout.main0[-1] % 8192 + 0xA000)
    assert all(a // 8192 == 0 for a in layout.main0[:4] + layout.main0[-1:])
    assert len(spans(layout.main0[:4])) == len(spans(layout.main1[0][:4])) == 1
    # Format check writes neither metadata nor legacy SRAM.
    emit('PSFormatCheck:')
    for addresses, values in ((layout.save_header, layout.new_header), (layout.descriptor, layout.format_record)):
        last = None
        for physical, value in zip(addresses, values):
            bank, offset = divmod(physical, 8192)
            if bank != last:
                emit(f'\tld a, {bank}\n\tcall PSBankSelect')
                last = bank
            emit(f'\tld a, [${0xA000 + offset:04x}]\n\tcp ${value:02x}\n\tret nz')
    emit('\txor a\n\tret')
    emit('PSPayloadTable:\n\tld hl, PSFixedPayload\n\tld a, [wPSSlot]\n\tand a\n\tret z\n\tld a, [wPSActive]\n\tadd a\n\tld e, a\n\tld d, 0\n\tld hl, PSShadowPayloads\n\tadd hl, de\n\tld a, [hli]\n\tld h, [hl]\n\tld l, a\n\tret')
    emit('PSCodeEnd::')
    regions = [('wPlayerName', 11), ('wMainDataStart', layout.sym['wMainDataEnd'][1] - layout.sym['wMainDataStart'][1]),
               ('wSpriteDataStart', layout.sym['wSpriteDataEnd'][1] - layout.sym['wSpriteDataStart'][1]),
               ('wPartyDataStart', layout.sym['wPartyDataEnd'][1] - layout.sym['wPartyDataStart'][1]),
               ('wBoxDataStart', layout.sym['wBoxDataEnd'][1] - layout.sym['wBoxDataStart'][1]),
               ('hTileAnimations', 1), ('hCurMap', 1)]
    assert sum(size for _, size in regions) == 3800
    sources = [(name, i) for name, size in regions for i in range(size)]
    emit('PSWRAMRegions:')
    for name, size in regions:
        emit(f'\tdw {name}, {size}')
    emit('\tdw 0, 0')
    emit('PSShadowMaps:\n\tdw ' + ', '.join(f'PSShadowMap{i}' for i in range(12)))
    emit('PSShadowPayloads:\n\tdw ' + ', '.join(f'PSShadowPayload{i}' for i in range(12)))
    emit('PSShadowMarkers:')
    for addresses in layout.main1:
        bank, offset = divmod(addresses[-1], 8192)
        emit(f'\tdb {bank}\n\tdw ${offset + 0xA000:04x}')
    for label, addresses in [('PSFixed', layout.main0)] + [(f'PSShadow{i}', addresses) for i, addresses in enumerate(layout.main1)]:
        map_label = 'PSFixedMap' if label == 'PSFixed' else label.replace('Shadow', 'ShadowMap')
        payload_label = 'PSFixedPayload' if label == 'PSFixed' else label.replace('Shadow', 'ShadowPayload')
        emit(map_label + ':')
        for bank, address, size in spans(addresses):
            emit(f'\tdb {bank}\n\tdw ${address:04x}, {size}')
        emit('\tdb $ff')
        emit(payload_label + ':')
        # Coalesce only when physical destination and WRAM source are contiguous.
        rows = []
        for physical, (name, offset) in zip(addresses[4:-2], sources):
            bank, addr = divmod(physical, 8192)
            addr += 0xA000
            if rows and rows[-1][0] == bank and rows[-1][1] + rows[-1][2] == addr and rows[-1][3] == name and rows[-1][4] + rows[-1][2] == offset:
                rows[-1][2] += 1
            else:
                rows.append([bank, addr, 1, name, offset])
        for bank, address, size, name, offset in rows:
            emit(f'\tdb {bank}\n\tdw ${address:04x}, {size}, {name} + {offset}')
        emit('\tdb $ff')
    (destination / 'assembled.asm').write_text('\n'.join(generated[:6]) + '\n' + core + '\n' + '\n'.join(generated[6:]) + '\n')
    # Scratch exists only in the experiment. No production WRAM field moves.
    fields = [('Records', 36), ('Selected', 18), ('CRC', 4), ('Delta', 4), ('Valid', 1), ('Which', 1),
              ('Slot', 1), ('Active', 1), ('Result', 1), ('Sum', 1), ('Stream', 2), ('Address', 2),
              ('Remaining', 2), ('Bank', 1), ('Length', 2), ('Table', 2)]
    assert 'EMPTY: $de5e-$deff ($00a2 bytes)' in (target / 'pokeblue_debug.map').read_text()
    ram = ['SECTION "Protected Main Prototype Scratch", WRAM0[$DE5E]', 'wPSScratch::']
    ram += [f'wPS{name}:: ds {size}' for name, size in fields]
    ram += ['wPSScratchEnd::', 'ASSERT wPSScratchEnd - wPSScratch == 79']
    # Free extents are actually allocated in the prototype; padding becomes named.
    import json
    budget = json.loads((ROOT / 'tools/pyboy_smoke/artifacts/save_writer_fused_2026-10-21_20e709cd/recovery_budget_candidate.json').read_text())
    for i, extent in enumerate(budget['pool_extents']):
        if extent['kind'] == 'map_free':
            ram += [f'SECTION "Protected Main Pool {i}", SRAM[${extent["start"]:04x}], BANK[{extent["bank"]}]', f'sPSPool{i}:: ds {extent["bytes"]}']
    (destination / 'ram.asm').write_text('\n'.join(ram) + '\n')
    sram = (target / 'ram/sram.asm').read_text()
    replacements = [('sSpriteBuffer2:: ds SPRITEBUFFERSIZE\n\n\tds $100', 'sSpriteBuffer2:: ds SPRITEBUFFERSIZE\n\nsPSPadding0:: ds $100'),
                    ('\tds $40 - (sStolenRecordEnd - sStolenRecord)', 'sPSPadding1:: ds $40 - (sStolenRecordEnd - sStolenRecord)'),
                    ('\tds $3b7 - 7 - SAVE_HEADER_SIZE', 'sPSPadding2:: ds $3b7 - 7 - SAVE_HEADER_SIZE')]
    for old, new in replacements:
        assert sram.count(old) == 1, old
        sram = sram.replace(old, new)
    (target / 'ram/sram.asm').write_text(sram)
    with (target / 'main.asm').open('a') as stream:
        stream.write('\nINCLUDE "tools/save_prototype/assembled.asm"\n')
    with (target / 'ram.asm').open('a') as stream:
        stream.write('\nINCLUDE "tools/save_prototype/ram.asm"\n')
    save_path = target / 'engine/menus/save.asm'
    save = save_path.read_text()
    assert save.count('SaveGameData::\n') == 1
    save = save.replace('SaveGameData::\n', 'SaveGameData::\n\trfarcall PSIsExperimentalFormat\n\tjr nz, .productionFormat\n\trfarcall PSSave\n\tret\n.productionFormat\n', 1)
    save_path.write_text(save)
    print(f'Prepared isolated main-record prototype in {target}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('target', type=Path)
    args = parser.parse_args()
    target = args.target.resolve()
    assert target != ROOT and ROOT in target.parents, 'Use an isolated copy inside this workspace'
    assert 'tools/save_prototype/assembled.asm' not in (target / 'main.asm').read_text(), 'Already prepared'
    prepare(target)
