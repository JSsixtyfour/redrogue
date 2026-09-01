; Fixed-Pikachu follower test slice, selectively ported from pret/pokeyellow
; e6ba56989b0f2694f393e6924820be11dcc1fbb8.
;
; Donor lifecycle correspondences:
; - FollowerPrepareMap       = SchedulePikachuSpawnForAfterText / Func_fc76a
; - FollowerUpdate           = SpawnPikachu_ / Func_fc793 / Func_fc7aa
; - FollowerQueuePlayerStep  = Func_fcc08 / Func_fcc42
; - FollowerClearQueue       = ClearPikachuFollowCommandBuffer
; - FollowerAppendCommand    = AppendPikachuFollowCommandToBuffer
; - FollowerDequeueCommand   = Func_fcc92
; - FollowerStartCommand     = Pointer_fc7e3 dispatch
; - FollowerAdvanceStep      = NormalPikachuFollow / FastPikachuFollow
; - FollowerRefreshAfterText = Func_fc76a / RefreshPikachuFollow
;
; Intentional Red Rogue deviations are narrow: resolved lead graphics, only
; the explicitly accepted follower maps, Yellow spawn states
; 0-7, no Pikachu
; happiness-dependent animation rate, and no idle/emotion/bike/surf state.
; Interaction currently uses fixed Pikachu text through Red's standard predef
; text path. Slot 15 and image base 2 match Yellow. The existing player
; camera loop only shifts authored slots, so FollowerApplyCameraScroll mirrors
; its already-scaled delta for slot 15. Red Rogue's tight HOME bank invokes the
; three Yellow transition selectors through one common banked dispatch seam.

SECTION "Follower Core", ROMX, BANK[$2F]

DEF FOLLOWER_COMMAND_EMPTY      EQU $ff
DEF FOLLOWER_COMMAND_BUFFER_LEN EQU 16
DEF FOLLOWER_COMMAND_LAST       EQU FOLLOWER_COMMAND_BUFFER_LEN - 1

DEF FOLLOWER_COMMAND_DOWN  EQU 1
DEF FOLLOWER_COMMAND_UP    EQU 2
DEF FOLLOWER_COMMAND_LEFT  EQU 3
DEF FOLLOWER_COMMAND_RIGHT EQU 4
DEF FOLLOWER_COMMAND_LEDGE_DOWN  EQU 5
DEF FOLLOWER_COMMAND_LEDGE_UP    EQU 6
DEF FOLLOWER_COMMAND_LEDGE_LEFT  EQU 7
DEF FOLLOWER_COMMAND_LEDGE_RIGHT EQU 8

DEF FOLLOWER_STATUS_READY   EQU 1
DEF FOLLOWER_STATUS_WALKING EQU 3
DEF FOLLOWER_STATUS_TWO_STEP EQU 4
DEF FOLLOWER_STATUS_FAST    EQU 5

DEF FOLLOWER_NORMAL_FRAMES EQU 8
DEF FOLLOWER_FAST_FRAMES   EQU 4
DEF FOLLOWER_ANIM_TICKS    EQU 2 ; Yellow's happy walking cadence

; Carry set on ordinary indoor maps, the accepted procedural maps, and the
; explicitly-scoped outside maps. Exceptional systems retain explicit
; suppression until their own lifecycle checkpoints are accepted.
FollowerIsTestMap:
	ldh a, [hCurMap]
	cp FIRST_INDOOR_MAP
	jr c, .yes
	ld hl, .excludedIndoorMaps
	push bc
	call FollowerMapInArray
	pop bc
	jr c, .no
	jr .yes
.no
	and a
	ret
.yes
	scf
	ret

.excludedIndoorMaps
	db TRUCK
	db UNUSED_MAP_6F
	db MINI_SAFFRON
	db LANCES_ROOM
	db UNUSED_MAP_72
	db UNUSED_MAP_73
	db UNUSED_MAP_74
	db UNUSED_MAP_75
	db HALL_OF_FAME
	db CHAMPIONS_ROOM
	db INDIGO_PLATEAU_LOBBY
	db UNUSED_MAP_CC
	db UNUSED_MAP_CD
	db UNUSED_MAP_CE
	db UNUSED_MAP_E7
	db TRADE_CENTER
	db COLOSSEUM
	db PROCEDURAL_FACILITY
	db SILPH_CO_VR
	db LORELEIS_ROOM
	db BRUNOS_ROOM
	db AGATHAS_ROOM
	db $ff

; Yellow CheckMapConnections sets spawn state 2 before scheduling Pikachu on
; the connected map. Red Rogue's HOME bank is full, so its existing banked
; InitMapSprites call targets this size-neutral tail wrapper instead.
FollowerInitConnectedMapSprites::
	ld a, 2
	ld [wFollowerSpawnState], a
	farjp InitMapSprites

; Yellow makes these decisions in three separate WarpFound2 branches. Red
; Rogue moves the existing indoor warp-pad farcall before the source-map split
; and resolves the same branch choice there, spending no additional HOME.
; The wrapper then reaches the original warp-pad detector for its indoor user.
FollowerSetWarpSpawnStateAndCheck::
	ldh a, [hWarpDestinationMap]
	cp LAST_MAP
	jr z, .backOutside
	call CheckIfInOutsideMap
	jr nz, .warpPad
	jp FollowerSetSpawnOutside
