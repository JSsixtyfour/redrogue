; Armored Mewtwo - MEWTWO form 1.
;
; Graphic only: stats, type, moves, growth and tmhm are Mewtwo's. Fielded ONLY
; by Giovanni's Challenge 11 (Legendary Boss) ace and handed over, armor kept,
; by his post-battle legendary trade (custom_functions/legendary_boss_helpers.asm).
; Never a rarity, reward, wild or trade-NPC pick: it has no rarity_mon entry.
	form_record MEWTWO, 1

	db DEX_MEWTWO ; pokedex id (documentation only - GetMonHeader overwrites
	             ; byte 0 with the species index right after the patch)

	db 106, 110,  90, 130, 154
	;   hp  atk  def  spd  spc

	db PSYCHIC_TYPE, PSYCHIC_TYPE ; type
	db 3 ; catch rate
	db 220 ; base exp

	INCBIN "gfx/pokemon/front/armoredmewtwo.dim" ; sprite dimensions
	dw ArmoredMewtwoPicFront, ArmoredMewtwoPicBack

	db CONFUSION, DISABLE, SWIFT, PSYCHIC_M ; level 1 learnset
	db GROWTH_SLOW ; growth rate

	; tm/hm learnset - Mewtwo's
	tmhm MEGA_PUNCH,   MEGA_KICK,    TOXIC,        BODY_SLAM,    TAKE_DOWN,    \
	     DOUBLE_EDGE,  BUBBLEBEAM,   WATER_GUN,    ICE_BEAM,     BLIZZARD,     \
	     HYPER_BEAM,   PAY_DAY,      SUBMISSION,   COUNTER,      SEISMIC_TOSS, \
	     RAGE,         SOLARBEAM,    THUNDERBOLT,  THUNDER,      PSYCHIC_M,    \
	     LIGHT_SCREEN, MIMIC,        DOUBLE_TEAM,  REFLECT,      BIDE,         \
	     METRONOME,    SELFDESTRUCT, FIRE_BLAST,   SWIFT,        SKULL_BASH,   \
	     REST,         THUNDER_WAVE, PSYWAVE,      TRI_ATTACK,   SUBSTITUTE,   \
	     STRENGTH,     FLASH,        FLAMETHROWER
	; end

	db BANK(ArmoredMewtwoPicFront) ; pic bank

	dname "MEWTWO"

	form_end PAL_GRAYMON
