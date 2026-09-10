; Hisuian Sneasel - SNEASEL form 1.
;
; NOTE: this base/slot pairing is not listed in PHASE_2R_SONNET_SPEC.md section
; 3's table (an omission in that table, not a capacity problem - Sneasel's slot
; 1 is free, same as every other single-form regional base). Filled in here
; following the table's own stated default: 'every other Group R base -> its
; one regional variant' in slot 1.
;
; Fighting/Poison, both valid Gen 1 types.
; Special split: modern SpA 35 / SpD 75, take the HIGHER -> spc 75.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Sneasel.
; Placeholder blank art per PHASE_2R_SONNET_SPEC.md section 2 - record written
; anyway, sprite is a separate task.
	form_record SNEASEL, 1

	db DEX_SNEASEL ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  55,  95,  55, 115,  75
	;   hp  atk  def  spd  spc

	db FIGHTING, POISON ; type
	db 60 ; catch rate
	db 132 ; base exp

	INCBIN "gfx/pokemon/front/hsneasel.pic", 0, 1 ; sprite dimensions
	dw HSneaselPicFront, HSneaselPicBack

	db SCRATCH, LEER, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_SLOW ; growth rate

	; tm/hm learnset - modeled on Persian (fast Normal-type physical
	; attacker) plus Jynx's Ice-type coverage
	tmhm TOXIC,        BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  ICE_BEAM,     \
	     BLIZZARD,     HYPER_BEAM,   RAGE,         MIMIC,        DOUBLE_TEAM,  \
	     BIDE,         SWIFT,        SKULL_BASH,   REST,         SUBSTITUTE
	; end

	db BANK(HSneaselPicFront) ; pic bank

	dname "H-SNEASEL"

	form_end
