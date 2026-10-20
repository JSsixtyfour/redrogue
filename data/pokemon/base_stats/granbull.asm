	db DEX_GRANBULL ; pokedex id

	db  90, 120,  75,  45,  60
	;   hp  atk  def  spd  spc

	db NORMAL, NORMAL ; type
	db 75 ; catch rate
	db 178 ; base exp

	INCBIN "gfx/pokemon/front/granbull.dim" ; sprite dimensions
	dw GranbullPicFront, GranbullPicBack

	db TACKLE, LEER, TAIL_WHIP, NO_MOVE ; level 1 learnset
	db GROWTH_FAST ; growth rate

	; tm/hm learnset
	tmhm MEGA_PUNCH,   MEGA_KICK,    TOXIC,        BODY_SLAM,    TAKE_DOWN,    \
	     DOUBLE_EDGE,  DIG,          FLAMETHROWER, THUNDER_WAVE, REFLECT,      \
	     SOLARBEAM,   SUBMISSION,   COUNTER,      SEISMIC_TOSS, RAGE,         \
	     THUNDERBOLT,  THUNDER,      EARTHQUAKE,   METRONOME,      MIMIC,        \
	     DOUBLE_TEAM,  BIDE,         FIRE_BLAST,   SKULL_BASH,   REST,         \
	     SUBSTITUTE,   STRENGTH,     HYPER_BEAM
	; end

	db BANK(GranbullPicFront) ; pic bank
