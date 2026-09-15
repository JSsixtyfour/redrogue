PlayBattleMusic::
	xor a
	ld [wAudioFadeOutControl], a
	ld [wLowHealthAlarm], a
	dec a ; SFX_STOP_ALL_MUSIC
	ld [wNewSoundID], a
	call PlaySound
	call DelayFrame
	ld c, BANK(Music_GymLeaderBattle)
	ld a, [wGymLeaderNo]
	and a
	jr z, .notGymLeaderBattle
	ld a, MUSIC_GYM_LEADER_BATTLE
	jr .playSong
.notGymLeaderBattle
	ld a, [wIsTrainerBattle]
	and a
	jr z, .wildBattle
	ld a, [wCurOpponent]
	cp OPP_RIVAL3
	jr z, .finalBattle
	cp OPP_LANCE
	jr z, .checkChampionsRoomLance
	cp OPP_PROF_OAK
	jr z, .checkChampionsRoomOak
	jr .normalTrainerBattle
.checkChampionsRoomLance
; Lance as an Elite Four member still gets the gym leader theme; Lance as an
; alternate Champion (Phase 7e, wRunChampion == LANCE) gets the same finale
; theme RIVAL3 does. wCurOpponent alone can't tell the two apart.
	ldh a, [hCurMap]
	cp CHAMPIONS_ROOM
	jr z, .finalBattle
	ld a, MUSIC_GYM_LEADER_BATTLE ; lance also plays gym leader theme
	jr .playSong
.checkChampionsRoomOak
; OPP_PROF_OAK only ever reaches battle as an alternate Champion (Phase 7e);
; give him the same finale theme for consistency with LANCE and RIVAL3.
	ldh a, [hCurMap]
	cp CHAMPIONS_ROOM
	jr z, .finalBattle
	jr .normalTrainerBattle
.normalTrainerBattle
	ld a, MUSIC_TRAINER_BATTLE
	jr .playSong
.finalBattle
	ld a, MUSIC_FINAL_BATTLE
	jr .playSong
.wildBattle
	ld a, MUSIC_WILD_BATTLE
.playSong
	jp PlayMusic
