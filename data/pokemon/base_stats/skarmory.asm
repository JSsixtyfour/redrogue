	db DEX_SKARMORY ; pokedex id

	db  65,  80, 140,  70,  70
	;   hp  atk  def  spd  spc

	db ROCK, FLYING ; type - Steel (primary) -> Rock per project type rules
	db 25 ; catch rate
	db 168 ; base exp

	INCBIN "gfx/pokemon/front/skarmory.pic", 0, 1 ; sprite dimensions
	dw SkarmoryPicFront, SkarmoryPicBack

	db LEER, PECK, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_SLOW ; growth rate

	; tm/hm learnset - modeled on Aerodactyl (Rock/Flying)
	tmhm RAZOR_WIND,   TOXIC,        TAKE_DOWN,    DOUBLE_EDGE,  HYPER_BEAM,   \
	     RAGE,         MIMIC,        DOUBLE_TEAM,  REFLECT,      BIDE,         \
	     SWIFT,        SKY_ATTACK,   REST,         SUBSTITUTE,   FLY
	; end

	db BANK(SkarmoryPicFront) ; pic bank
