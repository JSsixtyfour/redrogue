; Red Rogue follower movement core draft.
;
; Provenance: selective port of pret/pokeyellow
;   commit e6ba56989b0f2694f393e6924820be11dcc1fbb8
;   engine/pikachu/pikachu_follow.asm
;   Yellow source routines adapted by this draft:
;     ClearPikachuFollowCommandBuffer
;     AppendPikachuFollowCommandToBuffer
;     Func_fcc92 (dequeue/shift)
;     AreThereAtLeastTwoStepsInPikachuFollowCommandBuffer
;     Func_fc7e3 / NormalPikachuFollow / FastPikachuFollow / Func_fca0a
;     AddPikachuStepVector / DoubleAddPikachuStepVectorToScreenPixelCoords
;     UpdatePikachuWalkingSprite
;     Func_fc803 / Func_fc842 / Func_fc862 / Func_fc8f8 / Func_fc92b / Func_fc95d
;     RefreshPikachuFollow / ComputePikachuFollowCommand / Func_fcae2
;     Func_fc793 / Func_fc76a / SchedulePikachuSpawnForAfterText
;     Func_fc745 (face-player request, with explicit stationary guards)
;
; This file is intentionally not included in the game build yet. Isolated
; assembly tests exercise it without allocating game RAM or reserving slot 15.
; Placement/culling below also port CalculatePikachuPlacementCoords,
; CalculatePikachuFacingDirection, ComputePikachuFacingDirection and
; WillPikachuSpawnOnTheScreen. The transition caller, not a Yellow map-ID
; table, will choose a placement mode. Geometry-only deferred scheduling is
; present; policy, loader, interaction and lifecycle hooks remain integration
; work. The outer lifecycle must gate active/visible state before ticking.
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
DEF FOLLOWER_STATUS_WAITING      EQU 2
DEF FOLLOWER_STATUS_WALKING      EQU 3
DEF FOLLOWER_STATUS_TWO_STEP     EQU 4
DEF FOLLOWER_STATUS_FAST         EQU 5
DEF FOLLOWER_STATUS_HOP          EQU 6
DEF FOLLOWER_STATUS_IDLE_WALK    EQU 7
DEF FOLLOWER_STATUS_IDLE_TOGGLE  EQU 8
DEF FOLLOWER_STATUS_IDLE_TURN    EQU 9
DEF FOLLOWER_NORMAL_FRAMES       EQU $08
DEF FOLLOWER_FAST_FRAMES         EQU $04
DEF FOLLOWER_ANIM_TICKS          EQU $04
DEF FOLLOWER_PIXEL_STEP          EQU 2

; Yellow wPikachuSpawnState values, now explicit geometry-only inputs.
DEF FOLLOWER_PLACE_OVERLAP       EQU 0
DEF FOLLOWER_PLACE_RIGHT         EQU 1
DEF FOLLOWER_PLACE_BEHIND        EQU 2
DEF FOLLOWER_PLACE_OVERLAP_DOWN  EQU 3
DEF FOLLOWER_PLACE_BELOW         EQU 4
DEF FOLLOWER_PLACE_ABOVE         EQU 5
DEF FOLLOWER_PLACE_LEFT          EQU 6
DEF FOLLOWER_PLACE_AHEAD         EQU 7

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
	xor a
	ld [wFollowerLedgeLatch], a
	ret

; Yellow: ClearPikachuFollowCommandBuffer.
FollowerClearCommandBuffer::
	push bc
	ld hl, wFollowerCommandBufferSize
	ld [hl], FOLLOWER_COMMAND_EMPTY
	ld hl, wFollowerCommandBuffer
	ld bc, FOLLOWER_COMMAND_BUFFER_LEN
	xor a
	call FillMemory
	pop bc
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

; Future hook: once per ACCEPTED map-tile player step, never raw input or
; fishing ticks. Yellow Func_fcc08 / Func_fcc64: the first half of a ledge
; appends a two-tile command; the second half only clears the latch. Yellow's
; second-half RET inherited carry from Func_fcc23; make that contract explicit.
; No walking/bike/surf gating here: caller owns active/suppressed policy.
FollowerQueuePlayerStep::
	ld a, [wMovementFlags]
	bit BIT_LEDGE_OR_FISHING, a
	jr nz, .ledge
	xor a
	ld [wFollowerLedgeLatch], a
	call FollowerEncodePlayerDirection
	ret c
	jp FollowerAppendCommand
