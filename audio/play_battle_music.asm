; Battle music is picked in two steps: the battle is sorted into a BMUSIC_*
; category, then the category's ramp table names the song for this point in
; the run. Ramp rows are (first round, song), ascending; the last row whose
; round has been reached plays, so a category with one row plays one song all
; game. In Endless (wEndlessDepth != 0) the ramp is ignored and any of the
; category's rows can play. A one-row category never calls Random, so it costs
; no RNG draw.
	const_def
	const BMUSIC_WILD
	const BMUSIC_TRAINER
	const BMUSIC_GYM_LEADER
	const BMUSIC_FINAL
	const BMUSIC_STAGE_BOSS     ; procedural stage boss, Johto off
	const BMUSIC_JOHTO_TRAINER  ; gym trainer on one of the 8 Johto gym maps
	const BMUSIC_JOHTO_LEADER   ; Johto gym leader (not Janine), Will, Karen
	const BMUSIC_JOHTO_BOSS     ; procedural stage boss, EVENT_JOHTO_ACTIVATED set
	const BMUSIC_JOHTO_CHAMPION ; Lance as this run's Champion
DEF NUM_BMUSIC_CATEGORIES EQU const_value

PlayBattleMusic::
	call GetBattleMusicSong
	ld e, a
	; fall through

; e = song. The mid-battle evolution rebuild enters here with the song that
; was playing: re-running the routing would re-roll an Endless pick, and the
; cemetery boss flag it reads is one-shot (cleared by LoadEnemyMonData).
; Passed in e, not a: farcall clobbers a, b, c, h and l going in.
PlayBattleSong::
	xor a
	ld [wMusicFade], a
	ld [wLowHealthAlarm], a
	dec a ; SFX_STOP_ALL_MUSIC
	call PlaySound
	call DelayFrame
	ld a, e
	ld c, 0 ; PlayMusic ignores c: songs carry their own bank (Crystal audio)
	jp PlayMusic

; Out: a = song for the battle being set up. No frame waits, so the smoke
; harness can drive it directly.
GetBattleMusicSong::
	call GetBattleMusicCategory
	add a
	ld e, a
	ld d, 0
	ld hl, BattleMusicRamps
	add hl, de
	ld a, [hli]
	ld h, [hl]
	ld l, a
.gotRamp ; hl = this category's ramp (smoke tests swap in their own here)
	ld a, [wEndlessDepth]
	and a
	jr nz, .endless
	ld a, [wBattleCount]
	ld b, -1
.round
	inc b
	sub ROUND_BATTLES
	jr nc, .round
	; b = round. Row 0 always applies; take each later row while b reaches it.
	inc hl
	ld a, [hli]
	ld c, a
.ramp
	ld a, [hli]
	cp -1
	jr z, .done
	cp b
	jr z, .take
	jr nc, .done ; this row's round is still ahead
.take
	ld a, [hli]
	ld c, a
	jr .ramp
.endless
	push hl
	ld b, 0
.count
	ld a, [hli]
	inc hl
	inc b
	cp -1
	jr nz, .count
	dec b ; rows, without the terminator
	pop hl
	ld a, b
	dec a
	jr z, .pick ; one row: no roll
	call Random
.mod
	sub b
	jr nc, .mod
	add b
.pick
	add a
	inc a
	ld e, a
	ld d, 0
	add hl, de
	ld c, [hl]
.done
	ld a, c
	ret

; Out: a = BMUSIC_*
GetBattleMusicCategory:
	ld a, [wGymLeaderNo]
	and a
	jr nz, .gymLeader
	ld a, [wIsTrainerBattle]
	and a
	jr z, .wildBattle
	ld a, [wCurOpponent]
	cp OPP_RIVAL3
	jr z, .finalBattle
	cp OPP_FINAL_AI
	jr z, .finalBattle
	cp OPP_LANCE
	jr z, .checkChampionsRoomLance
	cp OPP_PROF_OAK
	jr z, .checkChampionsRoomOak
	cp OPP_WILL
	jr z, .johtoLeader
	cp OPP_KAREN
	jr z, .johtoLeader
	; Johto gym trainers by map: they are ordinary classes. Janine's Fuchsia
	; Gym is a Kanto map, so its trainers keep the Kanto theme.
	ldh a, [hCurMap]
	ld c, a
	ld hl, JohtoGymMaps
.johtoGymLoop
	ld a, [hli]
	cp -1
	jr z, .normalTrainerBattle
	cp c
	jr nz, .johtoGymLoop
	ld a, BMUSIC_JOHTO_TRAINER
	ret
.normalTrainerBattle
	ld a, BMUSIC_TRAINER
	ret
.gymLeader
	ld a, [wCurOpponent]
	; Janine leads a Kanto gym, so she keeps the Kanto leader theme.
	ASSERT CLAIR == FALKNER + 7 ; the eight Johto leaders, contiguous
	cp OPP_FALKNER
	jr c, .kantoLeader
	cp OPP_CLAIR + 1
	jr c, .johtoLeader
