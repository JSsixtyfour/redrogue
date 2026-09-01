; custom_functions/bridge_selection.asm
; Bridge System: twice-per-run gift-room interludes that sit ON TOP of the lobby
; door randomization. When a bridge fires, BOTH lobby doors become two different
; bridge rooms; entering either gives a gift (see engine/events/bridge_gift_menu.asm)
; and its exit warp routes straight to the pre-decided next route/gym (wRogueMap)
; via PatchBridgeExit. Bridges do NOT consume a route/gym/special slot.
;
; Run-state (wBridgeOfferedLo + wBridgeState, in wGameProgressFlags): a per-run
; "offered" bitmask over the bridge rooms (no repeat until the pool is exhausted)
; plus a saturating bridge count for the 2-per-run guarantee.

; Bridge room map ids. Index = "room index" used by the offered-mask bits
; (0-7 -> wBridgeOfferedLo, 8-13 -> wBridgeState bits 0-5; 14 rooms max).
; KEEP IN SYNC with the giver tables in engine/events/bridge_gift_menu.asm and the
; sign table in scripts/IndigoPlateauLobby.asm.
BridgeRoomMaps:
	db COPYCATS_HOUSE_2F        ; 0
	db BILLS_HOUSE               ; 1
	db MR_FUJIS_HOUSE            ; 2
	db SS_ANNE_CAPTAINS_ROOM     ; 3
	db CINNABAR_LAB_FOSSIL_ROOM  ; 4
	db POKEMON_FAN_CLUB          ; 5
	db WARDENS_HOUSE             ; 6
	db VIRIDIAN_SCHOOL_HOUSE     ; 7
	db VIRIDIAN_NICKNAME_HOUSE   ; 8
	db CERULEAN_TRASHED_HOUSE    ; 9
	db REDS_HOUSE_1F             ; 10
	db LAVENDER_CUBONE_HOUSE     ; 11
	db CERULEAN_TRADE_HOUSE      ; 12
	db OAKS_LAB                  ; 13
DEF NUM_BRIDGE_ROOMS EQU 14

; ============================================================
; BridgeRollAndAssign
; Called from SelectAndPatchLobbyExit after _PickNextStage set both doors to
; wRogueMap (and before the special-encounter roll). If a bridge fires this
; visit, overwrites BOTH doors with two different not-yet-offered bridge rooms
; and returns carry SET (caller then skips the special roll). Otherwise carry
; CLEAR. wRogueMap (the real next stage) is left intact for the rooms' exit
; warps. Fires during BOTH route and gym cycles. Clobbers a/bc/de/hl.
; ============================================================
BridgeRollAndAssign::
IF DEF(_DEBUG)
	; Debug 2 choice 2 forces this visit, including early/capped test states.
	ld a, [wStatusFlags6]
	bit BIT_DEBUG2_MODE, a
	jr z, .normalGates
	ld a, [wDebug2ForcedDoor1]
	and %11000000
	cp %01000000
	jr z, .fire
	cp %10000000
	jr nc, .no                    ; mini-boss/wild choices suppress normal bridge rolls
.normalGates
ENDC
	; gate: not until after the first route
	ld a, [wBattleCount]
	cp BRIDGE_FIRST_BATTLECOUNT
	jr c, .no
	; gate: already hit the per-run cap?
	call GetBridgeCount
	cp BRIDGE_PER_RUN
	jr nc, .no
	call BridgeShouldOccur
	jr nc, .no
.fire
	call BridgePickTwoRooms       ; sets both door maps, marks both offered
	call BridgeIncCount
	scf
	ret
.no
	and a                         ; clear carry
	ret

; ------------------------------------------------------------
; BridgeShouldOccur - OUT: carry set = a bridge fires this visit.
; Escalating guarantee: force the next bridge once wBattleCount passes its
; threshold (so ~2 land per run), otherwise a flat ~1-in-N chance. Clobbers all.
BridgeShouldOccur:
	call GetBridgeCount           ; a = current count (0 or 1 here)
	ld e, a
	ld d, 0
	ld hl, BridgeGuaranteeThresholds
	add hl, de
	ld a, [wBattleCount]
	cp [hl]
	jr nc, .fire                  ; wBattleCount >= threshold -> guaranteed
	ld c, BRIDGE_CHANCE_RANGE
	call Rangerandom              ; a in [0, range-1]
	and a
	jr z, .fire                   ; 1-in-range
	and a                         ; clear carry
	ret
