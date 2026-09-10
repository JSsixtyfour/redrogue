; Alolan Persian - PERSIAN form 1.
;
; Dark (single type in modern games). PRIMARY Dark becomes NORMAL, matching
; vanilla Persian's typing.
; Special split: modern SpA 115 / SpD 60, take the HIGHER -> spc 115.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Persian.
; Form 2 on this base is Perrserker - see perrserker.asm.
	form_record PERSIAN, 1

	db DEX_PERSIAN ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  65,  60,  60, 115, 115
	;   hp  atk  def  spd  spc

	db NORMAL, NORMAL ; type
	db 90 ; catch rate
	db 148 ; base exp

	INCBIN "gfx/pokemon/front/apersian.pic", 0, 1 ; sprite dimensions
	dw APersianPicFront, APersianPicBack

	db SCRATCH, GROWL, BITE, SCREECH ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm TOXIC,        BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  BUBBLEBEAM,   \
	     WATER_GUN,    HYPER_BEAM,   PAY_DAY,      RAGE,         THUNDERBOLT,  \
	     THUNDER,      MIMIC,        DOUBLE_TEAM,  BIDE,         SWIFT,        \
	     SKULL_BASH,   REST,         SUBSTITUTE
	; end

	db BANK(APersianPicFront) ; pic bank

	dname "A-PERSIAN"

	form_end
