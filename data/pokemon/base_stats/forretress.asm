	db DEX_FORRETRESS ; pokedex id

	db  75,  90, 140,  40,  60
	;   hp  atk  def  spd  spc

	db BUG, BUG ; type - Steel (secondary) dropped per project type rules
	db 75 ; catch rate
	db 118 ; base exp

	INCBIN "gfx/pokemon/front/forretress.pic", 0, 1 ; sprite dimensions
	dw ForretressPicFront, ForretressPicBack

	db TACKLE, METRONOME, SELFDESTRUCT, NO_MOVE ; level 1 learnset - PROTECT filled with METRONOME
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm SWORDS_DANCE, TOXIC,        BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  \
	     HYPER_BEAM,   RAGE,         MEGA_DRAIN,   SOLARBEAM,    DIG,          \
	     MIMIC,        DOUBLE_TEAM,  REFLECT,      BIDE,         SKULL_BASH,   \
	     REST,         SUBSTITUTE,   CUT,          LIGHT_SCREEN
	; end

	db BANK(ForretressPicFront) ; pic bank