.fire
	scf
	ret

BridgeGuaranteeThresholds:
	db 40   ; force the 1st bridge once wBattleCount reaches this
	db 90   ; force the 2nd bridge once wBattleCount reaches this

; ------------------------------------------------------------
; BridgePickTwoRooms - pick two DISTINCT not-yet-offered bridge rooms, assign to
; wLobbyDoor1/2StageMap, and mark both offered. Resets the offered mask first if
; fewer than 2 rooms remain unoffered. Clobbers all.
BridgePickTwoRooms:
	call BridgeCountUnoffered
	cp 2
	jr nc, .haveTwo
	call BridgeResetOfferedMask
.haveTwo
	call BridgePickOneUnoffered   ; a = room index (now marked offered)
	call BridgeRoomIndexToMap
	ld [wLobbyDoor1StageMap], a
	call BridgePickOneUnoffered   ; distinct: the first is already marked
	call BridgeRoomIndexToMap
	ld [wLobbyDoor2StageMap], a
	ret

; ------------------------------------------------------------
; BridgePickOneUnoffered - pick a random unoffered room, mark it, return its
; index in a. Assumes at least one unoffered room. Clobbers a/bc/de/hl.
BridgePickOneUnoffered:
	call BridgeCountUnoffered      ; a = unoffered count (>=1)
	ld c, a
	call Rangerandom               ; a = [0, unoffered-1]
	ld c, a                        ; c = target-th unoffered
	ld e, 0                        ; e = index iterator
.loop
	ld a, e
	push bc
	call BridgeRoomOffered         ; Z = not offered
	pop bc
	jr nz, .next
	ld a, c
	and a
	jr z, .found
	dec c
.next
	inc e
	jr .loop
.found
	ld a, e
	call BridgeMarkRoomOffered
	ld a, e
	ret

; ------------------------------------------------------------
; BridgeCountUnoffered - OUT: a = number of not-yet-offered rooms. Clobbers all.
BridgeCountUnoffered:
	ld d, 0                        ; d = unoffered count
	ld e, 0                        ; e = index
.loop
	ld a, e
	cp NUM_BRIDGE_ROOMS
	jr z, .done
	ld a, e
	push de
	call BridgeRoomOffered
	pop de
	jr nz, .skip
	inc d
.skip
	inc e
	jr .loop
.done
	ld a, d
	ret

; ------------------------------------------------------------
; BridgeResetOfferedMask - clear the offered bits, keep the count. Clobbers a.
BridgeResetOfferedMask:
	xor a
	ld [wBridgeOfferedLo], a
	ld a, [wBridgeState]
	and BRIDGE_COUNT_MASK          ; keep count (bits 6-7), clear room bits 0-5
	ld [wBridgeState], a
	ret

; ------------------------------------------------------------
; BridgeRoomOffered - in: a = room index. OUT: Z = not offered / NZ = offered.
; Clobbers a/bc/hl.
BridgeRoomOffered:
	call BridgeRoomMaskPtr         ; hl -> byte, b = mask
	ld a, [hl]
	and b
	ret

; BridgeMarkRoomOffered - in: a = room index. Clobbers a/bc/hl.
BridgeMarkRoomOffered:
	call BridgeRoomMaskPtr
	ld a, [hl]
	or b
	ld [hl], a
	ret

; BridgeRoomMaskPtr - in: a = room index (0-13). OUT: hl -> the offered byte,
; b = the room's bit mask. Rooms 0-7 -> wBridgeOfferedLo; 8-13 -> wBridgeState
; bits 0-5. Clobbers a/c.
BridgeRoomMaskPtr:
	cp 8
	jr nc, .hi
	ld c, a
	ld hl, wBridgeOfferedLo
	jr .mask
