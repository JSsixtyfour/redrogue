	db DEX_MAGCARGO ; pokedex id

	db  50,  50, 120,  30,  80
	;   hp  atk  def  spd  spc

	db FIRE, ROCK ; type
	db 75 ; catch rate
	db 154 ; base exp

	INCBIN "gfx/pokemon/front/magcargo.pic", 0, 1 ; sprite dimensions
	dw MagcargoPicFront, MagcargoPicBack

	db SMOG, EMBER, ROCK_THROW, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset - modeled on Ninetales (Fire) plus Rock coverage
	tmhm TOXIC,        BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  HYPER_BEAM,   \
	     RAGE,         MIMIC,        DOUBLE_TEAM,  REFLECT,      BIDE,         \
	     FIRE_BLAST,   SKULL_BASH,   REST,         ROCK_SLIDE,   SUBSTITUTE,   \
	     STRENGTH,     FLAMETHROWER
	; end

	db BANK(MagcargoPicFront) ; pic bank
