; Red Rogue follower movement core draft.
;
; Provenance: selective port of pret/pokeyellow
;   commit e6ba56989b0f2694f393e6924820be11dcc1fbb8
;   engine/pikachu/pikachu_follow.asm
;   Yellow labels retained by this draft:
;     ClearPikachuFollowCommandBuffer
;     AppendPikachuFollowCommandToBuffer
;     Func_fcc92 (dequeue/shift)
;     AreThereAtLeastTwoStepsInPikachuFollowCommandBuffer
;     Func_fc7e3 / NormalPikachuFollow / FastPikachuFollow / Func_fca0a
;     AddPikachuStepVector / DoubleAddPikachuStepVectorToScreenPixelCoords
;     UpdatePikachuWalkingSprite
;
; This file is intentionally not included in the build yet. It is the bounded
; queue/state draft for the Phase 2 integration. Spawn placement, visibility,
; map transitions, graphics loading, interaction, and option policy remain
; integration work. In particular, these Yellow routines are deliberately not
; copied here:
;   ShouldPikachuSpawn, SchedulePikachuSpawnForAfterText,
;   CalculatePikachuPlacementCoords, SetPikachuSpawnOutside,
;   SetPikachuSpawnWarpPad, SetPikachuSpawnBackOutside,
;   SpawnPikachu_, WillPikachuSpawnOnTheScreen, IsPikachuRightNextToPlayer.
;
; The core owns slot 15's standard 16-byte state structs. It does not call
; TryWalking: its command stream is already the validated player path.

SECTION "Follower Core Draft", ROMX

DEF FOLLOWER_COMMAND_EMPTY       EQU $ff
DEF FOLLOWER_COMMAND_BUFFER_LEN  EQU 16
DEF FOLLOWER_COMMAND_LAST_INDEX  EQU FOLLOWER_COMMAND_BUFFER_LEN - 1

; Yellow command encoding. Commands 1-4 are ordinary one-tile steps. Commands
; 5-8 are the corresponding two-tile/ledge steps (Func_fc7e3, status $04).
DEF FOLLOWER_COMMAND_DOWN        EQU 1
DEF FOLLOWER_COMMAND_UP          EQU 2
DEF FOLLOWER_COMMAND_LEFT        EQU 3
DEF FOLLOWER_COMMAND_RIGHT       EQU 4
DEF FOLLOWER_COMMAND_LEDGE_DOWN  EQU 5
DEF FOLLOWER_COMMAND_LEDGE_UP    EQU 6
DEF FOLLOWER_COMMAND_LEDGE_LEFT  EQU 7
DEF FOLLOWER_COMMAND_LEDGE_RIGHT EQU 8

DEF FOLLOWER_STATUS_READY        EQU 1
DEF FOLLOWER_STATUS_WALKING      EQU 3
DEF FOLLOWER_STATUS_TWO_STEP     EQU 4
DEF FOLLOWER_STATUS_FAST         EQU 5
DEF FOLLOWER_NORMAL_FRAMES       EQU $08
DEF FOLLOWER_FAST_FRAMES         EQU $04
DEF FOLLOWER_ANIM_TICKS          EQU $04
DEF FOLLOWER_PIXEL_STEP          EQU 2

; Reset slot 15 and the Yellow size-sentinel command queue. This is the core
; half of the future FollowerClearState lifecycle entry point.
FollowerClearState::
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
	call FollowerClearCommandBuffer
	ret

; Yellow: ClearPikachuFollowCommandBuffer.
FollowerClearCommandBuffer::
	ld hl, wFollowerCommandBufferSize
	ld [hl], FOLLOWER_COMMAND_EMPTY
	inc hl
	ld bc, FOLLOWER_COMMAND_BUFFER_LEN
	xor a
	call FillMemory
	ret

; Yellow: AppendPikachuFollowCommandToBuffer, with an explicit full-queue
; guard. INPUT A = encoded command 1-8. C set means rejected/full/invalid;
; C clear means appended. The size byte is the last occupied index, so $ff
; means empty and 15 means full.
FollowerAppendCommand::
	cp FOLLOWER_COMMAND_DOWN
	jr c, .reject
	cp FOLLOWER_COMMAND_LEDGE_RIGHT + 1
	jr nc, .reject
	ld b, a
	ld a, [wFollowerCommandBufferSize]
	cp FOLLOWER_COMMAND_EMPTY
	jr z, .store_first
	cp FOLLOWER_COMMAND_LAST_INDEX
	jr nc, .reject
