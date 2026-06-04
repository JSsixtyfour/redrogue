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
; slots 1-15. Slot 15 is permanently reserved for the Pokemon follower
; (Yellow-style wSprite15StateData1/2), so maps may only use slots 1-14.
; Add ASSERT const_value <= MAX_OBJECT_EVENTS_SAFE + 1 to each map's object file.
DEF MAX_OBJECT_EVENTS_SAFE EQU 14

; flower and water tile animations
	const_def
	const TILEANIM_NONE          ; 0
	const TILEANIM_WATER         ; 1
	const TILEANIM_WATER_FLOWER  ; 2
