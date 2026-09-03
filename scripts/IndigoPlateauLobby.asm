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
	; Door 2's baked-in notepad is absent when its block is a wall.
	; Refresh even after battle/header reloads, not only on EVENT_ENTER_ROOM.
	call Lobby_IsDoor2Blocked
	ld a, 1
	jr nz, .setSignCount
	inc a
.setSignCount
	ld [wNumSigns], a
	CheckEvent EVENT_ENTER_ROOM
	jr nz, .normal

	SetEvent EVENT_ENTER_ROOM
	; Blacking out mid-run should respawn the player in their dorm room, not
	; wherever wLastMap happens to be (SetLastBlackoutMap is only ever called
	; from the vanilla Pokemon Center heal flow, which this hub bypasses).
	; Every lobby entry is a safe choke point to (re)assert this.
	ld a, SILPH_CO_DORM
	ld [wLastBlackoutMap], a
	; Lobby music: MapSongBanks (data/maps/songs.asm) defaults this map to
	; MUSIC_POKECENTER; once Victory Road is cleared, permanently override to
	; MUSIC_INDIGO_PLATEAU for the rest of the run (re-applied every visit,
	; since EVENT_ENTER_ROOM resets on every warp).
	ld hl, wElite4Flags
	bit BIT_VICTORY_ROAD_CLEARED, [hl]
	jr z, .lobbyMusicDone
	ld a, MUSIC_INDIGO_PLATEAU
	ld [wMapMusicSoundID], a
	ld a, BANK(Music_IndigoPlateau)
	ld [wMapMusicROMBank], a
.lobbyMusicDone
	; update exit door tile based on whether gym or route is next (or, during
	; the final sequence, the Elite Four - see Lobby_IsDoor2Blocked)
	call Lobby_IsDoor2Blocked
	jr nz, .blockExitToSecondDoor
	ld a, $08 ; authored open door plus tile-based notepad
	jr .setExitDoor
.blockExitToSecondDoor
	ld a, $C
.setExitDoor
	ld [wNewTileBlockID], a
	lb bc, 0, 5
	predef ReplaceTileBlock
	; Pick the next random stage on map entry and patch the exit warp.
	; Uses SelectAndPatchLobbyExit (no BIT_WARP_FROM_CUR_SCRIPT — that flag
	; would cause an immediate warp before the player could do anything).
	farcall SelectAndPatchLobbyExit
	farcall ProcPreloadAssignedWildArea
	ld c, TRADE_FOR_RANDOM
	ld b, FLAG_RESET
	ld hl, wCompletedInGameTradeFlags
	predef FlagActionPredef
	ResetEvent EVENT_BOUGHT_POKEMON
	call PCTraderSuperNerdSetup
	call PCPokemonSalesmanSetup
	call PCClerksSetup
	farcall PCWitchSetup

.normal
	ld hl, wCurrentMapScriptFlags
	bit BIT_CUR_MAP_LOADED_2, [hl]
	res BIT_CUR_MAP_LOADED_2, [hl]
	ret z
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
    dw_const IndigoPlateauLobbyGymGuideText,         TEXT_PC_PSYCHIC
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
; door 2 is hidden whenever a gym is next (see IndigoPlateauLobby_Script), so
; this is the only sign visible in that case. Gyms don't grant the door's item
; reward, so just say "GYM" rather than a misleading reward category.
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
	ld hl, .gymSignText
	ret
.gymSignText
	text "GYM AHEAD@"
	text_end
.itemPtrs
	dw .healingText
	dw .statText
	dw .tmText
	dw .moneyText
.itemPtrsGym ; unused (gyms now use .gymSignText); kept to avoid touching the texts below
	dw .healingTextGym
	dw .statTextGym
	dw .tmTextGym
	dw .moneyTextGym
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
.healingTextGym
	text "GYM:"
	line "HEALING ITEMS@"
	text_end
.statTextGym
	text "GYM:"
	line "STAT BOOSTS@"
	text_end
.tmTextGym
	text "GYM:"
	line "TM ITEMS@"
	text_end
