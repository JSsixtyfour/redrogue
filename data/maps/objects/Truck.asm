Truck_Object:
	db $3 ; border block

	def_warp_events
; The two rear-door tiles. Both lead to SAFFRON_CITY warp 9, which puts the
; player at (18,23), two tiles south of the Silph Co entrance.
	warp_event  0,  1, SAFFRON_CITY, 9
	warp_event  0,  2, SAFFRON_CITY, 9

	def_bg_events

	def_object_events

	def_warps_to TRUCK
