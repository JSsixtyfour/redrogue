	db DEX_HOUNDOOM ; pokedex id

	db  75,  90,  50,  95, 110
	;   hp  atk  def  spd  spc

	db NORMAL, FIRE ; type - Dark (primary) -> Normal per project type rules
	db 45 ; catch rate
	db 204 ; base exp

	INCBIN "gfx/pokemon/front/houndoom.pic", 0, 1 ; sprite dimensions
	dw HoundoomPicFront, HoundoomPicBack

	db LEER, EMBER, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_SLOW ; growth rate

	; tm/hm learnset - modeled on Ninetales/Arcanine (Fire)
	tmhm TOXIC,        BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  HYPER_BEAM,   \
	     RAGE,         DIG,          MIMIC,        DOUBLE_TEAM,  REFLECT,      \
	     BIDE,         FIRE_BLAST,   SWIFT,        SKULL_BASH,   REST,         \
	     SUBSTITUTE,   FLAMETHROWER
	; end

	db BANK(HoundoomPicFront) ; pic bank
