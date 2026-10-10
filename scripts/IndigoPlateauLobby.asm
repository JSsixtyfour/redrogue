IndigoPlateauLobby_Script:
	; force facing up on entry only, regardless of which warp brought the player here
	ld hl, wCurrentMapScriptFlags
	bit BIT_CUR_MAP_LOADED_1, [hl]
	res BIT_CUR_MAP_LOADED_1, [hl]
	jr z, .skipFaceUp
	; ShinRed normally applies its 60 fps option from the overworld loop. Red
	; Rogue does not run that global path, so enable the configured CGB CPU speed
	; for this sprite-heavy hub only. WarpFound2 restores normal speed on exit.
	predef SetCPUSpeed
	ld a, SPRITE_FACING_UP
	ld [wSpritePlayerStateData1FacingDirection], a
.skipFaceUp
	call EnableAutoTextBoxDrawing
	CheckEvent EVENT_ENTER_ROOM
	jr nz, .normal

	SetEvent EVENT_ENTER_ROOM
	; Blacking out mid-run should respawn the player in their dorm room, not
	; wherever wLastMap happens to be. This is the run's sole blackout target;
	; the Lobby nurse deliberately does not update it when healing.
	ld a, SILPH_CO_DORM
	ld [wLastBlackoutMap], a

	; Pick the next random stage and patch the exit warp before deriving either
	; the visible door block or the active sign count from that selection.
	; Uses SelectAndPatchLobbyExit (no BIT_WARP_FROM_CUR_SCRIPT, since that flag
	; would cause an immediate warp before the player could do anything).
	farcall SelectAndPatchLobbyExit
	farcall ProcPreloadAssignedWildArea
	; Lobby music: MapSongBanks (data/maps/songs.asm) defaults this map to
	; MUSIC_POKECENTER; once Victory Road is cleared, permanently override to
	; MUSIC_INDIGO_PLATEAU for the rest of the run (re-applied every visit,
	; since EVENT_ENTER_ROOM resets on every warp).
	CheckEvent EVENT_VICTORY_ROAD_CLEARED
	jr z, .lobbyMusicDone
	ld a, MUSIC_INDIGO_PLATEAU
	ld [wMapMusicSoundID], a
	ld a, BANK(Music_IndigoPlateau)
	ld [wMapMusicROMBank], a
.lobbyMusicDone
	; Place the exit door as soon as the selection exists; the setups below take
	; several frames. The map-loaded path re-applies it (a no-op by then).
	call Lobby_UpdateExitDoor
	ld c, TRADE_FOR_RANDOM
	ld b, FLAG_RESET
	ld hl, wCompletedInGameTradeFlags
	predef FlagActionPredef
	ResetEvent EVENT_BOUGHT_POKEMON
	call PCPokemonSalesmanSetup
	; Both setups use wroguenpctradename as scratch. Leave the trader last so its
	; receive species, rather than the salesman's species, owns the trade nickname.
	call PCTraderSuperNerdSetup
	call PCClerksSetup
	farcall PCWitchSetup
	farcall PCPsychicSetup    ; after SelectAndPatchLobbyExit: reads wRogueMap; also rolls salesman/trader/tutor

.normal
	; Door 2's baked-in notepad is absent when its block is a wall. Refresh on
	; the finalized selection and after battle/header reloads.
	call Lobby_IsDoor2Blocked
	ld a, 1
	jr nz, .setSignCount
	inc a
.setSignCount
	ld [wNumSigns], a
	ld hl, wCurrentMapScriptFlags
	bit BIT_CUR_MAP_LOADED_2, [hl]
	res BIT_CUR_MAP_LOADED_2, [hl]
	ret z
	; Re-apply the exit door on EVERY map load, not just the first entry:
	; LoadMapData rebuilds the blocks from ROM, so continuing a save made in the
	; lobby would otherwise show door 2 open even though the selection says it
	; is a wall.
	jp Lobby_UpdateExitDoor
	;ResetEvent EVENT_VICTORY_ROAD_1_BOULDER_ON_SWITCH
	; Reset Elite Four events if the player started challenging them before
	;ld hl, wElite4Flags
	;bit BIT_STARTED_ELITE_4, [hl]
	;res BIT_STARTED_ELITE_4, [hl]
	;ret z
	;ResetEventRange INDIGO_PLATEAU_EVENTS_START, EVENT_LANCES_ROOM_LOCK_DOOR
	ret

IndigoPlateauLobby_TextPointers:
	def_text_pointers
	dw_const IndigoPlateauLobbyNurseText,            TEXT_PC_NURSE
    dw_const PCClerkText1,                           TEXT_PC_CLERK1
    dw_const PCClerkText2,                           TEXT_PC_CLERK2
    dw_const PCDaycareGentlemanText,                 TEXT_PC_DAYCARE_GENTLEMAN
    dw_const PCDaycareLadyText,                      TEXT_PC_DAYCARE_LADY
    dw_const MoveRelearnerText1,                     TEXT_PC_MOVE_RELEARNER
    dw_const PCPsychicText,                          TEXT_PC_PSYCHIC
	dw_const PCWitchText,                            TEXT_PC_WITCH
	dw_const PCPokemonSalesmanText,                  TEXT_PC_POKEMON_SALESMAN
    dw_const PCTraderSuperNerdText,                  TEXT_PC_TRADER_SUPER_NERD
    dw_const PCMoveTutorText,                        TEXT_PC_MOVE_TUTOR
	dw_const LobbyDoor1SignText,                     TEXT_PC_DOOR1_SIGN
	dw_const LobbyDoor2SignText,                     TEXT_PC_DOOR2_SIGN

LobbyDoor1SignText:
	text_asm
; Final sequence: once all 8 badges are obtained, both doors always lead to
; the same place, so the usual item/mini-boss framing below never applies
; (MiniBossRollAndAssign is skipped entirely during the finale) - handled
; here instead. Victory Road still offers a real per-door item choice (the
; category rolls happen unconditionally in SelectAndPatchLobbyExit, same as
; a normal route), so its sign keeps the category line; the Elite Four has
; no item rewards at all, so its sign drops it entirely.
	ld a, [wRogueDoor1]
	call LobbyFinaleSignCheck
	ret nz
	ld a, [wLobbyDoor1StageMap]
	call LobbySignWildAreaCheck   ; hl -> "WILD AREA + subtype" text if this door is wild
	ret nz                        ; NZ = handled (hl set); Z = not wild, fall through
	ld a, [wLobbyDoor1StageMap]
	call LobbySignBridgeCheck     ; hl -> room-name text if this door is a bridge room
	ret nz