.warpPad
	call FollowerSetSpawnWarpPad
	farjp IsPlayerStandingOnWarpPadOrHole
.backOutside
	jp FollowerSetSpawnBackOutside

; Yellow SetPikachuSpawnOutside.
FollowerSetSpawnOutside::
	ldh a, [hWarpDestinationMap]
	cp OAKS_LAB
	jr z, .state6
	cp ROUTE_22_GATE
	jr z, .route22Gate
	cp MT_MOON_B1F
	jr z, .state3
	cp ROCK_TUNNEL_1F
	jr z, .state3
	ld hl, .state4Maps
	call FollowerMapInArray
	jr c, .state4
	ldh a, [hWarpDestinationMap]
	ld hl, .facingDownState3Maps
	call FollowerMapInArray
	jr nc, .state1
	ld a, [wSpritePlayerStateData1FacingDirection]
	and a ; SPRITE_FACING_DOWN
	jr z, .state3
.state1
	ld a, 1
	jr .store
.route22Gate
	ld a, [wSpritePlayerStateData1FacingDirection]
	and a ; SPRITE_FACING_DOWN
	jr z, .state3
	jr .state1
.state3
	ld a, 3
	jr .store
.state4
	ld a, 4
	jr .store
.state6
	ld a, 6
.store
	ld [wFollowerSpawnState], a
	ret

.state4Maps
	db VICTORY_ROAD_2F
	db ROUTE_7_GATE
	db ROUTE_8_GATE
	db ROUTE_16_GATE_1F
	db ROUTE_18_GATE_1F
	db ROUTE_15_GATE_1F
	db ROUTE_11_GATE_1F
	db $ff

.facingDownState3Maps
	db VIRIDIAN_FOREST_NORTH_GATE
	db CERULEAN_BADGE_HOUSE
	db CERULEAN_TRASHED_HOUSE
	db VERMILION_DOCK
	db CELADON_MANSION_1F
	db ROUTE_2_GATE
	db FUCHSIA_GOOD_ROD_HOUSE
	db $ff

; Yellow SetPikachuSpawnWarpPad.
FollowerSetSpawnWarpPad::
	ldh a, [hWarpDestinationMap]
	cp VIRIDIAN_FOREST_NORTH_GATE
	jr z, .viridianForestExit
	cp VIRIDIAN_FOREST_SOUTH_GATE
	jr z, .viridianForestEntrance
	ld hl, .state1Maps
.findMap
	cp [hl]
	jr z, .state1
	inc hl
	ld b, [hl]
	inc b
	jr nz, .findMap
.state0
	xor a
	jr .storeState
.viridianForestExit
	ld a, [wSpritePlayerStateData1FacingDirection]
	cp SPRITE_FACING_UP
	jr z, .state1
	jr .state0
.viridianForestEntrance
	ld a, [wSpritePlayerStateData1FacingDirection]
	and a ; SPRITE_FACING_DOWN
	jr z, .state0
.state1
	ld a, 1
.storeState
	ld [wFollowerSpawnState], a
	ret

.state1Maps
	db VIRIDIAN_FOREST
	db SAFARI_ZONE_CENTER_REST_HOUSE
	db SAFARI_ZONE_WEST_REST_HOUSE
	db SAFARI_ZONE_EAST_REST_HOUSE
	db SAFARI_ZONE_NORTH_REST_HOUSE
	db SAFARI_ZONE_SECRET_HOUSE
	db SILPH_CO_ELEVATOR
	db CELADON_MART_ELEVATOR
	db CINNABAR_LAB_TRADE_ROOM
	db CINNABAR_LAB_METRONOME_ROOM
	db CINNABAR_LAB_FOSSIL_ROOM
	db $ff

; Yellow SetPikachuSpawnBackOutside. This runs before hCurMap changes, matching
; the donor call order.
FollowerSetSpawnBackOutside::
	ldh a, [hCurMap]
	cp ROUTE_22_GATE
	jr z, .gate
	cp ROUTE_2_GATE
	jr nz, .state3
.gate
	ld a, [wSpritePlayerStateData1FacingDirection]
	cp SPRITE_FACING_UP
	jr z, .state1
.state3
	ld a, 3
	jr .store
.state1
	ld a, 1
.store
	ld [wFollowerSpawnState], a
	ret

; Yellow's Pikachu_IsInArray carry contract.
FollowerMapInArray:
	cp [hl]
	scf
	ret z
	inc hl
	ld b, [hl]
	inc b
	jr nz, FollowerMapInArray
	and a
	ret

