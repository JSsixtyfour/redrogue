	db DEX_FORRETRESS ; pokedex id

	db  75,  90, 140,  40,  60
	;   hp  atk  def  spd  spc

	db BUG, BUG ; type - Steel (secondary) dropped per project type rules
	db 75 ; catch rate
	db 118 ; base exp

	INCBIN "gfx/pokemon/front/forretress.dim" ; sprite dimensions
	dw ForretressPicFront, ForretressPicBack

	db TACKLE, SELFDESTRUCT, NO_MOVE, NO_MOVE ; level 1 learnset - PROTECT does not exist in Gen 1, dropped
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm SELFDESTRUCT, TOXIC,        BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  \
	     LIGHT_SCREEN, RAGE,         MEGA_DRAIN,   SOLARBEAM,    MIMIC,        \
	     DOUBLE_TEAM,  REFLECT,      BIDE,         SWIFT,        REST,         \
	     SUBSTITUTE,   STRENGTH,     ROCK_SLIDE,   EXPLOSION,    HYPER_BEAM
	; end

	db BANK(ForretressPicFront) ; pic bank