.moneyTextGym
	text "GYM:"
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
Lobby_IsDoor2Blocked:
	ld a, [wObtainedBadges]
	cp $FF
	jr nz, .normalCheck
	ld a, [wElite4Flags]
	bit BIT_VICTORY_ROAD_CLEARED, a
	jr z, .door2Open        ; Victory Road phase - both doors stay open
	or 1                    ; Elite Four phase - force NZ (blocked)
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
	; forced wild-area collapse: door1 == door2 == a wild entry map -> block door 2
	ld a, [wLobbyDoor1StageMap]
	call LobbyIsWildEntryMap      ; NZ = wild entry map
	jr z, .checkGymNext
	ld a, [wLobbyDoor1StageMap]
	ld b, a
	ld a, [wLobbyDoor2StageMap]
	cp b
	jr nz, .checkGymNext
	or 1                          ; NZ = blocked
	ret
.checkGymNext
	ld a, [wRogueFlagsBitfield]
	bit 0, a
	ret

; CLOBBERS: a, de, hl
LobbyFinaleSignCheck:
	ld e, a                       ; stash caller's item category
	ld a, [wObtainedBadges]
	cp $FF
	jr nz, .notFinale
	ld a, [wElite4Flags]
	bit BIT_VICTORY_ROAD_CLEARED, a
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

; a = map -> NZ if it's a wild-area entry map (cave/forest/cemetery_1), else Z.
; Clobbers a.
LobbyIsWildEntryMap:
	cp PROCEDURAL_CAVE_1
	jr z, .yes
	cp PROCEDURAL_FOREST
	jr z, .yes
	cp PROCEDURAL_CEMETERY_1
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
	db LAVENDER_CUBONE_HOUSE
	dw .cuboneHouseText
	db CERULEAN_TRADE_HOUSE
	dw .tradeHouseText
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
.cuboneHouseText:
	text "CUBONE"
	line "HOUSE@"
	text_end
.tradeHouseText:
	text "TRADE"
	line "HOUSE@"
	text_end
.oaksLabText:
	text "OAK's"
	line "LAB@"
	text_end

; Mini-boss door sign: line 1 = the boss, line 2 = the door's item reward
; category - so both the boss indicator AND the reward stay visible (a full
; replacement hid the reward). Shared by both door sign handlers.
; INPUT: a = item category (0-3, from wRogueDoor1/2). Returns hl -> combined text.
; TODO (multi-boss): dispatch on the offered type (wRogueFlagsBitfield bits 4-5)
; to a per-boss category table. Only the Rival rolls today
; (MINIBOSS_MAX_ROLLABLE_TYPE), so the Rival table is used unconditionally.
LobbyMiniBossSign:
	ld hl, .rivalPtrs
	ld d, 0
	ld e, a
	add hl, de
	add hl, de
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ret
.rivalPtrs
	dw .rivalHealing
	dw .rivalStat
	dw .rivalTM
	dw .rivalMoney
.rivalHealing
	text "RIVAL TRAINER"
	line "HEALING ITEMS@"
	text_end
.rivalStat
	text "RIVAL TRAINER"
	line "STAT BOOSTS@"
	text_end
.rivalTM
	text "RIVAL TRAINER"
	line "TM ITEMS@"
	text_end
.rivalMoney
	text "RIVAL TRAINER"
	line "MONEY@"
	text_end

IndigoPlateauLobbyNurseText:
	script_pokecenter_nurse

IndigoPlateauLobbyGymGuideText:
	text_far _IndigoPlateauLobbyGymGuideText
	text_end

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

; index = wWitchPrize - 1; see constants/ram_constants.asm for the PRIZE_* ids.
; Rolled independently of the challenge - no fixed pairing.
.PrizeTextTable:
	dw .Prize1
	dw .Prize2
	dw .Prize3
	dw .Prize4
	dw .Prize5
	dw .Prize6

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

PCDaycareLadyText:
	text_asm
	call SaveScreenTilesToBuffer2
	ld a, [wDayCareInUse2]
	and a
	jp nz, .daycareInUse
	ld hl, IntroText
	call PrintText
	call YesNoChoice
	ldh a, [hCurrentMenuItem]
	and a
	ld hl, ComeAgainText
	jp nz, .done
	ld a, [wPartyCount]
	dec a
	ld hl, OnlyHaveOneMonText
	jp z, .done
	ld hl, WhichMonText
	call PrintText
	xor a
	ldh [hUpdateSpritesEnabled], a
	ld [wPartyMenuTypeOrMessageID], a
	ld [wMenuItemToSwap], a
	call DisplayPartyMenu
	push af
	call GBPalWhiteOutWithDelay3
	call RestoreScreenTilesAndReloadTilePatterns
	call LoadGBPal
	pop af
	ld hl, AllRightThenText
	jp c, .done
	xor a
	ld [wPartyAndBillsPCSavedMenuItem], a
	ldh a, [hWhichPokemon]
	ld hl, wPartyMonNicks
	call GetPartyMonName
	ld hl, WillLookAfterMonText
	call PrintText
	ld a, 1
	ld [wDayCareInUse2], a
	ld a, [wBattleCount]
	ld [wDayCareDepositBattleCount2], a
	ld a, PARTY_TO_DAYCARE2
	ld [wMoveMonType], a
	call MoveMon
	xor a
	ld [wRemoveMonFromBox], a
	call RemovePokemon
	ld a, [wCurPartySpecies]
	call PlayCry
	ld hl, ComeSeeMeInAWhileText
	jp .done