; Resolve the current lead once at the LCD-safe map sprite preparation seam.
; PCGetPokemonSpriteCategory returns its farcall-safe result in E. Translate
; the three neutral still-object categories to their existing 12-tile walking
; decoration sheets, matching the preserved all-species resolver work.
; OUTPUT: E = SPRITE_* picture ID and carry set, or E = 0 and carry clear.
FollowerResolveLeadPicture:
	ld a, [wPartyCount]
	and a
	jr z, .reject
	ld a, [wPartySpecies]
	and a
	jr z, .reject
	cp NUM_POKEMON_INDEXES + 1
	jr nc, .reject
	ld e, a
	farcall PCGetPokemonSpriteCategory
	ld a, e
	cp NUM_MON_SPRITE_CATEGORIES
	jr nc, .reject
	ld hl, .categoryToWalkingSprite
	add a, l
	ld l, a
	jr nc, .noCarry
	inc h
.noCarry
	ld e, [hl]
	scf
	ret
.reject
	xor a
	ld e, a
	ret

.categoryToWalkingSprite
	db SPRITE_MONSTER
	db SPRITE_BIRD
	db SPRITE_SEEL
	db SPRITE_FAIRY
	db SPRITE_VOLTORB_DECO
	db SPRITE_SNORLAX_DECO
	db SPRITE_OMANYTE_DECO
	db SPRITE_PIKACHU
	db SPRITE_CHANSEY
	assert @ - .categoryToWalkingSprite == NUM_MON_SPRITE_CATEGORIES

; Called by InitMapSprites before picture IDs are copied into the loader.
; A normal map load has already cleared slot 15, so it creates a pending
; overlap spawn. InitMapSprites also runs after text; an existing Pikachu is
; preserved and follows Yellow's text-recovery path instead of being respawned.
FollowerPrepareMap::
	call FollowerIsTestMap
	jr c, .enabledMap
	; Yellow consumes connected state immediately because Pikachu is global.
	; This contained port clears it when the destination is excluded so a
	; dormant edge transition cannot leak into a later unrelated map load.
	xor a
	ld [wFollowerSpawnState], a
	ret
.enabledMap
	ld a, [wOptions2]
	bit BIT_FOLLOWER_DISABLED, a
	jr z, .enabledOption
	call FollowerClearState
	xor a
	ld [wFollowerSpawnState], a
	ld [wSpriteSetID], a ; restore an unmodified outside set while disabled
	ret
.enabledOption
	; Yellow LoadMapHeader skips both sprite initialization and follower spawn
	; scheduling while returning from battle. Preserve slot 15 exactly.
	ld a, [wStatusFlags4]
	bit BIT_BATTLE_OVER_OR_BLACKOUT, a
	ret nz
	call FollowerResolveLeadPicture
	jp nc, .noLead
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_PICTUREID]
	cp e
	jr z, .samePicture
	and a
	jr z, .newSpawn
	; A party-menu reorder closes through the normal font-loaded sprite reload.
	; Preserve the accepted Yellow movement state and replace only the sheet so
	; the new lead is drawn immediately with the existing position and facing.
	ld a, [wFontLoaded]
	bit BIT_FONT_LOADED, a
	jr z, .newSpawn
	ld a, e
	ld [wSprite15StateData1 + SPRITESTATEDATA1_PICTUREID], a
	ld a, 2
	ld [wSprite15StateData2 + SPRITESTATEDATA2_IMAGEBASEOFFSET], a
	jp FollowerRefreshAfterText
.samePicture
	ld a, [wFontLoaded]
	bit BIT_FONT_LOADED, a
	ret z
	jp FollowerRefreshAfterText
.newSpawn
	push de
	call FollowerClearState
	pop de
	ld a, e
	ld [wSprite15StateData1 + SPRITESTATEDATA1_PICTUREID], a
	ld a, 2
	ld [wSprite15StateData2 + SPRITESTATEDATA2_IMAGEBASEOFFSET], a
	ld a, [wYCoord]
	add 4
	ld b, a
	ld a, [wXCoord]
	add 4
	ld c, a
	ld a, [wFollowerSpawnState]
	ld e, a
	and a
	jr z, .storeSpawnCoords
	cp 1
	jr z, .spawnRight
	cp 2
	jr z, .spawnBehind
	cp 3
	jr z, .storeSpawnCoords
	cp 4
	jr z, .spawnBelow
	cp 5
	jr z, .spawnAbove
	cp 6
	jr z, .spawnLeft
	cp 7
	jr z, .spawnAhead
	jr .spawnRight ; Yellow's invalid-state fallback
.spawnBehind
	; Yellow CalculatePikachuPlacementCoords state 2: put Pikachu one tile
	; behind the player according to the player's arrival facing.
	ld a, [wSpritePlayerStateData1FacingDirection]
	and a ; SPRITE_FACING_DOWN
	jr nz, .spawnBehindUp
	dec b
	jr .storeSpawnCoords
.spawnBehindUp
	cp SPRITE_FACING_UP
	jr nz, .spawnBehindLeft
	inc b
	jr .storeSpawnCoords
.spawnBehindLeft
	cp SPRITE_FACING_LEFT
	jr nz, .spawnBehindRight
	inc c
	jr .storeSpawnCoords
.spawnBehindRight
	dec c
	jr .storeSpawnCoords
.spawnRight
	inc c
	jr .storeSpawnCoords
.spawnBelow
	inc b
	jr .storeSpawnCoords
