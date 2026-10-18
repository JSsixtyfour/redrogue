; Paldean Tauros (Blaze Breed) - TAUROS form 2.
;
; Fighting/Fire, both valid Gen 1 types.
; Stats are 75/110/105/100/60, shared by all three breeds (the modern breeds
; share one spread too). Speed 100 and spc 60 are set so the total matches
; vanilla Tauros's 450. Only the secondary type differs from the other breeds.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Tauros.
	form_record TAUROS, 2

	db DEX_TAUROS ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  75, 110, 105, 100,  60
	;   hp  atk  def  spd  spc

	db FIGHTING, FIRE ; type
	db 45 ; catch rate
	db 211 ; base exp

	INCBIN "gfx/pokemon/front/ptaurosblaze.dim" ; sprite dimensions
	dw PTaurosBlazePicFront, PTaurosBlazePicBack

	db TACKLE, NO_MOVE, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_SLOW ; growth rate

	; tm/hm learnset
	tmhm TOXIC,        HORN_DRILL,   BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  \
	     ICE_BEAM,     BLIZZARD,     HYPER_BEAM,   RAGE,         THUNDERBOLT,  \
	     THUNDER,      EARTHQUAKE,   FISSURE,      MIMIC,        DOUBLE_TEAM,  \
	     BIDE,         FIRE_BLAST,   SKULL_BASH,   REST,         SUBSTITUTE,   \
	     STRENGTH,     FLAMETHROWER, MEGA_KICK
	; end

	db BANK(PTaurosBlazePicFront) ; pic bank

	dname "B-TAUROS"

	form_end PAL_REDMON
