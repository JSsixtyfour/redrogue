	db DEX_PHANPY ; pokedex id

	db  90,  60,  60,  40,  40
	;   hp  atk  def  spd  spc

	db GROUND, GROUND ; type
	db 120 ; catch rate
	db 124 ; base exp

	INCBIN "gfx/pokemon/front/phanpy.pic", 0, 1 ; sprite dimensions
	dw PhanpyPicFront, PhanpyPicBack

	db TACKLE, GROWL, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset - modeled on Rhyhorn (Ground)
	tmhm TOXIC,        BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  RAGE,         \
	     EARTHQUAKE,   FISSURE,      DIG,          MIMIC,        DOUBLE_TEAM,  \
	     BIDE,         SKULL_BASH,   REST,         SUBSTITUTE,   STRENGTH
	; end

	db BANK(PhanpyPicFront) ; pic bank
