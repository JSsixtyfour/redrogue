; Fossil Aerodactyl - AERODACTYL form 1 (FOSSIL_FORM).
;
; Graphic only: the cemetery ghost boss's look when it rolls Aerodactyl
; (PCemRollBoss), kept by the gifted mon. Everything else is Aerodactyl's own
; row verbatim; the ghost type and move come from PCemApplyGhostBoss as for any
; other boss. Never a rarity, reward, wild or trade-NPC pick: it has no
; rarity_mon entry. If Aerodactyl's base stats or tmhm change, copy them here.
	form_record AERODACTYL, 1 ; FOSSIL_FORM (literal: tools/balance/parse.py and the tests read a number)

	db DEX_AERODACTYL ; pokedex id (documentation only - GetMonHeader overwrites
	                  ; byte 0 with the species index right after the patch)

	db  80, 105,  65, 130,  60
	;   hp  atk  def  spd  spc

	db ROCK, FLYING ; type
	db 45 ; catch rate
	db 202 ; base exp

	INCBIN "gfx/pokemon/front/fossilaerodactyl.dim" ; sprite dimensions
	dw FossilAerodactylPicFront, FossilAerodactylPicBack

	db WING_ATTACK, AGILITY, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_SLOW ; growth rate

	; tm/hm learnset - Aerodactyl's
	tmhm RAZOR_WIND,   FLAMETHROWER, TOXIC,        TAKE_DOWN,    DOUBLE_EDGE,  \
	     HYPER_BEAM,   RAGE,         DRAGON_RAGE,  MIMIC,        DOUBLE_TEAM,  \
	     REFLECT,      BIDE,         FIRE_BLAST,   SWIFT,        SKY_ATTACK,   \
	     REST,         ROCK_SLIDE,   SUBSTITUTE,   FLY
	; end

	db BANK(FossilAerodactylPicFront) ; pic bank

	dname "AERODACTYL"

	form_end PAL_PURPLEMON
