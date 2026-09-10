; Alolan Sandslash - SANDSLASH form 1.
;
; Ice/Steel. SECONDARY Steel is DROPPED, leaving ICE/ICE.
; Special split: modern SpA 25 / SpD 65, take the HIGHER -> spc 65.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Sandslash.
; Name ASANDSLASH has no hyphen: 'A-SANDSLASH' is 11 characters, one over cap.
	form_record SANDSLASH, 1

	db DEX_SANDSLASH ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  75, 100, 120,  65,  65
	;   hp  atk  def  spd  spc

	db ICE, ICE ; type
	db 90 ; catch rate
	db 163 ; base exp

	INCBIN "gfx/pokemon/front/asandslash.pic", 0, 1 ; sprite dimensions
	dw ASandslashPicFront, ASandslashPicBack

	db SCRATCH, SAND_ATTACK, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm SWORDS_DANCE, TOXIC,        BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  \
	     HYPER_BEAM,   SUBMISSION,   SEISMIC_TOSS, RAGE,         EARTHQUAKE,   \
	     FISSURE,      DIG,          MIMIC,        DOUBLE_TEAM,  BIDE,         \
	     SWIFT,        SKULL_BASH,   REST,         ROCK_SLIDE,   SUBSTITUTE,   \
	     CUT,          STRENGTH
	; end

	db BANK(ASandslashPicFront) ; pic bank

	dname "ASANDSLASH"

	form_end
