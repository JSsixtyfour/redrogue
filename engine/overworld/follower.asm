; engine/overworld/follower.asm
;
; Pokemon follower system, ported from pokeyellow's Pikachu follow code.
;
; ARCHITECTURE (Yellow-faithful):
;   The follower uses wSprite15StateData1/2 — sprite slot 15, same as Yellow's
;   Pikachu. VRAM slot 2 is reserved (NPCs start from slot 3). The NPC shift
;   loop runs hardcoded for 15 sprites so scroll compensation is automatic.
;   OAM is written by the standard PrepareOAMData path (IMAGEBASEOFFSET=2 in
;   IMAGEINDEX high nibble). Tiles are loaded to $8180/$8980 (slot 2).
;
;   - Command buffer: player direction encoded (1-4) and pushed each step.
;     Size-sentinel scheme ($ff = empty); one-step lag is intentional.
;   - FollowerTick advances animation each frame, pops commands when idle.
;     Fast mode (4 frames) when 3+ commands backed up; normal 8 frames otherwise.

; Give the follower its own ROM bank section (mirrors pokeyellow's dedicated
; Pikachu bank), keeping it out of bank1 so that bank doesn't overflow.
; All external callers use farcall/farjp.
SECTION "Follower", ROMX

; Field layout constants shared with wSpriteStateData1/2 (see
; constants/map_object_constants.asm). We reuse the SPRITESTATEDATA1_* /
; SPRITESTATEDATA2_* offsets against our own structs.

