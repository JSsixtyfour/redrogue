import io
p='/mnt/K/Other computers/My Laptop/Red Rogue Files/ROM_BIBLE.md'
try:
    s=io.open(p,encoding='utf-8',newline='').read()
except Exception as e:
    print("ERR",e); raise SystemExit(1)

rows={
"| `$08` | 205 | Audio bank, current Debug minimum after Bill's PC relocation; keep reclaimed room for audio work |":
"| `$08` | **116** | Audio bank. Now also the first-fit home of the floating `Self-Target Stat Penalty` section (grown 61 -> 116 bytes by follow-up F4 on 2026-09-01, and it landed in `$08` in ALL THREE targets this time, unlike the 2026-08-26 split). Measured 2026-09-01. |",
"| `$0E` | **213** | **Tight, and effectively the AI ceiling.** Pinned home of every `AILayer*` routine (same-bank `jp hl` dispatch), plus Phase 6/7 additions and the 2026-08-27 narrow double-speed wrap around `AIEnemyTrainerChooseMoves` (15 bytes). Updated 2026-08-27. |":
"| `$0E` | **854** | Pinned home of every `AILayer*` routine (same-bank `jp hl` dispatch). **The 2026-08-27 figure of 213 was STALE, not spent** - re-measured at 854 on 2026-09-01 after first-fit churn moved floaters elsewhere; only `Battle Engine 7`, `Credit Exchange` and `Procedural Facility Maps` remain in the bank. F2's 8-byte AI_TYPES skip is included. Re-measure before trusting any figure here; this bank's floaters move often. Updated 2026-09-01. |",
"| `$0F` | **15** | Battle Core. **EXHAUSTED - do not budget anything else here without a relocation first.** Phase 4 recovered it from 0 via a farcall swap; Phase 6 spent 30 of 53; Phase 7's `AITrackSeenPlayerMove` hook spent 8 more. Updated 2026-08-26. |":
"| `$0F` | **17** | Battle Core. **EXHAUSTED - do not budget anything else here without a relocation first.** Phase 4 recovered it from 0 via a farcall swap; Phase 6 spent 30 of 53; Phase 7's `AITrackSeenPlayerMove` hook spent 8 more; follow-up F4 spent 2 more (a 6-byte `call`+`jp` pair became an 8-byte `jpfar`). Red/Blue read 24; **Debug binds at 17.** Updated 2026-09-01. |",
}
for k,v in rows.items():
    assert s.count(k)==1, ("row not found/unique", k[:40], s.count(k))
    s=s.replace(k,v)

entry = """
**2026-09-01 AI Overhaul follow-ups F2 and F4 measurement.** Two small, independent battle-engine
edits, both landing in already-tight banks, so both were measured rather than assumed.

**F2 (Metronome/Mirror Move vs the type chart), bank `$0E`, +8 bytes.** Two `cp`/`jr z` pairs added
to `AIMoveChoiceModification3` (`engine/battle/trainer_ai.asm`) so `METRONOME_EFFECT` and
`MIRROR_MOVE_EFFECT` skip the type-effectiveness layer entirely, exactly as `SPECIAL_DAMAGE_EFFECT`
and `SUPER_FANG_EFFECT` already did. Chosen over the plan's original "retype Metronome to BIRD"
because it is data-free, fixes two moves instead of one, and does not change what the move-info
preview screen displays (`BIRD` has a real name string in `data/types/names.asm`).

**F4 (stat-down burn/paralysis re-application), bank `$0F`, +2 bytes; bank `$08`, +55 bytes.**
`StatModifierDownEffect`'s tail (`engine/battle/effects.asm`) was `call QuarterSpeedDueToParalysis` /
`jp HalveAttackDueToBurn` - 6 bytes, both penalties unconditionally. It is now a single 8-byte
`jpfar ApplyTargetStatPenalty`, a new routine appended to the existing floating
`Self-Target Stat Penalty` section (`custom_functions/apply_self_stat_penalty.asm`), which dispatches
on the move effect so only the stat that was actually recalculated gets its penalty re-applied.

*The `jpfar`-into-a-routine-that-`farcall`s-back pattern was traced through `home/bankswitch.asm`
before being used, not assumed.* `jpfar` is `jp Bankswitch`, so it reuses the caller's existing
return address; the inner `farcall` pushes a second `Bankswitch` frame; both frames unwind through
the same shared `.Return` label in order, restoring `$08` then `$0F`. Nested `Bankswitch` frames are
safe, and this file already relied on it (`ApplySelfTargetStatPenalty` farcalls back into Battle
Core from the same section).

**Measured after (all three ROMs build clean, no warnings):**

| Bank | Before | After | Note |
|---|---:|---:|---|
| `$0E` Battle Engine 7 | 213 (stale) | **854** | F2's +8 is included. The "before" number was drift, not spend - see the table row. |
| `$0F` Battle Core | 15 (stale; 19 measured) | **17** | Debug binds. Red/Blue read 24. |
| `$08` | 205 | **116** | The `Self-Target Stat Penalty` floater grew 61 -> 116 bytes and stayed in `$08` in all three targets. |

**Gates:** `make` clean on `pokered` + `pokeblue` + `pokeblue_debug`; `make ai_scenarios` 56/56;
`make integration` clean; `make smoke` 152/154, with the two failures
(`test_follower_yellow_runtime` CGB-classification, `test_lobby_pose_layout`'s missing
`jp UpdateSprites`) **bisect-confirmed pre-existing** by stashing all three edited files, rebuilding
and re-running those two modules alone. Neither touches battle code.

"""

marker = "**2026-08-26 AI Overhaul Phase 6, Opus portion - bank `$0F` is now CLOSED.**"
i = s.find(marker)
assert i != -1
s = s[:i] + entry.lstrip('\n') + "\n" + s[i:]
io.open(p,'w',encoding='utf-8',newline='').write(s)
print("ok")
