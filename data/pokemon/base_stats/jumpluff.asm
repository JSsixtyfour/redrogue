	db DEX_JUMPLUFF ; pokedex id

	db  75,  55,  70, 110,  85
	;   hp  atk  def  spd  spc

	db GRASS, FLYING ; type
	db 45 ; catch rate
	db 176 ; base exp

	INCBIN "gfx/pokemon/front/jumpluff.pic", 0, 1 ; sprite dimensions
	dw JumpluffPicFront, JumpluffPicBack

	db SPLASH, METRONOME, TAIL_WHIP, TACKLE ; level 1 learnset - SYNTHESIS filled with METRONOME
	db GROWTH_MEDIUM_SLOW ; growth rate

	; tm/hm learnset
	tmhm SWORDS_DANCE, TOXIC,        TAKE_DOWN,    DOUBLE_EDGE,  RAGE,         \
	     MEGA_DRAIN,   SOLARBEAM,    MIMIC,        DOUBLE_TEAM,  REFLECT,      \
	     BIDE,         REST,         SUBSTITUTE,   CUT,          FLY
	; end

	db BANK(JumpluffPicFront) ; pic bank
