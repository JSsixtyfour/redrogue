	db DEX_HOPPIP ; pokedex id

	db  35,  35,  40,  50,  55
	;   hp  atk  def  spd  spc

	db GRASS, FLYING ; type
	db 255 ; catch rate
	db 74 ; base exp

	INCBIN "gfx/pokemon/front/hoppip.pic", 0, 1 ; sprite dimensions
	dw HoppipPicFront, HoppipPicBack

	db SPLASH, METRONOME, NO_MOVE, NO_MOVE ; level 1 learnset - SYNTHESIS filled with METRONOME
	db GROWTH_MEDIUM_SLOW ; growth rate

	; tm/hm learnset
	tmhm SWORDS_DANCE, TOXIC,        TAKE_DOWN,    DOUBLE_EDGE,  RAGE,         \
	     MEGA_DRAIN,   SOLARBEAM,    MIMIC,        DOUBLE_TEAM,  REFLECT,      \
	     BIDE,         REST,         SUBSTITUTE,   CUT,          FLY
	; end

	db BANK(HoppipPicFront) ; pic bank