; Mini-boss framework: if a mini-boss is offered this route selection AND
; door 1 is the mini-boss door (BIT_MINIBOSS_DOOR clear), the sign is replaced
; entirely with a boss-specific message instead of the item category. Gym-next
; selections never offer a mini-boss (MiniBossRollAndAssign clears the type
; bits on that path), so this can never fire alongside the gym framing below.
; NOTE: this runs as a text_asm handler - bc holds the LIVE text cursor
; (TextCommand_START prints via ld h,b/ld l,c), so it must NOT be clobbered.
; That means re-reading wRogueFlagsBitfield rather than caching it in a
; register (an earlier `ld c, a` corrupted the cursor and drifted the text).
	ld a, [wRogueFlagsBitfield]
	and MINIBOSS_TYPE_MASK
	jr z, .noMiniBoss
	ld a, [wRogueFlagsBitfield]
	bit BIT_MINIBOSS_DOOR, a
	jr nz, .noMiniBoss            ; door 2 is the boss door, not this one
	ld a, [wRogueDoor1]           ; this door's item category (0-3)
	call LobbyMiniBossSign        ; hl -> "boss + reward category" combined text
	ret
.noMiniBoss
; Gym next: door 1 is the first of the two latched gyms (or the single hidden
; last one). The sign names it once revealed (LobbyGymSign).
	ld a, [wRogueFlagsBitfield]
	bit 0, a
	jr nz, .gymSign
	ld hl, .itemPtrs
	ld a, [wRogueDoor1]
	ld d, 0
	ld e, a
	add hl, de
	add hl, de          ; hl += 2 * class (each entry is a dw)
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ret
.gymSign
	ld e, 1
	jp LobbyGymSign
.itemPtrs
	dw .healingText
	dw .statText
	dw .tmText
	dw .moneyText
.healingText
	text "DOOR 1:"
	line "HEALING ITEMS@"
	text_end
.statText
	text "DOOR 1:"
	line "STAT BOOSTS@"
	text_end
.tmText
	text "DOOR 1:"
	line "TM ITEMS@"
	text_end
.moneyText
	text "DOOR 1:"
	line "MONEY@"
	text_end

LobbyDoor2SignText:
	text_asm
; Final sequence: see LobbyDoor1SignText - same shared finale check.
	ld a, [wRogueDoor2]
	call LobbyFinaleSignCheck
	ret nz
	ld a, [wLobbyDoor2StageMap]
	call LobbySignWildAreaCheck   ; hl -> "WILD AREA + subtype" text if this door is wild
	ret nz                        ; NZ = handled (hl set); Z = not wild, fall through
	ld a, [wLobbyDoor2StageMap]
	call LobbySignBridgeCheck     ; hl -> room-name text if this door is a bridge room
	ret nz
; Mini-boss framework: mirrors LobbyDoor1SignText. The script disables this
; background event when door 2 is blocked, so it needs no gym-framing
; branch here. As in door 1, bc is the live text cursor here
; (text_asm) - do NOT clobber it; re-read wRogueFlagsBitfield instead of caching.
	ld a, [wRogueFlagsBitfield]
	and MINIBOSS_TYPE_MASK
	jr z, .noMiniBoss
	ld a, [wRogueFlagsBitfield]
	bit BIT_MINIBOSS_DOOR, a
	jr z, .noMiniBoss             ; door 1 is the boss door, not this one
	ld a, [wRogueDoor2]           ; this door's item category (0-3)
	call LobbyMiniBossSign        ; hl -> "boss + reward category" combined text
	ret
.noMiniBoss
	ld a, [wRogueFlagsBitfield]
	bit 0, a
	ld e, 2
	jp nz, LobbyGymSign
	ld a, [wRogueDoor2]
	ld hl, .itemPtrs
	ld d, 0
	ld e, a
	add hl, de
	add hl, de
.deref
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ret
.itemPtrs
	dw .healingText
	dw .statText
	dw .tmText
	dw .moneyText
.healingText
	text "DOOR 2:"
	line "HEALING ITEMS@"
	text_end
.statText
	text "DOOR 2:"
	line "STAT BOOSTS@"
	text_end
.tmText
	text "DOOR 2:"
	line "TM ITEMS@"
	text_end
.moneyText
	text "DOOR 2:"
	line "MONEY@"
	text_end

; Final sequence sign check, shared by both door sign handlers. Once all 8
; badges are obtained, both doors lead to the same place: Victory Road
; (still a real per-door item choice - the category rolls happen
; unconditionally in SelectAndPatchLobbyExit, same as a normal route, so the
; sign keeps the "MINIBOSS" + category framing, mirroring LobbyMiniBossSign),
; then the Elite Four (no item rewards at all, so no category line).
; INPUT: a = this door's item category (0-3, from wRogueDoor1/wRogueDoor2) -
;        only consulted for the Victory Road case.
; OUTPUT: Z set - not in the final sequence; caller falls through to its
;             normal item/mini-boss framing.
;         Z clear, hl -> the finale sign text - caller should `ret` (the
;             `ret nz` right after the call site does this).
; Whether door 2 (tile + sign) should be blocked, shared by the two call
; sites in IndigoPlateauLobby_Script. During the final sequence, Victory
; Road still offers a real choice of two doors (both routes to the same
; place, different item category), same as a normal route - but the Elite
; Four has no second option, so it always blocks door 2, same as gym-next.
; OUTPUT: NZ - door 2 blocked (Elite Four phase, or the existing gym-next
;             case). Z - door 2 open (Victory Road phase, or a normal
;             route-next case).
; CLOBBERS: a
; update exit door tile based on whether gym or route is next (or, during the
; final sequence, the Elite Four - see Lobby_IsDoor2Blocked). ReplaceTileBlock
; returns early when the block already matches, so repeat calls are cheap.
Lobby_UpdateExitDoor:
	call Lobby_IsDoor2Blocked
	jr nz, .blockExitToSecondDoor
	ld a, $08 ; authored open door plus tile-based notepad
	jr .setExitDoor
.blockExitToSecondDoor
	ld a, $C
