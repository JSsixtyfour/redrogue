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
DEF NUM_EVOS_IN_BUFFER EQU 3

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
