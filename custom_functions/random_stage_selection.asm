; custom_functions/random_stage_selection.asm
;
; No-duplicate stage selection for the roguelike run.
; Uses a 4-byte bitfield (wVisitedStagesBitfield) where bit N
; tracks whether stage N (by index in RogueStageMapTable) has
; been visited this run.

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
SelectRandomUnvisitedStage::
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
	push bc
	call BattleRandom   ; a = random byte
	pop bc
.srus_mod               ; reduce a to range [0, b-1] via repeated subtraction
	cp b
	jr c, .srus_modDone
	sub b
	jr .srus_mod
.srus_modDone
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
	and b               ; Z = unvisited
	pop bc
	pop af              ; restore map ID into a
	pop hl
	jr nz, .srus_pickSkip   ; visited: skip this stage
	ld b, a             ; stash map ID in b while we check the counter
	ld a, c
	and a               ; is target counter 0?
	jr z, .srus_chosen  ; yes — this is the stage we want
	dec c               ; not yet — move to next unvisited
.srus_pickSkip
	inc e
	jr .srus_pick

.srus_chosen
	ld a, b             ; a = chosen stage map ID
	ldh [hWarpDestinationMap], a
	ld a, 1             ; warp ID 1 = lobby-entrance position in every stage map
	ld [wDestinationWarpID], a
	ld a, INDIGO_PLATEAU_LOBBY
	ld [wLastMap], a
	ld hl, wStatusFlags3
	set BIT_WARP_FROM_CUR_SCRIPT, [hl]
	ret