.ledge
	ld a, [wFollowerLedgeLatch]
	and a
	jr z, .first_half
	xor a
	ld [wFollowerLedgeLatch], a
	scf
	ret
.first_half
	call FollowerEncodePlayerDirection
	ret c
	add FOLLOWER_COMMAND_LEDGE_DOWN - FOLLOWER_COMMAND_DOWN
	call FollowerAppendCommand
	ret c
	ld a, 1
	ld [wFollowerLedgeLatch], a
	and a
	ret

; Banked entry: INPUT E = encoded Yellow command 1-8. A cannot carry inputs
; through Red Rogue's farcall trampoline. Local helpers may still use A.
FollowerQueueEncodedStep::
	ld a, e
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
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_PICTUREID]
	and a
	ret z ; clear state is disabled, not a pending spawn
	ld hl, wSprite15StateData1 + SPRITESTATEDATA1_MOVEMENTSTATUS
	bit BIT_FACE_PLAYER, [hl]
	jr z, .no_interaction
; Yellow handles this request before font handling and numeric dispatch.
; Consume even a stale request, but never reinterpret $80 as initialization.
	res BIT_FACE_PLAYER, [hl]
	jp FollowerFacePlayer
.no_interaction
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_MOVEMENTSTATUS]
	and a
	jp z, FollowerInitializePendingSpawn
	ld a, [wFontLoaded]
	bit BIT_FONT_LOADED, a
	jp nz, FollowerRefreshAfterText
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_MOVEMENTSTATUS]
	cp FOLLOWER_STATUS_IDLE_TURN + 1
	jp nc, FollowerInitializePendingSpawn
	cp FOLLOWER_STATUS_HOP
	jp nc, FollowerUpdateIdleAction
	cp FOLLOWER_STATUS_WALKING
	jp z, FollowerAdvanceStep
	cp FOLLOWER_STATUS_TWO_STEP
	jp z, FollowerAdvanceStep
	cp FOLLOWER_STATUS_FAST
	jp z, FollowerAdvanceStep
	cp FOLLOWER_STATUS_READY
	jp nz, FollowerWait
	call FollowerDequeueCommand
	jp nc, FollowerStartCommand
	jp FollowerWait

; Core interaction eligibility, not party/option/script spawn policy or a
; front-tile hit test. The caller must establish those before opening text.
; Carry clear = stationary initialized visible state; carry set = rejected.
; No input registers; clobbers AF/BC/DE/HL. Visibility checks may hide the
; image or refresh grass priority, but never change position or the queue.
FollowerCanInteract::
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_PICTUREID]
	and a
	jr z, .reject
	ld a, [wWalkCounter]
	and a
	jr nz, .reject
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_MOVEMENTSTATUS]
	and $7f
	jr z, .reject
	cp FOLLOWER_STATUS_IDLE_TURN + 1
	jr nc, .reject
	cp FOLLOWER_STATUS_WALKING
	jr c, .stationary
	cp FOLLOWER_STATUS_HOP
	jr c, .reject
.stationary
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_IMAGEINDEX]
	cp $ff
	jr z, .reject
	call FollowerHideIfOverlappingPlayer
	ret c
	jp FollowerCheckVisibility
.reject
	scf
	ret

