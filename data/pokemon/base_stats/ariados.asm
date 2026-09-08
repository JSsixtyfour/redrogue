	db DEX_ARIADOS ; pokedex id

	db  70,  90,  70,  40,  60
	;   hp  atk  def  spd  spc

	db BUG, POISON ; type
	db 90 ; catch rate
	db 134 ; base exp

	INCBIN "gfx/pokemon/front/ariados.pic", 0, 1 ; sprite dimensions
	dw AriadosPicFront, AriadosPicBack

	db POISON_STING, STRING_SHOT, METRONOME, CONSTRICT ; level 1 learnset - SCARY_FACE filled with METRONOME
	db GROWTH_FAST ; growth rate

	; tm/hm learnset
	tmhm TOXIC,        TAKE_DOWN,    DOUBLE_EDGE,  RAGE,         MEGA_DRAIN,   \
	     SOLARBEAM,    PSYCHIC_M,    MIMIC,        DOUBLE_TEAM,  REFLECT,      \
	     BIDE,         REST,         PSYWAVE,      SUBSTITUTE
	; end

	db BANK(AriadosPicFront) ; pic bank
