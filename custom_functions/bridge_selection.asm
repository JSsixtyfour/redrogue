; custom_functions/bridge_selection.asm
; Bridge System: twice-per-run gift-room interludes that sit ON TOP of the lobby
; door randomization. When a bridge fires, BOTH lobby doors become two different
; bridge rooms; entering either gives a gift (see engine/events/bridge_gift_menu.asm)
; and its exit warp returns to the lobby (PatchBridgeExit), where the gym-next
; doors offer the gym choice (player feedback #1, 2026-10-09; it used to route
; straight to the pre-decided gym, wRogueMap). Bridges do NOT consume a route/gym/special slot.
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
	db IGAS_DOJO     ; 11
	db FLORAS_GROTTO      ; 12
	db OAKS_LAB                  ; 13
DEF NUM_BRIDGE_ROOMS EQU 14

; ============================================================
; BridgeRollAndAssign
; Called from SelectAndPatchLobbyExit after _PickNextStage set both doors to
; wRogueMap (and before the special-encounter roll). If a bridge fires this
; visit, overwrites BOTH doors with two different not-yet-offered bridge rooms
; and returns carry SET (caller then skips the special roll). Otherwise carry
; CLEAR. wRogueMap (the real next stage) is left intact for the rooms' exit
; warps. Fires only during gym cycles (except explicit Debug 2 overrides).
; Counted on room entry by BridgeRecordVisit. Clobbers a/bc/de/hl.
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
	; Gifts are interludes before gyms, never a competing route selection.
	ld a, [wRogueFlagsBitfield]
	bit BIT_ROGUE_GYM_NEXT, a
	jr z, .no
	; gate: already hit the per-run cap?
	call GetBridgeCount
	cp BRIDGE_PER_RUN
	jr nc, .no
	call BridgeShouldOccur
	jr nc, .no
.fire
	call BridgePickTwoRooms       ; sets both door maps, marks both offered
	scf
	ret
.no
	and a                         ; clear carry
	ret

; ------------------------------------------------------------
; BridgeShouldOccur - OUT: carry set = a bridge fires this visit.
; One gift before gyms 2-3, another before gyms 5-6. Each remaining eligible
; gym is equally likely; the last one in each window is mandatory.
; Counts are badges already earned, so the windows are 1-2 and 4-5: the
; back-to-back pairs' lobbies (PAIR_BADGES_A/B) are never eligible.
BridgeShouldOccur:
	call GetBridgeCount           ; a = current count (0 or 1 here)
	add a
	ld e, a
	ld d, 0
	ld hl, BridgeGuaranteeThresholds
	add hl, de
	push hl
	call MiniBossCountBadges
	pop hl
	; A back-to-back pair's lobby comes straight from the Reward Room.
	cp PAIR_BADGES_A
	jr z, .no
	cp PAIR_BADGES_B
	jr z, .no
	cp [hl]
	jr c, .no
	ld b, a
	inc hl
	ld a, [hl]
	sub b
	jr c, .fire
	inc a
	ld c, a
	call Rangerandom              ; a in [0, range-1]
	and a
	jr z, .fire                   ; 1-in-range
.no
	and a                         ; clear carry
	ret
.fire
	scf
	ret

BridgeGuaranteeThresholds:
	; Each window ends before its back-to-back pair's lobby, which never hosts
	; a gift (until 2026-10-09 these were 1-3 and 4-6).
	db 1, PAIR_BADGES_A - 1 ; first gift: before gym 2 or 3
	db PAIR_BADGES_A + 1, PAIR_BADGES_B - 1 ; second gift: before gym 5 or 6
	ASSERT PAIR_BADGES_A - 1 >= 1 && PAIR_BADGES_B - 1 >= PAIR_BADGES_A + 1

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
IF DEF(_DEBUG)
	ld hl, wDebug2ForcedDoor1
ENDC
	call BridgePickRoomForDoor    ; a = room map (its room now marked offered)
	ld [wLobbyDoor1StageMap], a
IF DEF(_DEBUG)
	ld hl, wDebug2ForcedDoor2
ENDC
	call BridgePickRoomForDoor    ; distinct unless Debug 2 forces otherwise
	ld [wLobbyDoor2StageMap], a
	ret

; ------------------------------------------------------------
; BridgePickRoomForDoor - pick one door's gift room and mark it offered.
; OUT: a = its map id. In debug builds, hl = that door's Debug 2 forced-index
; byte; a non-zero low five bits name a specific room (1-based) instead of
; rolling. That is what lets the Debug 2 screen put a chosen gift room behind a
; chosen door - before this, a forced GIFT status could only produce two random
; rooms. Clobbers all.
BridgePickRoomForDoor:
IF DEF(_DEBUG)
	ld a, [wStatusFlags6]
	bit BIT_DEBUG2_MODE, a
	jr z, .roll
	ld a, [hl]
	and %00011111
	and a
	jr z, .roll                   ; 0 = random, which is the normal roll
	dec a                         ; 1-based screen index -> 0-based room index
	cp NUM_BRIDGE_ROOMS
	jr nc, .roll                  ; out of range: roll rather than read past
	push af
	call BridgeMarkRoomOffered
	pop af
	jr .toMap
.roll
ENDC
	call BridgePickOneUnoffered
.toMap
	jp BridgeRoomIndexToMap

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

; Count a gift-room visit, not an offer the player can leave in the lobby.
; Consume the offered destinations to make map reloads idempotent. Bridge
; exit patching uses wRogueMap, which remains the queued gym throughout.
BridgeRecordVisit::
	ld a, [wWarpedFromWhichMap]
	cp INDIGO_PLATEAU_LOBBY
	ret nz
	ldh a, [hCurMap]
	ld c, a
	ld a, [wLobbyDoor1StageMap]
	cp c
	jr z, .offered
	ld a, [wLobbyDoor2StageMap]
	cp c
	ret nz
.offered
	ld hl, BridgeRoomMaps
	ld b, NUM_BRIDGE_ROOMS
.scan
	ld a, [hli]
	cp c
	jr z, .found
	dec b
	jr nz, .scan
	ret
.found
	call GetBridgeCount
	cp BRIDGE_PER_RUN
	call c, BridgeIncCount
	ld a, [wRogueMap]
	ld [wLobbyDoor1StageMap], a
	ld [wLobbyDoor2StageMap], a
	ret

; ============================================================
; PatchBridgeExit  (farcall'd from each bridge room's setup script on load)
; Redirect every warp in the current map whose destination is the lobby
; (LAST_MAP) to land on the lobby's first warp explicitly (the gym choice is
; made there since 2026-10-09; this used to be the pre-decided gym, wRogueMap). Handles rooms with two entrance warps both -> LAST_MAP.
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
	ld d, INDIGO_PLATEAU_LOBBY     ; back to the lobby for the gym choice
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
; Like PatchBridgeExit, but reroutes EVERY warp in the map to the lobby - for
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
	ld d, INDIGO_PLATEAU_LOBBY     ; back to the lobby for the gym choice
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