; Yellow Func_fc745: face opposite the player, reset animation, redraw.
; Deliberate adaptation: reject an in-flight step instead of changing its
; facing or counter. Finish idle actions and remove our reused hop offsets
; before releasing their state. Queue, ledge latch and map coords survive.
; Carry clear = accepted; carry set = rejected. No argument registers;
; clobbers AF/BC/DE/HL. Does not print text, save facing, or tick movement.
FollowerFacePlayer::
	call FollowerCanInteract
	ret c
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_MOVEMENTSTATUS]
	and $7f
	cp FOLLOWER_STATUS_HOP
	call z, FollowerRemoveIdleOffset
	ld a, FOLLOWER_STATUS_READY
	ld [wSprite15StateData1 + SPRITESTATEDATA1_MOVEMENTSTATUS], a
	xor a
	ld [wSprite15StateData2 + SPRITESTATEDATA2_WALKANIMATIONCOUNTER], a
	ld [wSprite15StateData2 + SPRITESTATEDATA2_0A], a
	call FollowerResetAnimation
	ld a, [wSpritePlayerStateData1FacingDirection]
	xor 4
	ld [wSprite15StateData1 + SPRITESTATEDATA1_FACINGDIRECTION], a
	call FollowerUpdateImage
	and a
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
; A command starts a complete pair of 60 FPS half-steps. Waiting/idle may
; have left phase 1; inheriting it would finish one pixel update too early.
	xor a
	ld [wSprite15StateData2 + SPRITESTATEDATA2_0A], a
	ld a, b
	ld [wSprite15StateData2 + SPRITESTATEDATA2_WALKANIMATIONCOUNTER], a
	call FollowerAddStepVector
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_MOVEMENTSTATUS]
	cp FOLLOWER_STATUS_TWO_STEP
	call z, FollowerAddStepVector
; Yellow starts the first pixel update on the same call as command dispatch.
	jp FollowerAdvanceStep

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
; eight logical updates. At 60 FPS split each delta across two calls and
; advance counters only on phase 0. This preserves 16/16/32 pixels and the
; 8/4/8 logical durations without adding a stationary frame between steps.
; The slot-local phase is exactly Sprite60FPS's state2 + $0a toggle. That
; helper is in bank1, so use its small math here rather than a cross-bank CALL.
FollowerAdvanceStep::
	ld a, [wSprite15StateData2 + SPRITESTATEDATA2_WALKANIMATIONCOUNTER]
	and a
	jp z, .finish
	call FollowerTickPhase
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
	ld a, [wOptions2]
	bit BIT_60_FPS, a
	ld a, b
	jr z, .full_y_delta
	sra a
.full_y_delta
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
	ld a, [wOptions2]
	bit BIT_60_FPS, a
	ld a, b
	jr z, .full_x_delta
	sra a
.full_x_delta
	ld b, a
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_XPIXELS]
	add b
	ld [wSprite15StateData1 + SPRITESTATEDATA1_XPIXELS], a
	ld a, [wSprite15StateData2 + SPRITESTATEDATA2_0A]
	and a
	jr nz, .refresh

; Deliberate happiness omission: fixed four-logical-tick cadence, matching
; Red Rogue's ordinary NPC cadence rather than Yellow's happiness thresholds.
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
	call FollowerComputeFacing
.refresh
	call FollowerUpdateImage
	ret

; Yellow UpdatePikachuWalkingSprite. IMAGEBASEOFFSET is converted to the
; high nibble used by PrepareOAMData; slot 2 therefore selects $10-$1f.
FollowerUpdateImage::
	ld a, [wFontLoaded]
	bit BIT_FONT_LOADED, a
	jr z, .visibility
	call FollowerHideIfOverlappingPlayer
	ret c
.visibility
	call FollowerCheckVisibility
	ret c
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

; Yellow Func_fc803. No dequeueable command: hide under the player, otherwise
; count down before looking around. The zero -> $ff wrap is intentional in
; Yellow; movement completion leaves zero, while an idle action leaves $10.
FollowerWait:
	call FollowerHideIfOverlappingPlayer
	ret c
	call FollowerTickPhase
	and a
	jr nz, .image
	ld hl, wSprite15StateData2 + SPRITESTATEDATA2_WALKANIMATIONCOUNTER
	dec [hl]
	jr nz, .image
	call FollowerGetLastCommand
	cp FOLLOWER_COMMAND_LEDGE_DOWN
	jp nc, FollowerStartIdleAction
	ld a, $20
	ld [wSprite15StateData2 + SPRITESTATEDATA2_WALKANIMATIONCOUNTER], a
	call Random
	and $0c
	ld [wSprite15StateData1 + SPRITESTATEDATA1_FACINGDIRECTION], a
.image
	call FollowerResetAnimation
	jp FollowerUpdateImage

