; Alolan Meowth - MEOWTH form 1.
;
; The reference implementation for Phase 2R form records. Every other form file
; copies this shape exactly; see data/pokemon/forms.asm for the record layout
; and data/pokemon/base_stats/meowth.asm for the base species it overrides.
;
; Transcription rules applied (SPECIES_GROUPS_PLAN.md §6 "Type rules"):
;  - Alolan Meowth is Dark in modern games. PRIMARY Dark becomes NORMAL here, so
;    the typing ends up identical to vanilla Meowth. That is correct, not a
;    missed edit.
;  - Special split: modern SpA 50 / SpD 40, take the HIGHER -> spc 50.
;  - Base exp kept at Meowth's 69: the two forms have the same 290 BST.
;  - TM/HM list kept identical - Gen 1 has no Dark-type TMs to differentiate.
;
; So this form differs from vanilla Meowth in exactly four observable ways:
; ATK 45 -> 35, SPC 40 -> 50, the sprite, and the name. All four are worth
; checking in the emulator, because each one exercises a different part of the
; override path.
	form_record MEOWTH, 1

	db DEX_MEOWTH ; pokedex id - byte 0 is overwritten with the species index by
	              ; GetMonHeader immediately after the patch, exactly as it is
	              ; for an ordinary species, so this is documentation only.

	db  40,  35,  35,  90,  50
	;   hp  atk  def  spd  spc

	db NORMAL, NORMAL ; type (primary Dark -> Normal per the type rules)
	db 255 ; catch rate
	db 69 ; base exp

	INCBIN "gfx/pokemon/front/ameowth.pic", 0, 1 ; sprite dimensions
	dw AMeowthPicFront, AMeowthPicBack

	db SCRATCH, GROWL, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm TOXIC,        BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  BUBBLEBEAM,   \
	     WATER_GUN,    PAY_DAY,      RAGE,         THUNDERBOLT,  THUNDER,      \
	     MIMIC,        DOUBLE_TEAM,  BIDE,         SWIFT,        SKULL_BASH,   \
	     REST,         SUBSTITUTE
	; end

	db BANK(AMeowthPicFront) ; pic bank

	dname "A-MEOWTH"

	form_end
