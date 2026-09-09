	db DEX_MANTINE ; pokedex id

	db  65,  40,  70,  70, 140
	;   hp  atk  def  spd  spc

	db WATER, FLYING ; type
	db 25 ; catch rate
	db 168 ; base exp

	INCBIN "gfx/pokemon/front/mantine.pic", 0, 1 ; sprite dimensions
	dw MantinePicFront, MantinePicBack

	db TACKLE, BUBBLE, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_SLOW ; growth rate

	; tm/hm learnset - modeled on Gyarados (Water)
	tmhm TOXIC,        BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  BUBBLEBEAM,   \
	     WATER_GUN,    ICE_BEAM,     BLIZZARD,     HYPER_BEAM,   RAGE,         \
	     MIMIC,        DOUBLE_TEAM,  REFLECT,      BIDE,         SKULL_BASH,   \
	     REST,         SUBSTITUTE,   SURF,         FLY
	; end

	db BANK(MantinePicFront) ; pic bank