; Yellow Func_fc842 / PointerTable_fc85a: only a last queued two-tile command
; enables the four idle actions. They do not depend on happiness or emotions.
; LOCAL INPUT A = last command 5-8. Yellow selects with hRandomAdd, not A.
FollowerStartIdleAction:
	push af
	call Random
	ldh a, [hRandomAdd]
	and 3
	ld e, a
	ld d, 0
	ld hl, .actions
	add hl, de
	add hl, de
	ld a, [hli]
	ld h, [hl]
	ld l, a
	pop af
	jp hl
.actions
	dw .hop, .walk, .toggle, .turn
.hop
	dec a
	add a
	add a
	and $0c
	ld [wSprite15StateData1 + SPRITESTATEDATA1_FACINGDIRECTION], a
; Yellow wd431/wd432 are previous visual offsets, not new path vectors.
; Reuse our vectors only while in HOP state; restore them before READY.
	xor a
	ld [wSprite15StateData1 + SPRITESTATEDATA1_YSTEPVECTOR], a
	ld [wSprite15StateData1 + SPRITESTATEDATA1_XSTEPVECTOR], a
	ld a, FOLLOWER_STATUS_HOP
	ld e, $11
	jr .start
.walk
	ld a, FOLLOWER_STATUS_IDLE_WALK
	ld e, $30
	jr .start
.toggle
	ld a, FOLLOWER_STATUS_IDLE_TOGGLE
	ld e, $20
	jr .start
.turn
	ld a, FOLLOWER_STATUS_IDLE_TURN
	ld e, $20
.start
	ld [wSprite15StateData1 + SPRITESTATEDATA1_MOVEMENTSTATUS], a
	ld a, e
	ld [wSprite15StateData2 + SPRITESTATEDATA2_WALKANIMATIONCOUNTER], a
; As in Yellow, initialization immediately performs the first action tick.
	jp FollowerAdvanceIdleAction

FollowerUpdateIdleAction:
	ld a, [wWalkCounter]
	and a
	jp nz, FollowerFinishIdleAction
	call FollowerTickPhase
	and a
	jp nz, FollowerUpdateImage
FollowerAdvanceIdleAction:
	ld a, [wWalkCounter]
	and a
	jp nz, FollowerFinishIdleAction
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_MOVEMENTSTATUS]
	cp FOLLOWER_STATUS_HOP
	jr z, .hop
	ld hl, wSprite15StateData1 + SPRITESTATEDATA1_INTRAANIMFRAMECOUNTER
	inc [hl]
	ld a, [hl]
	cp 8
	jr nz, .decrement
	xor a
	ld [hl], a
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_MOVEMENTSTATUS]
	cp FOLLOWER_STATUS_IDLE_TURN
	jr z, .turn
	ld hl, wSprite15StateData1 + SPRITESTATEDATA1_ANIMFRAMECOUNTER
	cp FOLLOWER_STATUS_IDLE_TOGGLE
	ld a, [hl]
	jr z, .toggle
	inc a
	and 3
	jr .store_frame
.toggle
	xor 1
.store_frame
	ld [hl], a
	jr .decrement
.turn
; Exact Yellow clockwise sequence, indexed by the current facing / 4.
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_FACINGDIRECTION]
	srl a
	srl a
	ld e, a
	ld d, 0
	ld hl, .clockwise
	add hl, de
	ld a, [hl]
	ld [wSprite15StateData1 + SPRITESTATEDATA1_FACINGDIRECTION], a
	jr .decrement
.hop
	call FollowerRemoveIdleOffset
	ld a, [wSprite15StateData2 + SPRITESTATEDATA2_WALKANIMATIONCOUNTER]
	dec a
	add a
	ld e, a
	ld d, 0
	ld hl, .hop_offsets
	add hl, de
	ld a, [hli]
	ld [wSprite15StateData1 + SPRITESTATEDATA1_YSTEPVECTOR], a
	ld b, a
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_YPIXELS]
	add b
	ld [wSprite15StateData1 + SPRITESTATEDATA1_YPIXELS], a
	ld a, [hl]
	ld [wSprite15StateData1 + SPRITESTATEDATA1_XSTEPVECTOR], a
	ld b, a
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_XPIXELS]
	add b
	ld [wSprite15StateData1 + SPRITESTATEDATA1_XPIXELS], a
