; Alolan Golem - GOLEM form 1.
;
; Rock/Electric. Special split: modern SpA 55 / SpD 65, take the HIGHER -> spc 65.
; ATK is the stat that differs most: 120 vs vanilla Golem's 110.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Golem.
	form_record GOLEM, 1

	db DEX_GOLEM ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  80, 120, 130,  45,  65
	;   hp  atk  def  spd  spc

	db ROCK, ELECTRIC ; type
	db 45 ; catch rate
	db 177 ; base exp

	INCBIN "gfx/pokemon/front/agolem.pic", 0, 1 ; sprite dimensions
	dw AGolemPicFront, AGolemPicBack

	db TACKLE, DEFENSE_CURL, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_SLOW ; growth rate

	; tm/hm learnset
	tmhm MEGA_PUNCH,   MEGA_KICK,    TOXIC,        BODY_SLAM,    TAKE_DOWN,    \
	     DOUBLE_EDGE,  HYPER_BEAM,   SUBMISSION,   COUNTER,      SEISMIC_TOSS, \
	     RAGE,         EARTHQUAKE,   FISSURE,      DIG,          MIMIC,        \
	     DOUBLE_TEAM,  BIDE,         METRONOME,    SELFDESTRUCT, FIRE_BLAST,   \
	     REST,         EXPLOSION,    ROCK_SLIDE,   SUBSTITUTE,   STRENGTH,     \
         FLAMETHROWER
	; end

	db BANK(AGolemPicFront) ; pic bank

	dname "A-GOLEM"

	form_end