.setExitDoor
	ld [wNewTileBlockID], a
	lb bc, 0, 5
	predef_jump ReplaceTileBlock

Lobby_IsDoor2Blocked:
	ld a, [wObtainedBadges]
	cp $FF
	jr nz, .normalCheck
	CheckEvent EVENT_VICTORY_ROAD_CLEARED
	jr z, .door2Open        ; Victory Road phase - both doors stay open
	or 1                    ; Elite Four phase - force NZ (blocked). a now holds
	                        ; the event byte rather than wElite4Flags; the `or 1`
	                        ; guarantees NZ either way.
	ret
.door2Open
	xor a                   ; force Z (open)
	ret
.normalCheck
	; bridge visit: both doors are (different) bridge rooms -> door 2 stays OPEN
	; even during a gym cycle (bridges fire during gyms too, unlike wild areas).
	ld a, [wLobbyDoor1StageMap]
	call LobbyIsBridgeMap         ; NZ = bridge room
	jr z, .notBridge
	ld a, [wLobbyDoor2StageMap]
	call LobbyIsBridgeMap
	jr z, .notBridge
	xor a                         ; both bridge -> Z = door 2 open
	ret
.notBridge
	; A forced single wild area or miniboss collapses both destinations.
	ld a, [wLobbyDoor1StageMap]
	call LobbyIsWildEntryMap      ; NZ = wild entry map
	jr nz, .checkCollapsed
	ld a, [wRogueFlagsBitfield]
	and MINIBOSS_TYPE_MASK
	jr z, .checkGymNext
.checkCollapsed
	ld a, [wLobbyDoor1StageMap]
	ld b, a
	ld a, [wLobbyDoor2StageMap]
	cp b
	jr nz, .checkGymNext
	or 1                          ; NZ = blocked
	ret
.checkGymNext
	; Gym next: door 2 is open when it leads to a second gym (SelectAndPatchLobbyExit
	; points it there), blocked when one gym is left (both doors the same map).
	ld a, [wRogueFlagsBitfield]
	bit 0, a
	ret z
	ld a, [wLobbyDoor1StageMap]
	ld b, a
	ld a, [wLobbyDoor2StageMap]
	cp b
	jr z, .gymSingle
	xor a                         ; Z = open
	ret
.gymSingle
	or 1                          ; NZ = blocked
	ret

; e = door (1 or 2). The gym sign's two lines, built in $3C (LobbyBuildGymSign):
; "PEWTER GYM" / "BROCK/ROCK", or "??? GYM" / "???/???" while hidden.
; bc is the live text cursor in these text_asm handlers; a farcall destroys it.
LobbyGymSign:
	push bc
	farcall LobbyBuildGymSign
	pop bc
	ld hl, .text
	ret
.text
	text_ram wNameBuffer
	text_start
	line "@"
	text_ram wStringBuffer
	text_end

; CLOBBERS: a, de, hl
LobbyFinaleSignCheck:
	ld e, a                       ; stash caller's item category
	ld a, [wObtainedBadges]
	cp $FF
	jr nz, .notFinale
	CheckEvent EVENT_VICTORY_ROAD_CLEARED
	jr nz, .eliteFour
	ld a, e                       ; restore item category
	call LobbyMiniBossVictoryRoadSign ; hl -> "MINIBOSS" + category combined text
	jr .isFinale
.eliteFour
	ld hl, .EliteFourSign
.isFinale
	or 1                ; force Z clear regardless of what's in a
	ret
.notFinale
	xor a               ; Z set
	ret
.EliteFourSign
	text "ELITE FOUR"
	line "AWAITS@"
	text_end

; Victory Road door sign: line 1 = "MINIBOSS", line 2 = the door's item
; reward category (still shown - Victory Road offers a real choice per door,
; unlike the Elite Four). Mirrors LobbyMiniBossSign's structure/table shape.
; INPUT: a = item category (0-3). Returns hl -> combined text.
LobbyMiniBossVictoryRoadSign:
	ld hl, .ptrs
	ld d, 0
	ld e, a
	add hl, de
	add hl, de
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ret
.ptrs
	dw .healing
	dw .stat
	dw .tm
	dw .money
.healing
	text "MINIBOSS"
	line "HEALING ITEMS@"
	text_end
.stat
	text "MINIBOSS"
	line "STAT BOOSTS@"
	text_end
.tm
	text "MINIBOSS"
	line "TM ITEMS@"
	text_end
.money
	text "MINIBOSS"
	line "MONEY@"
	text_end

; a = this door's stage map. If it's a wild-area entry map, returns hl -> the matching
; "WILD AREA / <subtype>" text and NZ (caller rets). Otherwise Z (caller falls through
; to the normal mini-boss/item sign). Clobbers a/hl only (bc = live text cursor kept).
LobbySignWildAreaCheck:
	cp PROCEDURAL_CAVE_1
	jr z, .cave
	cp PROCEDURAL_FOREST
	jr z, .forest
	cp PROCEDURAL_CEMETERY_1
	jr z, .cem
	cp PROCEDURAL_FACILITY
	jr z, .facility
	xor a                 ; Z = not wild
	ret
.cave:
	ld hl, .caveText
	jr .done
.forest:
	ld hl, .forestText
	jr .done
.cem:
	ld hl, .cemText
	jr .done
.facility:
	ld hl, .facilityText
.done:
	or 1                  ; NZ = handled
	ret
.caveText:
	text "WILD AREA:"
	line "CAVE@"
	text_end
.forestText:
	text "WILD AREA:"
	line "FOREST@"
	text_end
.cemText:
	text "WILD AREA:"
	line "CEMETERY@"
	text_end
.facilityText:
	text "WILD AREA:"
	line "FACILITY@"
	text_end

; a = map -> NZ if it's a wild-area entry map, else Z.
; Clobbers a.
LobbyIsWildEntryMap:
	cp PROCEDURAL_CAVE_1
	jr z, .yes
	cp PROCEDURAL_FOREST
	jr z, .yes
	cp PROCEDURAL_CEMETERY_1
	jr z, .yes
	cp PROCEDURAL_FACILITY
	jr z, .yes
	xor a
	ret
.yes:
	or 1
	ret