.decrement
	call FollowerUpdateImage
	ld hl, wSprite15StateData2 + SPRITESTATEDATA2_WALKANIMATIONCOUNTER
	dec [hl]
	ret nz
	jp FollowerFinishIdleAction
.clockwise
	db SPRITE_FACING_LEFT, SPRITE_FACING_RIGHT, SPRITE_FACING_UP, SPRITE_FACING_DOWN
; Yellow Pointer_fc8d6, consumed from last pair to first.
.hop_offsets
	db  0,  0, -2,  1, -4,  2, -2,  3,  0,  4, -2,  3
	db -4,  2, -2,  1,  0,  0, -2, -1, -4, -2, -2, -3
	db  0, -4, -2, -3, -4, -2, -2, -1,  0,  0

FollowerRemoveIdleOffset:
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_YSTEPVECTOR]
	ld b, a
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_YPIXELS]
	sub b
	ld [wSprite15StateData1 + SPRITESTATEDATA1_YPIXELS], a
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_XSTEPVECTOR]
	ld b, a
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_XPIXELS]
	sub b
	ld [wSprite15StateData1 + SPRITESTATEDATA1_XPIXELS], a
	xor a
	ld [wSprite15StateData1 + SPRITESTATEDATA1_YSTEPVECTOR], a
	ld [wSprite15StateData1 + SPRITESTATEDATA1_XSTEPVECTOR], a
	ret

; Yellow Func_fc835 / Func_fc8c7. Player movement interrupts idle actions;
; remove a hop's previous displacement before returning control to the queue.
FollowerFinishIdleAction:
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_MOVEMENTSTATUS]
	cp FOLLOWER_STATUS_HOP
	call z, FollowerRemoveIdleOffset
	ld a, $10
	ld [wSprite15StateData2 + SPRITESTATEDATA2_WALKANIMATIONCOUNTER], a
	ld a, FOLLOWER_STATUS_READY
	ld [wSprite15StateData1 + SPRITESTATEDATA1_MOVEMENTSTATUS], a
	ret

FollowerResetAnimation:
	xor a
	ld [wSprite15StateData1 + SPRITESTATEDATA1_INTRAANIMFRAMECOUNTER], a
	ld [wSprite15StateData1 + SPRITESTATEDATA1_ANIMFRAMECOUNTER], a
	ret

; Slot-specific equivalent of Sprite60FPS. A = phase (0: logical tick).
; Walking splits pixels over both phases; idle animation advances on phase 0.
FollowerTickPhase:
	ld hl, wSprite15StateData2 + SPRITESTATEDATA2_0A
	ld a, [wOptions2]
	bit BIT_60_FPS, a
	ld a, [hl]
	jr nz, .toggle
	xor a
	jr .store
.toggle
	xor 1
.store
	ld [hl], a
	ret

; Yellow Func_fcae2. Overlap is hidden only in waiting/text paths; moving
; through the player's tile must still execute the replayed command.
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
	ld a, $ff
	ld [wSprite15StateData1 + SPRITESTATEDATA1_IMAGEINDEX], a
	scf
	ret
.visible
	and a
	ret

; Yellow GetPikachuFollowCommand: last appended value, or zero when empty.
FollowerGetLastCommand:
	ld a, [wFollowerCommandBufferSize]
	cp FOLLOWER_COMMAND_EMPTY
	jr z, .empty
	ld e, a
	ld d, 0
	ld hl, wFollowerCommandBuffer
	add hl, de
	ld a, [hl]
	ret
.empty
	xor a
	ret

; Yellow RefreshPikachuFollow / ComputePikachuFollowCommand. Reconstruct one
; lag command from geometry, Y before X. Exactly one tile uses commands 1-4;
; two or more uses 5-8. No command on overlap. This seeds a chosen placement,
; not an arbitrary pathfinder; transition callers must supply safe geometry.
FollowerRefreshQueue::
	call FollowerClearCommandBuffer
	call FollowerComputeSeedCommand
	ret c
	jp FollowerAppendCommand

