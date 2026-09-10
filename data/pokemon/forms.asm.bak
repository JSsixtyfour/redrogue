; Species Groups Phase 2R - form override records.
;
; A form record patches wMonHeader AFTER GetMonHeader has copied the base
; species' row, so a form gets its own stats, both types, catch rate, base exp,
; pic size, front/back pic pointers, PIC BANK, starting moves, growth rate and
; TM/HM compatibility - everything that lives in the 28-byte base-stats struct.
; Only the level-up learnset stays species-keyed (EvosMovesPointerTable is
; indexed by species), which is an accepted limitation.
;
; Record layout is FORM_REC_* in constants/pokemon_data_constants.asm:
;   db <base species>, <form index 1..NUM_FORM_SLOTS>
;   <BASE_DATA_SIZE bytes: an ordinary base-stats row>
;   <10 name characters, no terminator>
;
; The table is walked linearly by ApplyFormOverride and terminated by a 0
; species byte. Linear is fine: the walk only runs when a mon actually has
; non-zero form bits, which is never true for any of the 252 ordinary species.

; NAME_LENGTH is in scope here but not in pokemon_data_constants.asm (include
; order), so this is where the two are tied together.
ASSERT FORM_REC_NAME_LEN == NAME_LENGTH - 1, \
       "form record name field must match the MonsterNames stride"
ASSERT FORM_REC_SIZE == 2 + BASE_DATA_SIZE + FORM_REC_NAME_LEN, \
       "FORM_REC_SIZE is out of step with the FORM_REC_* offsets"

; A form index must fit in MON_CATCH_RATE bits 5-6.
ASSERT NUM_FORM_SLOTS == (FORM_MASK >> FORM_SHIFT), \
       "NUM_FORM_SLOTS does not match the width of FORM_MASK"

MACRO form_record
; \1 = base species constant, \2 = form index. Opens a record.
	ASSERT \2 >= 1 && \2 <= NUM_FORM_SLOTS, \
	       "form index out of range - MON_CATCH_RATE bits 5-6 hold 1..3"
	db \1, \2
ENDM

MACRO form_end
; Closes a record and proves it is exactly FORM_REC_SIZE bytes.
;
; NOT optional, and not belt-and-braces. ApplyFormOverride walks this table with
; a flat FORM_REC_SIZE stride, so a record that is one byte short or long does
; not fail loudly - it silently shifts every RECORD AFTER IT, and each one then
; reads its key from the middle of its predecessor's data. That is the same
; failure shape as the Mew hole in BaseStats (SPECIES_GROUPS_STATUS.md §5),
; where `assert_table_length` passed for 25 years while the table was misaligned.
; A count assert cannot see this; an offset assert can.
;
; Put this at the end of EVERY form record file. Increment 7 adds 51 more of
; them by hand, which is precisely when this will earn its keep.
	ASSERT (@ - FormOverrides) % FORM_REC_SIZE == 0, \
	       "form record is not FORM_REC_SIZE bytes - the table is now misaligned"
ENDM

; Form names use the same `dname` macro MonsterNames does - it pads to
; NAME_LENGTH - 1 with '@' and asserts the 10-character cap, which is exactly
; the stride the name hook copies.

; Form index allocation. Two bits give three non-zero forms per base species;
; TAUROS is the binding case and needs all three. Keep this table in sync as
; records are added - it is the only place the whole allocation is visible.
;
;   Base        form 1        form 2        form 3
;   ---------   -----------   -----------   -----------
;   MEOWTH      Alolan        Galarian      -
;   PERSIAN     Alolan        Perrserker    -
;   DIGLETT     Alolan        Wiglett       -
;   DUGTRIO     Alolan        Wugtrio       -
;   TENTACOOL   Toedscool     -             -
;   TENTACRUEL  Toedscruel    -             -
;   JIGGLYPUFF  Scream Tail   -             -
;   MAGNETON    Sandy Shocks  -             -
;   VAPOREON    Glaceon       Sylveon       -
;   JOLTEON     Espeon        Umbreon       -
;   FLAREON     Leafeon       -             -
;   TAUROS      P-Combat      P-Blaze       P-Aqua
;   (every other Group R base) its one regional variant

FormOverrides::
; Records must be dex-order-independent - ApplyFormOverride walks linearly and
; matches on (species, form), so order here is cosmetic. Group by base species.
INCLUDE "data/pokemon/forms/ameowth.asm"
INCLUDE "data/pokemon/forms/adugtrio.asm"

	db 0 ; terminator
