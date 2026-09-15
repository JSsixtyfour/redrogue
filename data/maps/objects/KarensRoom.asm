	object_const_def
	const_export KARENSROOM_KAREN

KarensRoom_Object:
	db $0 ; border block

; Warp coordinates are MEASURED from maps/KarensRoom.blk, not copied from the
; three original Elite Four rooms: this map is 5x8 blocks (16 steps tall), so
; its south row is 15 and not the 11 those rooms use, and not the 13 Koga's and
; Will's use either. The matching row in Elite4RoomWarpTiles
; (custom_functions/final_sequence.asm) carries the same numbers, and both must
; agree or backtracking misroutes.
;
; The destinations below are the vanilla-order placeholders the engine
; overwrites: Elite4PatchRoomWarps rewrites both pairs on every map load to
; match this run's shuffled wRunElite4.
	def_warp_events
	warp_event  4, 15, BRUNOS_ROOM, 3
	warp_event  5, 15, BRUNOS_ROOM, 4
	warp_event  4,  0, AGATHAS_ROOM, 1
	warp_event  5,  0, AGATHAS_ROOM, 1

	def_bg_events

	def_object_events
	object_event  5,  2, SPRITE_BEAUTY, STAY, DOWN, TEXT_KARENSROOM_KAREN, OPP_KAREN, 1

	def_warps_to KARENS_ROOM
