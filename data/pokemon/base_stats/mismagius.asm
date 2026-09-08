	db DEX_MISMAGIUS ; pokedex id

	db  60,  60,  60, 100, 105
	;   hp  atk  def  spd  spc

	db GHOST, GHOST ; type - mono Ghost, no Dark/Fairy/Steel involved
	db 45 ; catch rate
	db 187 ; base exp

	INCBIN "gfx/pokemon/front/mismagius.pic", 0, 1 ; sprite dimensions
	dw MismagiusPicFront, MismagiusPicBack

	db LICK, METRONOME, NO_MOVE, NO_MOVE ; level 1 learnset - FILLER, expand later
	db GROWTH_MEDIUM_SLOW ; growth rate

	; tm/hm learnset - modeled on Gengar's (the closest Gen 1 Ghost-type)
	tmhm TOXIC,          MEGA_DRAIN,   MIMIC,        DOUBLE_TEAM,  BIDE,         \
	     METRONOME,      SKULL_BASH,   DREAM_EATER,  REST,         PSYWAVE,      \
	     SUBSTITUTE
	; end

	db BANK(MismagiusPicFront) ; pic bank
