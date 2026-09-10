; Galarian Farfetch'd - FARFETCHD form 1.
;
; Fighting (single type in modern games).
; Special split: modern SpA 58 / SpD 62, take the HIGHER -> spc 62.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Farfetch'd.
; Name GFARFETCHD has no hyphen: 'G-FARFETCHD' is 11 characters, one over cap.
	form_record FARFETCHD, 1

	db DEX_FARFETCHD ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  52,  90,  55,  55,  62
	;   hp  atk  def  spd  spc

	db FIGHTING, FIGHTING ; type
	db 45 ; catch rate
	db 94 ; base exp

	INCBIN "gfx/pokemon/front/gfarfetchd.pic", 0, 1 ; sprite dimensions
	dw GFarfetchdPicFront, GFarfetchdPicBack

	db PECK, SAND_ATTACK, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm RAZOR_WIND,   SWORDS_DANCE, SUBSTITUTE,    TOXIC,        BODY_SLAM,    \
	     TAKE_DOWN,    DOUBLE_EDGE,  RAGE,         MIMIC,        DOUBLE_TEAM,  \
	     REFLECT,      BIDE,         SWIFT,        SKULL_BASH,   REST,         \
	     CUT,          FLY
	; end

	db BANK(GFarfetchdPicFront) ; pic bank

	dname "GFARFETCHD"

	form_end
