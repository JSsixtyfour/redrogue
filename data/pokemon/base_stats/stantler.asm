	db DEX_STANTLER ; pokedex id

	db  73,  95,  62,  85,  85
	;   hp  atk  def  spd  spc

	db NORMAL, NORMAL ; type
	db 45 ; catch rate
	db 165 ; base exp

	INCBIN "gfx/pokemon/front/stantler.pic", 0, 1 ; sprite dimensions
	dw StantlerPicFront, StantlerPicBack

	db TACKLE, NO_MOVE, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_SLOW ; growth rate

	; tm/hm learnset - modeled on Kangaskhan (Normal-type)
	tmhm MEGA_PUNCH,   MEGA_KICK,    TOXIC,        BODY_SLAM,    TAKE_DOWN,    \
	     DOUBLE_EDGE,  HYPER_BEAM,   SUBMISSION,   COUNTER,      SEISMIC_TOSS, \
	     RAGE,         EARTHQUAKE,   MIMIC,        DOUBLE_TEAM,  BIDE,         \
	     REST,         ROCK_SLIDE,   SUBSTITUTE,   STRENGTH
	; end

	db BANK(StantlerPicFront) ; pic bank
