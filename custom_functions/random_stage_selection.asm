; custom_functions/random_stage_selection.asm
;
; No-duplicate stage selection for the roguelike run.
; Uses a 4-byte bitfield (wVisitedStagesBitfield) where bit N
; tracks whether stage N (by index in RogueStageMapTable) has
; been visited this run.
;
; RogueStageMapTable and IsRogueStageMap live here (rogue bank) so that
; _PickRandomUnvisitedStage can read the table directly without a bank switch.
DEF NUM_STAGE_MAPS EQU 21

RogueStageMapTable:
	db ROUTE_1
	db ROUTE_3
	db ROUTE_5
	db ROUTE_6
	db ROUTE_9
	db ROUTE_12
	db ROUTE_13
	db ROUTE_15
	; db ROUTE_17
	db ROUTE_24          ; unique: reward gated by Nugget Bridge NPC (vanilla nugget flow), not ALL_TRAINERS_MASK
	db ROUTE_25
	db VIRIDIAN_FOREST
	db DIGLETTS_CAVE
	db MT_MOON_1F
	db ROCK_TUNNEL_1F
	db ROCKET_HIDEOUT_B1F
	db POKEMON_TOWER_2F
	db POKEMON_TOWER_7F
	db SS_ANNE_B1F       ; unique: custom multi-room mechanics and EVENT_SSANNE_ALL_TRAINERS_DEFEATED gate
	;db SS_ANNE_BOW
	db POWER_PLANT
	;db SILPH_CO_1F
	db POKEMON_MANSION_1F
	db SEAFOAM_ISLANDS_1F
	;db VICTORY_ROAD_1F
	db -1

; Badge bit → gym map. Index matches wObtainedBadges bit position (0=Boulder…7=Earth).
; Used by _PickNextGym to find which gym the player should face next.
GymMapByBadge:
	db PEWTER_GYM      ; bit 0 – Boulder Badge
	db CERULEAN_GYM    ; bit 1 – Cascade Badge
	db VERMILION_GYM   ; bit 2 – Thunder Badge
	db CELADON_GYM     ; bit 3 – Rainbow Badge
	db FUCHSIA_GYM     ; bit 4 – Soul Badge
	db SAFFRON_GYM     ; bit 5 – Marsh Badge
	db CINNABAR_GYM    ; bit 6 – Volcano Badge
	db VIRIDIAN_GYM    ; bit 7 – Earth Badge

; ============================================================
; _PickNextGym  (private)
; Picks a RANDOM unvisited gym using wObtainedBadges as the visited
; bitfield (unset bit = gym not yet beaten this run).
; If all 8 gyms are done, treats all 8 as available again.
; ============================================================
_PickNextGym:
	; Pass 1: count unvisited gyms (unset bits in wObtainedBadges)
	ld a, [wObtainedBadges]
	ld b, 0             ; b = unvisited count
	ld d, a             ; d = badges copy for iteration
	ld e, 8             ; e = loop counter (8 gyms)
.gym_cnt
	bit 0, d
	jr nz, .gym_cntSkip
	inc b
.gym_cntSkip
	srl d
	dec e
	jr nz, .gym_cnt
	ld a, b
	and a
	jr nz, .gym_has
	; All gyms beaten — pick from all 8
	ld b, 8
.gym_has
	; Pick random index in [0, b-1]
	ld c, b
	call Rangerandom    ; a = random in [0, c-1] (same bank, safe call)
	ld c, a             ; c = target (0-based index into unvisited gyms)

	; Pass 2: find the c-th unset bit in wObtainedBadges
	ld a, [wObtainedBadges]
	ld e, 0             ; e = gym index (= GymMapByBadge offset)
.gym_pick
	bit 0, a            ; is this gym already beaten?
	jr nz, .gym_pickSkip
	ld b, a             ; stash badges while checking counter
	ld a, c
	and a               ; reached target?
	jr z, .gym_chosen
	dec c
	ld a, b
.gym_pickSkip
	srl a
	inc e
	jr .gym_pick
.gym_chosen
	ld hl, GymMapByBadge
	ld d, 0
	add hl, de
	ld a, [hl]
	ldh [hWarpDestinationMap], a
	ld [wRogueMap], a
	ret

; Returns: Z clear if current map is a roguelike stage, Z set if not
IsRogueStageMap::
	ldh a, [hCurMap]
	ld hl, RogueStageMapTable
