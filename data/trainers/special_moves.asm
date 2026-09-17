; Yellow entry format:
;	db trainerclass, trainerid
;	repeat { db partymon location, partymon move, move id }
;	db 0

SpecialTrainerMoves:
	db BROCK, 1
	db 2, 3, BIDE ;Onix has bide in the third slot
	db 0

	db MISTY, 1
	db 2, 3, BUBBLEBEAM ;Starmie has Bubblebeam in the third slot
	db 0

	db LT_SURGE, 1
	db 3, 3, THUNDERBOLT ;Raichu has Thunderbolt in the third slot
	db 0

	db ERIKA, 1
	db 3, 3, MEGA_DRAIN ;Vileplume has Mega Drain in the third slot
	db 0

	db KOGA, 1
	db 4, 3, TOXIC ;Weezing has Toxic in the third slot
	db 0

	db BLAINE, 1
	db 4, 3, FIRE_BLAST ; Arcanine has Fire Blast in the third slot
	db 0

	db SABRINA, 1
	db 4, 3, PSYWAVE ; Alakazam has Psywave in the third slot
	db 0

	db GIOVANNI, 3
	db 5, 3, FISSURE ; Rhydon has Fissure in the third slot
	db 0

	db LORELEI, 1
	db 5, 3, BLIZZARD ; Lapras has Blizzard in the third slot
	db 0

	db BRUNO, 1
	db 5, 3, FISSURE ; Machamp has Fissure in the third slot
	db 0

	db AGATHA, 1
	db 5, 3, TOXIC ; Gengar 2 has Toxic in the third slot
	db 0

	db LANCE, 1
	db 5, 3, BARRIER ; Dragonite has Barrier in the third slot
	db 0

	db RIVAL3, 1 ; Blastoise Team
	db 1, 3, SKY_ATTACK ; Pidgeot has Sky Attack in the third slot
	db 6, 3, BLIZZARD ; Blastoise has Blizzard in the third slot
	db 0

	db RIVAL3, 2 ; Venusaur Team
	db 1, 3, SKY_ATTACK ; Pidgeot has Sky Attack in the third slot
	db 6, 3, MEGA_DRAIN ; Venusaur has Mega Drain in the third slot
	db 0

	db RIVAL3, 3 ; Charizard Team
	db 1, 3, SKY_ATTACK ; Pidgeot has Sky Attack in the third slot
	db 6, 3, FIRE_BLAST ; Charizard has Fire Blast in the third slot
	db 0

; Phase 7f: donor move records from reference/yellow_legacy/joy_jenny/options.asm
; (cRz-Shadows/Pokemon_Yellow_Legacy), kept verbatim - only the trainer id
; changed. wTrainerNo 9 is the stage event's final round tier, the one place
; the built team is guaranteed the donor's original six mons, so these are
; flavour for that tier rather than a fixed team: whatever six species the
; round-9 pool rolls receives these moves in these slots, same as every other
; SpecialTrainerMoves entry in this file.
	db NURSE_JOY, 9
	db 1, 1, REST
	db 1, 2, DOUBLE_TEAM
	db 1, 3, FISSURE
	db 2, 2, ICE_BEAM
	db 2, 3, AMNESIA
	db 2, 4, DOUBLE_TEAM
	db 3, 1, RECOVER
	db 3, 3, THUNDER_WAVE
	db 3, 4, SUBSTITUTE
	db 4, 1, REFLECT
	db 4, 2, BLIZZARD
	db 4, 3, RECOVER
	db 4, 4, THUNDER_WAVE
	db 5, 1, SOFTBOILED
	db 5, 2, REFLECT
	db 5, 3, DREAM_EATER
	db 6, 1, SOFTBOILED
	db 6, 2, REFLECT
	db 6, 3, EGG_BOMB
	db 6, 4, THUNDER_WAVE
	db 0

	db OFFICER_JENNY, 9
	db 1, 1, TAKE_DOWN
	db 1, 4, TOXIC
	db 2, 1, SURF
	db 2, 2, EARTHQUAKE
	db 2, 4, BODY_SLAM
	db 3, 2, SLEEP_POWDER
	db 3, 3, MIMIC
	db 4, 1, PSYCHIC_M
	db 4, 4, THUNDERBOLT
	db 5, 4, LEECH_LIFE
	db 6, 1, REFLECT
	db 6, 2, FIRE_BLAST
	db 6, 3, BODY_SLAM
	db 6, 4, DIG
	db 0

	db -1 ; end