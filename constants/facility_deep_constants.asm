; The Facility's optional deep floor (PROCEDURAL_DEEP_FLOOR_PLAN.md, Facility
; SPEC X0-X8; custom_functions/facility_deep_floor.asm). Floor 2 is
; PROCEDURAL_FACILITY loaded again with the Facility's bank-1 state exchanged
; for a shadow copy kept in two idle bank-0 buffers: nothing writes the cave's
; or the Forest's during a Facility stage (measured, plan Facility Phase 0.8).
;
; A deep Facility has floor 2 INSTEAD of its subroom: the subroom pad leads to
; its own warp, which the arrival seam turns into a trip between the floors.

; The live state: one bank-1 block, the 600 B map then 102 B of fields and scratch.
DEF FACILITY_DEEP_MAP_SIZE    EQU 600 ; sProcFacilityStagingBuffer
DEF FACILITY_DEEP_STATE_SIZE  EQU 102 ; sProcFacilityExitI..sProcFacilityGenScratch + 80
DEF FACILITY_DEEP_BLOCK_SIZE  EQU 21  ; sProcFacilityExitI..sProcFacilityEntryBattleCount
; The shadow, bank 0: the map in the cave's buffer, the 102 B in the Forest's
; state block (exactly 102 B).
DEF FACILITY_DEEP_SHADOW_MAP   EQUS "sProcCaveStagingBuffer"
DEF FACILITY_DEEP_SHADOW_STATE EQUS "sProcForestExitI"
; The control word (a byte and its complement) and the save, bank 0, in the
; Forest's idle map. Only the Facility's preload writes the control word
; (FacilityDeepLobbyDecide), so a Forest's map bytes left here only matter if
; they pass the check, and a Facility stage always rewrites it first.
DEF FACILITY_DEEP_CTRL        EQUS "sProcForestStagingBuffer"
DEF FACILITY_DEEP_SAVE        EQUS "(sProcForestStagingBuffer + 2)"
DEF FACILITY_DEEP_MAGIC       EQU $E0 ; bits 5-7 when valid (deep)
DEF BIT_FACILITY_DEEP_LIVE_2  EQU 0   ; the live copy holds floor 2
DEF BIT_FACILITY_DEEP_MADE    EQU 1   ; floor 2 has been generated
DEF BIT_FACILITY_DEEP_FAST_FADE EQU 2 ; transient: this warp is the first descent, so
                                      ; its fades run fast (set by the leave fade,
                                      ; cleared by the arrival fade)
DEF BIT_FACILITY_DEEP_BALLS_2 EQU 3   ; floor 2 keeps ball 2 too (slot 3)
DEF BIT_FACILITY_DEEP_ENC_2   EQU 4   ; the subroom's encounter moved to floor 2
	ASSERT (1 << BIT_FACILITY_DEEP_ENC_2) & FACILITY_DEEP_MAGIC == 0
; The deep-floor roll, made once per Facility in its preload, is the shared ramp
; (DeepRampRoll, DEEP_ODDS_* in round_constants.asm; 50% flat until 2026-11-20).
; 0 = every Facility is decided ordinary: the kill switch. The PyBoy harness
; decides Facilities ordinary on its own unless a test sets allow_deep_facility_floor.
DEF FACILITY_DEEP_ENABLED     EQU 1
; What floor 2's fresh PFacFinalize rewrites for the Facility as a whole
; (measured, probe_facility_deep_finalize_diff.py): the wild budget it refills,
; the lobby's door choice, the stage event its restage may disarm. The diff's
; wRogueItem..+6 are not: every load copies the live floor's ball items there.
DEF FACILITY_DEEP_NUM_SAVED_WRAM EQU 1 + 1 + 1
; Mirrors of the generator's own constants (procedural_facility_gen.asm ASSERTs
; that they still agree): the wall/void block, the three exit doorways, and the
; compact map's layout.
DEF FACILITY_DEEP_WALL        EQU 46  ; PFAC_WALL
DEF FACILITY_DEEP_EXIT_N      EQU $08 ; PFAC_EXIT_N
DEF FACILITY_DEEP_EXIT_E      EQU $04 ; PFAC_EXIT_E
DEF FACILITY_DEEP_EXIT_W      EQU $05 ; PFAC_EXIT_W
DEF FACILITY_DEEP_SIZE        EQU 20  ; PFAC_SIZE
DEF FACILITY_DEEP_STRIDE      EQU 26  ; PFAC_STRIDE
DEF FACILITY_DEEP_BASE        EQU 81  ; PFAC_BASE