.stageLoop
	ld c, [hl]
	inc hl
	inc c
	jr z, .notStage   ; c was $FF sentinel (db -1 = $FF)
	dec c
	cp c
	jr nz, .stageLoop
	xor a
	inc a             ; Z clear = is a stage map
	ret
.notStage
	xor a             ; Z set = not a stage map
	ret

; ============================================================
; _StageBitInfo  (private helper)
; Converts a stage index into the byte address and bit mask
; needed to read or write that stage's visited flag.
;
; INPUT:  c = stage index (0 to NUM_STAGE_MAPS-1)
; OUTPUT: hl = address of the relevant byte in wVisitedStagesBitfield
;         b  = bit mask with only the stage's bit set (1 << (c & 7))
; CLOBBERS: a, d, e
; ============================================================
_StageBitInfo:
	; Bit position within byte = c & 7 (lower 3 bits of index)
	ld a, c
	and 7
	ld d, a
	inc d               ; loop trick: inc so first dec lands on the original value
	ld a, 1             ; start with mask = 00000001
.sbi_loop
	dec d
	jr z, .sbi_done
	rlca                ; shift mask left one position
	jr .sbi_loop
.sbi_done
	ld b, a             ; b = finished bit mask

	; Byte offset = c >> 3 (upper bits of index, i.e. which of the 4 bytes)
	ld a, c
	srl a
	srl a
	srl a
	ld hl, wVisitedStagesBitfield
	ld d, 0
	ld e, a
	add hl, de          ; hl points to the correct byte
	ret

; ============================================================
; MarkCurrentStageVisited
; Records that the current map has been played by setting its
; bit in wVisitedStagesBitfield.  Does nothing if the current
; map is not in RogueStageMapTable.
; ============================================================
MarkCurrentStageVisited::
	ldh a, [hCurMap]
	ld b, a             ; b = map ID to search for
	ld hl, RogueStageMapTable
	ld c, 0             ; c = stage index counter
.mcsv_scan
	ld a, [hli]
	cp $ff              ; end-of-table sentinel
	ret z               ; map not found — not a stage, nothing to mark
	cp b
	jr z, .mcsv_found
	inc c
	jr .mcsv_scan
.mcsv_found
	call _StageBitInfo  ; hl = byte address, b = mask
	ld a, [hl]
	or b                ; set the bit (OR forces it on without touching others)
	ld [hl], a
	ret

; ============================================================
; SelectRandomUnvisitedStage
; Picks a random stage that has not been visited yet and
; redirects the player there via BIT_WARP_FROM_CUR_SCRIPT.
; If every stage has been visited, the bitfield resets first
; so the cycle begins again.
;
; Sets: hWarpDestinationMap, wDestinationWarpID, wLastMap,
;       BIT_WARP_FROM_CUR_SCRIPT
; ============================================================
; Private helper: pick a random unvisited stage and store its map ID in
; hWarpDestinationMap. Does NOT set BIT_WARP_FROM_CUR_SCRIPT or wLastMap.
; Use SelectRandomUnvisitedStage for the full exit-tile behaviour, or call
; this directly when patching the warp table on map entry instead.
_PickRandomUnvisitedStage:
	; --- Pass 1: count how many stages are unvisited ---
	ld hl, RogueStageMapTable
	ld b, 0             ; b = running unvisited count
	ld c, 0             ; c = current stage index
.srus_cnt
	ld a, [hli]
	cp $ff
	jr z, .srus_cntDone
	push hl
	push bc
	call _StageBitInfo  ; hl = byte, b = mask for this stage index
	ld a, [hl]
	and b               ; Z flag set = bit is 0 = stage not yet visited
	pop bc              ; pop does not affect flags, so Z is still valid
	pop hl
	jr nz, .srus_cntSkip
	inc b               ; unvisited: add to count
.srus_cntSkip
	inc c
	jr .srus_cnt
.srus_cntDone
	ld a, b
	and a
	jr nz, .srus_has
	; All stages visited — reset the bitfield and start a new cycle
	ld hl, wVisitedStagesBitfield
	xor a
	ld [hli], a
	ld [hli], a
	ld [hli], a
	ld [hl], a
	ld b, NUM_STAGE_MAPS