; Frames per follower step. Normal = 8 (matches the player's wWalkCounter);
; fast = 4 (used when commands are backed up so the follower can catch up).
; These mirror NormalPikachuFollow / FastPikachuFollow in pokeyellow.
DEF FOLLOWER_WALK_FRAMES_NORMAL EQU $08
DEF FOLLOWER_WALK_FRAMES_FAST   EQU $04
; Step vector magnitude. Yellow stores +-1 and doubles it per frame in the
; pixel update (YPIXELS += YSTEPVECTOR * 2), giving 2 px/frame * 8 = 16 px tile.
DEF FOLLOWER_STEP_PX     EQU  1
; Empty-buffer sentinel for wFollowerCommandBufferSize (pokeyellow uses $ff).
DEF FOLLOWER_BUFFER_EMPTY EQU $ff
; movement status values
DEF FOLLOWER_STATUS_IDLE    EQU 1
DEF FOLLOWER_STATUS_WALKING EQU 3

; Encoded command values (match the pokeyellow command table indices 1-4).
DEF FOLLOWER_CMD_DOWN  EQU 1
DEF FOLLOWER_CMD_UP    EQU 2
DEF FOLLOWER_CMD_LEFT  EQU 3
DEF FOLLOWER_CMD_RIGHT EQU 4

; ============================================================
; FollowerClearBuffer
; Reset the FIFO command buffer to empty.
; Call on every map entry or warp.
; Mirrors ClearPikachuFollowCommandBuffer: size = $ff sentinel, buffer zeroed.
; ============================================================
FollowerClearBuffer::
	ld hl, wFollowerCommandBufferSize
	ld [hl], FOLLOWER_BUFFER_EMPTY  ; $ff = empty sentinel
	inc hl                          ; -> wFollowerCommandBuffer
	ld bc, 16
	xor a
	call FillMemory                 ; zero the 16-byte buffer
	ret

; ============================================================
; SpawnFollower
; Called on map entry after InitMapSprites.
; Loads the follower's sprite state and places it 1 tile behind the player.
; Does nothing on roguelike stage maps or when the party is empty.
; ============================================================
SpawnFollower::
	xor a
	ld [wFollowerActive], a

	; Always clear slot 15 first (Yellow: ClearPikachuSpriteStateData).
	; Prevents ghost rendering when follower transitions from active to inactive.
	ld hl, wSprite15StateData1
	ld de, wSprite15StateData2
	xor a
	ld b, 16
.clearLoop
	ld [hli], a
	ld [de], a
	inc e
	dec b
	jr nz, .clearLoop

	; skip on roguelike stage maps (no follower during trainer stages)
	farcall IsRogueStageMap
	jr nz, .noSpawn             ; Z clear -> is a stage map -> skip

	; skip if the party is empty
	ld a, [wPartyCount]
	and a
	jr z, .noSpawn

	call FollowerInitState
	; select the sprite type for the lead party member
	call FollowerSelectSprite
	; place 1 tile behind the player based on the player's facing direction
	call FollowerPlaceBehindPlayer
	call FollowerInitPixelsFromMap

	ld a, $01
	ld [wFollowerActive], a
	call FollowerClearBuffer
	; Seed one command from facing direction (mirrors RefreshPikachuFollow).
	; SPRITE_FACING 0/4/8/12 -> srl*2 -> 0/1/2/3 -> inc -> cmd 1/2/3/4.
	ld a, [wSpritePlayerStateData1FacingDirection]
	srl a
	srl a
	inc a               ; -> FOLLOWER_CMD 1-4
	ld b, a
	ld hl, wFollowerCommandBufferSize
	inc [hl]            ; $ff -> $00
	ld e, [hl]
	ld d, 0
	ld hl, wFollowerCommandBuffer
	add hl, de
	ld [hl], b
	ret

.noSpawn
	ret

; ============================================================
; SpawnFollowerFromSave
; Like SpawnFollower, but uses the MapY/MapX/facing saved in SRAM instead of
; computing the position from the player. Called on map load (continue).
; LoadFollowerPosition reads SRAM and then jumps here.
; INPUT: b = saved MapY, c = saved MapX, d = saved facing
; ============================================================
SpawnFollowerFromSave::
	push bc
	push de
	call FollowerInitState
	pop de
	pop bc

	; MAPY / MAPX from the save
	ld hl, wSprite15StateData2 + SPRITESTATEDATA2_MAPY
	ld [hl], b
	inc hl
	ld [hl], c

	; facing from the save
	ld a, d
	ld [wSprite15StateData1 + SPRITESTATEDATA1_FACINGDIRECTION], a

	call FollowerInitPixelsFromMap

	ld a, $01
	ld [wFollowerActive], a
	call FollowerClearBuffer
	ret

; ============================================================
; FollowerSelectSprite
; Load the appropriate NPC overworld sprite into VRAM slot 1 for the follower.
; All 151 Gen 1 species are mapped to one of 7 existing sprite categories.
; Calls LoadFollowerSprite (HOME bank) which handles the ROM bank switch.
; INPUT: a = species (wPartyMon1Species, 1-based)
; RESULT: follower sprite tiles loaded to VRAM slot 2 ($8180/$8980)
; ============================================================
DEF FSPRITE_MONSTER  EQU 0
DEF FSPRITE_BIRD     EQU 1
DEF FSPRITE_SEEL     EQU 2
DEF FSPRITE_FAIRY    EQU 3
DEF FSPRITE_POKEBALL EQU 4
DEF FSPRITE_SNORLAX  EQU 5
DEF FSPRITE_FOSSIL   EQU 6
DEF FSPRITE_PIKACHU  EQU 7  ; dedicated Pikachu sprite from pokeyellow

FollowerSelectSprite::
	ld a, [wPartyMon1Species]    ; internal species ID (1-based, NOT Pokedex order)
	dec a                        ; 0-based index (ID $01→0, $BE→189)
	ld b, a                      ; b = original index (saved — add hl,de clobbers carry)
	srl a                        ; a = index/2 (byte offset)
	ld hl, FollowerSpriteTable
	ld d, 0
	ld e, a
	add hl, de                   ; hl = &table[index/2]  (carry clobbered here)
	ld a, [hl]                   ; packed byte: high nibble = even idx, low = odd
	bit 0, b                     ; check parity from saved original index
	jr z, .evenIndex             ; bit 0 = 0 → even → high nibble
	and $0F                      ; odd: low nibble
	jr .gotCategory
.evenIndex
	swap a
	and $0F                      ; even: high nibble
.gotCategory
	ld b, a
	add a
	add b                        ; a = category * 3
	ld hl, FollowerSpriteDataTable
	ld d, 0
	ld e, a
	add hl, de
	ld a, [hli]                  ; ROM bank
	ld e, [hl]
	inc hl
	ld d, [hl]
	ld h, d
	ld l, e
	jp LoadFollowerSprite

; Sprite data table: bank, addr_lo, addr_hi  (one entry per FSPRITE_* category)
FollowerSpriteDataTable:
	db BANK(MonsterSprite),  LOW(MonsterSprite),  HIGH(MonsterSprite)  ; MONSTER
	db BANK(BirdSprite),     LOW(BirdSprite),     HIGH(BirdSprite)     ; BIRD
	db BANK(SeelSprite),     LOW(SeelSprite),     HIGH(SeelSprite)     ; SEEL
	db BANK(FairySprite),    LOW(FairySprite),    HIGH(FairySprite)    ; FAIRY
	db BANK(PokeBallSprite), LOW(PokeBallSprite), HIGH(PokeBallSprite) ; POKEBALL
	db BANK(SnorlaxSprite),  LOW(SnorlaxSprite),  HIGH(SnorlaxSprite)  ; SNORLAX
	db BANK(FossilSprite),   LOW(FossilSprite),   HIGH(FossilSprite)   ; FOSSIL
	db BANK(PikachuFollowerSprite), LOW(PikachuFollowerSprite), HIGH(PikachuFollowerSprite) ; PIKACHU

; 95-byte nibble-packed table indexed by (internal species ID - 1).
; Each byte: high nibble = even index, low nibble = odd index.
; Gaps (const_skip IDs) default to MONSTER(0).
; M=0 B=1 S=2 F=3 P=4 N=5 O=6 K=7(Pikachu)
FollowerSpriteTable:
	db $00 ; $01,$02 RHYDON,KANGASKHAN
	db $03 ; $03,$04 NIDORAN_M,CLEFAIRY
	db $14 ; $05,$06 SPEAROW,VOLTORB
	db $02 ; $07,$08 NIDOKING,SLOWBRO
	db $00 ; $09,$0A IVYSAUR,EXEGGUTOR
	db $00 ; $0B,$0C LICKITUNG,EXEGGCUTE
	db $00 ; $0D,$0E GRIMER,GENGAR
	db $00 ; $0F,$10 NIDORAN_F,NIDOQUEEN
	db $00 ; $11,$12 CUBONE,RHYHORN
	db $20 ; $13,$14 LAPRAS,ARCANINE
	db $00 ; $15,$16 MEW,GYARADOS
	db $62 ; $17,$18 SHELLDER,TENTACOOL
	db $00 ; $19,$1A GASTLY,SCYTHER
	db $62 ; $1B,$1C STARYU,BLASTOISE
	db $00 ; $1D,$1E PINSIR,TANGELA
	db $00 ; $1F,$20 skip,skip
	db $00 ; $21,$22 GROWLITHE,ONIX
	db $11 ; $23,$24 FEAROW,PIDGEY
	db $20 ; $25,$26 SLOWPOKE,KADABRA
	db $03 ; $27,$28 GRAVELER,CHANSEY
	db $00 ; $29,$2A MACHOKE,MR_MIME
	db $00 ; $2B,$2C HITMONLEE,HITMONCHAN
	db $00 ; $2D,$2E ARBOK,PARASECT
	db $20 ; $2F,$30 PSYDUCK,DROWZEE
	db $00 ; $31,$32 GOLEM,skip
	db $00 ; $33,$34 MAGMAR,skip
	db $04 ; $35,$36 ELECTABUZZ,MAGNETON
	db $00 ; $37,$38 KOFFING,skip
	db $02 ; $39,$3A MANKEY,SEEL
	db $00 ; $3B,$3C DIGLETT,TAUROS
	db $00 ; $3D,$3E skip,skip
	db $01 ; $3F,$40 skip,FARFETCHD
	db $00 ; $41,$42 VENONAT,DRAGONITE
	db $00 ; $43,$44 skip,skip
	db $01 ; $45,$46 skip,DODUO
	db $20 ; $47,$48 POLIWAG,JYNX
	db $11 ; $49,$4A MOLTRES,ARTICUNO
	db $10 ; $4B,$4C ZAPDOS,DITTO
	db $02 ; $4D,$4E MEOWTH,KRABBY
	db $00 ; $4F,$50 skip,skip
	db $00 ; $51,$52 skip,VULPIX
	db $07 ; $53,$54 NINETALES,PIKACHU
	db $30 ; $55,$56 RAICHU,skip
	db $02 ; $57,$58 skip,DRATINI
	db $26 ; $59,$5A DRAGONAIR,KABUTO
	db $02 ; $5B,$5C KABUTOPS,HORSEA
	db $20 ; $5D,$5E SEADRA,skip
	db $00 ; $5F,$60 skip,SANDSHREW
	db $06 ; $61,$62 SANDSLASH,OMANYTE
	db $63 ; $63,$64 OMASTAR,JIGGLYPUFF
	db $30 ; $65,$66 WIGGLYTUFF,EEVEE
	db $00 ; $67,$68 FLAREON,JOLTEON
	db $20 ; $69,$6A VAPOREON,MACHOP
	db $00 ; $6B,$6C ZUBAT,EKANS
	db $02 ; $6D,$6E PARAS,POLIWHIRL
	db $20 ; $6F,$70 POLIWRATH,WEEDLE
	db $00 ; $71,$72 KAKUNA,BEEDRILL
	db $01 ; $73,$74 skip,DODRIO
	db $00 ; $75,$76 PRIMEAPE,DUGTRIO
	db $02 ; $77,$78 VENOMOTH,DEWGONG
	db $00 ; $79,$7A skip,skip
	db $00 ; $7B,$7C CATERPIE,METAPOD
	db $00 ; $7D,$7E BUTTERFREE,MACHAMP
	db $02 ; $7F,$80 skip,GOLDUCK
	db $00 ; $81,$82 HYPNO,GOLBAT
	db $05 ; $83,$84 MEWTWO,SNORLAX
	db $20 ; $85,$86 MAGIKARP,skip
	db $00 ; $87,$88 skip,MUK
	db $02 ; $89,$8A skip,KINGLER
	db $60 ; $8B,$8C CLOYSTER,skip
	db $43 ; $8D,$8E ELECTRODE,CLEFABLE
	db $00 ; $8F,$90 WEEZING,PERSIAN
	db $00 ; $91,$92 MAROWAK,skip
	db $00 ; $93,$94 HAUNTER,ABRA
	db $01 ; $95,$96 ALAKAZAM,PIDGEOTTO
	db $16 ; $97,$98 PIDGEOT,STARMIE
	db $00 ; $99,$9A BULBASAUR,VENUSAUR
	db $20 ; $9B,$9C TENTACRUEL,skip
	db $22 ; $9D,$9E GOLDEEN,SEAKING
	db $00 ; $9F,$A0 skip,skip
	db $00 ; $A1,$A2 skip,skip
	db $00 ; $A3,$A4 PONYTA,RAPIDASH
	db $00 ; $A5,$A6 RATTATA,RATICATE
	db $00 ; $A7,$A8 NIDORINO,NIDORINA
	db $00 ; $A9,$AA GEODUDE,PORYGON
	db $10 ; $AB,$AC AERODACTYL,skip
	db $40 ; $AD,$AE MAGNEMITE,skip
	db $00 ; $AF,$B0 skip,CHARMANDER
	db $20 ; $B1,$B2 SQUIRTLE,CHARMELEON
	db $20 ; $B3,$B4 WARTORTLE,CHARIZARD
	db $00 ; $B5,$B6 skip,FOSSIL_KABUTOPS
	db $00 ; $B7,$B8 FOSSIL_AERODACTYL,MON_GHOST
	db $00 ; $B9,$BA ODDISH,GLOOM
	db $00 ; $BB,$BC VILEPLUME,BELLSPROUT
	db $00 ; $BD,$BE WEEPINBELL,VICTREEBEL

; Initialise the dedicated follower state structs to a clean idle state.
; Leaves MAPY/MAPX/FACINGDIRECTION at their defaults (player-derived); callers
; overwrite those as needed.
FollowerInitState:
	; zero StateData1 for slot 15
	ld hl, wSprite15StateData1
	ld bc, 16
	xor a
	call FillMemory
	; zero StateData2 for slot 15 (not contiguous with StateData1)
	ld hl, wSprite15StateData2
	ld bc, 16
	xor a
	call FillMemory

	; IMAGEBASEOFFSET = 2: must be non-zero so _UpdateSprites enters .updateCurrentSprite
	; for slot 15, which is where our cp $f0 / BIT_FONT_LOADED dispatch lives.
	ld a, 2
	ld [wSprite15StateData2 + SPRITESTATEDATA2_IMAGEBASEOFFSET], a

	; PICTUREID: non-zero so PrepareOAMData renders this slot
	ld a, SPRITE_RED
	ld [wSprite15StateData1 + SPRITESTATEDATA1_PICTUREID], a

	; MOVEMENTSTATUS = idle
	ld a, FOLLOWER_STATUS_IDLE
	ld [wSprite15StateData1 + SPRITESTATEDATA1_MOVEMENTSTATUS], a

	; FACINGDIRECTION: face same direction as player initially
	ld a, [wSpritePlayerStateData1FacingDirection]
	ld [wSprite15StateData1 + SPRITESTATEDATA1_FACINGDIRECTION], a

	; IMAGEINDEX: hidden until first rendered with a valid facing
	ld a, $ff
	ld [wSprite15StateData1 + SPRITESTATEDATA1_IMAGEINDEX], a
	ret

; Place follower MAPY/MAPX 1 map tile behind the player based on facing.
FollowerPlaceBehindPlayer:
	ld a, [wSpritePlayerStateData2MapY]
	ld b, a
	ld a, [wSpritePlayerStateData2MapX]
	ld c, a

	ld a, [wSpritePlayerStateData1FacingDirection]
	cp SPRITE_FACING_UP
	jr z, .behindUp
	cp SPRITE_FACING_LEFT
	jr z, .behindLeft
	cp SPRITE_FACING_RIGHT
	jr z, .behindRight
	; SPRITE_FACING_DOWN (default): follower 1 tile north
	dec b
	jr .write
.behindUp
	inc b               ; player facing up -> follower 1 tile south
	jr .write
.behindLeft
	inc c               ; player facing left -> follower 1 tile east
	jr .write
.behindRight
	dec c               ; player facing right -> follower 1 tile west
.write
	ld hl, wSprite15StateData2 + SPRITESTATEDATA2_MAPY
	ld [hl], b
	inc hl
	ld [hl], c
	ret

; Compute the follower's on-screen pixel coordinates from its MAPY/MAPX
; relative to the player, so the first render is correctly positioned.
; Player is drawn at screen pixel (Y=$3c, X=$40) (tile 4,4 of the view).
FollowerInitPixelsFromMap:
	; Y pixels = player_Y_pixels + (followerMapY - playerMapY) * 16
	ld a, [wSprite15StateData2 + SPRITESTATEDATA2_MAPY]
	ld b, a
	ld a, [wSpritePlayerStateData2MapY]
	ld c, a
	ld a, b
	sub c                       ; a = signed tile delta Y (-1 / 0 / +1)
	call .timesSixteen
	ld b, a
	ld a, [wSpritePlayerStateData1YPixels]
	add b
	ld [wSprite15StateData1 + SPRITESTATEDATA1_YPIXELS], a

	; X pixels
	ld a, [wSprite15StateData2 + SPRITESTATEDATA2_MAPX]
	ld b, a
	ld a, [wSpritePlayerStateData2MapX]
	ld c, a
	ld a, b
	sub c
	call .timesSixteen
	ld b, a
	ld a, [wSpritePlayerStateData1XPixels]
	add b
	ld [wSprite15StateData1 + SPRITESTATEDATA1_XPIXELS], a
	ret

; Multiply a signed byte in a by 16 (two's-complement, low byte). Returns in a.
; Used only for small magnitudes (the spawn delta is always -1/0/+1), so the
; result always fits in one byte: -1 -> $F0 (-16), 0 -> 0, +1 -> $10 (+16).
.timesSixteen
	add a
	add a
	add a
	add a
	ret

; ============================================================
; FollowerPushCommand
; Encode the player's current direction and append it to the back of the FIFO
; command buffer. Called once at .noCollision in home/overworld.asm after
; wWalkCounter is set (player confirmed taking a step).
;
; Direction encoding matches pokeyellow's Func_fcc42: it reads wPlayerDirection
; (NOT wPlayerMovingDirection) and tests the PLAYER_DIR_BIT_* bits to produce
; UP=2 DOWN=1 LEFT=3 RIGHT=4. The append matches
; AppendPikachuFollowCommandToBuffer (inc size, store at buffer[size]).
; ============================================================
FollowerPushCommand::
	ld a, [wFollowerActive]
	and a
	ret z                       ; follower not active

	; encode wPlayerDirection -> command value (1-4); carry set = no direction
	call FollowerEncodeDirection
	ret c                       ; no direction pressed: nothing to push

	; guard against overflowing the 16-byte buffer (size index 0..15)
	ld b, a                     ; b = command to append
	ld a, [wFollowerCommandBufferSize]
	cp FOLLOWER_BUFFER_EMPTY
	jr z, .append               ; empty ($ff) -> first push lands at index 0
	cp 15
	ret nc                      ; size index already at last slot (full)
.append
	; AppendPikachuFollowCommandToBuffer: size++ (so $ff -> $00 first time),
	; then buffer[size] = command.
	ld hl, wFollowerCommandBufferSize
	inc [hl]
	ld e, [hl]
	ld d, 0
	ld hl, wFollowerCommandBuffer
	add hl, de
	ld [hl], b                  ; buffer[size] = command
	ret

; Encode wPlayerDirection (PLAYER_DIR bit-mask) into a command value 1-4.
; Mirrors pokeyellow's Func_fcc42. Returns:
;   a = 1 (DOWN) / 2 (UP) / 3 (LEFT) / 4 (RIGHT), carry clear
;   carry set if no direction bit is set.
FollowerEncodeDirection:
	ldh a, [hPlayerDirection]
	bit PLAYER_DIR_BIT_UP, a
	jr nz, .up
	bit PLAYER_DIR_BIT_DOWN, a
	jr nz, .down
	bit PLAYER_DIR_BIT_LEFT, a
	jr nz, .left
	bit PLAYER_DIR_BIT_RIGHT, a
	jr nz, .right
	scf                         ; no direction pressed
	ret
.up
	ld a, FOLLOWER_CMD_UP       ; clears carry
	ret
.down
	ld a, FOLLOWER_CMD_DOWN
	ret
.left
	ld a, FOLLOWER_CMD_LEFT
	ret
.right
	ld a, FOLLOWER_CMD_RIGHT
	ret

; ============================================================
; FollowerTick
; Called once per frame from OverworldLoop.
; If the follower is walking, advance its animation. If it is idle and a
; command is poppable, pop the oldest command and start a step. The step uses
; the fast (4-frame) timing when the buffer size index is still >= 2 after the
; pop check (matches AreThereAtLeastTwoStepsInPikachuFollowCommandBuffer).
; ============================================================
FollowerTick::
	ld a, [wFollowerActive]
	and a
	ret z                       ; follower not active

	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_MOVEMENTSTATUS]
	cp FOLLOWER_STATUS_WALKING
	jp z, FollowerAdvanceStep   ; mid-step: advance animation

	; idle: pop the oldest command from the FRONT of the buffer (Func_fcc92).
	; The pop treats size index 0 (one queued command) as empty, giving the
	; built-in one-step lag.
	call FollowerPopCommand
	ret c                       ; nothing poppable yet -> keep waiting
	push af                     ; a = popped command (1-4)

	; choose fast vs normal timing based on what REMAINS after the pop.
	call FollowerAtLeastTwoQueued
	ld b, FOLLOWER_WALK_FRAMES_NORMAL
	jr nc, .haveFrames          ; no carry = fewer than 2 -> normal speed
	ld b, FOLLOWER_WALK_FRAMES_FAST
.haveFrames
	pop af                      ; restore command
	jp FollowerStartStep        ; b = frame count for this step

; ============================================================
; FollowerPopCommand
; Pop the oldest command from the front of the FIFO buffer with a linear shift.
; Direct port of pokeyellow's Func_fcc92.
; OUTPUT: a = oldest command (1-4), carry clear. Carry set if there is nothing
;         to pop (empty sentinel, or only one command queued -> the lag slot).
; ============================================================
FollowerPopCommand:
	ld hl, wFollowerCommandBufferSize
	ld a, [hl]
	cp FOLLOWER_BUFFER_EMPTY
	jr z, .empty                ; $ff sentinel = empty
	and a
	jr z, .empty                ; size index 0 = single queued command (lag slot)
	dec [hl]                    ; size index--
	ld e, a                     ; e = old size index
	ld d, 0
	ld hl, wFollowerCommandBuffer
	add hl, de                  ; hl -> buffer[old size index]
	inc e                       ; loop count = old size index + 1
	ld a, FOLLOWER_BUFFER_EMPTY ; sentinel fill written into the vacated slot
.shift_loop
	ld d, [hl]                  ; d = current entry
	ld [hld], a                 ; write previous value (or sentinel) here
	ld a, d                     ; a = current entry (becomes "previous")
	dec e
	jr nz, .shift_loop          ; after loop a = buffer[0] = oldest command
	and a                       ; clear carry (success)
	ret
.empty
	scf
	ret

; ============================================================
; FollowerAtLeastTwoQueued
; Test whether the buffer size index is >= 2.
; Direct port of AreThereAtLeastTwoStepsInPikachuFollowCommandBuffer.
; OUTPUT: carry SET if size index >= 2 (enough backlog to run a fast step);
;         carry CLEAR otherwise (size index 0/1, or $ff empty).
; ============================================================
FollowerAtLeastTwoQueued:
	ld a, [wFollowerCommandBufferSize]
	cp FOLLOWER_BUFFER_EMPTY
	ret z                       ; empty ($ff): cp clears carry -> "fewer than 2"
	cp 2
	jr nc, .set_carry
	and a                       ; size index 0/1 -> clear carry
	ret
.set_carry
	scf
	ret

; ============================================================
; FollowerStartStep
; Begin one walking step in the given direction.
; INPUT: a = encoded command (FOLLOWER_CMD_DOWN/UP/LEFT/RIGHT, 1-4)
;        b = walk frame count for this step (normal 8 / fast 4)
; Sets MOVEMENTSTATUS = walking, configures step vectors (+-1) and facing,
; resets WALKANIMATIONCOUNTER to the requested frame count, and advances
; MAPY/MAPX one tile in the step direction (like AddPikachuStepVector).
; ============================================================
FollowerStartStep:
	push bc                     ; preserve frame count in b
	; decode command 1-4 -> facing (c), Y step (d), X step (e)
	ld d, 0
	ld e, 0
	cp FOLLOWER_CMD_UP
	jr z, .up
	cp FOLLOWER_CMD_LEFT
	jr z, .left
	cp FOLLOWER_CMD_RIGHT
	jr z, .right
	; FOLLOWER_CMD_DOWN (default)
	ld c, SPRITE_FACING_DOWN
	ld d, FOLLOWER_STEP_PX      ; +1 = south
	jr .apply
.up
	ld c, SPRITE_FACING_UP
	ld d, -FOLLOWER_STEP_PX     ; -1 = north
	jr .apply
.left
	ld c, SPRITE_FACING_LEFT
	ld e, -FOLLOWER_STEP_PX     ; -1 = west
	jr .apply
.right
	ld c, SPRITE_FACING_RIGHT
	ld e, FOLLOWER_STEP_PX      ; +1 = east
.apply
	; c = facing, d = Y step vector (+-1), e = X step vector (+-1)
	ld a, c
	ld [wSprite15StateData1 + SPRITESTATEDATA1_FACINGDIRECTION], a
	ld a, d
	ld [wSprite15StateData1 + SPRITESTATEDATA1_YSTEPVECTOR], a
	ld a, e
	ld [wSprite15StateData1 + SPRITESTATEDATA1_XSTEPVECTOR], a

	ld a, FOLLOWER_STATUS_WALKING
	ld [wSprite15StateData1 + SPRITESTATEDATA1_MOVEMENTSTATUS], a
	pop bc                      ; b = frame count
	ld a, b
	ld [wSprite15StateData2 + SPRITESTATEDATA2_WALKANIMATIONCOUNTER], a

	; advance MAPY/MAPX by one tile in the step direction now, at step start
	; (matches AddPikachuStepVector updating MAPY/MAPX up front).
	ld a, d
	and a
	jr z, .checkX
	ld hl, wSprite15StateData2 + SPRITESTATEDATA2_MAPY
	bit 7, a                    ; negative (north)?
	jr nz, .north
	inc [hl]                    ; south
	jr .checkX
.north
	dec [hl]
.checkX
	ld a, e
	and a
	jr z, .doneStep
	ld hl, wSprite15StateData2 + SPRITESTATEDATA2_MAPX
	bit 7, a                    ; negative (west)?
	jr nz, .west
	inc [hl]                    ; east
	jr .doneStep
.west
	dec [hl]
.doneStep
	; Advance pixels on the SAME frame the step starts, matching Yellow's
	; NormalPikachuFollow fall-through to asm_fc9c3 (AddPikachuStepVector...).
	; Without this, scroll compensation runs but no pixel advance → 2px drift.
	jp FollowerAdvanceStep

; ============================================================
; FollowerAdvanceStep
; Advance the walking animation by one frame: add (step vector * 2) to the
; pixel position and update the displayed frame. When the counter reaches 0
; the step is complete and the follower returns to idle.
;
; Pixel advance matches AddPikachuStepVectorToScreenPixelCoords:
;   YPIXELS += YSTEPVECTOR * 2   (step vector is +-1)
;   XPIXELS += XSTEPVECTOR * 2
; ============================================================
FollowerAdvanceStep:
	ld hl, wSprite15StateData2 + SPRITESTATEDATA2_WALKANIMATIONCOUNTER
	ld a, [hl]
	and a
	jr z, .stepDone             ; safety: counter already 0 (no advance)

	; YPIXELS += YSTEPVECTOR * 2 (scroll compensation is applied separately by
	; the scrollBackgroundAndSprites hook in overworld.asm)
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_YSTEPVECTOR]
	add a                       ; * 2
	ld b, a
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_YPIXELS]
	add b
	ld [wSprite15StateData1 + SPRITESTATEDATA1_YPIXELS], a
	; XPIXELS += XSTEPVECTOR * 2
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_XSTEPVECTOR]
	add a                       ; * 2
	ld b, a
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_XPIXELS]
	add b
	ld [wSprite15StateData1 + SPRITESTATEDATA1_XPIXELS], a

	; advance the walk animation frame counter.
	; Yellow uses d=2 (happy Pikachu) or d=5 (sad) in GetPikachuWalkingAnimationSpeed.
	; cp 4 matches original NPC speed (2 frames: stand/walk). cp 2 = Yellow happy (all 4 frames).
	ld hl, wSprite15StateData1 + SPRITESTATEDATA1_INTRAANIMFRAMECOUNTER
	ld a, [hl]
	inc a
	cp 4
	jr nz, .storeIntra
	xor a
	ld [hl], a
	inc hl                      ; ANIMFRAMECOUNTER
	ld a, [hl]
	inc a
	and $03
	ld [hl], a
	jr .decCounter
