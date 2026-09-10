; Hisuian Voltorb - VOLTORB form 1.
;
; Electric/Grass, both valid Gen 1 types.
; Special split: modern SpA 55 / SpD 55, tie either way -> spc 55.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Voltorb.
	form_record VOLTORB, 1

	db DEX_VOLTORB ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  40,  30,  50, 100,  55
	;   hp  atk  def  spd  spc

	db ELECTRIC, GRASS ; type
	db 190 ; catch rate
	db 103 ; base exp

	INCBIN "gfx/pokemon/front/hvoltorb.pic", 0, 1 ; sprite dimensions
	dw HVoltorbPicFront, HVoltorbPicBack

	db TACKLE, SCREECH, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm TOXIC,        TAKE_DOWN,    RAGE,         THUNDERBOLT,  THUNDER,      \
	     LIGHT_SCREEN, MIMIC,        DOUBLE_TEAM,  REFLECT,      BIDE,         \
	     SELFDESTRUCT, SWIFT,        REST,         THUNDER_WAVE, EXPLOSION,    \
	     SUBSTITUTE,   FLASH
	; end

	db BANK(HVoltorbPicFront) ; pic bank

	dname "H-VOLTORB"

	form_end
