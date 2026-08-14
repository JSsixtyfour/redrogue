	object_const_def
	const_export SAFFRONCITY_PROF_PALM

SaffronCity_Object:
	db $f ; border block

	def_warp_events
	warp_event  7,  5, COPYCATS_HOUSE_1F, 1
	warp_event 26,  3, FIGHTING_DOJO, 1
	warp_event 34,  3, SAFFRON_GYM, 1
	warp_event 13, 11, SAFFRON_PIDGEY_HOUSE, 1
	warp_event 25, 11, SAFFRON_MART, 1
	warp_event 18, 21, SILPH_CO_1F, 1
	warp_event  9, 29, SAFFRON_POKECENTER, 1
	warp_event 29, 29, MR_PSYCHICS_HOUSE, 1
; Warp 9 - where the truck drops the player off, two tiles south of the Silph Co
; door at (18,21). APPENDED, never inserted: warps 1-8 keep their indices, so
; every `SAFFRON_CITY, N` reference in other maps stays valid.
; WARP_NO_RETURN makes this arrival-only. Arrival placement reads this entry's
; X/Y, so the player still lands here; the sentinel is only consulted when the
; player STEPS on the tile (home/overworld.asm WarpFound2), where it aborts the
; warp so they can never climb back into the intro truck.
	warp_event 18, 23, WARP_NO_RETURN, 1

	def_bg_events
	bg_event 17,  5, TEXT_SAFFRONCITY_SIGN
	bg_event 27,  5, TEXT_SAFFRONCITY_FIGHTING_DOJO_SIGN
	bg_event 35,  5, TEXT_SAFFRONCITY_GYM_SIGN
	bg_event 26, 11, TEXT_SAFFRONCITY_MART_SIGN
	bg_event 39, 19, TEXT_SAFFRONCITY_TRAINER_TIPS1
	bg_event  5, 21, TEXT_SAFFRONCITY_TRAINER_TIPS2
	bg_event 15, 21, TEXT_SAFFRONCITY_SILPH_CO_SIGN
	bg_event 10, 29, TEXT_SAFFRONCITY_POKECENTER_SIGN
	bg_event 27, 29, TEXT_SAFFRONCITY_MR_PSYCHICS_HOUSE_SIGN
	bg_event  1, 19, TEXT_SAFFRONCITY_SILPH_CO_LATEST_PRODUCT_SIGN

	def_object_events
; Prof Palm, the intro escort and the only NPC in Saffron. Stands one tile below
; the Silph Co door, facing down toward the truck drop-off at (18,23).
	object_event 18, 22, SPRITE_SCIENTIST, STAY, DOWN, TEXT_SAFFRONCITY_PROF_PALM

	def_warps_to SAFFRON_CITY
