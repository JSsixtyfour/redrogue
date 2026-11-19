; The shared deep-floor core (custom_functions/deep_floor_core.asm,
; PROCEDURAL_DEEP_FLOOR_PLAN.md Facility SPEC D0). Each area with a deep floor
; is one row of DeepAreaTable; its own module passes the id in d.
	const_def
	const DEEP_AREA_CAVE   ; 0
	const DEEP_AREA_FOREST ; 1
	const DEEP_AREA_FACILITY ; 2
DEF NUM_DEEP_AREAS EQU const_value

; Every area's control word is a byte and its complement, valid when its top
; three bits hold the area's magic; bit 0 says the live copy holds floor 2.
DEF DEEP_MAGIC_MASK EQU $E0
DEF BIT_DEEP_LIVE_2 EQU 0

; What a floor-2 generation would rewrite for the area as a whole ends with the
; same 10 SRAM bytes in every area: sProcCavePalette..sStageEventHideoutFloor
; (the palettes and the stage-event hideout), bank 0.
DEF DEEP_SRAM_TAIL EQU 10
