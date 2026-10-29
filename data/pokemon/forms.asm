; Species Groups Phase 2R - form override records.
;
; A form record patches wMonHeader AFTER GetMonHeader has copied the base
; species' row, so a form gets its own stats, both types, catch rate, base exp,
; pic size, front/back pic pointers, PIC BANK, starting moves, growth rate and
; TM/HM compatibility - everything that lives in the 28-byte base-stats struct.
; The level-up learnset is form-aware too (Phase 2, Species Groups form
; learnsets): GetEvosMovesEntry (engine/pokemon/get_levelup_moves.asm) resolves
; FormEvosMovesPointers (data/pokemon/form_evos_moves.asm) whenever the loaded
; header carries a form, falling back to the species' own EvosMovesPointerTable
; entry otherwise. Only the tutor learnset stays species-keyed - form records
; carry no tutor block by design, so a form keeps its base species' tutor moves.
;
; Record layout is FORM_REC_* in constants/pokemon_data_constants.asm:
;   db <base species>, <form index 1..NUM_FORM_SLOTS>
;   <BASE_DATA_SIZE bytes: an ordinary base-stats row>
;   <10 name characters, no terminator>
;   <1 palette byte, PAL_*MON, emitted by form_end>
;
; The table is walked linearly by ApplyFormOverride and terminated by a 0
; species byte. Linear is fine: the walk only runs when a mon actually has
; non-zero form bits, which is never true for any of the 252 ordinary species.

; NAME_LENGTH is in scope here but not in pokemon_data_constants.asm (include
; order), so this is where the two are tied together.
ASSERT FORM_REC_NAME_LEN == NAME_LENGTH - 1, \
       "form record name field must match the MonsterNames stride"
ASSERT FORM_REC_SIZE == 2 + BASE_DATA_SIZE + FORM_REC_NAME_LEN + 1, \
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
; \1 = the form's palette (PAL_*MON). Closes a record and proves it is exactly
; FORM_REC_SIZE bytes.
;
; The palette is an argument rather than a free `db` line so a record cannot
; forget it. It must be a MON palette: ShinyPaletteConvert only permutes
; PAL_MEWMON..PAL_GRAYMON, so anything else would make the shiny look identical.
	ASSERT \1 >= PAL_MEWMON && \1 <= PAL_GRAYMON, \
	       "form palette must be one of the PAL_*MON palettes"
	db \1
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
;   MEWTWO      Armored       -             -
;   AERODACTYL  Fossil        -             -      (cemetery ghost boss only)
;   KABUTOPS    Fossil        -             -      (cemetery ghost boss only)
;   (every other Group R base) its one regional variant
;
; Hisuian Sneasel, Paldean Wooper and Hisuian Qwilfish were cut 2026-10-15:
; placeholder art only, and their evolutions (Sneasler, Clodsire, Overqwil)
; do not exist here.

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
INCLUDE "data/pokemon/forms/hvoltorb.asm"
INCLUDE "data/pokemon/forms/armoredmewtwo.asm"
INCLUDE "data/pokemon/forms/fossilaerodactyl.asm"
INCLUDE "data/pokemon/forms/fossilkabutops.asm"

	db 0 ; terminator

; ===========================================================================
; Which species-group unlock each form rides on - Phase 2R increment 8c.
;
; Forms are expansion content and must never appear in a base Kanto run, even
; though most records hang off KANTO base species (Meowth, Dugtrio,
; Moltres, Tauros...). Without this, Alolan Meowth shows up on turn one of a
; fresh game - which is exactly what testing found.
;
; The rule is GENERATIONAL, by design: Gen 2 content unlocks with
; JOHTO, everything Gen 4 and later with KANTO TIME WARP.
;
; That makes Warp the default for every other record, so only the Johto
; exceptions are listed here. A form absent from this table is a Warp form. A new
; record therefore needs no edit here unless it is Gen 2.
FormJohtoPairs::
	db JOLTEON, 1 ; Espeon  - Gen 2
	db JOLTEON, 2 ; Umbreon - Gen 2
FormJohtoPairsEnd::
; Everything else is Time Warp: Glaceon/Leafeon (Gen 4), Sylveon (Gen 6), all
; Alolan (Gen 7), Galarian/Hisuian/Perrserker (Gen 8), Paldean and the
; convergents/paradoxes (Gen 9).

; ===========================================================================
 ; Rarity picks are explicit in engine/pokemon/rarity.asm. There is no form
; substitution chance or separate tier override lottery. Evolution-only forms
; are documented beside their tier there and reached through their predecessor.
