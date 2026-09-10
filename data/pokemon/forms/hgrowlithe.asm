; Hisuian Growlithe - GROWLITHE form 1.
;
; Fire/Rock, both valid Gen 1 types.
; Special split: modern SpA 65 / SpD 50, take the HIGHER -> spc 65.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Growlithe.
; Name HGROWLITHE has no hyphen: 'H-GROWLITHE' is 11 characters, one over cap.
	form_record GROWLITHE, 1

	db DEX_GROWLITHE ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  55,  75,  45,  60,  65
	;   hp  atk  def  spd  spc

	db FIRE, ROCK ; type
	db 190 ; catch rate
	db 91 ; base exp

	INCBIN "gfx/pokemon/front/hgrowlithe.pic", 0, 1 ; sprite dimensions
	dw HGrowlithePicFront, HGrowlithePicBack

	db BITE, NO_MOVE, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_SLOW ; growth rate

	; tm/hm learnset
	tmhm TOXIC,        BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  RAGE,         \
	     DRAGON_RAGE,  DIG,          MIMIC,        DOUBLE_TEAM,  REFLECT,      \
	     BIDE,         FIRE_BLAST,   SWIFT,        SKULL_BASH,   REST,         \
	     SUBSTITUTE,   FLAMETHROWER
	; end

	db BANK(HGrowlithePicFront) ; pic bank

	dname "HGROWLITHE"

	form_end
