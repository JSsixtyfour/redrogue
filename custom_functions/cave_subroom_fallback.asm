; Bank26 helper for the existing cave generator. One ordinary ladder remains
; in A; only when no distant partner fits, supply the entrance as ladder B.
; Applies to all one-ladder caves. SRAM0 stays open; no new scans or RNG rolls.
CaveAddEntranceLadder::
	; The protected entrance block36 is four walkable floor quadrants. Block40
	; preserves its two NPC spots and BL arrival; only BR becomes a ladder.
	; No item/prefab is placed on block36. Its return uses existing ROM warp0,
	; so no dynamic camera/parity override or extra warp slot is needed.
	ld a, CAVE_LADDER_BLOCK
	ld hl, wOverworldMap + 81 + CAVESUB_ENTRANCE_Y * 26 + CAVESUB_ENTRANCE_X
	ld [hl], a
	; Floor decals14/19 east of BR have BL open but TL blocked. Restore that
	; known floor cell so its route goes around the ladder through TR instead.
	; Other decals and all authored terrain remain untouched. Items cannot
	; stand this close to the entrance, and drop-in buffers exclude this row.
	inc hl
	ld a, [hl]
	cp 14
	jr z, .floor
	cp 19
	jr nz, .saved
.floor
	ld [hl], 1
.saved
	ld a, CAVESUB_ENTRANCE_LADDER
	ld [CAVESUB_LADDER_B], a
	ret
