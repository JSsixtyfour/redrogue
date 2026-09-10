; Alolan Rattata - RATTATA form 1.
;
; Dark/Normal. PRIMARY Dark becomes NORMAL; secondary Normal is unaffected.
; Special split: modern SpA 25 / SpD 35, take the HIGHER -> spc 35.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Rattata.
	form_record RATTATA, 1

	db DEX_RATTATA ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  30,  56,  35,  72,  35
	;   hp  atk  def  spd  spc

	db NORMAL, NORMAL ; type
	db 255 ; catch rate
	db 57 ; base exp

	INCBIN "gfx/pokemon/front/arattata.pic", 0, 1 ; sprite dimensions
	dw ARattataPicFront, ARattataPicBack

	db TACKLE, TAIL_WHIP, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm TOXIC,        BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  BUBBLEBEAM,   \
	     WATER_GUN,    BLIZZARD,     RAGE,         THUNDERBOLT,  THUNDER,      \
	     DIG,          MIMIC,        DOUBLE_TEAM,  BIDE,         SWIFT,        \
	     SKULL_BASH,   REST,         SUBSTITUTE
	; end

	db BANK(ARattataPicFront) ; pic bank

	dname "A-RATTATA"

	form_end
