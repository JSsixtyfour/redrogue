Truck_Object:
	db $3 ; border block

	def_warp_events
; The two rear-door tiles lead to the arrival-only Mini Saffron warp at
; (12,11), directly below Prof Palm and the Silph Co entrance.
	warp_event  0,  1, MINI_SAFFRON, 2
	warp_event  0,  2, MINI_SAFFRON, 2

	def_bg_events

	def_object_events

	def_warps_to TRUCK
