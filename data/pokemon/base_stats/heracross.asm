	db DEX_HERACROSS ; pokedex id

	db  80, 125,  75,  85,  95
	;   hp  atk  def  spd  spc

	db BUG, FIGHTING ; type
	db 45 ; catch rate
	db 200 ; base exp

	INCBIN "gfx/pokemon/front/heracross.dim" ; sprite dimensions
	dw HeracrossPicFront, HeracrossPicBack

	db TACKLE, LEER, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_SLOW ; growth rate

	; tm/hm learnset - modeled on Machamp/Primeape (Fighting-type physical
	; attackers)
	tmhm MEGA_PUNCH,   MEGA_KICK,    TOXIC,        BODY_SLAM,    TAKE_DOWN,    \
	     DOUBLE_EDGE,  SUBMISSION,   COUNTER,      SEISMIC_TOSS, RAGE,         \
	     MIMIC,        DOUBLE_TEAM,  BIDE,         EARTHQUAKE,   SKULL_BASH,   \
	     REST,         SUBSTITUTE,   CUT,          STRENGTH,     ROCK_SLIDE,   \
	     SWORDS_DANCE
	; end

	db BANK(HeracrossPicFront) ; pic bank
