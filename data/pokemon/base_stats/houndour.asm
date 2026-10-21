	db DEX_HOUNDOUR ; pokedex id

	db  45,  60,  30,  65,  80
	;   hp  atk  def  spd  spc

	db NORMAL, FIRE ; type - Dark (primary) -> Normal per project type rules
	db 120 ; catch rate
	db 114 ; base exp

	INCBIN "gfx/pokemon/front/houndour.dim" ; sprite dimensions
	dw HoundourPicFront, HoundourPicBack

	db LEER, EMBER, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_SLOW ; growth rate

	; tm/hm learnset - modeled on Ninetales (Fire)
	tmhm TOXIC,        BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  COUNTER,      \
	     RAGE,         SOLARBEAM,    DIG,          MIMIC,        DOUBLE_TEAM,  \
	     REFLECT,      BIDE,         FIRE_BLAST,   SWIFT,        SKULL_BASH,   \
	     DREAM_EATER,  REST,         SUBSTITUTE,   FLAMETHROWER
	; end

	db BANK(HoundourPicFront) ; pic bank
