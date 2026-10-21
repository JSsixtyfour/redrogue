	db DEX_MISMAGIUS ; pokedex id

	db  60,  60,  60, 100, 105
	;   hp  atk  def  spd  spc

	db GHOST, GHOST ; type - mono Ghost, no Dark/Fairy/Steel involved
	db 45 ; catch rate
	db 187 ; base exp

	INCBIN "gfx/pokemon/front/mismagius.dim" ; sprite dimensions
	dw MismagiusPicFront, MismagiusPicBack

	db LICK, PSYWAVE, NO_MOVE, NO_MOVE ; level 1 learnset - PSYWAVE is canon Mismagius Lv 1 (Gen 4)
	db GROWTH_FAST ; growth rate - matches Misdreavus

	; tm/hm learnset - modeled on Gengar's (the closest Gen 1 Ghost-type)
	tmhm LIGHT_SCREEN, FLASH,        THUNDER_WAVE, TOXIC,        SUBSTITUTE,   \
	     SWIFT,        DOUBLE_EDGE,  HYPER_BEAM,   RAGE,         MEGA_DRAIN,   \
	     THUNDERBOLT,  THUNDER,      PSYCHIC_M,    MIMIC,        DOUBLE_TEAM,  \
	     BIDE,         MIMIC,        DOUBLE_TEAM,  BIDE,         DREAM_EATER,  \
	     REST,         PSYWAVE
	; end

	db BANK(MismagiusPicFront) ; pic bank