.store_first
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

; Encode the current accepted player direction using Yellow Func_fcc42's
; priority and values. This helper only encodes ordinary commands. Ledge
; callers may pass commands 5-8 directly to FollowerQueueEncodedStep.
FollowerEncodePlayerDirection::
	ld a, [wPlayerDirection]
	bit PLAYER_DIR_BIT_UP, a
	jr nz, .up
	bit PLAYER_DIR_BIT_DOWN, a
	jr nz, .down
	bit PLAYER_DIR_BIT_LEFT, a
	jr nz, .left
	bit PLAYER_DIR_BIT_RIGHT, a
	jr nz, .right
	scf
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
.right
	ld a, FOLLOWER_COMMAND_RIGHT
	and a
	ret

; Future hook: call once after a player step has been accepted. Yellow's
; Func_fcc08 also owns bike/fishing policy and the bit-6 ledge latch. Bicycle
; and surfing are intentionally omitted. The integration layer can use this
; normal-step entry or pass a Yellow encoded ledge command to the next entry.
FollowerQueuePlayerStep::
	call FollowerEncodePlayerDirection
	ret c
	jp FollowerAppendCommand

; INPUT A = already encoded Yellow command 1-8. This is the escape hatch for
; the future ledge hook until wFollowerLedgeLatch is allocated and wired.
FollowerQueueEncodedStep::
	jp FollowerAppendCommand

; Yellow: Func_fcc92. The sentinel/last-index convention intentionally keeps
; the one-step lag: size 0 is not dequeued. OUTPUT A = command, C clear on
; success; C set when empty or only the lag command remains.
FollowerDequeueCommand::
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

; Yellow: AreThereAtLeastTwoStepsInPikachuFollowCommandBuffer.
FollowerAtLeastTwoQueued::
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

; Called once per overworld update for the reconstructed slot-15 state. The
; integration caller owns the active/hidden policy and must not call this
; while a script has temporarily suppressed follower control.
FollowerUpdate::
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_MOVEMENTSTATUS]
	cp FOLLOWER_STATUS_WALKING
	jr z, FollowerAdvanceStep
	cp FOLLOWER_STATUS_TWO_STEP
	jr z, FollowerAdvanceStep
	cp FOLLOWER_STATUS_FAST
	jr z, FollowerAdvanceStep
	cp FOLLOWER_STATUS_READY
	ret nz
	call FollowerDequeueCommand
	ret c
	call FollowerStartCommand
	ret

; Start one queued command. Normal/fast selection mirrors Yellow's queue
; backlog rule. Commands 5-8 always use the eight-frame two-step path.
; INPUT A = encoded command 1-8.
FollowerStartCommand::
	push af
	call FollowerAtLeastTwoQueued
	ld b, FOLLOWER_NORMAL_FRAMES
	ld c, FOLLOWER_STATUS_WALKING
	jr nc, .speed_done
	ld b, FOLLOWER_FAST_FRAMES
	ld c, FOLLOWER_STATUS_FAST
.speed_done
	pop af
	cp FOLLOWER_COMMAND_LEDGE_DOWN
	jr c, .normal_speed_done
	ld b, FOLLOWER_NORMAL_FRAMES
	ld c, FOLLOWER_STATUS_TWO_STEP
.normal_speed_done
	push bc
	dec a
	ld e, a
	add a ; * 2
	add e ; * 3-byte command record
	ld e, a
	ld d, 0
	ld hl, FollowerCommandData
	add hl, de
	ld a, [hli]
	ld [wSprite15StateData1 + SPRITESTATEDATA1_FACINGDIRECTION], a
	ld a, [hli]
	ld [wSprite15StateData1 + SPRITESTATEDATA1_XSTEPVECTOR], a
	ld a, [hli]
	ld [wSprite15StateData1 + SPRITESTATEDATA1_YSTEPVECTOR], a
	pop bc
	ld a, c
	ld [wSprite15StateData1 + SPRITESTATEDATA1_MOVEMENTSTATUS], a
	ld a, b
	ld [wSprite15StateData2 + SPRITESTATEDATA2_WALKANIMATIONCOUNTER], a
	call FollowerAddStepVector
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_MOVEMENTSTATUS]
	cp FOLLOWER_STATUS_TWO_STEP
	ret nz
	call FollowerAddStepVector
	ret

