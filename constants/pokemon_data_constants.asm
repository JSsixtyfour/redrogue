; base data struct members (see data/pokemon/base_stats/*.asm)
rsreset
DEF BASE_DEX_NO      rb
DEF BASE_STATS       rb NUM_STATS
rsset BASE_STATS
DEF BASE_HP          rb
DEF BASE_ATK         rb
DEF BASE_DEF         rb
DEF BASE_SPD         rb
DEF BASE_SPC         rb
DEF BASE_TYPES       rw
rsset BASE_TYPES
DEF BASE_TYPE_1      rb
DEF BASE_TYPE_2      rb
DEF BASE_CATCH_RATE  rb
DEF BASE_EXP         rb
DEF BASE_PIC_SIZE    rb
DEF BASE_FRONTPIC    rw
DEF BASE_BACKPIC     rw
DEF BASE_MOVES       rb NUM_MOVES
DEF BASE_GROWTH_RATE rb
DEF BASE_TMHM        rb (NUM_TM_HM + 7) / 8
; Was an unnamed `rb_skip` whose byte every base_stats file emitted as
; `db 0 ; padding`. Claimed 2026-09-03 for the pic bank, per pret's "Improve the
; Pokemon picture system": UncompressMonSprite used to pick the ROM bank from a
; hardcoded compare chain on the species index, which silently sent anything
; >= $BF to "Pics 5". Storing the bank per species removes that ceiling and lets
; pics live in any bank. BASE_DATA_SIZE is UNCHANGED - this costs no ROM and no
; WRAM, it just names a byte that was already there.
DEF BASE_PIC_BANK    rb
DEF BASE_DATA_SIZE EQU _RS

; party_struct members (see macros/ram.asm)
rsreset
DEF MON_SPECIES    rb
DEF MON_HP         rw
DEF MON_BOX_LEVEL  rb
DEF MON_STATUS     rb
DEF MON_TYPE       rw
rsset MON_TYPE
DEF MON_TYPE1      rb
DEF MON_TYPE2      rb
DEF MON_CATCH_RATE rb
DEF MON_MOVES      rb NUM_MOVES
DEF MON_OTID       rw
DEF MON_EXP        rb 3
DEF MON_HP_EXP     rw
DEF MON_ATK_EXP    rw
DEF MON_DEF_EXP    rw
DEF MON_SPD_EXP    rw
DEF MON_SPC_EXP    rw
DEF MON_DVS        rw
DEF MON_PP         rb NUM_MOVES
DEF BOXMON_STRUCT_LENGTH EQU _RS ; $21
DEF MON_LEVEL      rb
DEF MON_STATS      rw NUM_STATS
rsset MON_STATS
DEF MON_MAXHP      rw
DEF MON_ATK        rw
DEF MON_DEF        rw
DEF MON_SPD        rw
DEF MON_SPC        rw
DEF PARTYMON_STRUCT_LENGTH EQU _RS ; $2c

DEF PARTY_LENGTH EQU 6

DEF MONS_PER_BOX EQU 20
DEF NUM_BOXES    EQU 12

; Bridge selected-Pokémon effects use a sparse run-scoped registry instead of
; adding fields to party_struct/box_struct. A record stores one owner byte and
; one effect byte. Owner 0 is empty; party owners are 1..6, box owners are
; absolute across all 12 boxes, and the final two values identify the two
; daycare slots. Keep the owner range below $ff so malformed/legacy save data
; can never be mistaken for a valid owner.
DEF BRIDGE_SELECTED_OWNER_NONE       EQU 0
DEF BRIDGE_SELECTED_OWNER_PARTY_BASE EQU 1
DEF BRIDGE_SELECTED_OWNER_BOX_BASE   EQU BRIDGE_SELECTED_OWNER_PARTY_BASE + PARTY_LENGTH
DEF BRIDGE_SELECTED_OWNER_DAYCARE1   EQU BRIDGE_SELECTED_OWNER_BOX_BASE + NUM_BOXES * MONS_PER_BOX
DEF BRIDGE_SELECTED_OWNER_DAYCARE2   EQU BRIDGE_SELECTED_OWNER_DAYCARE1 + 1
DEF BRIDGE_SELECTED_OWNER_MAX        EQU BRIDGE_SELECTED_OWNER_DAYCARE2
ASSERT BRIDGE_SELECTED_OWNER_MAX < $ff

; Effect 0 is the empty-record marker. Each owner may occupy at most one record;
; intrinsic special-form traits such as Quick Claw and Intimidating Presence
; are resolved from species/form data and do not use a record here.
const_def 1
const BRIDGE_SELECTED_EFFECT_CRITICAL_RATE
const BRIDGE_SELECTED_EFFECT_SHRINK_RAY
const BRIDGE_SELECTED_EFFECT_GROWTH_RAY
const BRIDGE_SELECTED_EFFECT_FLINCH
const BRIDGE_SELECTED_EFFECT_BODY_ARMOR
const BRIDGE_SELECTED_EFFECT_POISON_IMMUNITY
const BRIDGE_SELECTED_EFFECT_LIFE_ORB
const BRIDGE_SELECTED_EFFECT_STATUS_IMMUNITY
DEF NUM_BRIDGE_SELECTED_EFFECTS EQU const_value - 1
DEF BRIDGE_SELECTED_RECORD_SIZE  EQU 2 ; owner byte + effect byte
DEF BRIDGE_SELECTED_RECORD_COUNT EQU BRIDGE_PER_RUN
ASSERT NUM_BRIDGE_SELECTED_EFFECTS == 8
ASSERT BRIDGE_SELECTED_RECORD_COUNT == 2

DEF HOF_MON           EQU $10
DEF HOF_TEAM          EQU PARTY_LENGTH * HOF_MON
DEF HOF_TEAM_CAPACITY EQU 50

; mon data locations
; Note that some values are not supported by all functions that use these values.
	const_def
	const PLAYER_PARTY_DATA ; 0
	const ENEMY_PARTY_DATA  ; 1
	const BOX_DATA          ; 2
	const DAYCARE_DATA      ; 3
	const BATTLE_MON_DATA   ; 4
    const DAYCARE_DATA2     ; 5

; Evolution types
	const_def 1
	const EVOLVE_LEVEL ; 1
	const EVOLVE_ITEM  ; 2
	const EVOLVE_TRADE ; 3

; evolution data (see data/pokemon/evos_moves.asm)
;
; Raised 3 -> 8 for Species Groups Phase 2R (plan 2R.8b). This is NOT cosmetic:
; EvolveMonByLevel (custom_functions/func_enc_gen.asm) does not stream the
; evolution list, it BULK-COPIES it into wEvoDataBuffer, which is sized
; NUM_EVOS_IN_BUFFER * 4 + 1. The old comment on that WRAM line read "enough for
; Eevee's three 4-byte evolutions" - and Eevee reaches EIGHT once the
; eeveelutions land (Fire/Thunder/Water plus Leaf/Sun/Dusk/Ice/Moon). At 3 that
; copy would have written 33 bytes into a 13-byte buffer: a 20-byte overrun, on
; every reward and trainer path that evolves anything, not just Eevee's.
;
; Cost, per WRAM_BIBLE.md's Potential-vs-Actual rule: the buffer is a UNION
; member and the union spans 20 bytes (set by wNameBuffer, NAME_BUFFER_LENGTH).
; Growing the member to 33 grows the union 20 -> 33, so the ACTUAL WRAM0 cost is
; 13 bytes, not 20.
DEF NUM_EVOS_IN_BUFFER EQU 8

; ---------------------------------------------------------------------------
; Species Groups Phase 2R - regional / convergent / eeveelution FORMS.
;
; A "form" is a distinct-looking mon delivered as <existing species> + a small
; form index rather than as a new species id, so it costs ZERO species ids.
; The index lives in MON_CATCH_RATE bits 5-6 - see MON_CATCH_RATE_BITFIELD_PC.md
; for the full registry of that byte (bits 0-4 are ghost/fusion/type-variant/
; special-form/shiny; bit 7 is the last free one and is deliberately reserved).
;
; TWO BITS = 3 non-zero forms per base species. That is not arbitrary: the
; binding case across the whole 52-form roster is TAUROS, which needs exactly
; three (Paldean Combat/Blaze/Aqua). Nothing else needs more than two. A fourth
; form on any base species means spending bit 7.
;
; NOTE this is a small INTEGER sharing a flag byte, not an independent flag.
; Read and write it with the mask/shift below, never bit/set/res on one of its
; two bits.
DEF FORM_MASK      EQU %01100000 ; MON_CATCH_RATE bits 5-6
DEF FORM_SHIFT     EQU 5
DEF NUM_FORM_SLOTS EQU 3         ; non-zero form indexes per base species

; How often a rolled species spawns as one of its regional forms, out of 256.
; Checked ONCE per spawn, before the form table is consulted, so it is the rate
; for "this mon is a form at all" and NOT a per-form rate: a species with three
; forms is no more likely to be formed than a species with one, it just picks
; uniformly among its own once the roll succeeds.
;
; 32/256 = 12.5%. Deliberately in the same "pleasant surprise" band as the shiny
; rate rather than the "every other Meowth is Alolan" band. This is the one knob
; that tunes how often the 48 records in data/pokemon/forms/ are actually seen -
; raise it to make forms common, set it to 0 to switch the whole system off
; without touching code.
DEF FORM_SPAWN_ODDS EQU 32

; How often a pick at a given rarity tier is taken over by a TIER-PLACED form
; instead of an ordinary species roll, out of 256. Only forms listed in
; FormTierTable (data/pokemon/forms.asm) are reachable this way - the ones whose
; power does not match their base species' tier, currently just Scream Tail.
;
; Checked only after confirming the tier HAS entries, so tiers with an empty list
; consume no randomness and roll exactly as they did before this existed.
;
; 16/256 = 6.25%, half the ordinary form rate: these are the outliers, and a
; tier-placed form displaces the species the tier would otherwise have offered.
DEF FORM_TIER_ODDS EQU 16

; One FormTierTable row: pair count + list pointer.
DEF FORM_TIER_ENTRY_SIZE EQU 3

; Trainer party layout markers - the FIRST byte of a team in data/trainers/parties.asm.
;
;   (any level 1-100) = every mon on the team shares that level; entries are
;                       <species> bytes.
;   TRAINERPARTY_LEVELS ($ff) = vanilla per-mon levels; entries are
;                       <level, species> pairs.
;   TRAINERPARTY_FORMS  ($fe) = per-mon levels AND regional forms; entries are
;                       <level, species, form> triples. Phase 2R increment 8c.
;
; $fe is safe as a marker for the same reason $ff is: the byte is otherwise a
; LEVEL, and no mon is level 254. In every layout the 0 terminator is tested on
; the level byte, so a form of 0 mid-record is fine.
DEF TRAINERPARTY_LEVELS EQU $ff
DEF TRAINERPARTY_FORMS  EQU $fe

; ===========================================================================
; ⚠⚠ TEMPORARY TEST SWITCH - SET BACK TO 0 BEFORE COMMITTING ⚠⚠
;
; 1 = every mon on every RANDOM ENEMY TRAINER's roster is forced to Alolan Grimer
;     (GRIMER + form 1), bypassing both the species roll and the unlock gate.
;
; This exists to test ONE thing: does a form STORED in a trainer mon's party
; struct survive being sent out? If the enemy leads with "A-GRIMER" and the
; Alolan sprite, GetEnemySpawnForm is reading the stored bits correctly. If it
; leads with a plain "GRIMER", the send-out path is still wiping the form.
;
; It deliberately bypasses RogueFormsUnlocked, so it works WITHOUT Debug 2 and
; without any champion wins - it is testing the battle path, not the gating.
;
; ⚠ `make smoke` WILL FAIL with this set to 1. Every trainer roster becomes six
; Alolan Grimers, which is exactly what several AI/roster tests assert against.
; That is expected, not a regression. Set it to 0 and re-run before trusting a
; smoke result.
DEF FORCE_TRAINER_FORM_TEST EQU 0

; ⚠⚠ TEMPORARY TEST SWITCH - SET BACK TO 0 BEFORE COMMITTING ⚠⚠
;
; 1 = every WILD encounter, in procedural stages and on vanilla routes alike, is
;     forced to a fixed species + form (edit the two `ld a,` lines at
;     .afterEncounterData in engine/battle/wild_encounters.asm to change which).
;
; It writes wSpawnForm DIRECTLY, which deliberately bypasses BOTH gates that make
; casual testing so slow:
;   - FORM_SPAWN_ODDS (32/256 = 12.5%), so you are not waiting on a 1-in-8 roll
;   - RogueFormsUnlocked, so it works with NO champion wins and NO Debug 2
;
; Forcing only the species is not enough on its own: at that point the roll has
; already happened and wSpawnForm holds a form rolled for the species you just
; overwrote - which is 0 almost every time, hence "I forced a Meowth and got a
; plain Meowth".
DEF FORCE_WILD_FORM_TEST EQU 0

; ⚠⚠ TEMPORARY TEST SWITCH - SET BACK TO 0 BEFORE COMMITTING ⚠⚠
;
; 1 = the WILD AREA (procedural cave) boss is always Alolan Grimer. Edit the two
;     `ld` lines in PCRollBoss (custom_functions/procedural_cave_gen.asm) to test
;     a different record.
;
; Forces both wRoguePokemon1 and wRoguePokemonForm1, so it also bypasses
; FORM_SPAWN_ODDS and RogueFormsUnlocked - no Debug 2 or champion wins needed.
; Without it you would be waiting for a random boss species that happens to own a
; form record AND for a 1-in-8 roll on top.
;
; The forced species feeds the overworld SPRITE lookup too, so the boss sprite on
; the map should be a Grimer before you ever engage it - a useful early signal
; that PCRollBoss ran at all.
DEF FORCE_BOSS_FORM_TEST EQU 0

; ⚠⚠ TEMPORARY TEST SWITCH - SET BACK TO 0 BEFORE COMMITTING ⚠⚠
;
; 1 = the three reward offers are forced to A-MEOWTH / G-MEOWTH / A-DUGTRIO.
;
; This is the ONE test that actually proves the per-offer form storage
; (wRoguePokemonForm1..3) fixed the shared-global labelling bug, and the species
; choice is the whole point: slots 1 and 2 are the SAME SPECIES differing only by
; FORM. Under the old single-wSpawnForm code every slot was labelled with
; whichever form was rolled last, so those two would have printed an identical
; name. Three distinct names means each slot is reading its own byte.
;
; Forced after the batch has rolled, so the duplicate-species rejection in
; rogue_pokemon_randomized_batch cannot interfere. Bypasses FORM_SPAWN_ODDS and
; RogueFormsUnlocked - no Debug 2 or champion wins needed.
DEF FORCE_REWARD_FORM_TEST EQU 0
; ===========================================================================

; One row of the FormOverrides table (data/pokemon/forms.asm). A form record
; carries a FULL base-stats row, so a form gets its own stats, both types, catch
; rate, base exp, pic size, front/back pic pointers AND pic bank, starting
; moves, growth rate and TM/HM compatibility for free - all of it lives in the
; 28-byte struct that becomes wMonHeader. Only the level-up learnset stays
; species-keyed (EvosMovesPointerTable is indexed by species), which is an
; accepted limitation, not an oversight.
; NAME_LENGTH is NOT available here - includes.asm pulls this file in at line 33
; and constants/text_constants.asm only at line 53. The 10 below is the same
; NAME_LENGTH - 1 stride MonsterNames uses; data/pokemon/forms.asm carries an
; ASSERT tying the two together, which is where NAME_LENGTH *is* in scope.
DEF FORM_REC_NAME_LEN EQU 10
rsreset
DEF FORM_REC_BASE    rb        ; base species internal index
DEF FORM_REC_FORM    rb        ; form index, 1..NUM_FORM_SLOTS
DEF FORM_REC_DATA    rb BASE_DATA_SIZE     ; full base-stats row, patched over wMonHeader
DEF FORM_REC_NAME    rb FORM_REC_NAME_LEN  ; 10 chars, no terminator
DEF FORM_REC_SIZE EQU _RS

; wMonHGrowthRate values
; GrowthRateTable indexes (see data/growth_rates.asm)
	const_def
	const GROWTH_MEDIUM_FAST
	const GROWTH_SLIGHTLY_FAST
	const GROWTH_SLIGHTLY_SLOW
	const GROWTH_MEDIUM_SLOW
	const GROWTH_FAST
	const GROWTH_SLOW
DEF NUM_GROWTH_RATES EQU const_value

; wild data (see data/wild/maps/*.asm)
DEF NUM_WILDMONS EQU 10
DEF WILDDATA_LENGTH EQU 1 + NUM_WILDMONS * 2

; PP in box_struct (see macros/ram.asm)
DEF PP_UP_MASK EQU %11000000 ; number of PP Up used
DEF PP_MASK    EQU %00111111 ; currently remaining PP
