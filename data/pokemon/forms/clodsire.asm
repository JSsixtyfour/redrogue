; Clodsire - QUAGSIRE form 1, evolved from Paldean Wooper (WOOPER form 1).
;
; Poison/Ground, both valid Gen 1 types.
; Special split: modern SpA 45 / SpD 100, take the HIGHER -> spc 100.
; Catch rate/base exp/growth copied from Quagsire. TM list is Paldean
; Wooper's plus Hyper Beam, Fissure and Rock Slide (Quagsire's extras that
; are not Water or arm moves).
	form_record QUAGSIRE, 1

	db DEX_QUAGSIRE ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db 130,  75,  60,  20, 100
	;   hp  atk  def  spd  spc

	db POISON, GROUND ; type
	db 90 ; catch rate
	db 137 ; base exp

	INCBIN "gfx/pokemon/front/clodsire.dim" ; sprite dimensions
	dw ClodsirePicFront, ClodsirePicBack

	db POISON_STING, TAIL_WHIP, TACKLE, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm TOXIC,        BODY_SLAM,    TAKE_DOWN,    STRENGTH,     DOUBLE_EDGE,  \
	     HYPER_BEAM,   EARTHQUAKE,   FISSURE,      DIG,          ROCK_SLIDE,   \
	     RAGE,         MIMIC,        DOUBLE_TEAM,  BIDE,         SKULL_BASH,   \
	     REST,         SUBSTITUTE
	; end

	db BANK(ClodsirePicFront) ; pic bank

	dname "CLODSIRE"

	form_end PAL_BROWNMON
