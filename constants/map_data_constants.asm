; width of east/west connections
; height of north/south connections
DEF MAP_BORDER EQU 3

; connection directions
	const_def
	const EAST_F
	const WEST_F
	const SOUTH_F
	const NORTH_F

; wCurMapConnections
	const_def
	shift_const EAST   ; 1
	shift_const WEST   ; 2
	shift_const SOUTH  ; 4
	shift_const NORTH  ; 8

; wWarpEntries
DEF MAX_WARP_EVENTS EQU 32

; wNumSigns
DEF MAX_BG_EVENTS EQU 16

; wMapSpriteData
DEF MAX_OBJECT_EVENTS EQU 16

; Hard limit for map object events: sprite state data structs only exist for
; slots 1-15 (15 NPC slots). Any map defining 16+ objects would write past the
; allocated arrays and corrupt adjacent WRAM.
; The follower uses dedicated wFollowerStateData1/2 (pokeyellow architecture) and
; does NOT reserve any sprite slot, so all 15 slots are available to maps.
; Add ASSERT const_value <= MAX_OBJECT_EVENTS_SAFE + 1 to each map's object file.
DEF MAX_OBJECT_EVENTS_SAFE EQU 15

; flower and water tile animations
	const_def
	const TILEANIM_NONE          ; 0
	const TILEANIM_WATER         ; 1
	const TILEANIM_WATER_FLOWER  ; 2