.spawnAbove
	dec b
	jr .storeSpawnCoords
.spawnLeft
	dec c
	jr .storeSpawnCoords
.spawnAhead
	ld a, [wSpritePlayerStateData1FacingDirection]
	and a ; SPRITE_FACING_DOWN
	jr z, .spawnBelow
	cp SPRITE_FACING_UP
	jr z, .spawnAbove
	cp SPRITE_FACING_LEFT
	jr z, .spawnLeft
	jr .spawnRight
.storeSpawnCoords
	ld a, b
	ld [wSprite15StateData2 + SPRITESTATEDATA2_MAPY], a
	ld a, c
	ld [wSprite15StateData2 + SPRITESTATEDATA2_MAPX], a
	ld a, $fe ; Yellow following marker; movement never goes through TryWalking
	ld [wSprite15StateData2 + SPRITESTATEDATA2_MOVEMENTBYTE1], a
	ld a, e
	cp 3
	jr z, .faceDown
	cp 7
	jr z, .faceOpposite
	cp 2
	jr z, .computeFacing
	cp 5
	jr z, .computeFacing
	ld a, [wSpritePlayerStateData1FacingDirection]
	jr .storeFacing
.faceDown
	ld a, SPRITE_FACING_DOWN
	jr .storeFacing
.faceOpposite
	ld a, [wSpritePlayerStateData1FacingDirection]
	xor 4
	jr .storeFacing
.computeFacing
	call FollowerComputeFacing
	jr .clearSpawnState
.storeFacing
	ld [wSprite15StateData1 + SPRITESTATEDATA1_FACINGDIRECTION], a
.clearSpawnState
	xor a
	ld [wFollowerSpawnState], a
	; Movement status remains zero. The normal slot-15 UpdateSprites pass owns
	; first spawn initialization, as it does in Yellow.
	ret
.noLead
	call FollowerClearState
	xor a
	ld [wFollowerSpawnState], a
	ld [wSpriteSetID], a ; restore an unmodified outside set with no follower
	ret

FollowerClearState:
	ld hl, wSprite15StateData1
	ld bc, SPRITESTATEDATA1_LENGTH
	xor a
	call FillMemory
	ld hl, wSprite15StateData2
	ld bc, SPRITESTATEDATA2_LENGTH
	xor a
	call FillMemory
	ld a, FOLLOWER_COMMAND_EMPTY
	ld [wSprite15StateData1 + SPRITESTATEDATA1_IMAGEINDEX], a
	xor a
	ld [wFollowerLedgeLatch], a
	jp FollowerClearQueue

; Yellow ClearPikachuFollowCommandBuffer. The size byte is the last occupied
; index: $ff is empty, 0 is the single command retained for one-step lag.
FollowerClearQueue:
	push bc
	ld hl, wFollowerCommandBufferSize
	ld [hl], FOLLOWER_COMMAND_EMPTY
	ld hl, wFollowerCommandBuffer
	ld bc, FOLLOWER_COMMAND_BUFFER_LEN
	xor a
	call FillMemory
	pop bc
	ret

; Yellow Func_fcc08 seam. The HOME caller reaches this only after collision
; acceptance. Yellow's ledge simulation reaches this seam twice: the first
; call queues command 5..8 and sets a latch, while the second clears the latch
; and queues nothing.
FollowerQueuePlayerStep::
	call FollowerIsTestMap
	ret nc
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_PICTUREID]
	and a
	ret z
	ld a, [wWalkBikeSurfState]
	and a
	ret nz
	ld a, [wMovementFlags]
	bit BIT_LEDGE_OR_FISHING, a
	jr nz, .ledge
	xor a
	ld [wFollowerLedgeLatch], a
	call .encodeDirection
	ret c
	jp FollowerAppendCommand
.ledge
	ld a, [wFollowerLedgeLatch]
	and a
	jr z, .firstLedgeHalf
	xor a
	ld [wFollowerLedgeLatch], a
	scf
	ret
.firstLedgeHalf
	call .encodeDirection
	ret c
	add 4
	call FollowerAppendCommand
	ret c
	ld a, 1
	ld [wFollowerLedgeLatch], a
	and a
	ret
.encodeDirection
	ld a, [wPlayerDirection]
	bit PLAYER_DIR_BIT_UP, a
	jr nz, .up
	bit PLAYER_DIR_BIT_DOWN, a
	jr nz, .down
	bit PLAYER_DIR_BIT_LEFT, a
	jr nz, .left
	bit PLAYER_DIR_BIT_RIGHT, a
	jr z, .noDirection
	ld a, FOLLOWER_COMMAND_RIGHT
	and a
	ret
.up
	ld a, FOLLOWER_COMMAND_UP
	and a
	ret
.down
	ld a, FOLLOWER_COMMAND_DOWN
	and a
	ret
.left
	ld a, FOLLOWER_COMMAND_LEFT
	and a
	ret
.noDirection
	scf
	ret

