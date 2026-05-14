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

	db -1 ; end