FollowerComputeSeedCommand:
	ld a, [wSprite15StateData2 + SPRITESTATEDATA2_MAPY]
	ld b, a
	ld a, [wYCoord]
	add 4
	sub b
	jr z, .x
	ld e, FOLLOWER_COMMAND_DOWN
	jr nc, .magnitude
	ld e, FOLLOWER_COMMAND_UP
	jr .negative
.x
	ld a, [wSprite15StateData2 + SPRITESTATEDATA2_MAPX]
	ld b, a
	ld a, [wXCoord]
	add 4
	sub b
	jr z, .overlap
	ld e, FOLLOWER_COMMAND_RIGHT
	jr nc, .magnitude
	ld e, FOLLOWER_COMMAND_LEFT
.negative
	cpl
	inc a
.magnitude
	cp 2
	ld a, e
	jr c, .one_tile
	add 4
.one_tile
	and a
	ret
.overlap
	scf
	ret

; Deferred geometry-only scheduling, adapting SchedulePikachuSpawnForAfterText
; and Func_fc793. INPUT D = validated picture, E = placement mode. Unlike
; Yellow's global bit-4 policy this API gets an explicit placement from the
; lifecycle caller. A nonzero picture plus status 0 means pending; cleared
; picture 0 remains disabled. No additional saved or temporary RAM is needed.
FollowerScheduleSpawn::
	call FollowerPlaceAtPlayer
	ret c
	xor a
	ld [wSprite15StateData1 + SPRITESTATEDATA1_MOVEMENTSTATUS], a
	ret

FollowerInitializePendingSpawn:
	ld a, [wFontLoaded]
	bit BIT_FONT_LOADED, a
	ret nz
	call FollowerRefreshQueue
	call FollowerInitializeScreenPosition
	ld a, $ff
	ld [wSprite15StateData1 + SPRITESTATEDATA1_IMAGEINDEX], a
	ld a, FOLLOWER_STATUS_READY
	ld [wSprite15StateData1 + SPRITESTATEDATA1_MOVEMENTSTATUS], a
	ret

; Yellow Func_fc76a: font/text pause resets animation and re-seeds following.
; Rebase screen coordinates only if the player is stationary. Remove our
; reused hop offset before releasing HOP ownership, including mid-step text.
; Lifecycle suppression remains a separate caller contract. Interaction bit
; 7 is consumed before this path by FollowerUpdate.
FollowerRefreshAfterText:
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_MOVEMENTSTATUS]
	cp FOLLOWER_STATUS_HOP
	call z, FollowerRemoveIdleOffset
	call FollowerResetAnimation
	call FollowerUpdateImage
	ld a, [wWalkCounter]
	and a
	call z, FollowerInitializeScreenPosition
	ld a, FOLLOWER_STATUS_READY
	ld [wSprite15StateData1 + SPRITESTATEDATA1_MOVEMENTSTATUS], a
	xor a
	ld [wSprite15StateData2 + SPRITESTATEDATA2_WALKANIMATIONCOUNTER], a
	jp FollowerRefreshQueue

; Geometry half of Yellow CalculatePikachuPlacementCoords and
; CalculatePikachuFacingDirection. INPUT D = validated walking picture ID,
; E = FOLLOWER_PLACE_* (0-7). Invalid mode: carry set, no writes.
; This is not spawn policy: the caller must validate the species, load its
; slot-2 graphics, and choose a safe transition placement before calling.
; No collision guessing or fixed destination-map tables are imported.
FollowerPlaceAtPlayer::
	ld a, e
	cp FOLLOWER_PLACE_AHEAD + 1
	ccf
	ret c
	push de
	call FollowerClearState
	pop de
	ld a, d
	ld [wSprite15StateData1 + SPRITESTATEDATA1_PICTUREID], a
	ld a, 2
	ld [wSprite15StateData2 + SPRITESTATEDATA2_IMAGEBASEOFFSET], a
	ld b, e ; keep Yellow's placement mode while DE becomes map X/Y
	ld a, [wYCoord]
	add 4
	ld e, a
	ld a, [wXCoord]
	add 4
	ld d, a
	ld a, b
	and a
	jr z, .load_coords
	cp FOLLOWER_PLACE_RIGHT
	jr z, .right
	cp FOLLOWER_PLACE_BEHIND
	jr z, .behind
	cp FOLLOWER_PLACE_OVERLAP_DOWN
	jr z, .load_coords
	cp FOLLOWER_PLACE_BELOW
	jr z, .below
	cp FOLLOWER_PLACE_ABOVE
	jr z, .above
	cp FOLLOWER_PLACE_LEFT
	jr z, .left
	ld a, [wSpritePlayerStateData1FacingDirection]
	jr .direction