.srus_has
	; Pick a random number in [0, unvisited_count - 1]
	; Use Rangerandom (same rogue bank, no cross-bank issue) to pick an index
	; in [0, b-1]. Rangerandom takes c = count and returns a = result.
	ld c, b             ; c = unvisited count
	call Rangerandom    ; a = random in [0, c-1]; bc and de preserved internally
	ld c, a             ; c = which unvisited stage to pick (0-based)

	; --- Pass 2: walk the table and find the c-th unvisited stage ---
	ld hl, RogueStageMapTable
	ld e, 0             ; e = stage index
.srus_pick
	ld a, [hli]         ; read map ID, advance table pointer
	push hl
	push af             ; save map ID
	push bc             ; save target counter (c) and unvisited count (b)
	ld c, e             ; pass stage index to _StageBitInfo
	call _StageBitInfo
	ld a, [hl]
	and b               ; 0 = unvisited, non-zero = visited
	ld d, a             ; save bit-check result — pop af below clobbers Z flag
	pop bc
	pop af              ; a = map ID
	ld b, a             ; stash map ID NOW before a gets clobbered by ld a,d below
	pop hl
	ld a, d
	and a               ; re-establish Z from saved bit check
	jr nz, .srus_pickSkip   ; non-zero = visited: skip
	ld a, c
	and a               ; is target counter 0?
	jr z, .srus_chosen  ; yes — this is the stage we want
	dec c               ; not yet — move to next unvisited
.srus_pickSkip
	inc e
	jr .srus_pick

.srus_chosen
	ld a, b             ; a = chosen stage map ID
	ld [wRogueMap], a
	ret                 ; caller sets warp flags if needed

SelectRandomUnvisitedStage::
	; Full exit-tile behaviour: pick stage AND trigger the script warp.
	call _PickRandomUnvisitedStage
	ld a, 1
	ld [wDestinationWarpID], a
	ld a, INDIGO_PLATEAU_LOBBY
	ld [wLastMap], a
	ld hl, wStatusFlags3
	set BIT_WARP_FROM_CUR_SCRIPT, [hl]
	ret

; ============================================================
; _PickNextStage  (private)
; Decides whether the next stage should be a ROUTE or a GYM and picks it,
; based on wRogueFlagsBitfield bit 0: route scripts set this bit on entry
; ("gym is next"), and gym leader scripts clear it on badge receipt
; ("route is next"), giving the sequence route, gym, route, gym, ...
; OUTPUT: wRogueMap = picked stage's map ID
; ============================================================
_PickNextStage:
IF DEF(_DEBUG)
	; Debug 2: if a specific stage was chosen at setup, force it instead of
	; picking randomly. Index is interpreted as a gym (GymMapByBadge) or route
	; (RogueStageMapTable) per the gym-next flag. Consumed after one use so
	; later stages pick randomly again.
	ld a, [wStatusFlags6]
	bit BIT_DEBUG2_MODE, a
	jr z, .noDebug2Force
	ld a, [wDebug2ForcedStage]
	and a
	jr z, .noDebug2Force
	dec a                           ; 1-based -> 0-based index
	ld e, a
	ld d, 0
	xor a
	ld [wDebug2ForcedStage], a      ; consume: only force the next stage
	ld a, [wRogueFlagsBitfield]
	bit BIT_ROGUE_GYM_NEXT, a
	ld hl, RogueStageMapTable
	jr z, .haveForceTable
	ld hl, GymMapByBadge
.haveForceTable
	add hl, de
	ld a, [hl]
	ld [wRogueMap], a
	ret
.noDebug2Force
ENDC
	ld a, [wRogueFlagsBitfield]
	bit 0, a
	jp z, _PickRandomUnvisitedStage ; bit clear = route next
	jp _PickNextGym                 ; bit set = gym next (sets wRogueMap)

; ============================================================
; SelectAndPatchLobbyExit / SelectAndPatchRewardRoomExit
; Wrappers that combine _PickNextStage + PatchWarpEntry in one
; internal call (same bank), avoiding the farcall-clobbers-b problem.
; Scripts use farcall to reach these; the internal calls use direct call.
; Both doors lead to the SAME next stage (route/gym alternating); the
; door choice only determines which item-category reward is offered.
; ============================================================
SelectAndPatchLobbyExit::
	; Pick two distinct random item types (HEALING=0, STAT=1, TM=2, MONEY=3).
	; Door 1: pick freely from 4.
	ld c, 4
	call Rangerandom
	ld [wRogueDoor1], a
	ld b, a                        ; b = door 1 type
	; Door 2: pick from remaining 3, then shift up past door 1 to avoid duplicate.
	ld c, 3
	call Rangerandom               ; a = 0, 1, or 2
	cp b                           ; if a >= door1 type, increment to skip it
	jr c, .door2Done
	inc a
