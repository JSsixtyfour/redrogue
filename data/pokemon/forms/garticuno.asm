; Galarian Articuno - ARTICUNO form 1.
;
; Psychic/Flying, both valid Gen 1 types.
; Special split: modern SpA 125 / SpD 100, take the HIGHER -> spc 125.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Articuno.
	form_record ARTICUNO, 1

	db DEX_ARTICUNO ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  90,  85,  90, 95, 125
	;   hp  atk  def  spd  spc

	db PSYCHIC_TYPE, FLYING ; type
	db 3 ; catch rate
	db 215 ; base exp

	INCBIN "gfx/pokemon/front/garticuno.dim" ; sprite dimensions
	dw GArticunoPicFront, GArticunoPicBack

	db PECK, NO_MOVE, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_SLOW ; growth rate

	; tm/hm learnset
	tmhm RAZOR_WIND,   LIGHT_SCREEN, TOXIC,        TAKE_DOWN,    DOUBLE_EDGE,  \
	     DREAM_EATER,  SUBSTITUTE,   REST,         SKY_ATTACK,   HYPER_BEAM,   \
	     RAGE,         MIMIC,        DOUBLE_TEAM,  REFLECT,      BIDE,         \
	     SWIFT,        FLY
	; end

	db BANK(GArticunoPicFront) ; pic bank

	dname "G-ARTICUNO"

	form_end PAL_PURPLEMON
