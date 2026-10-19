	db DEX_AMPHAROS ; pokedex id

	db  90,  75,  75,  55, 115
	;   hp  atk  def  spd  spc

	db ELECTRIC, ELECTRIC ; type
	db 45 ; catch rate
	db 194 ; base exp

	INCBIN "gfx/pokemon/front/ampharos.dim" ; sprite dimensions
	dw AmpharosPicFront, AmpharosPicBack

	db TACKLE, GROWL, THUNDERSHOCK, THUNDER_WAVE ; level 1 learnset
	db GROWTH_MEDIUM_SLOW ; growth rate

	; tm/hm learnset
	tmhm TOXIC,        TAKE_DOWN,    RAGE,         THUNDERBOLT,  THUNDER,      \
	     LIGHT_SCREEN, MIMIC,        DOUBLE_TEAM,  REFLECT,      BIDE,         \
	     MEGA_PUNCH, SWIFT,        REST,         THUNDER_WAVE, MEGA_KICK,    \
	     SUBSTITUTE,   FLASH,        BODY_SLAM,    SUBMISSION,   SEISMIC_TOSS,  \
		 DOUBLE_EDGE,  DRAGON_RAGE,  DIG,          HYPER_BEAM,   STRENGTH,     \
		 COUNTER
	; end

	db BANK(AmpharosPicFront) ; pic bank
