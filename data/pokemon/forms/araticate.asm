; Alolan Raticate - RATICATE form 1.
;
; Dark/Normal. PRIMARY Dark becomes NORMAL; secondary Normal is unaffected.
; Special split: modern SpA 40 / SpD 80, take the HIGHER -> spc 80.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Raticate.
	form_record RATICATE, 1

	db DEX_RATICATE ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  75,  71,  70,  77,  80
	;   hp  atk  def  spd  spc

	db NORMAL, NORMAL ; type
	db 90 ; catch rate
	db 116 ; base exp

	INCBIN "gfx/pokemon/front/araticate.pic", 0, 1 ; sprite dimensions
	dw ARaticatePicFront, ARaticatePicBack

	db TACKLE, TAIL_WHIP, QUICK_ATTACK, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm TOXIC,        BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  BUBBLEBEAM,   \
	     WATER_GUN,    ICE_BEAM,     BLIZZARD,     HYPER_BEAM,   RAGE,         \
	     THUNDERBOLT,  THUNDER,      DIG,          MIMIC,        DOUBLE_TEAM,  \
	     BIDE,         SWIFT,        SKULL_BASH,   REST,         SUBSTITUTE
	; end

	db BANK(ARaticatePicFront) ; pic bank

	dname "A-RATICATE"

	form_end
