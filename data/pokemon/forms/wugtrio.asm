; Wugtrio - DUGTRIO form 2 (form 1 is Alolan, see adugtrio.asm).
;
; Paired with Dugtrio ('sea Dugtrio'): Water (single type in modern games).
; Special split: modern SpA 50 / SpD 70, take the HIGHER -> spc 70.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Dugtrio, same
; as the Espeon precedent.
	form_record DUGTRIO, 2

	db DEX_DUGTRIO ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  35, 100,  50, 120,  70
	;   hp  atk  def  spd  spc

	db WATER, WATER ; type
	db 50 ; catch rate
	db 153 ; base exp

	INCBIN "gfx/pokemon/front/wugtrio.pic", 0, 1 ; sprite dimensions
	dw WugtrioPicFront, WugtrioPicBack

	db SCRATCH, GROWL, DIG, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm TOXIC,        BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  HYPER_BEAM,   \
	     RAGE,         EARTHQUAKE,   FISSURE,      DIG,          MIMIC,        \
	     DOUBLE_TEAM,  BIDE,         REST,         ROCK_SLIDE,   SUBSTITUTE
	; end

	db BANK(WugtrioPicFront) ; pic bank

	dname "WUGTRIO"

	form_end
