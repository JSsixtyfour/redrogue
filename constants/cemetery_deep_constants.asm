; The Cemetery's two extra floors (PROCEDURAL_DEEP_FLOOR_PLAN.md, Cemetery SPEC
; C0-C6; custom_functions/cemetery_deep_floor.asm). Later in a run the chain is
; 1, 2, 3, 2b, 3b, 4: maps 2 and 3 each host an "a" and a "b" state, exchanged
; with a shadow in the cave's buffer, idle during a Cemetery stage (measured,
; Cemetery Phase 0: 0 writes while any Cemetery floor was live).
;
; Kept clear of sProcCaveStagingBuffer + 502/503: the lobby resets the Forest's
; control pair there before every wild area.

DEF CEM_DEEP_CTRL          EQUS "(sProcCaveStagingBuffer + 0)"   ; byte, then its complement
DEF CEM_DEEP_SHADOW_BITS   EQUS "(sProcCaveStagingBuffer + 2)"
DEF CEM_DEEP_CHAN_ORD      EQUS "(sProcCaveStagingBuffer + 3)"   ; the Channeler's ordinal, 0-5
DEF CEM_DEEP_HIDE_ORD      EQUS "(sProcCaveStagingBuffer + 4)"   ; the hideout's, 1-5 or STAGE_EVENT_NO_HIDEOUT
DEF CEM_DEEP_SHADOW_2      EQUS "(sProcCaveStagingBuffer + 8)"   ; map 2's other state
DEF CEM_DEEP_SHADOW_3      EQUS "(sProcCaveStagingBuffer + 8 + CEM_DEEP_SHADOW_SIZE)"
DEF CEM_DEEP_SHADOW_SIZE   EQU 90 + 3                           ; the map, then ball X, Y, item
DEF CEM_DEEP_END_OFFSET    EQU 8 + 2 * CEM_DEEP_SHADOW_SIZE
	ASSERT CEM_DEEP_END_OFFSET <= 502, "the Cemetery's shadow reaches the Forest's control pair"

DEF CEM_DEEP_MAGIC         EQU $80 ; bits 5-7 when valid (cave $A0, Forest $C0, Facility $E0)
DEF CEM_DEEP_MAGIC_MASK    EQU $E0
DEF BIT_CEM_DEEP_LIVE_2B   EQU 0   ; map 2's live state is 2b
DEF BIT_CEM_DEEP_LIVE_3B   EQU 1   ; map 3's live state is 3b

; CEM_DEEP_SHADOW_BITS: the shadow states' own bits, exchanged with the live
; sProcCemeteryReady / sProcCemeteryItemGot bit of that map.
DEF BIT_CEM_SHADOW_READY_2 EQU 0
DEF BIT_CEM_SHADOW_READY_3 EQU 1
DEF BIT_CEM_SHADOW_GOT_2   EQU 2
DEF BIT_CEM_SHADOW_GOT_3   EQU 3

; The gate: round 5 and later (the first round whose route trainers field five).
DEF CEM_DEEP_MIN_PROGRESS  EQU 4 * ROUND_BATTLES
DEF CEM_DEEP_NUM_ORDINALS  EQU 6   ; 1, 2, 3, 2b, 3b, 4
