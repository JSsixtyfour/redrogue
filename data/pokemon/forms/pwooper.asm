; Paldean Wooper - WOOPER form 1.
;
; Poison/Ground, both valid Gen 1 types. Stats unchanged from vanilla Wooper.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Wooper.
; Placeholder blank art per PHASE_2R_SONNET_SPEC.md section 2 - record written
; anyway, sprite is a separate task.
	form_record WOOPER, 1

	db DEX_WOOPER ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  55,  45,  45,  15,  25
	;   hp  atk  def  spd  spc

	db POISON, GROUND ; type
	db 255 ; catch rate
	db 52 ; base exp

	INCBIN "gfx/pokemon/front/pwooper.pic", 0, 1 ; sprite dimensions
	dw PWooperPicFront, PWooperPicBack

	db WATER_GUN, TAIL_WHIP, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm MEGA_PUNCH,   MEGA_KICK,    TOXIC,        BODY_SLAM,    TAKE_DOWN,    \
	     DOUBLE_EDGE,  BUBBLEBEAM,   WATER_GUN,    ICE_BEAM,     BLIZZARD,     \
	     HYPER_BEAM,   PAY_DAY,      SUBMISSION,   COUNTER,      SEISMIC_TOSS, \
	     RAGE,         DIG,          MIMIC,        DOUBLE_TEAM,  BIDE,         \
	     SWIFT,        SKULL_BASH,   REST,         SUBSTITUTE,   SURF,         \
	     STRENGTH,     LIGHT_SCREEN
	; end

	db BANK(PWooperPicFront) ; pic bank

	dname "P-WOOPER"

	form_end
