	db DEX_PINECO ; pokedex id

	db  50,  65,  90,  15,  35
	;   hp  atk  def  spd  spc

	db BUG, BUG ; type
	db 190 ; catch rate
	db 60 ; base exp

	INCBIN "gfx/pokemon/front/pineco.dim" ; sprite dimensions
	dw PinecoPicFront, PinecoPicBack

	db TACKLE, SELFDESTRUCT, NO_MOVE, NO_MOVE ; level 1 learnset - PROTECT does not exist in Gen 1, dropped
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm SELFDESTRUCT, TOXIC,        BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  \
	     LIGHT_SCREEN,   RAGE,         MEGA_DRAIN,   SOLARBEAM,    DIG,          \
	     MIMIC,        DOUBLE_TEAM,  REFLECT,      BIDE,         SWIFT,   \
	     REST,         SUBSTITUTE,   STRENGTH,     ROCK_SLIDE,   EXPLOSION
	; end

	db BANK(PinecoPicFront) ; pic bank
