	db DEX_CORSOLA ; pokedex id

	db  55,  55,  85,  35,  85
	;   hp  atk  def  spd  spc

	db WATER, ROCK ; type
	db 60 ; catch rate
	db 113 ; base exp

	INCBIN "gfx/pokemon/front/corsola.pic", 0, 1 ; sprite dimensions
	dw CorsolaPicFront, CorsolaPicBack

	db TACKLE, NO_MOVE, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_FAST ; growth rate

	; tm/hm learnset - modeled on Golduck (Water) plus Rock coverage
	tmhm TOXIC,        BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  BUBBLEBEAM,   \
	     WATER_GUN,    ICE_BEAM,     BLIZZARD,     HYPER_BEAM,   RAGE,         \
	     MIMIC,        DOUBLE_TEAM,  BIDE,         SKULL_BASH,   REST,         \
	     ROCK_SLIDE,   SUBSTITUTE,   SURF,         STRENGTH
	; end

	db BANK(CorsolaPicFront) ; pic bank
