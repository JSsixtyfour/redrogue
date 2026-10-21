	db DEX_SNEASEL ; pokedex id

	db  55,  95,  55, 115,  55
	;   hp  atk  def  spd  spc

	db NORMAL, ICE ; type - Dark (primary) -> Normal per project type rules
	db 60 ; catch rate
	db 132 ; base exp

	INCBIN "gfx/pokemon/front/sneasel.dim" ; sprite dimensions
	dw SneaselPicFront, SneaselPicBack

	db SCRATCH, LEER, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_SLOW ; growth rate

	; tm/hm learnset - modeled on Persian (fast Normal-type physical
	; attacker) plus Jynx's Ice-type coverage
	tmhm TOXIC,        SWORDS_DANCE, TAKE_DOWN,    DOUBLE_EDGE,  ICE_BEAM,     \
	     BLIZZARD,     RAGE,         MIMIC,        DOUBLE_TEAM,  BIDE,         \
	     SWIFT,        SKULL_BASH,   REST,         SUBSTITUTE,   MEGA_PUNCH,   \
	     MEGA_KICK,    COUNTER,      DIG,          CUT,          STRENGTH,     \
	     SURF,         REFLECT,      DREAM_EATER,  METRONOME,    HYPER_BEAM
	; end

	db BANK(SneaselPicFront) ; pic bank