; a = this door's stage map. If it's a bridge room, returns hl -> that room's
; "location name" sign text and NZ (caller rets). Otherwise Z (fall through).
; Runs as a text_asm handler, so bc (the live text cursor) is preserved.
; Clobbers a/hl. KEEP LobbyBridgeSignTable in sync with BridgeRoomMaps
; (custom_functions/bridge_selection.asm).
LobbySignBridgeCheck:
	push bc
	ld c, a                       ; c = door map to find
	ld hl, LobbyBridgeSignTable
.scan:
	ld a, [hl]
	cp $ff
	jr z, .notBridge
	cp c
	jr z, .found
	inc hl                        ; skip map id
	inc hl                        ; skip dw text ptr
	inc hl
	jr .scan
.found:
	inc hl
	ld a, [hli]
	ld h, [hl]
	ld l, a                       ; hl -> sign text
	pop bc
	or 1                          ; NZ = handled
	ret
.notBridge:
	pop bc
	xor a                         ; Z = not a bridge room
	ret

; a = map -> NZ if it's a bridge room map, else Z. Preserves bc/de/hl.
LobbyIsBridgeMap:
	push hl
	push de
	ld e, a
	ld hl, LobbyBridgeSignTable
.scan:
	ld a, [hl]
	cp $ff
	jr z, .no
	cp e
	jr z, .yes
	inc hl
	inc hl
	inc hl
	jr .scan
.yes:
	pop de
	pop hl
	or 1
	ret
.no:
	pop de
	pop hl
	xor a
	ret

LobbyBridgeSignTable:
	db COPYCATS_HOUSE_2F
	dw .copycatText
	db BILLS_HOUSE
	dw .billText
	db MR_FUJIS_HOUSE
	dw .fujiText
	db SS_ANNE_CAPTAINS_ROOM
	dw .captainText
	db CINNABAR_LAB_FOSSIL_ROOM
	dw .fossilText
	db POKEMON_FAN_CLUB
	dw .fanClubText
	db WARDENS_HOUSE
	dw .wardenText
	db VIRIDIAN_SCHOOL_HOUSE
	dw .schoolText
	db VIRIDIAN_NICKNAME_HOUSE
	dw .nicknameText
	db CERULEAN_TRASHED_HOUSE
	dw .trashedText
	db REDS_HOUSE_1F
	dw .redsHouseText
	db IGAS_DOJO
	dw .igaDojoText
	db FLORAS_GROTTO
	dw .floraGrottoText
	db OAKS_LAB
	dw .oaksLabText
	db $ff
.copycatText:
	text "COPY CAT's"
	line "HOUSE@"
	text_end
.billText:
	text "BILL's"
	line "HOUSE@"
	text_end
.fujiText:
	text "MR.FUJI's"
	line "HOUSE@"
	text_end
.captainText:
	text "CAPTAIN's"
	line "ROOM@"
	text_end
.fossilText:
	text "FOSSIL"
	line "ROOM@"
	text_end
.fanClubText:
	text "#MON FAN"
	line "CLUB@"
	text_end
.wardenText:
	text "WARDEN's"
	line "HOUSE@"
	text_end
.schoolText:
	text "SCHOOL"
	line "HOUSE@"
	text_end
.nicknameText:
	text "NICKNAME"
	line "HOUSE@"
	text_end
.trashedText:
	text "TRASHED"
	line "HOUSE@"
	text_end
.redsHouseText:
	text "RED's"
	line "HOUSE@"
	text_end
.igaDojoText:
	text "IGA's"
	line "DOJO@"
	text_end
.floraGrottoText:
	text "FLORA's"
	line "GROTTO@"
	text_end
.oaksLabText:
	text "OAK's"
	line "LAB@"
	text_end

; Door number, named encounter, then item prize. The far text keeps these
; permutations out of the tight map bank. Preserve bc, the live text cursor.
; INPUT: a = item category; type and door come from wRogueFlagsBitfield.
LobbyMiniBossSign:
	ld e, a
	ld a, [wRogueFlagsBitfield]
	and MINIBOSS_TYPE_MASK
	swap a
	dec a
	add a
	add a
	add e
	ld e, a
	ld a, [wRogueFlagsBitfield]
	bit BIT_MINIBOSS_DOOR, a
	jr z, .doorReady
	ld a, e
	add 12
	ld e, a
.doorReady
	ld d, 0
	ld hl, .texts
	add hl, de
	add hl, de
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ret
.texts
	dw .LobbyDoor1RivalHealing
	dw .LobbyDoor1RivalStat
	dw .LobbyDoor1RivalTM
	dw .LobbyDoor1RivalMoney
	dw .LobbyDoor1GiovanniHealing
	dw .LobbyDoor1GiovanniStat
	dw .LobbyDoor1GiovanniTM
	dw .LobbyDoor1GiovanniMoney
	dw .LobbyDoor1KarateHealing
	dw .LobbyDoor1KarateStat
	dw .LobbyDoor1KarateTM
	dw .LobbyDoor1KarateMoney
	dw .LobbyDoor2RivalHealing
	dw .LobbyDoor2RivalStat
	dw .LobbyDoor2RivalTM
	dw .LobbyDoor2RivalMoney
	dw .LobbyDoor2GiovanniHealing
	dw .LobbyDoor2GiovanniStat
	dw .LobbyDoor2GiovanniTM
	dw .LobbyDoor2GiovanniMoney
	dw .LobbyDoor2KarateHealing
	dw .LobbyDoor2KarateStat
	dw .LobbyDoor2KarateTM
	dw .LobbyDoor2KarateMoney
.LobbyDoor1RivalHealing
	text_far _LobbyDoor1RivalHealingText
	text_end
.LobbyDoor1RivalStat
	text_far _LobbyDoor1RivalStatText
	text_end
.LobbyDoor1RivalTM
	text_far _LobbyDoor1RivalTMText
	text_end
.LobbyDoor1RivalMoney
	text_far _LobbyDoor1RivalMoneyText
	text_end
.LobbyDoor1GiovanniHealing
	text_far _LobbyDoor1GiovanniHealingText
	text_end
.LobbyDoor1GiovanniStat
	text_far _LobbyDoor1GiovanniStatText
	text_end
.LobbyDoor1GiovanniTM
	text_far _LobbyDoor1GiovanniTMText
	text_end
.LobbyDoor1GiovanniMoney
	text_far _LobbyDoor1GiovanniMoneyText
	text_end
.LobbyDoor1KarateHealing
	text_far _LobbyDoor1KarateHealingText
	text_end
