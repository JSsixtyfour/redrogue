; Alolan Sandshrew - SANDSHREW form 1.
;
; Ice/Steel. SECONDARY Steel is DROPPED, leaving ICE/ICE.
; Special split: modern SpA 10 / SpD 35, take the HIGHER -> spc 35.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Sandshrew.
; Name ASANDSHREW has no hyphen: 'A-SANDSHREW' is 11 characters, one over cap.
	form_record SANDSHREW, 1

	db DEX_SANDSHREW ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  50,  75,  90,  40,  35
	;   hp  atk  def  spd  spc

	db ICE, ICE ; type
	db 255 ; catch rate
	db 93 ; base exp

	INCBIN "gfx/pokemon/front/asandshrew.pic", 0, 1 ; sprite dimensions
	dw ASandshrewPicFront, ASandshrewPicBack

	db SCRATCH, NO_MOVE, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm SWORDS_DANCE, TOXIC,        BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  \
	     SUBMISSION,   SEISMIC_TOSS, RAGE,         EARTHQUAKE,   FISSURE,      \
	     DIG,          MIMIC,        DOUBLE_TEAM,  BIDE,         SWIFT,        \
	     SKULL_BASH,   REST,         ROCK_SLIDE,   SUBSTITUTE,   CUT,          \
	     STRENGTH
	; end

	db BANK(ASandshrewPicFront) ; pic bank

	dname "ASANDSHREW"

	form_end