.door2Done
	ld [wRogueDoor2], a

	; Pick the next stage (alternates route/gym) and patch both doors to it.
	call _PickNextStage
	ld a, [wRogueMap]
	ld [wLobbyDoor1StageMap], a
	ld [wLobbyDoor2StageMap], a
	; Patch door 1 (warp_event 7,11 → Y=11,X=7).
	ld b, 11
	ld c, 7
	call PatchWarpEntry
	; Patch door 2 (warp_event 8,11 → Y=11,X=8).
	ld a, [wLobbyDoor2StageMap]
	ld b, 11
	ld c, 8
	call PatchWarpEntry
	ret

; Patches both lobby exit doors to GAME_CORNER.
; Called from PCWitchText after CHALLENGE_GAMBLERS_PARADISE is accepted,
; because SelectAndPatchLobbyExit already ran on map entry before acceptance.
PatchLobbyExitToGameCorner::
	ld a, GAME_CORNER
	ld [wRogueMap], a
	ld [wLobbyDoor1StageMap], a
	ld [wLobbyDoor2StageMap], a
	ld b, 11
	ld c, 7
	call PatchWarpEntry
	ld a, GAME_CORNER
	ld b, 11
	ld c, 8
	call PatchWarpEntry
	ret

SelectAndPatchRewardRoomExit::
	; Mirrors SelectAndPatchLobbyExit: the reward room is its own route+gym
	; choice hub, using its two ROGUE_MAP-dest door warps.
	; Pick two distinct random item types (HEALING=0, STAT=1, TM=2, MONEY=3).
	; Door 1: pick freely from 4.
	ld c, 4
	call Rangerandom
	ld [wRogueDoor1], a
	ld b, a                        ; b = door 1 type
	; Door 2: pick from remaining 3, then shift up past door 1 to avoid duplicate.
	ld c, 3
	call Rangerandom               ; a = 0, 1, or 2
	cp b                           ; if a >= door1 type, increment to skip it
	jr c, .door2Done
	inc a
.door2Done
	ld [wRogueDoor2], a

	; Pick the next stage (alternates route/gym) and patch both doors to it.
	call _PickNextStage
	ld a, [wRogueMap]
	ld [wLobbyDoor1StageMap], a
	ld [wLobbyDoor2StageMap], a
	; Patch door 1 (warp_event $6,$1 → Y=1,X=6).
	ld b, 1
	ld c, $6
	call PatchWarpEntry
	; Patch door 2 (warp_event $A,$1 → Y=1,X=$A).
	ld a, [wLobbyDoor2StageMap]
	ld b, 1
	ld c, $A
	call PatchWarpEntry
	ret

; ============================================================
; PatchWarpEntry
; Patches ALL warp entries in wWarpEntries that have Y==b and X==c,
; changing their destination map ID to a.
; Call this after SelectRandomUnvisitedStage to redirect exit warps.
;
; INPUT: a = new destination map ID, b = exit tile Y, c = exit tile X
; ============================================================
PatchWarpEntry::
	ld d, a                    ; d = new map ID to write
	ld a, [wNumberOfWarps]
	ld e, a                    ; e = remaining entries to check
	ld hl, wWarpEntries
.pwe_loop
	ld a, e
	and a
	ret z                      ; exhausted all entries
	ld a, [hli]                ; read Y coord
	cp b                       ; Y match?
	jr nz, .pwe_skip
	ld a, [hli]                ; read X coord
	cp c                       ; X match?
	jr nz, .pwe_skip2
	ld [hl], 1                 ; patch warpID = 1 (stage lobby-entrance position)
	inc hl
	ld [hl], d                 ; patch map ID
	inc hl                     ; advance past patched byte
	dec e
	jr .pwe_loop
.pwe_skip2
	inc hl                     ; skip warpID
	inc hl                     ; skip map ID
	dec e
	jr .pwe_loop
.pwe_skip
	inc hl                     ; skip X
	inc hl                     ; skip warpID
	inc hl                     ; skip map ID
	dec e
	jr .pwe_loop
