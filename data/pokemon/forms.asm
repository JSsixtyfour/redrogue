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
; \1 = base species constant, \2 = form index
	ASSERT \2 >= 1 && \2 <= NUM_FORM_SLOTS, \
	       "form index out of range - MON_CATCH_RATE bits 5-6 hold 1..3"
	db \1, \2
ENDM

; Form names use the same `dname` macro MonsterNames does - it pads to
; NAME_LENGTH - 1 with '@' and asserts the 10-character cap, which is exactly
; the stride the name hook copies.

FormOverrides::
; ---------------------------------------------------------------------------
; EMPTY BY DESIGN as of the first Phase 2R commit. The plan ships the machinery
; with a zero-length table first so the change is a provable no-op: with no
; records, ApplyFormOverride returns on its first compare and every mon in the
; game keeps exactly the header it had before. Populate this only after the
; plumbing is verified.
; ---------------------------------------------------------------------------
	db 0 ; terminator