; Yellow AppendPikachuFollowCommandToBuffer plus a required 16-byte bound.
; Carry is clear on success and set for an invalid command or full queue.
FollowerAppendCommand:
	ld b, a
	and a
	jr z, .reject
	cp FOLLOWER_COMMAND_LEDGE_RIGHT + 1
	jr nc, .reject
	ld a, [wFollowerCommandBufferSize]
	cp FOLLOWER_COMMAND_EMPTY
	jr z, .store
	cp FOLLOWER_COMMAND_LAST
	jr nc, .reject
.store
	ld hl, wFollowerCommandBufferSize
	inc [hl]
	ld e, [hl]
	ld d, 0
	ld hl, wFollowerCommandBuffer
	add hl, de
	ld [hl], b
	and a
	ret
.reject
	scf
	ret

; Native Yellow update ownership: this entry is reached only from slot 15's
; branch in _UpdateSprites, after player and ordinary-sprite dispatch order.
FollowerUpdate::
	call FollowerIsTestMap
	ret nc
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_PICTUREID]
	and a
	ret z
	call FollowerCheckVisibility
	ret c
	ld hl, wSprite15StateData1 + SPRITESTATEDATA1_MOVEMENTSTATUS
	bit BIT_FACE_PLAYER, [hl]
	jp nz, FollowerFacePlayer
	ld a, [wFontLoaded]
	bit BIT_FONT_LOADED, a
	jr z, .notFontLoaded
	jp FollowerRefreshAfterText
.notFontLoaded
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_MOVEMENTSTATUS]
	and a
	jp z, FollowerInitializeSpawn
	cp FOLLOWER_STATUS_WALKING
	jp z, FollowerAdvanceStep
	cp FOLLOWER_STATUS_TWO_STEP
	jp z, FollowerAdvanceStep
	cp FOLLOWER_STATUS_FAST
	jp z, FollowerAdvanceStep
	cp FOLLOWER_STATUS_READY
	jr nz, FollowerInitializeSpawn
	call FollowerDequeueCommand
	jp nc, FollowerStartCommand
	jp FollowerWait

; Yellow's A-button path scans all 15 object slots, while Red's collision
; caller must retain its authored-object limit so the follower never blocks
; the player. Reuse the original scanner with a temporary count of 15 only
; after the normal sign/NPC scan finds nothing.
FollowerFindInteraction::
	call IsSpriteOrSignInFrontOfPlayer
	ldh a, [hTextID]
	and a
	ret nz
	ld a, [wNumSprites]
	push af
	ld a, NUM_SPRITESTATEDATA_STRUCTS - 1
	ld [wNumSprites], a
	call IsSpriteInFrontOfPlayer
	pop af
	ld [wNumSprites], a
	ldh a, [hTextID]
	cp NUM_SPRITESTATEDATA_STRUCTS - 1
	ret nz
	; Use the standard predef-text path so DisplayTextID owns the normal bottom
	; dialogue box, prompt, font lifecycle, and sprite reload.
	call UpdateSprites
	ld a, 1
	ldh [hNoWaitAfterText], a
	tx_pre FollowerPokemonText
	; The outer overworld input path treats zero as "already handled."
	xor a
	ldh [hNoWaitAfterText], a
	ldh [hTextID], a
	ret

FollowerPokemonText::
	text_asm
	push bc
	ld a, [wPartySpecies]
	ld [wNamedObjectIndex], a
	call GetMonName
	ld a, [wPartySpecies]
	call PlayCry
	pop bc
	ld hl, .name
	ret
.name
	text_ram wNameBuffer
	text "!"
	prompt

; Yellow Func_fc745. Consume the face-player request before font/status
; dispatch, face opposite the player, reset animation, and redraw.
FollowerFacePlayer:
	res BIT_FACE_PLAYER, [hl]
	xor a
	ld [wSprite15StateData2 + SPRITESTATEDATA2_WALKANIMATIONCOUNTER], a
	ld [wSprite15StateData1 + SPRITESTATEDATA1_INTRAANIMFRAMECOUNTER], a
	ld [wSprite15StateData1 + SPRITESTATEDATA1_ANIMFRAMECOUNTER], a
	ld a, [wSpritePlayerStateData1FacingDirection]
	xor 4
	ld [wSprite15StateData1 + SPRITESTATEDATA1_FACINGDIRECTION], a
	jp FollowerUpdateImage

; Yellow Func_fc793: initialize screen geometry in the normal update pass,
; reconstruct the lag queue, and leave overlap hidden.
FollowerInitializeSpawn:
	call FollowerInitializeScreenPosition
	call FollowerRefreshQueue
	ld a, FOLLOWER_STATUS_READY
	ld [wSprite15StateData1 + SPRITESTATEDATA1_MOVEMENTSTATUS], a
	jp FollowerWait

; Yellow Func_fcc92. A size of zero deliberately does not dequeue, preserving
; one full player step between the player and follower.
FollowerDequeueCommand:
	ld hl, wFollowerCommandBufferSize
	ld a, [hl]
	cp FOLLOWER_COMMAND_EMPTY
	jr z, .empty
	and a
	jr z, .empty
	dec [hl]
	ld e, a
	ld d, 0
	ld hl, wFollowerCommandBuffer
	add hl, de
	inc e
	ld a, FOLLOWER_COMMAND_EMPTY
