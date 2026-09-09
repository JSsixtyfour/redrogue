	db DEX_REMORAID ; pokedex id

	db  35,  65,  35,  65,  65
	;   hp  atk  def  spd  spc

	db WATER, WATER ; type
	db 190 ; catch rate
	db 78 ; base exp

	INCBIN "gfx/pokemon/front/remoraid.pic", 0, 1 ; sprite dimensions
	dw RemoraidPicFront, RemoraidPicBack

	db WATER_GUN, NO_MOVE, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset - modeled on Tentacruel (Water)
	tmhm TOXIC,        TAKE_DOWN,    DOUBLE_EDGE,  BUBBLEBEAM,   WATER_GUN,    \
	     ICE_BEAM,     BLIZZARD,     HYPER_BEAM,   RAGE,         MIMIC,        \
	     DOUBLE_TEAM,  BIDE,         SKULL_BASH,   REST,         SUBSTITUTE,   \
	     SURF
	; end

	db BANK(RemoraidPicFront) ; pic bank
