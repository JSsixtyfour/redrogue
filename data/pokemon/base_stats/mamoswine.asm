	db DEX_MAMOSWINE ; pokedex id

	db 110, 130,  80,  80,  70
	;   hp  atk  def  spd  spc

	db ICE, GROUND ; type - no Dark/Fairy/Steel involved, unchanged
	db 45 ; catch rate
	db 210 ; base exp

	INCBIN "gfx/pokemon/front/mamoswine.pic", 0, 1 ; sprite dimensions
	dw MamoswinePicFront, MamoswinePicBack

	db PECK, NO_MOVE, NO_MOVE, NO_MOVE ; level 1 learnset - FILLER, expand later
	db GROWTH_MEDIUM_SLOW ; growth rate

	; tm/hm learnset
	tmhm SWORDS_DANCE, TOXIC,        BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  \
	     RAGE,         EARTHQUAKE,   FISSURE,      DIG,          MIMIC,        \
	     DOUBLE_TEAM,  BIDE,         REST,         SUBSTITUTE,   BLIZZARD
	; end

	db BANK(MamoswinePicFront) ; pic bank
