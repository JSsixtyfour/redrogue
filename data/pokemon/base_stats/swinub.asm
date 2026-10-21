	db DEX_SWINUB ; pokedex id

	db  50,  50,  40,  50,  30
	;   hp  atk  def  spd  spc

	db ICE, GROUND ; type
	db 225 ; catch rate
	db 78 ; base exp

	INCBIN "gfx/pokemon/front/swinub.dim" ; sprite dimensions
	dw SwinubPicFront, SwinubPicBack

	db TACKLE, NO_MOVE, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_SLOW ; growth rate

	; tm/hm learnset
	tmhm TOXIC,        BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  ICE_BEAM,     \
	     BLIZZARD,     RAGE,         EARTHQUAKE,   FISSURE,      MIMIC,        \
	     DOUBLE_TEAM,  BIDE,         SKULL_BASH,   REST,         SUBSTITUTE,   \
	     STRENGTH,     ROCK_SLIDE
	; end

	db BANK(SwinubPicFront) ; pic bank