.shift
	ld d, [hl]
	ld [hld], a
	ld a, d
	dec e
	jr nz, .shift
	and a
	ret
.empty
	scf
	ret

FollowerStartCommand:
	push af
	cp FOLLOWER_COMMAND_LEDGE_DOWN
	jr nc, .twoStep
	call FollowerAtLeastTwoQueued
	ld b, FOLLOWER_NORMAL_FRAMES
	ld c, FOLLOWER_STATUS_WALKING
	jr nc, .speedReady
	ld b, FOLLOWER_FAST_FRAMES
	ld c, FOLLOWER_STATUS_FAST
	jr .speedReady
.twoStep
	ld b, FOLLOWER_NORMAL_FRAMES
	ld c, FOLLOWER_STATUS_TWO_STEP
.speedReady
	; Red Rogue's 60 FPS overworld uses twice as many one-pixel updates for the
	; same tile. Preserve Yellow's logical 8/4-update normal/fast cadence.
	call Check60FPS
	jr z, .cadenceReady
	sla b
.cadenceReady
	pop af
	cp FOLLOWER_COMMAND_LEDGE_DOWN
	jr c, .normalizedCommand
	sub 4
.normalizedCommand
	dec a
	ld e, a
	add a
	add e ; three-byte record
	ld e, a
	ld d, 0
	ld hl, FollowerCommandData
	add hl, de
	ld a, [hli]
	ld [wSprite15StateData1 + SPRITESTATEDATA1_FACINGDIRECTION], a
	ld a, [hli]
	ld [wSprite15StateData1 + SPRITESTATEDATA1_XSTEPVECTOR], a
	ld a, [hl]
	ld [wSprite15StateData1 + SPRITESTATEDATA1_YSTEPVECTOR], a
	ld a, c
	ld [wSprite15StateData1 + SPRITESTATEDATA1_MOVEMENTSTATUS], a
	ld a, b
	ld [wSprite15StateData2 + SPRITESTATEDATA2_WALKANIMATIONCOUNTER], a
	call FollowerAddStepVector
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_MOVEMENTSTATUS]
	cp FOLLOWER_STATUS_TWO_STEP
	call z, FollowerAddStepVector
	; Yellow performs the first pixel update in the dispatch call.
	jr FollowerAdvanceStep

; facing, X map step, Y map step. Only ordinary four-direction commands exist
; in this test slice.
FollowerCommandData:
	db SPRITE_FACING_DOWN,   0,  1
	db SPRITE_FACING_UP,     0, -1
	db SPRITE_FACING_LEFT,  -1,  0
	db SPRITE_FACING_RIGHT,  1,  0

FollowerAtLeastTwoQueued:
	ld a, [wFollowerCommandBufferSize]
	cp FOLLOWER_COMMAND_EMPTY
	ret z
	cp 2
	jr nc, .yes
	and a
	ret
.yes
	scf
	ret

; Yellow AddPikachuStepVector: logical map coordinates advance when a command
; starts, while screen pixels advance over the following animation updates.
FollowerAddStepVector:
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_YSTEPVECTOR]
	ld b, a
	ld a, [wSprite15StateData2 + SPRITESTATEDATA2_MAPY]
	add b
	ld [wSprite15StateData2 + SPRITESTATEDATA2_MAPY], a
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_XSTEPVECTOR]
	ld b, a
	ld a, [wSprite15StateData2 + SPRITESTATEDATA2_MAPX]
	add b
	ld [wSprite15StateData2 + SPRITESTATEDATA2_MAPX], a
	ret

; Yellow normal is 2 pixels for 8 updates; fast catch-up is 4 pixels for 4.
; The happiness-dependent animation threshold is deliberately fixed because
; this slice has no starter-Pikachu happiness lifecycle.
FollowerAdvanceStep:
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_YSTEPVECTOR]
	ld b, a
	call Check60FPS
	jr nz, .haveYBase
	sla b
.haveYBase
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_MOVEMENTSTATUS]
	cp FOLLOWER_STATUS_FAST
	jr z, .doubleYDelta
	cp FOLLOWER_STATUS_TWO_STEP
	jr nz, .haveYDelta
.doubleYDelta
	sla b
.haveYDelta
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_YPIXELS]
	add b
	ld [wSprite15StateData1 + SPRITESTATEDATA1_YPIXELS], a
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_XSTEPVECTOR]
	ld b, a
	call Check60FPS
	jr nz, .haveXBase
	sla b
.haveXBase
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_MOVEMENTSTATUS]
	cp FOLLOWER_STATUS_FAST
	jr z, .doubleXDelta
	cp FOLLOWER_STATUS_TWO_STEP
	jr nz, .haveXDelta
.doubleXDelta
	sla b
.haveXDelta
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_XPIXELS]
	add b
	ld [wSprite15StateData1 + SPRITESTATEDATA1_XPIXELS], a
	ld hl, wSprite15StateData1 + SPRITESTATEDATA1_INTRAANIMFRAMECOUNTER
	inc [hl]
	call FollowerGetAnimationTicks
	call Check60FPS
	jr z, .haveAnimThreshold
	sla b
