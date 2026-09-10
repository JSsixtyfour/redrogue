; Galarian Ponyta - PONYTA form 1.
;
; Psychic (single type in modern games).
; Special split: modern SpA 65 / SpD 65, tie either way -> spc 65.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Ponyta.
	form_record PONYTA, 1

	db DEX_PONYTA ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  50,  85,  55,  90,  65
	;   hp  atk  def  spd  spc

	db PSYCHIC_TYPE, PSYCHIC_TYPE ; type
	db 190 ; catch rate
	db 152 ; base exp

	INCBIN "gfx/pokemon/front/gponyta.pic", 0, 1 ; sprite dimensions
	dw GPonytaPicFront, GPonytaPicBack

	db EMBER, NO_MOVE, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm TOXIC,        HORN_DRILL,   BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  \
	     RAGE,         MIMIC,        DOUBLE_TEAM,  REFLECT,      BIDE,         \
	     FIRE_BLAST,   SWIFT,        SKULL_BASH,   REST,         SUBSTITUTE,   \
         FLAMETHROWER
	; end

	db BANK(GPonytaPicFront) ; pic bank

	dname "G-PONYTA"

	form_end
