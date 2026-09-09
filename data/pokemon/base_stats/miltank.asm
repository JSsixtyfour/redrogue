	db DEX_MILTANK ; pokedex id

	db  95,  80, 105, 100,  70
	;   hp  atk  def  spd  spc

	db NORMAL, NORMAL ; type
	db 45 ; catch rate
	db 200 ; base exp

	INCBIN "gfx/pokemon/front/miltank.pic", 0, 1 ; sprite dimensions
	dw MiltankPicFront, MiltankPicBack

	db TACKLE, NO_MOVE, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_SLOW ; growth rate

	; tm/hm learnset - modeled on Chansey/Snorlax (defensive Normal-type)
	tmhm MEGA_PUNCH,   MEGA_KICK,    TOXIC,        BODY_SLAM,    TAKE_DOWN,    \
	     DOUBLE_EDGE,  HYPER_BEAM,   SEISMIC_TOSS, RAGE,         EARTHQUAKE,   \
	     MIMIC,        DOUBLE_TEAM,  REFLECT,      BIDE,         SELFDESTRUCT, \
	     REST,         SUBSTITUTE,   SURF,         STRENGTH
	; end

	db BANK(MiltankPicFront) ; pic bank
