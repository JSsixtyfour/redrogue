	db DEX_GIRAFARIG ; pokedex id

	db  70,  80,  65,  85,  90
	;   hp  atk  def  spd  spc

	db NORMAL, PSYCHIC_TYPE ; type
	db 60 ; catch rate
	db 149 ; base exp

	INCBIN "gfx/pokemon/front/girafarig.dim" ; sprite dimensions
	dw GirafarigPicFront, GirafarigPicBack

	db TACKLE, GROWL, CONFUSION, STOMP ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm TOXIC,        BODY_SLAM,    TAKE_DOWN,    LIGHT_SCREEN, REFLECT,      \
	     DOUBLE_EDGE,  SWIFT,        DREAM_EATER,  THUNDER_WAVE, RAGE,         \
	     PSYWAVE,      STRENGTH,     PSYCHIC_M,    THUNDERBOLT,  THUNDER,      \
	     MIMIC,        SUBSTITUTE,   STRENGTH,     DOUBLE_TEAM,  BIDE,         \
	     SKULL_BASH,   REST,         EARTHQUAKE,   DIG
	       
	; end

	db BANK(GirafarigPicFront) ; pic bank
