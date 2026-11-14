; ============================================================
; LobbyHealWarning
; Per-frame tail of IndigoPlateauLobby_Script (rfarjp). Once per lobby visit,
; when the player stands on the tile directly below an open exit door with a
; hurt party and has not used the nurse, print a one-box reminder. The player
; is not stopped; stepping into the door afterwards leaves as normal.
;
; Facing is deliberately not checked: from that tile a single Up press steps
; straight onto the door warp, and the warp fires before the next map-script
; frame, so a player who arrives sideways (e.g. after reading a door sign) and
; then presses Up would otherwise never see it.
;
; BIT_LOBBY_HEAL_HANDLED (wStatusFlags4) is the once-per-visit latch: cleared
; on fresh lobby entry, set by the nurse (DisplayPokemonCenterDialogue_) and
; by this warning.
;
; "Hurt" means any party mon below max HP (fainted included) or with a status.
; PP is not checked: max PP needs the move table and PP Ups, which the nurse
; already covers via HealParty.
;
; Clobbers everything. Returns straight to RunMapScript.
; ============================================================
LobbyHealWarning::
	ld hl, wStatusFlags4
	bit BIT_LOBBY_HEAL_HANDLED, [hl]
	ret nz
	ld a, [wWalkCounter]
	and a
	ret nz                        ; mid-step
	ld a, [wYCoord]
	cp 1                          ; the row below the doors (warps at y=0)
	ret nz
	ld a, [wXCoord]
	cp 8                          ; door 1 (warp 2)
	jr z, .door1
	cp 10                         ; door 2 (warp 3)
	ret nz
	farcall Lobby_IsDoor2Blocked  ; NZ = walled off
	ret nz
	jr .doorOpen
.door1
	farcall LegendaryBossClosedDoors
	bit 0, e                      ; door 1 closed by the legendary bargain
	ret nz
.doorOpen
	call LobbyPartyNeedsHealing
	ret z
.warn
	ld hl, wStatusFlags4
	set BIT_LOBBY_HEAL_HANDLED, [hl]
	; Same text-window lifecycle as the rental/loss notices: CloseTextDisplay
	; (reached through AfterDisplayingTextID) pops this saved bank.
	ldh a, [hLoadedROMBank]
	push af
	ld a, 1                       ; any non-zero id: DisplayTextIDInit draws the
	ldh [hTextID], a              ; dialogue box (0 means the start menu box)
	rfarcall DisplayTextIDInit
	ld hl, LobbyHealWarningText
	call PrintText
	jp AfterDisplayingTextID

; NZ if any party mon has lost HP or has a status condition; Z if the whole
; party is fit (or empty). Clobbers af, c, de, hl.
LobbyPartyNeedsHealing:
	ld a, [wPartyCount]
	and a
	ret z
	ld c, a
	ld hl, wPartyMon1
.loop
	push hl
	ld de, MON_MAXHP
	add hl, de
	ld a, [hli]
	ld d, a
	ld e, [hl]                    ; de = max HP
	pop hl
	push hl
	ASSERT MON_HP == 1
	inc hl
	ld a, [hli]
	cp d
	jr nz, .hurt
	ld a, [hli]
	cp e
	jr nz, .hurt
	ASSERT MON_STATUS == MON_HP + 3
	inc hl
	ld a, [hl]
	and a
	jr nz, .hurt
	pop hl
	ld de, PARTYMON_STRUCT_LENGTH
	add hl, de
	dec c
	jr nz, .loop
	xor a                         ; Z: nothing to heal
	ret
.hurt
	pop hl                        ; flags still NZ from the failed compare
	ret

LobbyHealWarningText:
	text "You have not"
	line "visited the"
	cont "NURSE."

	para "Are you sure you"
	line "want to leave?"
	done
