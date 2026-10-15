	db DEX_XATU ; pokedex id

	db  65,  75,  70,  95,  95
	;   hp  atk  def  spd  spc

	db PSYCHIC_TYPE, FLYING ; type
	db 75 ; catch rate
	db 171 ; base exp

	INCBIN "gfx/pokemon/front/xatu.dim" ; sprite dimensions
	dw XatuPicFront, XatuPicBack

	db PECK, LEER, NIGHT_SHADE, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm MEGA_DRAIN,   FLY,    TOXIC,        RAZOR_WIND,    SUBSTITUTE,     \
	     THUNDER_WAVE,  SWIFT,   DREAM_EATER,      REST, DREAM_EATER,         \
	     PSYCHIC_M,    LIGHT_SCREEN, MIMIC,        DOUBLE_TEAM,  REFLECT,      \
	     PSYWAVE,      HYPER_BEAM
	; end

	db BANK(XatuPicFront) ; pic bank
