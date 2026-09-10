; Alolan Vulpix - VULPIX form 1.
;
; Ice (single type in modern games). No secondary type to drop.
; Special split: modern SpA 50 / SpD 65, take the HIGHER -> spc 65.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Vulpix.
	form_record VULPIX, 1

	db DEX_VULPIX ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  38,  41,  40,  65,  65
	;   hp  atk  def  spd  spc

	db ICE, ICE ; type
	db 190 ; catch rate
	db 63 ; base exp

	INCBIN "gfx/pokemon/front/avulpix.pic", 0, 1 ; sprite dimensions
	dw AVulpixPicFront, AVulpixPicBack

	db EMBER, TAIL_WHIP, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm TOXIC,        BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  RAGE,         \
	     DIG,          MIMIC,        DOUBLE_TEAM,  REFLECT,      BIDE,         \
	     FIRE_BLAST,   SWIFT,        SKULL_BASH,   REST,         SUBSTITUTE,   \
         FLAMETHROWER
	; end

	db BANK(AVulpixPicFront) ; pic bank

	dname "A-VULPIX"

	form_end
