; Alolan Geodude - GEODUDE form 1.
;
; Rock/Electric. Stats identical to vanilla Geodude in modern games; sprite and
; typing are the only real differences here.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Geodude.
	form_record GEODUDE, 1

	db DEX_GEODUDE ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  40,  80, 100,  20,  30
	;   hp  atk  def  spd  spc

	db ROCK, ELECTRIC ; type
	db 255 ; catch rate
	db 86 ; base exp

	INCBIN "gfx/pokemon/front/ageodude.pic", 0, 1 ; sprite dimensions
	dw AGeodudePicFront, AGeodudePicBack

	db TACKLE, NO_MOVE, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_SLOW ; growth rate

	; tm/hm learnset
	tmhm MEGA_PUNCH,   TOXIC,        BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  \
	     SUBMISSION,   COUNTER,      SEISMIC_TOSS, RAGE,         EARTHQUAKE,   \
	     FISSURE,      DIG,          MIMIC,        DOUBLE_TEAM,  BIDE,         \
	     METRONOME,    SELFDESTRUCT, FIRE_BLAST,   REST,         EXPLOSION,    \
	     ROCK_SLIDE,   SUBSTITUTE,   STRENGTH,     FLAMETHROWER
	; end

	db BANK(AGeodudePicFront) ; pic bank

	dname "A-GEODUDE"

	form_end
