	db DEX_NATU ; pokedex id

	db  40,  50,  45,  70,  70
	;   hp  atk  def  spd  spc

	db PSYCHIC_TYPE, FLYING ; type
	db 190 ; catch rate
	db 73 ; base exp

	INCBIN "gfx/pokemon/front/natu.dim" ; sprite dimensions
	dw NatuPicFront, NatuPicBack

	db PECK, LEER, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm MEGA_DRAIN,   FLY,    TOXIC,        RAZOR_WIND,    SUBSTITUTE,     \
	     THUNDER_WAVE,  SWIFT,   DREAM_EATER,      REST, DREAM_EATER,         \
	     PSYCHIC_M,    LIGHT_SCREEN, MIMIC,        DOUBLE_TEAM,  REFLECT,      \
	     PSYWAVE                                                               \
	; end

	db BANK(NatuPicFront) ; pic bank
