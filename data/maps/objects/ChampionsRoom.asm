	object_const_def
	const_export CHAMPIONSROOM_RIVAL
	const_export CHAMPIONSROOM_OAK
; Lance and Oak as alternate Champions (Phase 7e). Appended, not slotted next
; to the rival: the first N text pointers must match the N object_events in
; order, so inserting mid-list would silently shift every later object's text
; (see FuchsiaGym's Janine for the same rule).
	const_export CHAMPIONSROOM_LANCE
	const_export CHAMPIONSROOM_OAK_CHAMPION

ChampionsRoom_Object:
	db $3 ; border block

	def_warp_events
	warp_event  3,  7, LANCES_ROOM, 2
	warp_event  4,  7, LANCES_ROOM, 3
	warp_event  3,  0, HALL_OF_FAME, 1
	warp_event  4,  0, HALL_OF_FAME, 1

	def_bg_events

	def_object_events
	object_event  4,  2, SPRITE_BLUE, STAY, DOWN, TEXT_CHAMPIONSROOM_RIVAL
	object_event  3,  7, SPRITE_OAK, STAY, UP, TEXT_CHAMPIONSROOM_OAK
; Lance and Oak-as-champion stand on the rival's own tile: exactly one of the
; three is ever visible (ChampionsRoomHideUnusedChampion), so they cannot all
; occupy it at once, same trick FuchsiaGym uses for Koga/Janine.
	object_event  4,  2, SPRITE_LANCE, STAY, DOWN, TEXT_CHAMPIONSROOM_LANCE
	object_event  4,  2, SPRITE_OAK, STAY, DOWN, TEXT_CHAMPIONSROOM_OAK_CHAMPION

	def_warps_to CHAMPIONS_ROOM