.kantoLeader
	ld a, BMUSIC_GYM_LEADER
	ret
.johtoLeader
	ld a, BMUSIC_JOHTO_LEADER
	ret
.checkChampionsRoomLance
; Lance as an Elite Four member keeps the gym leader theme; Lance as an
; alternate Champion (Phase 7e, wRunChampion == LANCE) gets the Johto Champion
; theme. wCurOpponent alone can't tell the two apart.
	ldh a, [hCurMap]
	cp CHAMPIONS_ROOM
	ld a, BMUSIC_JOHTO_CHAMPION
	ret z
	ld a, BMUSIC_GYM_LEADER
	ret
.checkChampionsRoomOak
; OPP_PROF_OAK only ever reaches battle as an alternate Champion (Phase 7e);
; give him the same finale theme as RIVAL3.
	ldh a, [hCurMap]
	cp CHAMPIONS_ROOM
	jr z, .finalBattle
	ld a, BMUSIC_TRAINER
	ret
.finalBattle
	ld a, BMUSIC_FINAL
	ret
.wildBattle
	call IsStageBossBattle
	ld a, BMUSIC_WILD
	ret nc
	CheckEvent EVENT_JOHTO_ACTIVATED
	ld a, BMUSIC_STAGE_BOSS
	ret z
	ld a, BMUSIC_JOHTO_BOSS
	ret

; Out: carry = this wild battle is a procedural stage's boss.
; The cemetery boss is started by its map script and flags itself
; (wProcCemBossBattle, still set here: LoadEnemyMonData clears it, and that
; runs after InitBattleVariables). The cave, forest and facility bosses are
; object slot 1 fought through TalkToTrainer, which sets BIT_TALKED_TO_TRAINER;
; the overworld loop clears that bit after every battle, so an ordinary wild
; encounter never sees it. The facility's fake-ball Voltorbs take the same
; path from slots 6-9, hence the slot test.
IsStageBossBattle:
	ld a, [wProcCemBossBattle]
	and a
	jr nz, .yes
	ld a, [wStatusFlags3]
	bit BIT_TALKED_TO_TRAINER, a
	ret z ; carry clear from the `and a`
	ldh a, [hActiveSpriteIndex]
	cp 1
	jr nz, .no
	ASSERT PROCEDURAL_FACILITY == PROCEDURAL_CAVE_1 + 2 && PROCEDURAL_FOREST == PROCEDURAL_CAVE_1 + 1
	ldh a, [hCurMap]
	cp PROCEDURAL_CAVE_1
	jr c, .no
	cp PROCEDURAL_FACILITY + 1
	ret ; carry = in range
.no
	and a
	ret
.yes
	scf
	ret

JohtoGymMaps:
	db VIOLET_GYM
	db AZALEA_GYM
	db GOLDENROD_GYM
	db ECRUTEAK_GYM
	db CIANWOOD_GYM
	db OLIVINE_GYM
	db MAHOGANY_GYM
	db BLACKTHORN_GYM
	db -1

BattleMusicRamps:
	table_width 2
	dw BattleMusicRampWild
	dw BattleMusicRampTrainer
	dw BattleMusicRampGymLeader
	dw BattleMusicRampFinal
	dw BattleMusicRampStageBoss
	dw BattleMusicRampJohtoTrainer
	dw BattleMusicRampJohtoLeader
	dw BattleMusicRampJohtoBoss
	dw BattleMusicRampJohtoChampion
	assert_table_length NUM_BMUSIC_CATEGORIES

; Each ramp: `db first round, song` rows in ascending round order, then -1.
; The first row must be round 0. To make a category change song as the run
; advances, add a row, e.g. `db 4, MUSIC_SOMETHING` plays from round 4 (battle
; 4 * ROUND_BATTLES) on. Every row is also in that category's Endless pool.
BattleMusicRampWild:
	db 0, MUSIC_WILD_BATTLE
	db -1
BattleMusicRampTrainer:
	db 0, MUSIC_TRAINER_BATTLE
	db -1
BattleMusicRampGymLeader:
	db 0, MUSIC_GYM_LEADER_BATTLE
	db -1
BattleMusicRampFinal:
	db 0, MUSIC_FINAL_BATTLE
	db -1
BattleMusicRampStageBoss:
	db 0, MUSIC_WILD_BATTLE
	db -1
BattleMusicRampJohtoTrainer:
	db 0, MUSIC_JOHTO_TRAINER_BATTLE
	db -1
BattleMusicRampJohtoLeader:
	db 0, MUSIC_JOHTO_GYM_BATTLE
	db -1
BattleMusicRampJohtoBoss:
	db 0, MUSIC_SUICUNE_BATTLE
	db -1
BattleMusicRampJohtoChampion:
	db 0, MUSIC_CHAMPION_BATTLE
	db -1
