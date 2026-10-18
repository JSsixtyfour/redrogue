; Alolan Golem - GOLEM form 1.
;
; Rock/Electric. Stats are identical to vanilla Golem (modern Alolan Golem's
; ATK 120 is lowered to 110 so the total matches Golem's 420).
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Golem.
	form_record GOLEM, 1

	db DEX_GOLEM ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  80, 110, 130,  45,  55
	;   hp  atk  def  spd  spc

	db ROCK, ELECTRIC ; type
	db 45 ; catch rate
	db 177 ; base exp

	INCBIN "gfx/pokemon/front/agolem.dim" ; sprite dimensions
	dw AGolemPicFront, AGolemPicBack

	db TACKLE, DEFENSE_CURL, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_SLOW ; growth rate

	; tm/hm learnset
	tmhm THUNDER,   MEGA_KICK,    TOXIC,        BODY_SLAM,    TAKE_DOWN,    \
	     DOUBLE_EDGE,  HYPER_BEAM,   SUBMISSION,   COUNTER,      SEISMIC_TOSS, \
	     RAGE,         EARTHQUAKE,   FISSURE,      DIG,          MIMIC,        \
	     DOUBLE_TEAM,  BIDE,         FLASH,    SELFDESTRUCT, FIRE_BLAST,   \
	     REST,         EXPLOSION,    ROCK_SLIDE,   SUBSTITUTE,   STRENGTH,     \
         FLAMETHROWER, THUNDER_WAVE, THUNDERBOLT
	; end

	db BANK(AGolemPicFront) ; pic bank

	dname "A-GOLEM"

	form_end PAL_GRAYMON