.behind
	ld a, [wSpritePlayerStateData1FacingDirection]
	xor 4
.direction
	and a ; down
	jr z, .below
	cp SPRITE_FACING_UP
	jr z, .above
	cp SPRITE_FACING_LEFT
	jr z, .left
.right
	inc d
	jr .load_coords
.left
	dec d
	jr .load_coords
.below
	inc e
	jr .load_coords
.above
	dec e
.load_coords
	ld a, e
	ld [wSprite15StateData2 + SPRITESTATEDATA2_MAPY], a
	ld a, d
	ld [wSprite15StateData2 + SPRITESTATEDATA2_MAPX], a
	ld a, $fe ; Yellow's following movement marker, not generic TryWalking
	ld [wSprite15StateData2 + SPRITESTATEDATA2_MOVEMENTBYTE1], a
	ld a, b
	cp FOLLOWER_PLACE_OVERLAP_DOWN
	jr z, .face_down
	cp FOLLOWER_PLACE_AHEAD
	jr z, .face_back
	cp FOLLOWER_PLACE_BEHIND
	jr z, .face_player
	cp FOLLOWER_PLACE_ABOVE
	jr z, .face_player
	ld a, [wSpritePlayerStateData1FacingDirection]
	jr .store_facing
.face_down
	ld a, SPRITE_FACING_DOWN
	jr .store_facing
.face_back
	ld a, [wSpritePlayerStateData1FacingDirection]
	xor 4
	jr .store_facing
.face_player
	call FollowerComputeFacing
	jr .screen_position
.store_facing
	ld [wSprite15StateData1 + SPRITESTATEDATA1_FACINGDIRECTION], a
.screen_position
; The raw geometry helper deliberately does not seed the queue. Use the
; scheduled entry below for normal activation, like Yellow's state 0 path.
	call FollowerInitializeScreenPosition
	ld a, FOLLOWER_STATUS_READY
	ld [wSprite15StateData1 + SPRITESTATEDATA1_MOVEMENTSTATUS], a
	and a
	ret ; image stays hidden until the first visibility refresh

FollowerInitializeScreenPosition:
; Exact InitializeSpriteScreenPosition coordinate math, explicit slot 15.
; The generic helper is bank1 and needs hCurrentSpriteOffset; this leaf must
; not assume either that bank or a caller-owned sprite offset.
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

; Yellow ComputePikachuFacingDirection: when >1 queued commands remain,
; use the most recently appended command; otherwise face the player, Y first.
; Same-position fallback copies player facing. This does not import Yellow's
; separate timed spinning/turning states.
FollowerComputeFacing::
	ld a, [wFollowerCommandBufferSize]
	cp FOLLOWER_COMMAND_EMPTY
	jr z, .check_y
	and a
	jr z, .check_y
	ld e, a
	ld d, 0
	ld hl, wFollowerCommandBuffer
	add hl, de
	ld a, [hl]
	and a
	jr z, .check_y
	dec a
	and 3
	add a
	add a
	jr .store
.check_y
	ld a, [wYCoord]
	add 4
	ld d, a
	ld a, [wXCoord]
	add 4
	ld e, a
	ld a, [wSprite15StateData2 + SPRITESTATEDATA2_MAPY]
	cp d
	jr z, .check_x
	ld a, SPRITE_FACING_DOWN
	jr c, .store
	ld a, SPRITE_FACING_UP
	jr .store
.check_x
	ld a, [wSprite15StateData2 + SPRITESTATEDATA2_MAPX]
	cp e
	jr z, .copy_player
	ld a, SPRITE_FACING_RIGHT
	jr c, .store
	ld a, SPRITE_FACING_LEFT
	jr .store
