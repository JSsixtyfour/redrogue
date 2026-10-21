	db DEX_SKIPLOOM ; pokedex id

	db  55,  45,  50,  80,  65
	;   hp  atk  def  spd  spc

	db GRASS, FLYING ; type
	db 120 ; catch rate
	db 136 ; base exp

	INCBIN "gfx/pokemon/front/skiploom.dim" ; sprite dimensions
	dw SkiploomPicFront, SkiploomPicBack

	db SPLASH, TAIL_WHIP, TACKLE, NO_MOVE ; level 1 learnset - SYNTHESIS dropped (RECOVER at Lv 16 covers healing)
	db GROWTH_MEDIUM_SLOW ; growth rate

	; tm/hm learnset
	tmhm SWORDS_DANCE, TOXIC,        TAKE_DOWN,    DOUBLE_EDGE,  RAGE,         \
	     MEGA_DRAIN,   SOLARBEAM,    MIMIC,        DOUBLE_TEAM,  REFLECT,      \
	     BIDE,         REST,         SUBSTITUTE,   CUT,          FLASH,        \
	     LIGHT_SCREEN
	; end

	db BANK(SkiploomPicFront) ; pic bank
