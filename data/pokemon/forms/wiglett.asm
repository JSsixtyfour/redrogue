; Wiglett - DIGLETT form 2 (form 1 is Alolan, see adiglett.asm).
;
; Paired with Diglett ('sea Diglett'): Water (single type in modern games).
; Special split: modern SpA 35 / SpD 25, take the HIGHER -> spc 35.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Diglett, same
; as the Espeon precedent.
	form_record DIGLETT, 2

	db DEX_DIGLETT ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  10,  55,  25,  95,  35
	;   hp  atk  def  spd  spc

	db WATER, WATER ; type
	db 255 ; catch rate
	db 81 ; base exp

	INCBIN "gfx/pokemon/front/wiglett.pic", 0, 1 ; sprite dimensions
	dw WiglettPicFront, WiglettPicBack

	db SCRATCH, NO_MOVE, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm TOXIC,        BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  RAGE,         \
	     EARTHQUAKE,   FISSURE,      DIG,          MIMIC,        DOUBLE_TEAM,  \
	     BIDE,         REST,         ROCK_SLIDE,   SUBSTITUTE
	; end

	db BANK(WiglettPicFront) ; pic bank

	dname "WIGLETT"

	form_end
