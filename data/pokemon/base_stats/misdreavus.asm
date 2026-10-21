	db DEX_MISDREAVUS ; pokedex id

	db  60,  60,  60,  85,  85
	;   hp  atk  def  spd  spc

	db GHOST, GHOST ; type
	db 45 ; catch rate
	db 147 ; base exp

	INCBIN "gfx/pokemon/front/misdreavus.dim" ; sprite dimensions
	dw MisdreavusPicFront, MisdreavusPicBack

	db GROWL, PSYWAVE, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_FAST ; growth rate

	; tm/hm learnset
	tmhm LIGHT_SCREEN, FLASH,        THUNDER_WAVE, TOXIC,        DOUBLE_EDGE,  \
	     RAGE,         MEGA_DRAIN,   THUNDERBOLT,  THUNDER,      PSYCHIC_M,    \
	     MIMIC,        DOUBLE_TEAM,  BIDE,         MIMIC,        DOUBLE_TEAM,  \
	     BIDE,         DREAM_EATER,  REST,         PSYWAVE,      SWIFT,        \
	     SUBSTITUTE
	; end

	db BANK(MisdreavusPicFront) ; pic bank
