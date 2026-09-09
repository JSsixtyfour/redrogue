	db DEX_URSARING ; pokedex id

	db  90, 130,  75,  55,  75
	;   hp  atk  def  spd  spc

	db NORMAL, NORMAL ; type
	db 60 ; catch rate
	db 189 ; base exp

	INCBIN "gfx/pokemon/front/ursaring.pic", 0, 1 ; sprite dimensions
	dw UrsaringPicFront, UrsaringPicBack

	db SCRATCH, LEER, LICK, FURY_SWIPES ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset - modeled on Kangaskhan (Normal-type physical attacker)
	tmhm MEGA_PUNCH,   MEGA_KICK,    TOXIC,        BODY_SLAM,    TAKE_DOWN,    \
	     DOUBLE_EDGE,  HYPER_BEAM,   SUBMISSION,   COUNTER,      SEISMIC_TOSS, \
	     RAGE,         EARTHQUAKE,   MIMIC,        DOUBLE_TEAM,  BIDE,         \
	     REST,         ROCK_SLIDE,   SUBSTITUTE,   STRENGTH
	; end

	db BANK(UrsaringPicFront) ; pic bank
