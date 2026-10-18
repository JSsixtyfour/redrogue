; Galarian Zapdos - ZAPDOS form 1.
;
; Fighting/Flying, both valid Gen 1 types.
; Special split: modern SpA 85 / SpD 90, take the LOWER -> spc 85, so the total
; matches vanilla Zapdos's 490.
; ATK is the biggest stat jump: 125 vs vanilla Zapdos's 90.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Zapdos.
	form_record ZAPDOS, 1

	db DEX_ZAPDOS ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  90, 125,  90, 100,  85
	;   hp  atk  def  spd  spc

	db FIGHTING, FLYING ; type
	db 3 ; catch rate
	db 216 ; base exp

	INCBIN "gfx/pokemon/front/gzapdos.dim" ; sprite dimensions
	dw GZapdosPicFront, GZapdosPicBack

	db PECK, FOCUS_ENERGY, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_SLOW ; growth rate

	; tm/hm learnset
	tmhm RAZOR_WIND,   LIGHT_SCREEN, TOXIC,        TAKE_DOWN,    DOUBLE_EDGE,  \
	     HYPER_BEAM,   RAGE,         MEGA_KICK,    FLASH,      MIMIC,        \
	     DOUBLE_TEAM,  REFLECT,      BIDE,         SWIFT,        SKY_ATTACK,   \
	     REST,         COUNTER,      SUBSTITUTE,   FLY,        \
	; end

	db BANK(GZapdosPicFront) ; pic bank

	dname "G-ZAPDOS"

	form_end PAL_REDMON
