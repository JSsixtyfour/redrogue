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
; Intentional Red Rogue deviations are narrow: fixed Pikachu, only
; SILPH_CO_B1F and SILPH_CO_DORM, Yellow spawn states 0/1/2, no Pikachu
; happiness-dependent animation rate, and no ledge/idle/emotion/interaction/
; bike/surf state. Slot 15 and image base 2 match Yellow. The existing player
; camera loop only shifts authored slots, so FollowerApplyCameraScroll mirrors
; its already-scaled delta for slot 15. Only state 0 is currently scheduled;
; the complete branch-local Yellow transition setter lifecycle remains deferred.

SECTION "Follower Core", ROMX, BANK[$2F]

DEF FOLLOWER_COMMAND_EMPTY      EQU $ff
DEF FOLLOWER_COMMAND_BUFFER_LEN EQU 16
DEF FOLLOWER_COMMAND_LAST       EQU FOLLOWER_COMMAND_BUFFER_LEN - 1

DEF FOLLOWER_COMMAND_DOWN  EQU 1
DEF FOLLOWER_COMMAND_UP    EQU 2
DEF FOLLOWER_COMMAND_LEFT  EQU 3
DEF FOLLOWER_COMMAND_RIGHT EQU 4

DEF FOLLOWER_STATUS_READY   EQU 1
DEF FOLLOWER_STATUS_WALKING EQU 3
DEF FOLLOWER_STATUS_FAST    EQU 5

DEF FOLLOWER_NORMAL_FRAMES EQU 8
DEF FOLLOWER_FAST_FRAMES   EQU 4
DEF FOLLOWER_ANIM_TICKS    EQU 2 ; Yellow's happy walking cadence

; Carry set only on the two explicitly-scoped maps.
FollowerIsTestMap:
	ldh a, [hCurMap]
	cp SILPH_CO_B1F
	jr z, .yes
	cp SILPH_CO_DORM
	jr z, .yes
	and a
	ret
.yes
	scf
	ret

; Called by InitMapSprites before picture IDs are copied into the loader.
; A normal map load has already cleared slot 15, so it creates a pending
; overlap spawn. InitMapSprites also runs after text; an existing Pikachu is
; preserved and follows Yellow's text-recovery path instead of being respawned.
FollowerPrepareMap::
	call FollowerIsTestMap
	ret nc
	; Yellow LoadMapHeader skips both sprite initialization and follower spawn
	; scheduling while returning from battle. Preserve slot 15 exactly.
	ld a, [wStatusFlags4]
	bit BIT_BATTLE_OVER_OR_BLACKOUT, a
	ret nz
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_PICTUREID]
	cp SPRITE_PIKACHU
	jr nz, .newSpawn
	ld a, [wFontLoaded]
	bit BIT_FONT_LOADED, a
	ret z
	jp FollowerRefreshAfterText
.newSpawn
	call FollowerClearState
	ld a, SPRITE_PIKACHU
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
	cp 1
	jr z, .spawnRight
	cp 2
	jr nz, .storeSpawnCoords
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
.storeSpawnCoords
	ld a, b
	ld [wSprite15StateData2 + SPRITESTATEDATA2_MAPY], a
	ld a, c
	ld [wSprite15StateData2 + SPRITESTATEDATA2_MAPX], a
	xor a
	ld [wFollowerSpawnState], a
	ld a, $fe ; Yellow following marker; movement never goes through TryWalking
	ld [wSprite15StateData2 + SPRITESTATEDATA2_MOVEMENTBYTE1], a
	ld a, [wSpritePlayerStateData1FacingDirection]
	ld [wSprite15StateData1 + SPRITESTATEDATA1_FACINGDIRECTION], a
	; Movement status remains zero. The normal slot-15 UpdateSprites pass owns
	; first spawn initialization, as it does in Yellow.
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
; acceptance; this routine rejects excluded movement modes and encodes the
; already-validated ordinary direction in Yellow's 1..4 format.
FollowerQueuePlayerStep::
	call FollowerIsTestMap
	ret nc
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_PICTUREID]
	cp SPRITE_PIKACHU
	ret nz
	ld a, [wWalkBikeSurfState]
	and a
	ret nz
	ld a, [wMovementFlags]
	bit BIT_LEDGE_OR_FISHING, a
	ret nz
	ld a, [wPlayerDirection]
	bit PLAYER_DIR_BIT_UP, a
	jr nz, .up
	bit PLAYER_DIR_BIT_DOWN, a
	jr nz, .down
	bit PLAYER_DIR_BIT_LEFT, a
	jr nz, .left
	bit PLAYER_DIR_BIT_RIGHT, a
	ret z
	ld a, FOLLOWER_COMMAND_RIGHT
	jr FollowerAppendCommand