.LobbyDoor1KarateStat
	text_far _LobbyDoor1KarateStatText
	text_end
.LobbyDoor1KarateTM
	text_far _LobbyDoor1KarateTMText
	text_end
.LobbyDoor1KarateMoney
	text_far _LobbyDoor1KarateMoneyText
	text_end
.LobbyDoor2RivalHealing
	text_far _LobbyDoor2RivalHealingText
	text_end
.LobbyDoor2RivalStat
	text_far _LobbyDoor2RivalStatText
	text_end
.LobbyDoor2RivalTM
	text_far _LobbyDoor2RivalTMText
	text_end
.LobbyDoor2RivalMoney
	text_far _LobbyDoor2RivalMoneyText
	text_end
.LobbyDoor2GiovanniHealing
	text_far _LobbyDoor2GiovanniHealingText
	text_end
.LobbyDoor2GiovanniStat
	text_far _LobbyDoor2GiovanniStatText
	text_end
.LobbyDoor2GiovanniTM
	text_far _LobbyDoor2GiovanniTMText
	text_end
.LobbyDoor2GiovanniMoney
	text_far _LobbyDoor2GiovanniMoneyText
	text_end
.LobbyDoor2KarateHealing
	text_far _LobbyDoor2KarateHealingText
	text_end
.LobbyDoor2KarateStat
	text_far _LobbyDoor2KarateStatText
	text_end
.LobbyDoor2KarateTM
	text_far _LobbyDoor2KarateTMText
	text_end
.LobbyDoor2KarateMoney
	text_far _LobbyDoor2KarateMoneyText
	text_end

IndigoPlateauLobbyNurseText:
	script_pokecenter_nurse

; Sells next-gym foresight; see engine/events/lobby_psychic.asm.
PCPsychicText:
	text_asm
	farcall PCPsychicTalk
	jp TextScriptEnd

YesNoScript:
	call PrintText
	call YesNoChoice
	ldh a, [hCurrentMenuItem]
	and a
	ret

PCWitchText:
	text_asm
	call SaveScreenTilesToBuffer2
	ld hl, .WitchIntroText
	call YesNoScript
	jr nz, .refuse
	ld a, [wWitchChallenge]
	dec a                    ; 0-based index
	ld hl, .ChallengeTextTable
	ld d, 0
	ld e, a
	add hl, de
	add hl, de                ; hl += 2 * index (each entry is a dw)
	ld a, [hli]
	ld h, [hl]
	ld l, a
	call PrintText             ; just the challenge description, no question yet
	ld a, [wWitchChallenge]
	cp CHALLENGE_LEGENDARY_BOSS
	jr z, .legendaryPrize      ; fixed reward: skip the random prize-table lookup
	                           ; (wWitchPrize = 0 sentinel would underflow the index)
	ld a, [wWitchPrize]
	and a
	jr nz, .havePrizeIndex
	inc a                    ; Defensive: 0 is the "no prize" sentinel, and only
	                         ; CHALLENGE_LEGENDARY_BOSS (handled above) is supposed
	                         ; to reach here with it. `dec a` on 0 underflows to
	                         ; $FF and indexes 510 bytes past .PrizeTextTable, so a
	                         ; stray 0 - a poked value while debugging, or any
	                         ; future challenge that forgets to roll a prize -
	                         ; crashed on a garbage pointer. Fall back to prize 1's
	                         ; teaser instead: wrong text, but harmless.
.havePrizeIndex
	dec a                    ; 0-based index
	ld hl, .PrizeTextTable
	ld d, 0
	ld e, a
	add hl, de
	add hl, de                ; hl += 2 * index (each entry is a dw)
	ld a, [hli]
	ld h, [hl]
	ld l, a
	jr .prizeAsk
.legendaryPrize
	ld hl, .PrizeLegendary
.prizeAsk
	call YesNoScript           ; prize teaser + "Do we have a bargain?"
	jr nz, .refuse
	ld hl, wRogueFlagsBitfield
	set BIT_WITCH_ACCEPTED, [hl]
	ld a, [wWitchChallenge]
	cp CHALLENGE_GAMBLERS_PARADISE
	jr nz, .noGamblerPatch
	farcall PatchLobbyExitToGameCorner
.noGamblerPatch
	ld hl, .Accept
	call PrintText
    call GBFadeOutToBlack
    ld a, TOGGLE_PC_WITCH
    ld [wToggleableObjectIndex], a
    predef HideObject
    call UpdateSprites
    call Delay3
    call GBFadeInFromBlack
	jp TextScriptEnd
.refuse
	ld hl, .Refusal
    call PrintText
	jp TextScriptEnd

.WitchIntroText:
	text_far _WitchIntroText
	text_end

.ChallengeTextTable:
	dw .Challenge1
	dw .Challenge2
	dw .Challenge3
	dw .Challenge4
	dw .Challenge5
	dw .Challenge6
	dw .Challenge7
	dw .Challenge8
	dw .Challenge9
	dw .Challenge10
	dw .Challenge11
	dw .Challenge12
	dw .Challenge13
	dw .Challenge14
	dw .Challenge15
	dw .Challenge16
	dw .Challenge17
	dw .Challenge18

.Challenge1:
	text_far _WitchChallenge1Text
	text_end

.Challenge2:
	text_far _WitchChallenge2Text
	text_end

.Challenge3:
	text_far _WitchChallenge3Text
	text_end

.Challenge4:
	text_far _WitchChallenge4Text
	text_end

.Challenge5:
	text_far _WitchChallenge5Text
	text_end

.Challenge6:
	text_far _WitchChallenge6Text
	text_end

.Challenge7:
	text_far _WitchChallenge7Text
	text_end

.Challenge8:
	text_far _WitchChallenge8Text
	text_end

.Challenge9:
	text_far _WitchChallenge9Text
	text_end

.Challenge10:
	text_far _WitchChallenge10Text
	text_end

.Challenge11:
	text_far _WitchChallenge11Text
	text_end

.Challenge12:
	text_far _WitchChallenge12Text
	text_end

.Challenge13:
	text_far _WitchChallenge13Text
	text_end

.Challenge14:
	text_far _WitchChallenge14Text
	text_end

.Challenge15:
	text_far _WitchChallenge15Text
	text_end

.Challenge16:
	text_far _WitchChallenge16Text
	text_end

