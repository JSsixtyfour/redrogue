	db DEX_WEAVILE ; pokedex id

	db  70, 120,  65, 125,  65
	;   hp  atk  def  spd  spc

	db NORMAL, ICE ; type - Dark (primary) -> Normal per project type rules
	db 45 ; catch rate
	db 199 ; base exp

	INCBIN "gfx/pokemon/front/weavile.dim" ; sprite dimensions
	dw WeavilePicFront, WeavilePicBack

	db SCRATCH, LEER, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_SLOW ; growth rate

	; tm/hm learnset
	tmhm SWORDS_DANCE, TOXIC,        BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  \
	     ICE_BEAM,     BLIZZARD,     HYPER_BEAM,   RAGE,         MIMIC,        \
	     DOUBLE_TEAM,  BIDE,         SWIFT,        SKULL_BASH,   REST,         \
	     SUBSTITUTE,   CUT
	; end

	db BANK(WeavilePicFront) ; pic bank
