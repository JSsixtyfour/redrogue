	object_const_def
	const_export KOGASROOM_KOGA

KogasRoom_Object:
	db 2 ; border block (forest tree, as ProceduralForest)

; Warp coordinates are MEASURED from maps/KogasRoom.blk, not copied from the
; three original Elite Four rooms: this map is 5x7 blocks (14 steps tall), so
; its south row is 13 and not the 11 those rooms use. The matching row in
; Elite4RoomWarpTiles (custom_functions/final_sequence.asm) carries the same
; numbers, and both must agree or backtracking misroutes.
;
; The destinations below are the vanilla-order placeholders the engine
; overwrites: Elite4PatchRoomWarps rewrites both pairs on every map load to
; match this run's shuffled wRunElite4.
	def_warp_events
	warp_event  4, 13, BRUNOS_ROOM, 3
	warp_event  5, 13, BRUNOS_ROOM, 4
	warp_event  4,  0, AGATHAS_ROOM, 1
	warp_event  5,  0, AGATHAS_ROOM, 1

	def_bg_events

	def_object_events
	object_event  5,  2, SPRITE_KOGA, STAY, DOWN, TEXT_KOGASROOM_KOGA, OPP_KOGA_E4, 1

	def_warps_to KOGAS_ROOM