.daycareInUse
	xor a
	ld hl, wDayCareMonName2
	call GetPartyMonName
	ld a, DAYCARE_DATA2
	ld [wMonDataLocation], a
	call LoadMonData            ; populates wCurPartySpecies, needed for CalcExperience below
	; GetRewardMonLevel's "return in a" does NOT survive a farcall: Bankswitch's
	; return path ends `pop bc / ld a, b`, which leaves a holding the CALLER's
	; bank number. This read used to be `ld d, a` and so grew every deposited mon
	; to level 6 (this script's bank) instead of the tier level. Read the value
	; the routine actually publishes instead.
	farcall GetRewardMonLevel   ; sets wCurEnemyLevel = current tier level
	ld a, [wCurEnemyLevel]
	ld d, a
	ld hl, wDayCareMon2BoxLevel
	ld a, [hl]
	ld [wDayCareStartLevel2], a
	cp d
	jr nc, .noGrowth            ; current level (a) >= target (d): never lower a deposited mon's level
	callfar CalcExperience
	ld hl, wDayCareMon2Exp
	ldh a, [hExperience]
	ld [hli], a
	ldh a, [hExperience + 1]
	ld [hli], a
	ldh a, [hExperience + 2]
	ld [hl], a
	ld hl, wDayCareMon2BoxLevel
	ld [hl], d
	ld a, [wDayCareStartLevel2]  ; display-only: how many levels it gained, no longer used for pricing
	ld b, a
	ld a, d
	sub b
	ld [wDayCareNumLevelsGrown2], a
	ld [wDayCareNumLevelsGrown], a  ; MonHasGrownText is shared with the Gentleman and hardcodes this variable
	ld hl, MonHasGrownText
	jr .next
.noGrowth
	ld hl, MonNeedsMoreTimeText

.next
	call PrintText
	ld a, [wPartyCount]
	cp PARTY_LENGTH
	ld hl, NoRoomForMonText
	jp z, .leaveMonInDayCare
	; price = $500 per stage (route/gym) completed since deposit
	ld a, [wBattleCount]
	ld b, a
	ld a, [wDayCareDepositBattleCount2]
	ld c, a
	ld a, b
	sub c                       ; a = battles fought since deposit
	ld b, 0                     ; b = stages elapsed
.countStagesElapsed
	cp 10
	jr c, .stagesElapsedDone
	sub 10
	inc b
	jr .countStagesElapsed
.stagesElapsedDone
	ld de, wDayCareTotalCost2
	xor a
	ld [de], a
	inc de
	ld [de], a
	ld hl, wDayCarePerLevelCost2
	ld a, $5
	ld [hli], a
	ld [hl], $0
	ld a, b                     ; a = stages elapsed (price multiplier; 0 = free)
	and a
	jr z, .noCost
	ld b, a
	ld c, 2
.calcPriceLoop
	push hl
	push de
	push bc
	predef AddBCDPredef
	pop bc
	pop de
	pop hl
	dec b
	jr nz, .calcPriceLoop
.noCost
	ld hl, OweMoneyText
	call PrintText
	ld a, MONEY_BOX
	ld [wTextBoxID], a
	call DisplayTextBoxID
	call YesNoChoice
	ld hl, AllRightThenText
	ldh a, [hCurrentMenuItem]
	and a
	jp nz, .leaveMonInDayCare
	ld hl, wDayCareTotalCost2
	ldh [hMoney], a
	ld a, [hli]
	ldh [hMoney + 1], a
	ld a, [hl]
	ldh [hMoney + 2], a
	call HasEnoughMoney
	jr nc, .enoughMoney
	ld hl, NotEnoughMoneyText
	jp .leaveMonInDayCare

.enoughMoney
	xor a
	ld [wDayCareInUse2], a
	ld hl, wDayCareNumLevelsGrown2
	ld [hli], a
	inc hl
	ld de, wPlayerMoney + 2
	ld c, $3
	predef SubBCDPredef
	ld a, SFX_PURCHASE
	call PlaySoundWaitForCurrent
	ld a, MONEY_BOX
	ld [wTextBoxID], a
	call DisplayTextBoxID
	ld hl, HeresYourMonText
	call PrintText
	ld a, DAYCARE_TO_PARTY2
	ld [wMoveMonType], a
	call MoveMon
	ld a, [wDayCareMon2Species]
	ld [wCurPartySpecies], a
; Shin Red import Phase 10. The cry moves ahead of everything else so it is the
; mon you handed over that greets you, not whatever it turns into; the upgrade
; pass has to run before the HP-to-max write below, because evolving changes
; MaxHP. The old `predef WriteMonMoves` (which silently shifted the oldest move
; out with no prompt) is gone, and with it the wLearningMovesFromDayCare flag
; this was the only place still setting - it was never cleared here either.
	ld a, [wCurPartySpecies]
	call PlayCry
	ld a, [wDayCareStartLevel2]
	ld [wDayCareStartLevel], a ; the helper reads slot 1's copy for both slots
	farcall DaycareRetrieveUpgrade

; set mon's HP to max
	ld a, [wPartyCount]
	dec a
	ld bc, PARTYMON_STRUCT_LENGTH
	ld hl, wPartyMon1HP
	call AddNTimes
	ld d, h
	ld e, l
	ld bc, MON_MAXHP - MON_HP
	add hl, bc
	ld a, [hli]
	ld [de], a
	inc de
	ld a, [hl]
	ld [de], a

	ld hl, GotMonBackText
	jr .done

.leaveMonInDayCare
	ld a, [wDayCareStartLevel2]
	ld [wDayCareMon2BoxLevel], a

.done
	call PrintText
	jp TextScriptEnd


PCDaycareGentlemanText:
	text_asm
	call SaveScreenTilesToBuffer2
	ld a, [wDayCareInUse]
	and a
	jp nz, .daycareInUse
	ld hl, IntroText
	call PrintText
	call YesNoChoice
	ldh a, [hCurrentMenuItem]
	and a
	ld hl, ComeAgainText
	jp nz, .done
	ld a, [wPartyCount]
	dec a
	ld hl, OnlyHaveOneMonText
	jp z, .done
	ld hl, WhichMonText
	call PrintText
	xor a
	ldh [hUpdateSpritesEnabled], a
	ld [wPartyMenuTypeOrMessageID], a
	ld [wMenuItemToSwap], a
	call DisplayPartyMenu
	push af
	call GBPalWhiteOutWithDelay3
	call RestoreScreenTilesAndReloadTilePatterns
	call LoadGBPal
	pop af
	ld hl, AllRightThenText
	jp c, .done
	xor a
	ld [wPartyAndBillsPCSavedMenuItem], a
	ldh a, [hWhichPokemon]
	ld hl, wPartyMonNicks
	call GetPartyMonName
	ld hl, WillLookAfterMonText
	call PrintText
	ld a, 1
	ld [wDayCareInUse], a
	ld a, [wBattleCount]
	ld [wDayCareDepositBattleCount], a
	ld a, PARTY_TO_DAYCARE
	ld [wMoveMonType], a
	call MoveMon
	xor a
	ld [wRemoveMonFromBox], a
	call RemovePokemon
	ld a, [wCurPartySpecies]
	call PlayCry
	ld hl, ComeSeeMeInAWhileText
	jp .done

.daycareInUse
	xor a
	ld hl, wDayCareMonName
	call GetPartyMonName
	ld a, DAYCARE_DATA
	ld [wMonDataLocation], a
	call LoadMonData            ; populates wCurPartySpecies, needed for CalcExperience below
	; GetRewardMonLevel's "return in a" does NOT survive a farcall: Bankswitch's
	; return path ends `pop bc / ld a, b`, which leaves a holding the CALLER's
	; bank number. This read used to be `ld d, a` and so grew every deposited mon
	; to level 6 (this script's bank) instead of the tier level. Read the value
	; the routine actually publishes instead.
	farcall GetRewardMonLevel   ; sets wCurEnemyLevel = current tier level
	ld a, [wCurEnemyLevel]
	ld d, a
	ld hl, wDayCareMonBoxLevel
	ld a, [hl]
	ld [wDayCareStartLevel], a
	cp d
	jr nc, .noGrowth            ; current level (a) >= target (d): never lower a deposited mon's level
	callfar CalcExperience
	ld hl, wDayCareMonExp
	ldh a, [hExperience]
	ld [hli], a
	ldh a, [hExperience + 1]
	ld [hli], a
	ldh a, [hExperience + 2]
	ld [hl], a
	ld hl, wDayCareMonBoxLevel
	ld [hl], d
	ld a, [wDayCareStartLevel]  ; display-only: how many levels it gained, no longer used for pricing
	ld b, a
	ld a, d
	sub b
	ld [wDayCareNumLevelsGrown], a
	ld hl, MonHasGrownText
	jr .next
.noGrowth
	ld hl, MonNeedsMoreTimeText

.next
	call PrintText
	ld a, [wPartyCount]
	cp PARTY_LENGTH
	ld hl, NoRoomForMonText
	jp z, .leaveMonInDayCare
	; price = $500 per stage (route/gym) completed since deposit
	ld a, [wBattleCount]
	ld b, a
	ld a, [wDayCareDepositBattleCount]
	ld c, a
	ld a, b
	sub c                       ; a = battles fought since deposit
	ld b, 0                     ; b = stages elapsed
.countStagesElapsed
	cp 10
	jr c, .stagesElapsedDone
	sub 10
	inc b
	jr .countStagesElapsed
.stagesElapsedDone
	ld de, wDayCareTotalCost
	xor a
	ld [de], a
	inc de
	ld [de], a
	ld hl, wDayCarePerLevelCost
	ld a, $5
	ld [hli], a
	ld [hl], $0
	ld a, b                     ; a = stages elapsed (price multiplier; 0 = free)
	and a
	jr z, .noCost
	ld b, a
	ld c, 2
.calcPriceLoop
	push hl
	push de
	push bc
	predef AddBCDPredef
	pop bc
	pop de
	pop hl
	dec b
	jr nz, .calcPriceLoop
.noCost
	ld hl, OweMoneyText
	call PrintText
	ld a, MONEY_BOX
	ld [wTextBoxID], a
	call DisplayTextBoxID
	call YesNoChoice
	ld hl, AllRightThenText
	ldh a, [hCurrentMenuItem]
	and a
	jp nz, .leaveMonInDayCare
	ld hl, wDayCareTotalCost
	ldh [hMoney], a
	ld a, [hli]
	ldh [hMoney + 1], a
	ld a, [hl]
	ldh [hMoney + 2], a
	call HasEnoughMoney
	jr nc, .enoughMoney
	ld hl, NotEnoughMoneyText
	jp .leaveMonInDayCare

.enoughMoney
	xor a
	ld [wDayCareInUse], a
	ld hl, wDayCareNumLevelsGrown
	ld [hli], a
	inc hl
	ld de, wPlayerMoney + 2
	ld c, $3
	predef SubBCDPredef
	ld a, SFX_PURCHASE
	call PlaySoundWaitForCurrent
	ld a, MONEY_BOX
	ld [wTextBoxID], a
	call DisplayTextBoxID
	ld hl, HeresYourMonText
	call PrintText
	ld a, DAYCARE_TO_PARTY
	ld [wMoveMonType], a
	call MoveMon
	ld a, [wDayCareMonSpecies]
	ld [wCurPartySpecies], a
; Shin Red import Phase 10. The cry moves ahead of everything else so it is the
; mon you handed over that greets you, not whatever it turns into; the upgrade
; pass has to run before the HP-to-max write below, because evolving changes
; MaxHP. The old `predef WriteMonMoves` (which silently shifted the oldest move
; out with no prompt) is gone, and with it the wLearningMovesFromDayCare flag
; this was the only place still setting - it was never cleared here either.
	ld a, [wCurPartySpecies]
	call PlayCry
	farcall DaycareRetrieveUpgrade

; set mon's HP to max
	ld a, [wPartyCount]
	dec a
	ld bc, PARTYMON_STRUCT_LENGTH
	ld hl, wPartyMon1HP
	call AddNTimes
	ld d, h
	ld e, l
	ld bc, MON_MAXHP - MON_HP
	add hl, bc
	ld a, [hli]
	ld [de], a
	inc de
	ld a, [hl]
	ld [de], a

	ld hl, GotMonBackText
	jr .done

.leaveMonInDayCare
	ld a, [wDayCareStartLevel]
	ld [wDayCareMonBoxLevel], a

.done
	call PrintText
	jp TextScriptEnd

IntroText:
	text_far _DaycareGentlemanIntroText
	text_end

WhichMonText:
	text_far _DaycareGentlemanWhichMonText
	text_end

WillLookAfterMonText:
	text_far _DaycareGentlemanWillLookAfterMonText
	text_end

ComeSeeMeInAWhileText:
	text_far _DaycareGentlemanComeSeeMeInAWhileText
	text_end

MonHasGrownText:
	text_far _DaycareGentlemanMonHasGrownText
	text_end

OweMoneyText:
	text_far _DaycareGentlemanOweMoneyText
	text_end

GotMonBackText:
	text_far _DaycareGentlemanGotMonBackText
	text_end

MonNeedsMoreTimeText:
	text_far _DaycareGentlemanMonNeedsMoreTimeText
	text_end

AllRightThenText:
	text_far _DaycareGentlemanAllRightThenText
ComeAgainText:
	text_far _DaycareGentlemanComeAgainText
	text_end

NoRoomForMonText:
	text_far _DaycareGentlemanNoRoomForMonText
	text_end

OnlyHaveOneMonText:
	text_far _DaycareGentlemanOnlyHaveOneMonText
	text_end

HeresYourMonText:
	text_far _DaycareGentlemanHeresYourMonText
	text_end

NotEnoughMoneyText:
	text_far _DaycareGentlemanNotEnoughMoneyText
	text_end

PCPokemonSalesmanText:
	text_asm
	CheckEvent EVENT_BOUGHT_POKEMON
	jp nz, .alreadyBoughtPokemon ; CheckEvent's 1-arg form returns via Z, not carry - jp c never fired
    
    ld a, [wroguenpcsell]   ; load pokemon for sale
    ld [wNamedObjectIndex], a   ; place pokemon id in spot for GetMonName
    call GetMonName         ; get name of pokemon to receive
    
    ld a, [wroguenpcclass]
    ld hl, .IGotADealTextPokeball
    ld c, 1
    cp c
    jr z, .print
    inc c       ; greatball class
    ld hl, .IGotADealTextGreatball
    ld b, $30
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
    
    ld a, [wroguenpcclass]
    ld b, $10
    ld c, 1
    cp c
    jr z, .pokemon_cost
    inc c       ; greatball class

    ld b, $30
    cp c
    jr z, .pokemon_cost
    
    ; ultraball class
    ld b, $50
    
    .pokemon_cost
    ld a, b
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
    ld a, [wroguenpcsell]
    ld b, a             ; b = species
	call GivePokemon
	jr nc, .done
	xor a
	ld [wPriceTemp], a
	ld [wPriceTemp + 2], a
    
    ld a, [wroguenpcclass]
    ld b, $10
    ld c, 1
    cp c
    jr z, .pokemon_cost_2
    inc c       ; greatball class

    ld b, $30
    cp c
    jr z, .pokemon_cost_2
    
    ; ultraball class
    ld b, $50
    
    
	.pokemon_cost_2
    ld a, b
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

; need a way to prevent trading for same pokemon or evolution
PCTraderSuperNerdText:
	text_asm
	ld a, TRADE_FOR_RANDOM
	ld [wWhichTrade], a
    predef RogueDoInGameTradeDialogue
	jp TextScriptEnd
    
PCMoveTutorText::
	text_asm
; Display the list of moves to the player.
	ld hl, PCMoveTutorGreetingText
	call PrintText
	ld a, MONEY_BOX
	ld [wTextBoxID], a
	call DisplayTextBoxID
	call YesNoChoice
	ldh a, [hCurrentMenuItem]
	and a
	jp nz, .exit
	xor a
	;charge 5000 money
	ld [hMoney], a
	ld [hMoney + 2], a
	ld a, $50                ; bcd3 5000 is $00,$50,$00
	ld [hMoney + 1], a
	call HasEnoughMoney
	jr nc, .enoughMoney
	; not enough money
	ld hl, PCMoveTutorNotEnoughMoneyText
	call PrintText
	jp TextScriptEnd
.enoughMoney
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
	ld b, a
	push bc
	ld hl, PrepareMoveTutorList
	ld b, Bank(PrepareMoveTutorList)
	call Bankswitch
	ld a, [wMoveBuffer]
	and a
	jr nz, .chooseMove
	pop bc
	ld hl, PCMoveTutorNoMovesText
	call PrintText
	jp TextScriptEnd
.chooseMove
	ld hl, PCMoveTutorWhichMoveText
	call PrintText
	xor a
	ldh [hCurrentMenuItem], a
	ld [wLastMenuItem], a
	ld a, MOVESLISTMENU
	ld [wListMenuID], a
	ld de, wMoveBuffer
	ld hl, wListPointer
	ld [hl], e
	inc hl
	ld [hl], d
	xor a
	ld [wPrintItemPrices], a ; don't print prices
	call DisplayListMenuID
	pop bc
	jr c, .exit  ; exit if player chose cancel
	push bc
	; Save the selected move id.
	ld a, [wCurListMenuItem]
	ld [wMoveNum], a
	ld [wNamedObjectIndex],a
	call GetMoveName
	call CopyToStringBuffer ; copy name to wcf4b
	pop bc
	ld a, b
	ldh [hWhichPokemon], a
	ld a, [wLetterPrintingDelayFlags]
	push af
	xor a
	ld [wLetterPrintingDelayFlags], a
	predef LearnMove
	pop af
	ld [wLetterPrintingDelayFlags], a
	ld a, b
	and a
	jr z, .exit
	; Charge 5000 money
	xor a
	ld [wPriceTemp], a
	ld [wPriceTemp + 2], a
	ld a, $50                ; bcd3 5000 is $00,$50,$00
	ld [wPriceTemp + 1], a
	ld hl, wPriceTemp + 2
	ld de, wPlayerMoney + 2
	ld c, $3
	predef SubBCDPredef
	ld a, MONEY_BOX
	ld [wTextBoxID], a
	call DisplayTextBoxID
	ld hl, PCMoveTutorByeText
	call PrintText
	jp TextScriptEnd
.exit
	ld hl, PCMoveTutorByeText
	call PrintText
	jp TextScriptEnd


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

PCMoveTutorByeText:
	text_far _PCMoveTutorByeText
	text_end

PCMoveTutorNoMovesText:
	text_far _PCMoveTutorNoMovesText
	text_end
    
DEF pokeball_pokemon_line_number EQU 28
DEF pokeball_pokemon_number EQU 28 + 26 + 6
DEF greatball_pokemon_line_number EQU pokeball_pokemon_line_number + 28
DEF greatball_pokemon_number EQU pokeball_pokemon_number + 28 + 25 + 8
DEF ultraball_pokemon_line_number EQU greatball_pokemon_line_number+ 16
DEF ultraball_pokemon_number EQU greatball_pokemon_number + 16 + 3 + 2
DEF masterball_pokemon_line_number EQU ultraball_pokemon_line_number + 5
DEF masterball_pokemon_number EQU ultraball_pokemon_number + 5 + 2
    
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
    
    ; begin finding pokemon that you get
    ld d, a ; place giving pokemon in d
    ld hl, pokemon_classes ; list of all pokemon
    ld e, 0
    
    .loopclass
    inc e    ; keep adding to get how far down the list we
    ld a, [hli] ; load pokemon
    cp d     ; see if we found the pokemon the trader wants from player
    jr nz, .loopclass   ; loop back until we find the pokemon
    
    ld a, pokeball_pokemon_number
    ld c, 1 ; auto pokeball class
    cp e ; see if pokeball class
    jr nc, .get_pokemon
    
    ld a, greatball_pokemon_number
    inc c
    cp e ; see if pokeball class
    jr nc, .get_pokemon
    
    inc c
    ld a, ultraball_pokemon_number
    cp e ; see if pokeball class
    jr nc, .get_pokemon
    inc c
    ; if we're here, it's masterball class
    ; will need to make some exception for mew and mewtwo UPDATE
    .get_pokemon
    push bc
    farcall GetRewardMonLevel  ; wCurEnemyLevel must be set before species pick for evolution check
    pop bc
    farcall Random_Pokemon_Selection  ; lives in a different bank (07) than this file (06) - plain call would execute garbage
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
    farcall Random_Pokemon_Selection  ; lives in a different bank (07) than this file (06) - plain call would execute garbage
    ld a, d
    ld [wroguenpcsell], a ; load in pokemon that they will give player
    
    
    ld [wNamedObjectIndex], a   ; place pokemon id in spot for GetMonName
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

