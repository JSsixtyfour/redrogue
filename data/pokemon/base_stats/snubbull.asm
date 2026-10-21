	db DEX_SNUBBULL ; pokedex id

	db  60,  80,  50,  30,  40
	;   hp  atk  def  spd  spc

	db NORMAL, NORMAL ; type
	db 190 ; catch rate
	db 63 ; base exp

	INCBIN "gfx/pokemon/front/snubbull.dim" ; sprite dimensions
	dw SnubbullPicFront, SnubbullPicBack

	db TACKLE, LEER, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_FAST ; growth rate

	; tm/hm learnset
	tmhm MEGA_PUNCH,   MEGA_KICK,    TOXIC,        BODY_SLAM,    TAKE_DOWN,    \
	     DOUBLE_EDGE,  FLAMETHROWER, THUNDER_WAVE, REFLECT,      SUBMISSION,   \
	     COUNTER,      SEISMIC_TOSS, RAGE,         THUNDERBOLT,  THUNDER,      \
	     METRONOME,    MIMIC,        DOUBLE_TEAM,  BIDE,         SKULL_BASH,   \
	     REST,         SUBSTITUTE,   STRENGTH
	; end

	db BANK(SnubbullPicFront) ; pic bank
