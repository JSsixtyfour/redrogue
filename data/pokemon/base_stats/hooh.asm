	db DEX_HO_OH ; pokedex id

	db 106, 130,  90,  90, 154
	;   hp  atk  def  spd  spc

	db FIRE, FLYING ; type
	db 3 ; catch rate
	db 220 ; base exp

	INCBIN "gfx/pokemon/front/hooh.pic", 0, 1 ; sprite dimensions
	dw HoOhPicFront, HoOhPicBack

	db EMBER, NO_MOVE, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_SLOW ; growth rate

	; tm/hm learnset - modeled on Moltres (legendary Fire/Flying)
	tmhm FLAMETHROWER, TOXIC,        TAKE_DOWN,    DOUBLE_EDGE,  HYPER_BEAM,   \
	     RAGE,         MIMIC,        DOUBLE_TEAM,  REFLECT,      BIDE,         \
	     FIRE_BLAST,   SWIFT,        SKY_ATTACK,   REST,         SUBSTITUTE,   \
	     FLY,          STRENGTH
	; end

	db BANK(HoOhPicFront) ; pic bank
