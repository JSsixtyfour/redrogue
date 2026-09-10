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
; Put this at the end of EVERY form record file. Increment 7 added 48 more of
; them by hand (SPECIES_GROUPS_STATUS.md §9h) and it fired correctly on every one.
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
;   SNEASEL     Hisuian       -             -
;   (every other Group R base) its one regional variant
;
; SNEASEL isn't listed in PHASE_2R_SONNET_SPEC.md section 3's table (an
; omission there, not a capacity problem) but follows the same one-slot
; default as every other single-form base; see hsneasel.asm.

FormOverrides::
; Records must be dex-order-independent - ApplyFormOverride walks linearly and
; matches on (species, form), so order here is cosmetic. Group by base species.
INCLUDE "data/pokemon/forms/ameowth.asm"
INCLUDE "data/pokemon/forms/gmeowth.asm"
INCLUDE "data/pokemon/forms/adugtrio.asm"
INCLUDE "data/pokemon/forms/wugtrio.asm"
INCLUDE "data/pokemon/forms/adiglett.asm"
INCLUDE "data/pokemon/forms/wiglett.asm"
INCLUDE "data/pokemon/forms/apersian.asm"
INCLUDE "data/pokemon/forms/perrserker.asm"
INCLUDE "data/pokemon/forms/espeon.asm"
INCLUDE "data/pokemon/forms/umbreon.asm"
INCLUDE "data/pokemon/forms/glaceon.asm"
INCLUDE "data/pokemon/forms/sylveon.asm"
INCLUDE "data/pokemon/forms/leafeon.asm"
INCLUDE "data/pokemon/forms/ptauroscombat.asm"
INCLUDE "data/pokemon/forms/ptaurosblaze.asm"
INCLUDE "data/pokemon/forms/ptaurosaqua.asm"
INCLUDE "data/pokemon/forms/toedscool.asm"
INCLUDE "data/pokemon/forms/toedscruel.asm"
INCLUDE "data/pokemon/forms/screamtail.asm"
INCLUDE "data/pokemon/forms/sandyshocks.asm"
INCLUDE "data/pokemon/forms/aexeggutor.asm"
INCLUDE "data/pokemon/forms/ageodude.asm"
INCLUDE "data/pokemon/forms/agolem.asm"
INCLUDE "data/pokemon/forms/agraveler.asm"
INCLUDE "data/pokemon/forms/agrimer.asm"
INCLUDE "data/pokemon/forms/amarowak.asm"
INCLUDE "data/pokemon/forms/amuk.asm"
INCLUDE "data/pokemon/forms/aninetales.asm"
INCLUDE "data/pokemon/forms/araichu.asm"
INCLUDE "data/pokemon/forms/araticate.asm"
INCLUDE "data/pokemon/forms/arattata.asm"
INCLUDE "data/pokemon/forms/asandshrew.asm"
INCLUDE "data/pokemon/forms/asandslash.asm"
INCLUDE "data/pokemon/forms/avulpix.asm"
INCLUDE "data/pokemon/forms/garticuno.asm"
INCLUDE "data/pokemon/forms/gfarfetchd.asm"
INCLUDE "data/pokemon/forms/gmoltres.asm"
INCLUDE "data/pokemon/forms/gmrmime.asm"
INCLUDE "data/pokemon/forms/gponyta.asm"
INCLUDE "data/pokemon/forms/grapidash.asm"
INCLUDE "data/pokemon/forms/gslowbro.asm"
INCLUDE "data/pokemon/forms/gslowking.asm"
INCLUDE "data/pokemon/forms/gslowpoke.asm"
INCLUDE "data/pokemon/forms/gweezing.asm"
INCLUDE "data/pokemon/forms/gzapdos.asm"
INCLUDE "data/pokemon/forms/harcanine.asm"
INCLUDE "data/pokemon/forms/helectrode.asm"
INCLUDE "data/pokemon/forms/hgrowlithe.asm"
INCLUDE "data/pokemon/forms/hqwilfish.asm"
INCLUDE "data/pokemon/forms/hsneasel.asm"
INCLUDE "data/pokemon/forms/hvoltorb.asm"
INCLUDE "data/pokemon/forms/pwooper.asm"

	db 0 ; terminator
