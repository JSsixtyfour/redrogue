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

; ===========================================================================
; Form rarity overrides - Phase 2R increment 8b.
;
; A form's rarity is its BASE SPECIES' rarity by default, and for 47 of the 48
; records that is correct. Measured 2026-09-09: every form except one lands
; within -15..+40 base-stat-total of the species it hangs off, because Gen 1
; folds SpA/SpD into a single Special (this file takes the HIGHER of the two),
; which collapses most of the modern power gap. Sandy Shocks is modern-BST 570
; but converts to 405 against Magneton's 395; Toedscruel and the Paldean Tauros
; trio come out dead level with their bases.
;
; SCREAM TAIL is the exception, and it is a big one: 505 against Jigglypuff's
; 225. Jigglypuff sits in the Kanto POKEBALL tier - the commonest pool in the
; game - so inheriting its base's rarity would let the single most common roll
; hand out a paradox mon.
;
; This table is the fix. A (species, form) pair listed under a tier:
;   1. is EXCLUDED from the ordinary per-species form roll, so it can never be
;      reached from its base species' tier, and
;   2. becomes reachable as a direct pick at the tier it is listed under,
;      overriding the species that tier's list would otherwise have rolled.
;
; Point 2 is why gating alone is not enough. Jigglypuff is never rolled at
; masterball tier, so a form that is merely BLOCKED at low tiers would become
; unreachable rather than rare.
;
; It deliberately does NOT live in engine/pokemon/rarity.asm. Those lists are
; scanned by species byte by RogueClassifySpecies to map an owned mon back to
; its tier, and a second `db JIGGLYPUFF` in another tier would make every owned
; Jigglypuff classify ambiguously. Keeping form rarity in its own table leaves
; classification untouched.
;
; Only exceptions belong here. A form that sits within a reasonable distance of
; its base does NOT need an entry - leave it out and it inherits, which keeps
; adding a new form record a one-file job.
; ===========================================================================

MACRO form_tier
; \1 = list label. Requires \1 and \1_End. Entries are (species, form) pairs.
	ASSERT (\1_End - \1) % 2 == 0, "form tier list must be whole (species, form) pairs"
	db (\1_End - \1) / 2 ; pair count
	dw \1
ENDM

FormTierTable::
	form_tier FormTierPokeball
	form_tier FormTierGreatball
	form_tier FormTierUltraball
	form_tier FormTierMasterball
	form_tier FormTierUber
FormTierTableEnd:
ASSERT FormTierTableEnd - FormTierTable == NUM_RARITY_TIERS * FORM_TIER_ENTRY_SIZE, \
       "FormTierTable needs exactly one entry per rarity tier"

; The five lists below MUST stay contiguous and in this order. The exclusion
; scan in RogueRollFormForSpecies walks FormTierPairs..FormTierPairsEnd as one
; flat array of pairs rather than re-walking the five-entry table above, which
; is both cheaper and immune to a tier being added without the scan noticing.
FormTierPairs::
FormTierPokeball:
FormTierPokeball_End:
FormTierGreatball:
FormTierGreatball_End:
FormTierUltraball:
FormTierUltraball_End:
FormTierMasterball:
	db JIGGLYPUFF, 1 ; Scream Tail - 505 BST hanging off a 225 BST base
FormTierMasterball_End:
FormTierUber:
FormTierUber_End:
FormTierPairsEnd::
