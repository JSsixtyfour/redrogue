	db DEX_FLAAFFY ; pokedex id

	db  70,  55,  55,  45,  80
	;   hp  atk  def  spd  spc

	db ELECTRIC, ELECTRIC ; type
	db 120 ; catch rate
	db 117 ; base exp

	INCBIN "gfx/pokemon/front/flaaffy.dim" ; sprite dimensions
	dw FlaaffyPicFront, FlaaffyPicBack

	db TACKLE, GROWL, THUNDERSHOCK, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_SLOW ; growth rate

	; tm/hm learnset
	tmhm TOXIC,        TAKE_DOWN,    RAGE,         THUNDERBOLT,  THUNDER,      \
	     LIGHT_SCREEN, MIMIC,        DOUBLE_TEAM,  REFLECT,      BIDE,         \
	     MEGA_PUNCH, SWIFT,        REST,         THUNDER_WAVE, MEGA_KICK,    \
	     SUBSTITUTE,   FLASH,        BODY_SLAM,    SUBMISSION,   SEISMIC_TOSS,  \
		 DOUBLE_EDGE,  DRAGON_RAGE,  STRENGTH,     COUNTER,      \  
	; end

	db BANK(FlaaffyPicFront) ; pic bank
