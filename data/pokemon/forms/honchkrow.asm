; Honchkrow - MURKROW form 1, evolved from Murkrow with a Dusk Stone.
; A distinct species stored as a form (numbered Pokedex row, DEX_FORM_HONCHKROW).
;
; Dark/Flying: primary Dark becomes NORMAL per the project type rules (as Murkrow).
; Stats from tmp/rpp/data/baseStats/honchkrow.asm (Special already collapsed:
; SpA 105 / SpD 52, the higher). Catch rate and base exp from the same file.
; Growth rate must match Murkrow's: the evolution keeps the experience total.
	form_record MURKROW, 1

	db DEX_MURKROW ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db 100, 125,  52,  71, 105
	;   hp  atk  def  spd  spc

	db NORMAL, FLYING ; type
	db 30 ; catch rate
	db 177 ; base exp

	INCBIN "gfx/pokemon/front/honchkrow.dim" ; sprite dimensions
	dw HonchkrowPicFront, HonchkrowPicBack

	db PECK, GUST, HAZE, WING_ATTACK ; level 1 learnset
	db GROWTH_MEDIUM_SLOW ; growth rate

	; tm/hm learnset - Murkrow's plus Hyper Beam
	tmhm RAZOR_WIND,   SUBSTITUTE,   TOXIC,        TAKE_DOWN,    DOUBLE_EDGE,  \
	     RAGE,         MIMIC,        DOUBLE_TEAM,  REFLECT,      BIDE,         \
	     SWIFT,        SKY_ATTACK,   REST,         FLY,          THUNDER_WAVE, \
	     DREAM_EATER,  HYPER_BEAM
	; end

	db BANK(HonchkrowPicFront) ; pic bank

	dname "HONCHKROW"

	form_end PAL_GRAYMON