; Yellow Pointer_fc7e3, reordered as explicit records for readability:
; facing, X map-step, Y map-step. Movement status is selected from queue depth
; or the ledge command range, matching Yellow's separate 3/5/4 state paths.
FollowerCommandData::
	db SPRITE_FACING_DOWN,  0,  1
	db SPRITE_FACING_UP,    0, -1
	db SPRITE_FACING_LEFT,  -1, 0
	db SPRITE_FACING_RIGHT, 1,  0
	db SPRITE_FACING_DOWN,  0,  1
	db SPRITE_FACING_UP,    0, -1
	db SPRITE_FACING_LEFT,  -1, 0
	db SPRITE_FACING_RIGHT, 1,  0

; Yellow AddPikachuStepVector. Map coordinates advance at command start,
; including twice for a two-step command.
FollowerAddStepVector::
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

; Yellow NormalPikachuFollow/FastPikachuFollow/Func_fca0a movement body.
; Yellow moves normal status 3 by two pixels for eight updates, fast status 5
; by four pixels for four updates, and two-step status 4 by four pixels for
; eight updates. Sprite60FPS phase selection still belongs in integration.
FollowerAdvanceStep::
	ld a, [wSprite15StateData2 + SPRITESTATEDATA2_WALKANIMATIONCOUNTER]
	and a
	jr z, .finish
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_YSTEPVECTOR]
	add a
	ld b, a
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_MOVEMENTSTATUS]
	cp FOLLOWER_STATUS_WALKING
	ld a, b
	jr z, .got_y_delta
	add a
.got_y_delta
	ld b, a
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_YPIXELS]
	add b
	ld [wSprite15StateData1 + SPRITESTATEDATA1_YPIXELS], a
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_XSTEPVECTOR]
	add a
	ld b, a
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_MOVEMENTSTATUS]
	cp FOLLOWER_STATUS_WALKING
	ld a, b
	jr z, .got_x_delta
	add a
.got_x_delta
	ld b, a
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_XPIXELS]
	add b
	ld [wSprite15StateData1 + SPRITESTATEDATA1_XPIXELS], a

	ld hl, wSprite15StateData1 + SPRITESTATEDATA1_INTRAANIMFRAMECOUNTER
	ld a, [hl]
	inc a
	cp FOLLOWER_ANIM_TICKS
	jr nz, .store_intra
	xor a
	ld [hl], a
	inc hl
	ld a, [hl]
	inc a
	and $03
	ld [hl], a
	jr .decrement
.store_intra
	ld [hl], a
.decrement
	ld hl, wSprite15StateData2 + SPRITESTATEDATA2_WALKANIMATIONCOUNTER
	dec [hl]
	jr nz, .refresh
.finish
	xor a
	ld [wSprite15StateData1 + SPRITESTATEDATA1_YSTEPVECTOR], a
	ld [wSprite15StateData1 + SPRITESTATEDATA1_XSTEPVECTOR], a
	ld a, FOLLOWER_STATUS_READY
	ld [wSprite15StateData1 + SPRITESTATEDATA1_MOVEMENTSTATUS], a
.refresh
	call FollowerUpdateImage
	ret

; Yellow UpdatePikachuWalkingSprite. IMAGEBASEOFFSET is converted to the
; high nibble used by PrepareOAMData; slot 2 therefore selects $10-$1f.
FollowerUpdateImage::
	ld a, [wSprite15StateData2 + SPRITESTATEDATA2_IMAGEBASEOFFSET]
	and a
	jr z, .hidden
	dec a
	swap a
	ld b, a
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_FACINGDIRECTION]
	or b
	ld b, a
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_ANIMFRAMECOUNTER]
	and $03
	or b
	ld [wSprite15StateData1 + SPRITESTATEDATA1_IMAGEINDEX], a
	ret
.hidden
	ld a, FOLLOWER_COMMAND_EMPTY
	ld [wSprite15StateData1 + SPRITESTATEDATA1_IMAGEINDEX], a
	ret

; TODO, exact Yellow labels intentionally left outside this bounded draft:
;   ShouldPikachuSpawn -> FollowerShouldSpawn
;   SchedulePikachuSpawnForAfterText -> FollowerScheduleSpawn
;   CalculatePikachuPlacementCoords / CalculatePikachuFacingDirection
;       -> transition-aware follower placement/facing integration
;   WillPikachuSpawnOnTheScreen / UpdatePikachuWalkingSprite's culling path
;       -> visibility/OAM integration
;   Func_fcc08 / Func_fcc64 -> ledge-latch policy (wFollowerLedgeLatch)
;   GetPikachuWalkingAnimationSpeed -> final Sprite60FPS cadence policy.