.storeIntra
	ld [hl], a
.decCounter
	; dec AFTER pixel advance + animation (Yellow asm_fc9c3: advance → dec → ret nz).
	; This means the step ends on the SAME frame as the last pixel advance, so
	; scroll compensation and advance cancel correctly — no accumulative drift.
	ld hl, wSprite15StateData2 + SPRITESTATEDATA2_WALKANIMATIONCOUNTER
	dec [hl]
	jr z, .stepDone             ; counter hit 0: process step completion below
	; still stepping: update IMAGEINDEX now so animation plays each frame
	call FollowerUpdateImage
	ret

.stepDone
	; walk finished: clear step vectors + animation counters, return to idle
	; Use hl+inc: YSTEPVECTOR(3) skip(4) XSTEPVECTOR(5) skip(6) INTRA(7) ANIM(8)
	ld hl, wSprite15StateData1 + SPRITESTATEDATA1_YSTEPVECTOR
	xor a
	ld [hli], a         ; YSTEPVECTOR = 0
	inc hl              ; skip YPIXELS
	ld [hli], a         ; XSTEPVECTOR = 0
	inc hl              ; skip XPIXELS
	ld [hli], a         ; INTRAANIMFRAMECOUNTER = 0
	ld [hl], a          ; ANIMFRAMECOUNTER = 0 (show idle frame)
	ld a, FOLLOWER_STATUS_IDLE
	ld [wSprite15StateData1 + SPRITESTATEDATA1_MOVEMENTSTATUS], a
	call FollowerComputeFacing  ; port of ComputePikachuFacingDirection
	; fallthrough to refresh image