.haveAnimThreshold
	ld a, [hl]
	cp b
	jr nz, .decrement
	xor a
	ld [hli], a
	ld a, [hl]
	inc a
	and 3
	ld [hl], a
.decrement
	; Yellow draws the movement-facing frame before completing the command.
	call FollowerUpdateImage
	ld hl, wSprite15StateData2 + SPRITESTATEDATA2_WALKANIMATIONCOUNTER
	dec [hl]
	ret nz
	xor a
	ld [wSprite15StateData1 + SPRITESTATEDATA1_YSTEPVECTOR], a
	ld [wSprite15StateData1 + SPRITESTATEDATA1_XSTEPVECTOR], a
	call FollowerComputeFacing
	ld a, FOLLOWER_STATUS_READY
	ld [wSprite15StateData1 + SPRITESTATEDATA1_MOVEMENTSTATUS], a
	ret

; Yellow uses two logical ticks when Pikachu happiness is at least 80 and five
; otherwise. Keep Pikachu's exact happy cadence; use Yellow's slower cadence
; for other walking sheets until species/category-specific tuning is approved.
FollowerGetAnimationTicks:
	ld b, FOLLOWER_ANIM_TICKS
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_PICTUREID]
	cp SPRITE_PIKACHU
	ret z
	ld b, 5
	ret

FollowerWait:
	call FollowerHideIfOverlappingPlayer
	ret c
	jp FollowerUpdateImage

; Yellow WillPikachuSpawnOnTheScreen. The outer update calls this before the
; font-loaded recovery path. Besides map bounds and grass priority, its four
; tile checks make Pikachu disappear only where menu/text tiles cover the
; sprite, including full-screen interfaces such as the Trainer Card.
FollowerCheckVisibility:
	ld a, [wSprite15StateData2 + SPRITESTATEDATA2_MAPY]
	ld b, a
	ld a, [wYCoord]
	cp b
	jr z, .sameY
	jr nc, .hidden
	add (SCREEN_HEIGHT / 2) - 1
	cp b
	jr c, .hidden
.sameY
	ld a, [wSprite15StateData2 + SPRITESTATEDATA2_MAPX]
	ld b, a
	ld a, [wXCoord]
	cp b
	jr z, .sameX
	jr nc, .hidden
	add (SCREEN_WIDTH / 2) - 1
	cp b
	jr c, .hidden
.sameX
	call .getCurrentTile
	ld d, MAP_TILESET_SIZE
	ld a, [hli]
	ld e, a
	cp d
	jr nc, .hidden
	ld a, [hld]
	cp d
	jr nc, .hidden
	ld bc, -SCREEN_WIDTH
	add hl, bc
	ld a, [hli]
	cp d
	jr nc, .hidden
	ld a, [hl]
	cp d
	jr c, .visible
.hidden
	ld a, FOLLOWER_COMMAND_EMPTY
	ld [wSprite15StateData1 + SPRITESTATEDATA1_IMAGEINDEX], a
	scf
	ret
.visible
	ld a, [wGrassTile]
	cp e
	ld a, 0
	jr nz, .storePriority
	ld a, OAM_PRIO
.storePriority
	ld [wSprite15StateData2 + SPRITESTATEDATA2_GRASSPRIORITY], a
	and a
	ret

.getCurrentTile
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_YPIXELS]
	add 4
	and $f0
	srl a
	ld c, a
	ld b, 0
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_XPIXELS]
	add 2
	srl a
	srl a
	srl a
	add SCREEN_WIDTH
	ld e, a
	ld d, 0
	ld hl, wTileMap
REPT 5
	add hl, bc
ENDR
	add hl, de
	ret

; Yellow UpdatePikachuWalkingSprite for dedicated image base 2.
FollowerUpdateImage:
	ld a, [wSprite15StateData2 + SPRITESTATEDATA2_IMAGEBASEOFFSET]
	and a
	jr z, .hide
	dec a
	swap a
	ld b, a
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_FACINGDIRECTION]
	or b
	ld b, a
	ld a, [wFontLoaded]
	bit BIT_FONT_LOADED, a
	jr z, .normalImage
	push bc
	call FollowerHideIfOverlappingPlayer
	pop bc
	ret c
	ld a, b
	jr .store
.normalImage
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_ANIMFRAMECOUNTER]
	and 3
	or b
.store
	ld [wSprite15StateData1 + SPRITESTATEDATA1_IMAGEINDEX], a
	ret
.hide
	ld a, FOLLOWER_COMMAND_EMPTY
	ld [wSprite15StateData1 + SPRITESTATEDATA1_IMAGEINDEX], a
	ret

; Yellow Func_fcae2: sharing the player's map coordinate hides the follower.
FollowerHideIfOverlappingPlayer:
	ld a, [wYCoord]
	add 4
	ld b, a
	ld a, [wSprite15StateData2 + SPRITESTATEDATA2_MAPY]
	cp b
	jr nz, .visible
	ld a, [wXCoord]
	add 4
	ld b, a
	ld a, [wSprite15StateData2 + SPRITESTATEDATA2_MAPX]
	cp b
	jr nz, .visible
	ld a, FOLLOWER_COMMAND_EMPTY
	ld [wSprite15StateData1 + SPRITESTATEDATA1_IMAGEINDEX], a
	scf
	ret