.Challenge17:
	text_far _WitchChallenge17Text
	text_end

.Challenge18:
	text_far _WitchChallenge18Text
	text_end

; index = wWitchPrize - 1; see constants/ram_constants.asm for the PRIZE_* ids.
; Rolled independently of the challenge - no fixed pairing.
.PrizeTextTable:
	dw .Prize1
	dw .Prize2
	dw .Prize3
	dw .Prize4
	dw .Prize5
	dw .Prize6
	dw .Prize7
	dw .Prize8
	dw .Prize9
	dw .Prize10

.Prize1:
	text_far _WitchPrize1Text
	text_end

.Prize2:
	text_far _WitchPrize2Text
	text_end

.Prize3:
	text_far _WitchPrize3Text
	text_end

.Prize4:
	text_far _WitchPrize4Text
	text_end

.Prize5:
	text_far _WitchPrize5Text
	text_end

.Prize6:
	text_far _WitchPrize6Text
	text_end

.Prize7:
	text_far _WitchPrize7Text
	text_end

.Prize8:
	text_far _WitchPrize8Text
	text_end

.Prize9:
	text_far _WitchPrize9Text
	text_end

.Prize10:
	text_far _WitchPrize10Text
	text_end

.PrizeLegendary:
	text_far _WitchPrizeLegendaryText
	text_end

.Accept:
	text_far _WitchAcceptanceText
	text_end

.Refusal:
	text_far _WitchRefusalText
	text_end

IndigoPlateauLobbyLinkReceptionistText:
	script_cable_club_receptionist

; The daycare NPCs live in engine/events/lobby_daycare.asm (pinned to $3C):
; this map's bank ($06) had 13 bytes free. See that file's header.
PCDaycareLadyText:
	text_asm
	farcall LobbyDaycareLady
	jp TextScriptEnd

PCDaycareGentlemanText:
	text_asm
	farcall LobbyDaycareGentleman
	jp TextScriptEnd

PCPokemonSalesmanText:
	text_asm
	CheckEvent EVENT_BOUGHT_POKEMON
	jp nz, .alreadyBoughtPokemon ; CheckEvent's 1-arg form returns via Z, not carry - jp c never fired
    
    ld a, [wroguenpcsell]   ; load pokemon for sale
    ld [wNamedObjectIndex], a   ; place pokemon id in spot for GetMonName
    ld a, [wroguenpcsellform]   ; increment 8j: name the offer as its form
    ld [wFormContextForm], a
    ld a, [wNamedObjectIndex]
    ld [wFormContextSpecies], a
    call GetMonName         ; get name of pokemon to receive
    
    ld a, [wroguenpcclass]
    ld hl, .IGotADealTextPokeball
    ld c, 1
    cp c
    jr z, .print
    inc c       ; greatball class
    ld hl, .IGotADealTextGreatball
    cp c
    jr z, .print
	ld hl, .IGotADealTextUltraball
    .print
	call PrintText
	ld a, MONEY_BOX
	ld [wTextBoxID], a
	call DisplayTextBoxID
	call YesNoChoice
	ldh a, [hCurrentMenuItem]
	and a
	jp nz, .choseNo
	ldh [hMoney], a
	ldh [hMoney + 2], a
    
    ; de = the price's two high BCD bytes (balance_constants.asm *_WORD):
    ; the knobs are BCD thousands, so a price can reach Y99,000.
    ld a, [wroguenpcclass]
    ld de, SALESMAN_PRICE_POKEBALL_WORD
    ld c, 1
    cp c
    jr z, .pokemon_cost
    inc c       ; greatball class

    ld de, SALESMAN_PRICE_GREATBALL_WORD
    cp c
    jr z, .pokemon_cost

    ; ultraball class
    ld de, SALESMAN_PRICE_ULTRABALL_WORD

    .pokemon_cost
    ld a, d
	ldh [hMoney], a
    ld a, e
	ldh [hMoney + 1], a
	call HasEnoughMoney
	jr nc, .enoughMoney
	ld hl, .NoMoneyText
	jr .printText
.enoughMoney
    ; this used to be its own hardcoded copy of the old flat formula, computed
    ; fresh and never updated when GetRewardMonLevel was redesigned to be
    ; tailored - the species was already being picked correctly at setup time
    ; using the new logic, but the level given here was silently using the
    ; stale formula. Call the real thing instead so they can't drift apart.
    ; Same farcall-clobbers-a trap as the daycare sites above: `ld c, a` right
    ; after the farcall picked up this script's bank number (6), so every mon
    ; the salesman sold came out at level 6. Read wCurEnemyLevel instead.
    farcall GetRewardMonLevel
    ld a, [wCurEnemyLevel]
    ld c, a             ; c = level
    ld a, [wroguenpcsellform]   ; increment 8j: build it as that form
    ld [wSpawnForm], a
    ld a, [wroguenpcsell]
    ld b, a             ; b = species
	call GivePokemon
	jr nc, .done
	xor a
	ld [wPriceTemp], a
	ld [wPriceTemp + 2], a
    
    ld a, [wroguenpcclass]
    ld de, SALESMAN_PRICE_POKEBALL_WORD
    ld c, 1
    cp c
    jr z, .pokemon_cost_2
    inc c       ; greatball class

    ld de, SALESMAN_PRICE_GREATBALL_WORD
    cp c
    jr z, .pokemon_cost_2

    ; ultraball class
    ld de, SALESMAN_PRICE_ULTRABALL_WORD


	.pokemon_cost_2
    ld a, d
	ld [wPriceTemp], a
    ld a, e
	ld [wPriceTemp + 1], a
	ld hl, wPriceTemp + 2
	ld de, wPlayerMoney + 2
	ld c, $3
	predef SubBCDPredef
	ld a, MONEY_BOX
	ld [wTextBoxID], a
	call DisplayTextBoxID
	SetEvent EVENT_BOUGHT_POKEMON
	jr .done
.choseNo
	ld hl, .NoText
	jr .printText
.alreadyBoughtPokemon
	ld hl, .NoRefundsText
.printText
	call PrintText
.done
	jp TextScriptEnd

.IGotADealTextPokeball
	text_far _PCPokemonSalesmanIGotADealPokeballText
	text_end

.IGotADealTextGreatball
	text_far _PCPokemonSalesmanIGotADealGreatballText
	text_end
    