; Build IMAGEINDEX from facing direction + animation frame.
; IMAGEINDEX layout (matches the engine): facing in bits 2-3 from
; FACINGDIRECTION ($0/$4/$8/$c), animation frame in bits 0-1.
FollowerUpdateImage:
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_FACINGDIRECTION]
	ld b, a
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_ANIMFRAMECOUNTER]
	and $03
	or b
	or $10  ; high nibble encodes tile base: (IMAGEBASEOFFSET-1)<<4 = (2-1)<<4 = $10 → tiles at $80C0
	ld [wSprite15StateData1 + SPRITESTATEDATA1_IMAGEINDEX], a
	ret

; ============================================================
; FollowerComputeFacing
; Port of ComputePikachuFacingDirection. Called at step end.
; Updates FACINGDIRECTION from the next queued command (if buffer non-empty),
; otherwise from the coordinate delta between follower and player.
; ============================================================
FollowerComputeFacing:
	; If buffer non-empty, decode top command to a facing direction.
	ld a, [wFollowerCommandBufferSize]
	cp FOLLOWER_BUFFER_EMPTY
	jr z, .fromCoords
	and a
	jr z, .fromCoords
	ld e, a
	ld d, 0
	ld hl, wFollowerCommandBuffer
	add hl, de
	ld a, [hl]          ; command 1-4
	and a
	jr z, .fromCoords
	dec a               ; 0-3
	and $3
	add a
	add a               ; * 4 = SPRITE_FACING (0/4/8/12)
	jr .setFacing

