	db DEX_YANMA ; pokedex id

	db  65,  65,  45,  95,  75
	;   hp  atk  def  spd  spc

	db BUG, FLYING ; type
	db 75 ; catch rate
	db 147 ; base exp

	INCBIN "gfx/pokemon/front/yanma.pic", 0, 1 ; sprite dimensions
	dw YanmaPicFront, YanmaPicBack

	db TACKLE, METRONOME, NO_MOVE, NO_MOVE ; level 1 learnset - FORESIGHT filled with METRONOME
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm RAZOR_WIND,   SUBSTITUTE,   TOXIC,        TAKE_DOWN,    DOUBLE_EDGE,  \
	     HYPER_BEAM,   RAGE,         MEGA_DRAIN,   SOLARBEAM,    PSYCHIC_M,    \
	     PSYWAVE,      MIMIC,        DOUBLE_TEAM,  REFLECT,      BIDE,         \
	     SWIFT,        REST,         FLY
	; end

	db BANK(YanmaPicFront) ; pic bank