.IGotADealTextUltraball
	text_far _PCPokemonSalesmanIGotADealUltraballText
	text_end

.NoText
	text_far _PCPokemonSalesmanNoText
	text_end

.NoMoneyText
	text_far _PCPokemonSalesmanNoMoneyText
	text_end

.NoRefundsText
	text_far _PCPokemonSalesmanNoRefundsText
	text_end

; The offer can't be a line the player already owns: PCTraderSuperNerdSetup rolls
; it through Random_Pokemon_Selection, whose AllSpeciesCheck rejects the family.
PCTraderSuperNerdText:
	text_asm
	ld a, TRADE_FOR_RANDOM
	ld [wWhichTrade], a
    predef RogueDoInGameTradeDialogue
	jp TextScriptEnd
    
PCMoveTutorText::
	text_asm
	push bc ; text engine cursor
	ld a, [wPrintItemPrices]
	push af
	call .teach
.finish
	pop af
	ld [wPrintItemPrices], a
	pop bc
	jp TextScriptEnd
.teach
	ld hl, PCMoveTutorGreetingText
	call PrintText
	ld a, MONEY_BOX
	ld [wTextBoxID], a
	call DisplayTextBoxID
	call YesNoChoice
	ldh a, [hCurrentMenuItem]
	and a
	jp nz, .exit
	ld hl, PCMoveTutorSaidYesText
	call PrintText
	; Select pokemon from party.
	call SaveScreenTilesToBuffer2
	xor a
	ld [wListScrollOffset], a
	ld [wPartyMenuTypeOrMessageID], a
	ldh [hUpdateSpritesEnabled], a
	ld [wMenuItemToSwap], a
	call DisplayPartyMenu
	push af
	call GBPalWhiteOutWithDelay3
	call RestoreScreenTilesAndReloadTilePatterns
	call LoadGBPal
	pop af
	jp c, .exit
	ldh a, [hWhichPokemon]
	push af ; party index for the lifetime of the move list
	farcall PrepareMoveTutorList
	ld a, [wMoveBuffer]
	and a
	jr nz, .initMoveMenu
	pop af
	ld hl, PCMoveTutorNoMovesText
	jp PrintText
.initMoveMenu
	xor a
	ldh [hCurrentMenuItem], a
	ld [wListScrollOffset], a
.chooseMove
	; PrintText and the money box reuse menu state. Keep the browsing position.
	ldh a, [hCurrentMenuItem]
	ld b, a
	ld a, [wListScrollOffset]
	ld c, a
	push bc
	ld hl, PCMoveTutorWhichMoveText
	call PrintText
	ld a, MONEY_BOX
	ld [wTextBoxID], a
	call DisplayTextBoxID
	xor a
	ld [wLastMenuItem], a
	ld a, MOVESLISTMENU
	ld [wListMenuID], a
	ld de, wMoveBuffer
	ld hl, wListPointer
	ld [hl], e
	inc hl
	ld [hl], d
	ld a, 1
	ld [wPrintItemPrices], a
	pop bc
	ld a, b
	ldh [hCurrentMenuItem], a
	ld a, c
	ld [wListScrollOffset], a
	call DisplayListMenuID
	pop bc ; b = selected party index; pop preserves the menu carry
	jp c, .exit
	push bc
	ld d, b
	ld a, [wCurListMenuItem]
	ld e, a
	ldh a, [hCurrentMenuItem]
	ld b, a
	ld a, [wListScrollOffset]
	ld c, a
	push bc ; position across confirmation and LearnMove
	call .tryTeach
	pop bc
	jr c, .learned
.retryMove
	ld a, b
	ldh [hCurrentMenuItem], a
	ld a, c
	ld [wListScrollOffset], a
	jp .chooseMove
.learned
	pop af ; party index
	ld a, MONEY_BOX
	ld [wTextBoxID], a
	call DisplayTextBoxID
.exit
	ld hl, PCMoveTutorByeText
	jp PrintText

; d = party index, e = move ID; hItemPrice = the selected list's quote.
; Carry = learned and paid; no carry = retry without payment.
.tryTeach
	push de
	ld a, e
	ld [wNamedObjectIndex], a
	call GetMoveName
	call CopyToStringBuffer
	ld hl, hItemPrice
	ld de, hMoney
	ld bc, 3
	call CopyData
	; Keep the quote across both dialogue and confirmation scratch use.
	ldh a, [hMoney]
	ld b, a
	ldh a, [hMoney + 1]
	ld c, a
	push bc
	ldh a, [hMoney + 2]
	ld b, a
	push bc
.confirmMove
	ld hl, PCMoveTutorConfirmText
	call PrintText
	call YesNoChoice
	ldh a, [hCurrentMenuItem]
	ld e, a
	pop bc
	ld a, b
	ldh [hMoney + 2], a
	pop bc
	ld a, b
	ldh [hMoney], a
	ld a, c
	ldh [hMoney + 1], a
	ld a, e
	and a
	jr nz, .declined
	call HasEnoughMoney
	jr c, .notEnoughMoney
	pop de ; selected Pokemon and move, not the yes/no menu's selection
	ld a, d
	ldh [hWhichPokemon], a
	ld a, e
	ld [wMoveNum], a
	ld [wNamedObjectIndex], a
	call GetMoveName
	call CopyToStringBuffer
	ldh a, [hMoney]
	ld b, a
	ldh a, [hMoney + 1]
	ld c, a
	push bc
	ldh a, [hMoney + 2]
	push af
	ld a, [wLetterPrintingDelayFlags]
	push af
	xor a
	ld [wLetterPrintingDelayFlags], a
.learnMove
	predef LearnMove
	ld e, b ; LearnMove returns b = 1 only when the move was learned
	pop af
	ld [wLetterPrintingDelayFlags], a
.restoreQuote
	pop af
	ld [wPriceTemp + 2], a
	pop bc
	ld a, b
	ld [wPriceTemp], a
	ld a, c
	ld [wPriceTemp + 1], a
	ld a, e
	and a
	ret z
	ld hl, wPriceTemp + 2
	ld de, wPlayerMoney + 2
	ld c, $3
	predef SubBCDPredef
	scf
	ret
.notEnoughMoney
	ld hl, PCMoveTutorNotEnoughMoneyText
	call PrintText
.declined
	pop de
	and a ; clear carry: no lesson, no payment
	ret