.hi
	sub 8
	ld c, a
	ld hl, wBridgeState
.mask
	ld b, 1
	inc c
.mloop
	dec c
	jr z, .mdone
	sla b
	jr .mloop
.mdone
	ret

; BridgeRoomIndexToMap - in: a = room index. OUT: a = map id. Clobbers bc/hl.
BridgeRoomIndexToMap:
	ld c, a
	ld b, 0
	ld hl, BridgeRoomMaps
	add hl, bc
	ld a, [hl]
	ret

; ------------------------------------------------------------
; GetBridgeCount - OUT: a = bridges given this run (0-3). Clobbers a.
GetBridgeCount:
	ld a, [wBridgeState]
	and BRIDGE_COUNT_MASK          ; bits 6-7
	rlca
	rlca                           ; -> value 0-3
	ret

; BridgeIncCount - bump the saturating bridge count. Clobbers a/b.
BridgeIncCount:
	call GetBridgeCount
	inc a
	cp 4
	jr c, .ok
	ld a, 3
.ok
	rrca
	rrca                           ; count -> bits 6-7
	ld b, a
	ld a, [wBridgeState]
	and BRIDGE_HI_ROOM_MASK        ; keep room bits 0-5
	or b
	ld [wBridgeState], a
	ret

; ============================================================
; PatchBridgeExit  (farcall'd from each bridge room's setup script on load)
; Redirect every warp in the current map whose destination is the lobby
; (LAST_MAP) to instead land on the pre-decided next route/gym (wRogueMap),
; entrance warp. Handles rooms with two entrance warps both -> LAST_MAP.
; Clobbers a/bc/de/hl.
; ============================================================
PatchBridgeExit::
	; Only act when entered as a bridge (arrived from the lobby door). A normal
	; visit or the temp diagnostic warp leaves wRogueMap stale, so leave those
	; warps alone. This is also what gates dual-purpose rooms (OaksLab starter
	; selection, RedsHouse1F) to only reroute when they're serving as a bridge.
	ld a, [wWarpedFromWhichMap]
	cp INDIGO_PLATEAU_LOBBY
	ret nz
	ld a, [wNumberOfWarps]
	and a
	ret z
	ld e, a                        ; e = warp count
	ld a, [wRogueMap]
	ld d, a                        ; d = new destination map
	ld bc, 4                       ; warp entry stride (Y,X,warpID,mapID)
	ld hl, wWarpEntries + 2        ; -> first entry's warpID byte
.loop
	inc hl                         ; -> mapID
	ld a, [hld]                    ; a = mapID; hl back to warpID
	cp LAST_MAP
	jr nz, .skip
	ld [hl], 0                     ; warpID -> 0 (target's entrance)
	inc hl
	ld [hl], d                     ; mapID -> wRogueMap
	dec hl                         ; back to warpID for a uniform advance
.skip
	add hl, bc                     ; -> next entry's warpID
	dec e
	jr nz, .loop
	ret

; ============================================================
; PatchBridgeExitAll  (farcall'd from dual-exit bridge rooms, e.g. OaksLab)
; Like PatchBridgeExit, but reroutes EVERY warp in the map to wRogueMap - for
; rooms whose non-LAST_MAP exit would otherwise lead somewhere wrong during a
; bridge (OaksLab's north exit normally goes to REWARD_ROOM). Same lobby-entry
; gate, so the vanilla intro path is untouched. Clobbers a/bc/de/hl.
; ============================================================
PatchBridgeExitAll::
	ld a, [wWarpedFromWhichMap]
	cp INDIGO_PLATEAU_LOBBY
	ret nz
	ld a, [wNumberOfWarps]
	and a
	ret z
	ld e, a
	ld a, [wRogueMap]
	ld d, a
	ld bc, 4
	ld hl, wWarpEntries + 2        ; -> first entry's warpID byte
.loop
	ld [hl], 0                     ; warpID -> 0
	inc hl
	ld [hl], d                     ; mapID -> wRogueMap
	dec hl
	add hl, bc                     ; -> next entry's warpID
	dec e
	jr nz, .loop
	ret