.fromCoords
	; Screen-relative MAPY/MAPX coordinates are unreliable for direction comparison
	; (player is always at a fixed center value). Just copy player facing — the
	; follower is always directly behind the player so same facing looks correct.
	ld a, [wSpritePlayerStateData1FacingDirection]
.setFacing
	ld [wSprite15StateData1 + SPRITESTATEDATA1_FACINGDIRECTION], a
	ret



; ============================================================
; SaveFollowerPosition
; Write the follower's active flag, species, MapY, MapX and facing to SRAM.
; Manages its own SRAM enable/disable. The 5 bytes live outside the main-data
; checksum (see ram/sram.asm), so this can be called independently.
; ============================================================
SaveFollowerPosition::
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a

	ld a, [wFollowerActive]
	ld [sFollowerActive], a
	and a
	jr z, .disable              ; not active: only the flag matters

	ld a, [wPartyMon1Species]
	ld [sFollowerSpecies], a
	ld a, [wSprite15StateData2 + SPRITESTATEDATA2_MAPY]
	ld [sFollowerMapY], a
	ld a, [wSprite15StateData2 + SPRITESTATEDATA2_MAPX]
	ld [sFollowerMapX], a
	ld a, [wSprite15StateData1 + SPRITESTATEDATA1_FACINGDIRECTION]
	ld [sFollowerFacingDirection], a
.disable
	xor a
	ld [rRAMG], a
	ret

; ============================================================
; LoadFollowerPosition
; Read the follower save state from SRAM and, if a follower was active, spawn
; it at the saved position via SpawnFollowerFromSave.
; ============================================================
LoadFollowerPosition::
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a

	ld a, [sFollowerActive]
	ld e, a                     ; e = active flag
	ld a, [sFollowerMapY]
	ld b, a
	ld a, [sFollowerMapX]
	ld c, a
	ld a, [sFollowerFacingDirection]
	ld d, a

	xor a
	ld [rRAMG], a

	ld a, e
	and a
	jr z, .notActive

	; only spawn if there is still a party mon and not on a stage map
	ld a, [wPartyCount]
	and a
	jr z, .notActive
	farcall IsRogueStageMap
	jr nz, .notActive           ; Z clear -> stage map -> skip

	; b = MapY, c = MapX, d = facing
	jp SpawnFollowerFromSave

.notActive
	xor a
	ld [wFollowerActive], a
	ret
