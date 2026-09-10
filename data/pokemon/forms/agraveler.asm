; Alolan Graveler - GRAVELER form 1.
;
; Rock/Electric. Stats identical to vanilla Graveler in modern games.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Graveler.
	form_record GRAVELER, 1

	db DEX_GRAVELER ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  55,  95, 115,  35,  45
	;   hp  atk  def  spd  spc

	db ROCK, ELECTRIC ; type
	db 120 ; catch rate
	db 134 ; base exp

	INCBIN "gfx/pokemon/front/agraveler.pic", 0, 1 ; sprite dimensions
	dw AGravelerPicFront, AGravelerPicBack

	db TACKLE, DEFENSE_CURL, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_SLOW ; growth rate

	; tm/hm learnset
	tmhm MEGA_PUNCH,   TOXIC,        BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  \
	     SUBMISSION,   COUNTER,      SEISMIC_TOSS, RAGE,         EARTHQUAKE,   \
	     FISSURE,      DIG,          MIMIC,        DOUBLE_TEAM,  BIDE,         \
	     METRONOME,    SELFDESTRUCT, FIRE_BLAST,   REST,         EXPLOSION,    \
	     ROCK_SLIDE,   SUBSTITUTE,   STRENGTH,     FLAMETHROWER
	; end

	db BANK(AGravelerPicFront) ; pic bank

	dname "A-GRAVELER"

	form_end
