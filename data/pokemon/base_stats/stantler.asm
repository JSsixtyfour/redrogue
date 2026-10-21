	db DEX_STANTLER ; pokedex id

	db  73,  95,  62,  85,  85
	;   hp  atk  def  spd  spc

	db NORMAL, NORMAL ; type
	db 45 ; catch rate
	db 165 ; base exp

	INCBIN "gfx/pokemon/front/stantler.dim" ; sprite dimensions
	dw StantlerPicFront, StantlerPicBack

	db TACKLE, NO_MOVE, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_SLOW ; growth rate

	; tm/hm learnset - modeled on Kangaskhan (Normal-type)
	tmhm LIGHT_SCREEN, TOXIC,        BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  \
	     RAGE,         THUNDERBOLT,  EARTHQUAKE,   PSYCHIC_M,    MIMIC,        \
	     DOUBLE_TEAM,  REFLECT,      BIDE,         SWIFT,        DREAM_EATER,  \
	     REST,         THUNDER_WAVE, SUBSTITUTE,   STRENGTH,     FLASH,        \
         PSYWAVE,      HYPER_BEAM
	; end

	db BANK(StantlerPicFront) ; pic bank