.copy_player
	ld a, [wSpritePlayerStateData1FacingDirection]
.store
	ld [wSprite15StateData1 + SPRITESTATEDATA1_FACINGDIRECTION], a
	ret

; Yellow WillPikachuSpawnOnTheScreen. Carry set = hidden, clear = visible.
; Slot-explicit pointers avoid depending on hCurrentSpriteOffset. Keep its
; map bounds and grass priority, plus Red Rogue's existing rounded-up Y
; textbox test from CheckSpriteAvailability. Tile IDs use MAP_TILESET_SIZE,
; not Yellow's literal $60. Pixel bounds guard every 2x2 tilemap read.
FollowerCheckVisibility::
	ld a, [wSprite15StateData2 + SPRITESTATEDATA2_MAPY]
	ld b, a
	ld a, [wYCoord]
	cp b
	jr z, .same_y
	jp nc, .hidden
	add SCREEN_HEIGHT / 2 - 1
	cp b
	jp c, .hidden
.same_y
	ld a, [wSprite15StateData2 + SPRITESTATEDATA2_MAPX]
	ld b, a
	ld a, [wXCoord]
	cp b
	jr z, .same_x
	jp nc, .hidden
	add SCREEN_WIDTH / 2 - 1
	cp b
	jp c, .hidden
.same_x
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_YPIXELS]
	add 4
	ld e, a
	and $f0
	push de
	call .tile_pointer
	jr c, .pop_hidden
	call .test_tiles
	jr nc, .pop_hidden
; Preserve Yellow's bottom-left tile for grass priority across the second
; test; E is otherwise scratch. Round up only when Y has a partial step.
	ld a, [hl]
	ld c, a
	pop de
	push bc
	ld a, e
	and $0f
	ld a, e
	jr z, .rounded
	and $f0
	add $10
.rounded
	call .tile_pointer
	jr c, .pop_hidden
	call .test_tiles
	jr nc, .pop_hidden
	pop bc
	ld a, [wGrassTile]
	cp c
	ld a, 0
	jr nz, .priority
	ld a, OAM_PRIO
.priority
	ld [wSprite15StateData2 + SPRITESTATEDATA2_GRASSPRIORITY], a
	and a
	ret
.pop_hidden
	pop bc
.hidden
	ld a, $ff
	ld [wSprite15StateData1 + SPRITESTATEDATA1_IMAGEINDEX], a
	scf
	ret

; INPUT A = rounded Y pixels, already +4. Returns bottom-left tile HL,
; carry clear, or carry set without reading the tilemap. Yellow's X +2
; sampling bias is retained; reject columns beyond the final full 2x2 cell.
.tile_pointer
	cp (SCREEN_HEIGHT - 1) * 8
	ccf
	ret c
	srl a
	ld c, a
	ld b, 0
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_XPIXELS]
	add 2
	ret c
	srl a
	srl a
	srl a
	cp SCREEN_WIDTH - 1
	ccf
	ret c
	add SCREEN_WIDTH
	ld e, a
	ld d, 0
	ld hl, wTileMap
REPT 5
	add hl, bc
ENDR
	add hl, de
	and a
	ret

; Same four tile tests as Yellow / CheckSpriteAvailability. Carry set means
; all four are map tiles. Restore HL to bottom-left for the priority read.
.test_tiles
	push hl
	ld a, [hli]
	cp MAP_TILESET_SIZE
	jr nc, .tiles_done
	ld a, [hld]
	cp MAP_TILESET_SIZE
	jr nc, .tiles_done
	ld bc, -SCREEN_WIDTH
	add hl, bc
	ld a, [hli]
	cp MAP_TILESET_SIZE
	jr nc, .tiles_done
	ld a, [hl]
	cp MAP_TILESET_SIZE
.tiles_done
	pop hl
	ret

; TODO integration: ShouldPikachuSpawn, interaction/suppression bit-7 policy,
; transition placement policy, camera scroll deltas, slot ownership, and a
; single update call per overworld tick. No game
; RAM is allocated: size byte + 16 commands + latch byte remain symbolic.
