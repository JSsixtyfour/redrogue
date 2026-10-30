; Paldean Wooper - WOOPER form 1. Restored 2026-10-29 with real art (cut
; 2026-10-15 while it had only placeholder art).
;
; Poison/Ground, both valid Gen 1 types. Stats unchanged from vanilla Wooper.
; Special split: modern SpA 25 / SpD 25, tie, so spc 25 either way.
; Catch rate/base exp/growth copied from Wooper. TM list is Wooper's minus
; the Water moves (Surf, BubbleBeam, Water Gun, Ice Beam) and Flash.
	form_record WOOPER, 1

	db DEX_WOOPER ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  55,  45,  45,  15,  25
	;   hp  atk  def  spd  spc

	db POISON, GROUND ; type
	db 255 ; catch rate
	db 52 ; base exp

	INCBIN "gfx/pokemon/front/pwooper.dim" ; sprite dimensions
	dw PWooperPicFront, PWooperPicBack

	db POISON_STING, TAIL_WHIP, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm TOXIC,        BODY_SLAM,    TAKE_DOWN,    STRENGTH,     DOUBLE_EDGE,  \
	     EARTHQUAKE,   RAGE,         DIG,          MIMIC,        DOUBLE_TEAM,  \
	     BIDE,         SKULL_BASH,   REST,         SUBSTITUTE,   SURF,         \
		 WATER_GUN,    BUBBLEBEAM,   FISSURE
	; end

	db BANK(PWooperPicFront) ; pic bank

	dname "P-WOOPER"

	form_end PAL_BROWNMON
