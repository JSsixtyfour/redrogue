	db DEX_AMPHAROS ; pokedex id

	db  90,  75,  75,  55, 115
	;   hp  atk  def  spd  spc

	db ELECTRIC, ELECTRIC ; type
	db 45 ; catch rate
	db 194 ; base exp

	INCBIN "gfx/pokemon/front/ampharos.pic", 0, 1 ; sprite dimensions
	dw AmpharosPicFront, AmpharosPicBack

	db TACKLE, GROWL, THUNDERSHOCK, THUNDER_WAVE ; level 1 learnset
	db GROWTH_MEDIUM_SLOW ; growth rate

	; tm/hm learnset
	tmhm TOXIC,        TAKE_DOWN,    DOUBLE_EDGE,  HYPER_BEAM,   RAGE,         \
	     THUNDERBOLT,  THUNDER,      LIGHT_SCREEN, MIMIC,        DOUBLE_TEAM,  \
	     REFLECT,      BIDE,         SELFDESTRUCT, SWIFT,        REST,         \
	     THUNDER_WAVE, EXPLOSION,    SUBSTITUTE,   FLASH
	; end

	db BANK(AmpharosPicFront) ; pic bank