.up
	ld a, FOLLOWER_COMMAND_UP
	jr FollowerAppendCommand
.down
	ld a, FOLLOWER_COMMAND_DOWN
	jr FollowerAppendCommand
.left
	ld a, FOLLOWER_COMMAND_LEFT

; Yellow AppendPikachuFollowCommandToBuffer plus a required 16-byte bound.
FollowerAppendCommand:
	ld b, a
	ld a, [wFollowerCommandBufferSize]
	cp FOLLOWER_COMMAND_EMPTY
	jr z, .store
	cp FOLLOWER_COMMAND_LAST
	ret nc
.store
	ld hl, wFollowerCommandBufferSize
	inc [hl]
	ld e, [hl]
	ld d, 0
	ld hl, wFollowerCommandBuffer
	add hl, de
	ld [hl], b
	ret

; Native Yellow update ownership: this entry is reached only from slot 15's
; branch in _UpdateSprites, after player and ordinary-sprite dispatch order.
FollowerUpdate::
	call FollowerIsTestMap
	ret nc
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_PICTUREID]
	cp SPRITE_PIKACHU
	ret nz
	call FollowerCheckVisibility
	ret c
	ld a, [wFontLoaded]
	bit BIT_FONT_LOADED, a
	jr z, .notFontLoaded
	jp FollowerRefreshAfterText
.notFontLoaded
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_MOVEMENTSTATUS]
	and a
	jr z, FollowerInitializeSpawn
	cp FOLLOWER_STATUS_WALKING
	jp z, FollowerAdvanceStep
	cp FOLLOWER_STATUS_FAST
	jp z, FollowerAdvanceStep
	cp FOLLOWER_STATUS_READY
	jr nz, FollowerInitializeSpawn
	call FollowerDequeueCommand
	jr nc, FollowerStartCommand
	jp FollowerWait

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
	call FollowerAtLeastTwoQueued
	ld b, FOLLOWER_NORMAL_FRAMES
	ld c, FOLLOWER_STATUS_WALKING
	jr nc, .speedReady
	ld b, FOLLOWER_FAST_FRAMES
	ld c, FOLLOWER_STATUS_FAST
.speedReady
	; Red Rogue's 60 FPS overworld uses twice as many one-pixel updates for the
	; same tile. Preserve Yellow's logical 8/4-update normal/fast cadence.
	call Check60FPS
	jr z, .cadenceReady
	sla b
.cadenceReady
	pop af
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
	jr nz, .haveYDelta
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
	jr nz, .haveXDelta
	sla b
.haveXDelta
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_XPIXELS]
	add b
	ld [wSprite15StateData1 + SPRITESTATEDATA1_XPIXELS], a
	ld hl, wSprite15StateData1 + SPRITESTATEDATA1_INTRAANIMFRAMECOUNTER
	inc [hl]
	ld b, FOLLOWER_ANIM_TICKS
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

; Yellow ComputePikachuFollowCommand, Y before X. This slice can only be one
; ordinary tile behind at accepted checkpoints; larger deltas still seed the
; correct axis without importing Yellow's ledge/two-tile command states.
FollowerComputeSeedCommand:
	ld a, [wSprite15StateData2 + SPRITESTATEDATA2_MAPY]
	ld b, a
	ld a, [wYCoord]
	add 4
	cp b
	jr z, .x
	ld a, FOLLOWER_COMMAND_DOWN
	jr nc, .command
	ld a, FOLLOWER_COMMAND_UP
	jr .command
.x
	ld a, [wSprite15StateData2 + SPRITESTATEDATA2_MAPX]
	ld b, a
	ld a, [wXCoord]
	add 4
	cp b
	jr z, .overlap
	ld a, FOLLOWER_COMMAND_RIGHT
	jr nc, .command
	ld a, FOLLOWER_COMMAND_LEFT
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
	cp SPRITE_PIKACHU
	ret nz
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_YPIXELS]
	sub d
	ld [wSprite15StateData1 + SPRITESTATEDATA1_YPIXELS], a
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_XPIXELS]
	sub e
	ld [wSprite15StateData1 + SPRITESTATEDATA1_XPIXELS], a
	ret