PCMoveTutorGreetingText:
	text_far _PCMoveTutorGreetingText
	text_end

PCMoveTutorSaidYesText:
	text_far _PCMoveTutorSaidYesText
	text_end

PCMoveTutorNotEnoughMoneyText:
	text_far _PCMoveTutorNotEnoughMoneyText
	text_end

PCMoveTutorWhichMoveText:
	text_far _PCMoveTutorWhichMoveText
	text_end

PCMoveTutorConfirmText:
	text_far _PCMoveTutorConfirmText
	text_end

PCMoveTutorByeText:
	text_far _PCMoveTutorByeText
	text_end

PCMoveTutorNoMovesText:
	text_far _PCMoveTutorNoMovesText
	text_end
    
    
PCTraderSuperNerdSetup:
    ld b, 0
    ld c, 0
    ld hl, wPartySpecies
    push hl
    
    .loop
    pop hl
    ld a, [hli]
    push hl
	cp $ff
	jr z, .box
    
    inc c
    ld hl, wAllSpecies - 1
    add hl, bc
    ld [hl], a ; load mon into allspecies
    jr .loop
    
    .box ;
    pop hl
    ld hl, wBoxSpecies
    push hl
    
    .loop2
    pop hl
    ld a, [hli]
    push hl
	cp $ff
	jr z, .randomselect
    
    inc c
    ld hl, wAllSpecies - 1
    add hl, bc
    ld [hl], a ; load mon into allspecies
    jr .loop2
    
    
	.randomselect
    call Rangerandom    ; now in HOME bank (home/random.asm), safe to call from any bank
    ld c, a     ; place random number in c
    ld hl, wAllSpecies
    add hl, bc
    ld a, [hl]    ; get the pokemon the trader wants
    ld [wroguenpctradegive], a
    
    ; begin finding pokemon that you get.
    ;
    ; This used to be a hand-rolled scan starting `ld hl, pokemon_classes`, but
    ; that table lives in bank $2F while this file is bank $06 - the plain
    ; `ld a, [hli]` read whatever bytes happened to sit at $616d in bank $06 and
    ; classified the trade against garbage. It must be a farcall.
    ;
    ; The species goes in e and the class comes back in e because Bankswitch
    ; destroys a/bc/hl on both sides of a farcall (see RogueClassifySpeciesFar).
    ld e, a                     ; e = species the trader wants
    farcall RogueClassifySpeciesFar
    ld c, e                     ; c = class 1-4
    .get_pokemon
    push bc
    farcall GetRewardMonLevel  ; wCurEnemyLevel must be set before species pick for evolution check
    pop bc
    ld e, c                     ; only d/e survive a farcall - c would arrive as garbage
    farcall Random_Pokemon_Selection_Far ; bank $2F; plain call would execute garbage
    ld a, d
    ld [wroguenpctradeget], a ; load in pokemon that they will give player
    ld [wNamedObjectIndex], a   ; place pokemon id in spot for GetMonName
    call GetMonName         ; get name of pokemon to receive
    ld hl, wNameBuffer      ; name address
    ld de, wroguenpctradename   ; load name into this location
    ld bc, NAME_LENGTH      ; name length
    call CopyData           ; copy name to location
    ; could make a list of random names to choose from
    pop hl
    ret 
    
    DEF salesman_pokeball_odds EQU $99
    DEF salesman_greatball_odds EQU $99 + $5E
    DEF salesman_ultraball_odds EQU $8 + $5E + $99

PCPokemonSalesmanSetup:
    call Random
    ld b, a     ; move random number to b
    ld c, 1     ; auto pokeball class
    ld hl, wroguenpcclass
    
    .determineClassSlot
    ld a, salesman_pokeball_odds
    ld [hl], c
    cp b
    jr nc, .get_pokemon
    inc c       ; greatball class
    ld [hl], c
    ld a, salesman_greatball_odds
    cp b
    jr nc, .get_pokemon
    inc c       ; ultraball class
    ld [hl], c
    
    .get_pokemon
    push bc
    farcall GetRewardMonLevel  ; wCurEnemyLevel must be set before species pick for evolution check
    pop bc
    ld e, c                     ; only d/e survive a farcall - c would arrive as garbage
    farcall Random_Pokemon_Selection_Far ; bank $2F; plain call would execute garbage
    ld a, d
    ld [wroguenpcsell], a ; load in pokemon that they will give player
; Phase 2R increment 8j: bank the salesman's form. e carries it out of the roll;
; the store above only touches a. Its own byte, not wRoguePokemonForm1 - the
; salesman's species is wroguenpcsell, so sharing would collide with the reward
; and trade offers.
    ld a, e
    ld [wroguenpcsellform], a
IF FORCE_GIFT_TRADE_FORM_TEST
; ⚠ TEMPORARY - see FORCE_GIFT_TRADE_FORM_TEST in pokemon_data_constants.asm.
    ld a, VULPIX
    ld [wroguenpcsell], a
    ld a, 1
    ld [wroguenpcsellform], a
ENDC
    ld a, [wroguenpcsell]
    ld [wNamedObjectIndex], a   ; place pokemon id in spot for GetMonName
    ld a, [wroguenpcsellform]   ; name the offer as its form
    ld [wFormContextForm], a
    ld a, [wNamedObjectIndex]
    ld [wFormContextSpecies], a
    call GetMonName         ; get name of pokemon to receive
    ld hl, wNameBuffer      ; name address
    ld de, wroguenpctradename   ; load name into this location
    ld bc, NAME_LENGTH      ; name length
    call CopyData           ; copy name to location
    ; could make a list of random names to choose from
    
    ret 
    
    PCClerksSetup:
    ld  hl, PCClerkText1    ; begining of address used for generating marts
    ld  a, TX_SCRIPT_MART
    ld [hli], a
    ld [hl], $A       ; Amount of items

    ld de, PCClerkText1Items    ; ram address to save ids to (passed via de - farcall clobbers hl/bc, not de)
    farcall Random_Healing_Mart_Selection  ; lives in bank 07, this file is bank 06

    ld hl, PCClerkText2    ; begining of address used for generating marts
    ld  a, TX_SCRIPT_MART
    ld [hli], a
    ld [hl], $A       ; Amount of items

    ld de, PCClerkText2Items    ; ram address to save ids to
    farcall Random_StatTM_Mart_Selection  ; same bank-mismatch issue as above
    ret