.visible
	and a
	ret

; Yellow Func_fc76a: menus/text can overwrite walking tiles and suspend sprite
; updates. Rebase the stationary screen position, reset animation, and rebuild
; exactly one lag command from geometry rather than creating a fresh spawn.
FollowerRefreshAfterText:
	xor a
	ld [wFollowerLedgeLatch], a
	ld [wSprite15StateData1 + SPRITESTATEDATA1_INTRAANIMFRAMECOUNTER], a
	ld [wSprite15StateData1 + SPRITESTATEDATA1_ANIMFRAMECOUNTER], a
	ld [wSprite15StateData2 + SPRITESTATEDATA2_WALKANIMATIONCOUNTER], a
	ld a, [wWalkCounter]
	and a
	call z, FollowerInitializeScreenPosition
	ld a, FOLLOWER_STATUS_READY
	ld [wSprite15StateData1 + SPRITESTATEDATA1_MOVEMENTSTATUS], a
	call FollowerRefreshQueue
	jp FollowerUpdateImage

FollowerRefreshQueue:
	call FollowerClearQueue
	call FollowerComputeSeedCommand
	ret c
	jp FollowerAppendCommand

; Yellow ComputePikachuFollowCommand, Y before X. A separation of two or more
; tiles rebuilds commands 5..8 so text recovery preserves ledge/catch-up state.
FollowerComputeSeedCommand:
	ld a, [wSprite15StateData2 + SPRITESTATEDATA2_MAPY]
	ld b, a
	ld a, [wYCoord]
	add 4
	sub b
	jr z, .x
	jr nc, .down
	cpl
	inc a
	ld b, a
	ld a, FOLLOWER_COMMAND_UP
	jr .magnitude
.down
	ld b, a
	ld a, FOLLOWER_COMMAND_DOWN
	jr .magnitude
.x
	ld a, [wSprite15StateData2 + SPRITESTATEDATA2_MAPX]
	ld b, a
	ld a, [wXCoord]
	add 4
	sub b
	jr z, .overlap
	jr nc, .right
	cpl
	inc a
	ld b, a
	ld a, FOLLOWER_COMMAND_LEFT
	jr .magnitude
.right
	ld b, a
	ld a, FOLLOWER_COMMAND_RIGHT
.magnitude
	ld c, a
	ld a, b
	cp 2
	ld a, c
	jr c, .command
	add 4
.command
	and a
	ret
.overlap
	scf
	ret

FollowerInitializeScreenPosition:
	ld a, [wYCoord]
	ld b, a
	ld a, [wSprite15StateData2 + SPRITESTATEDATA2_MAPY]
	sub b
	swap a
	sub 4
	ld [wSprite15StateData1 + SPRITESTATEDATA1_YPIXELS], a
	ld a, [wXCoord]
	ld b, a
	ld a, [wSprite15StateData2 + SPRITESTATEDATA2_MAPX]
	sub b
	swap a
	ld [wSprite15StateData1 + SPRITESTATEDATA1_XPIXELS], a
	ret

; Yellow ComputePikachuFacingDirection, restricted to ordinary commands.
FollowerComputeFacing:
	ld a, [wFollowerCommandBufferSize]
	cp FOLLOWER_COMMAND_EMPTY
	jr z, .facePlayer
	and a
	jr z, .facePlayer
	ld e, a
	ld d, 0
	ld hl, wFollowerCommandBuffer
	add hl, de
	ld a, [hl]
	dec a
	and 3
	add a
	add a
	jr .store
.facePlayer
	ld a, [wYCoord]
	add 4
	ld b, a
	ld a, [wSprite15StateData2 + SPRITESTATEDATA2_MAPY]
	cp b
	ld a, SPRITE_FACING_DOWN
	jr c, .store
	ld a, SPRITE_FACING_UP
	jr nz, .store
	ld a, [wXCoord]
	add 4
	ld b, a
	ld a, [wSprite15StateData2 + SPRITESTATEDATA2_MAPX]
	cp b
	ld a, SPRITE_FACING_RIGHT
	jr c, .store
	ld a, SPRITE_FACING_LEFT
	jr nz, .store
	ld a, [wSpritePlayerStateData1FacingDirection]
.store
	ld [wSprite15StateData1 + SPRITESTATEDATA1_FACINGDIRECTION], a
	ret

; AdvancePlayerSprite shifts only authored slots 1..wNumSprites in Red Rogue,
; unlike Yellow's fixed 15-slot loop. The caller passes its already-scaled,
; authoritative camera deltas in DE from the actual scroll branch.
FollowerApplyCameraScroll::
	call FollowerIsTestMap
	ret nc
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_PICTUREID]
	and a
	ret z
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_YPIXELS]
	sub d
	ld [wSprite15StateData1 + SPRITESTATEDATA1_YPIXELS], a
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_XPIXELS]
	sub e
	ld [wSprite15StateData1 + SPRITESTATEDATA1_XPIXELS], a
	ret
