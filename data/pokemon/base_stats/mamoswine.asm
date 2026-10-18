	db DEX_MAMOSWINE ; pokedex id

	db 110, 130,  80,  80,  70
	;   hp  atk  def  spd  spc

	db ICE, GROUND ; type - no Dark/Fairy/Steel involved, unchanged
	db 45 ; catch rate
	db 210 ; base exp

	INCBIN "gfx/pokemon/front/mamoswine.dim" ; sprite dimensions
	dw MamoswinePicFront, MamoswinePicBack

	db PECK, HORN_ATTACK, NO_MOVE, NO_MOVE ; level 1 learnset - FILLER, expand later
	db GROWTH_SLOW ; growth rate - matches Swinub and Piloswine

	; tm/hm learnset
	tmhm TOXIC,        BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  HYPER_BEAM,   \
	     ICE_BEAM,     BLIZZARD,     RAGE,         EARTHQUAKE,   FISSURE,      \
	     DIG,          MIMIC,        DOUBLE_TEAM,  BIDE,         SKULL_BASH,   \
	     REST,         SUBSTITUTE,   STRENGTH,     ROCK_SLIDE
	; end

	db BANK(MamoswinePicFront) ; pic bank
