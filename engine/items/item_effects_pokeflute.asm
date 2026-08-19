; Shin Red import Phase 5: relocated out of "bank3" (item_effects.asm), which
; has zero free bytes, into its own floating section. Reached only via the
; ItemUsePokeFlute stub left behind in item_effects.asm - see the comment
; there. ItemUseReloadOverworldData is bank3-local, so the one call to it
; below became a farcall.
ItemUsePokeFlute_Real::
	ldh a, [hIsInBattle]
	and a
	jr nz, .inBattle
; if not in battle
	farcall ItemUseReloadOverworldData
	ldh a, [hCurMap]
	cp ROUTE_12
	jr nz, .notRoute12
	CheckEvent EVENT_BEAT_ROUTE12_SNORLAX
	jr nz, .noSnorlaxToWakeUp
; if the player hasn't beaten Route 12 Snorlax
	ld hl, Route12SnorlaxFluteCoords
	call ArePlayerCoordsInArray
	jr nc, .noSnorlaxToWakeUp
	ld hl, PlayedFluteHadEffectText
	call PrintText
	SetEvent EVENT_FIGHT_ROUTE12_SNORLAX
	ret
.notRoute12
	cp ROUTE_16
	jr nz, .noSnorlaxToWakeUp
	CheckEvent EVENT_BEAT_ROUTE16_SNORLAX
	jr nz, .noSnorlaxToWakeUp
; if the player hasn't beaten Route 16 Snorlax
	ld hl, Route16SnorlaxFluteCoords
	call ArePlayerCoordsInArray
	jr nc, .noSnorlaxToWakeUp
	ld hl, PlayedFluteHadEffectText
	call PrintText
	SetEvent EVENT_FIGHT_ROUTE16_SNORLAX
	ret
.noSnorlaxToWakeUp
	ld hl, PlayedFluteNoEffectText
	jp PrintText
.inBattle
	xor a
	ld [wWereAnyMonsAsleep], a
	ld b, ~SLP_MASK
	ld hl, wPartyMon1Status
	call WakeUpEntireParty
	ldh a, [hIsInBattle]
	dec a ; is it a trainer battle?
	jr z, .skipWakingUpEnemyParty
; if it's a trainer battle
	ld hl, wEnemyMon1Status
	call WakeUpEntireParty
.skipWakingUpEnemyParty
	ld hl, wBattleMonStatus
	ld a, [hl]
	and b ; remove Sleep status
	ld [hl], a
	ld hl, wEnemyMonStatus
	ld a, [hl]
	; Shin Red import Phase 5: in a wild battle, WakeUpEntireParty is never
	; run on the enemy side above (there's no real roster, just this one
	; mon), so wWereAnyMonsAsleep never got set here even when the wild mon
	; itself was asleep - it still gets woken up below, but the flute wrongly
	; reports "no effect" for it.
	push af
	and SLP_MASK
	jr z, .wildMonWasAwake
	ldh a, [hIsInBattle]
	cp 1 ; wild battle?
	jr nz, .wildMonWasAwake
	ld a, 1
	ld [wWereAnyMonsAsleep], a
.wildMonWasAwake
	pop af
	and b ; remove Sleep status
	ld [hl], a
	call LoadScreenTilesFromBuffer2 ; restore saved screen
	ld a, [wWereAnyMonsAsleep]
	and a ; were any pokemon asleep before playing the flute?
	ld hl, PlayedFluteNoEffectText
	jp z, PrintText ; if no pokemon were asleep
; if some pokemon were asleep
	ld hl, PlayedFluteHadEffectText
	call PrintText
	ld a, [wLowHealthAlarm]
	and $80
	jr nz, .skipMusic
	call WaitForSoundToFinish ; wait for sound to end
	farcall Music_PokeFluteInBattle ; play in-battle pokeflute music
.musicWaitLoop ; wait for music to finish playing
	ld a, [wChannelSoundIDs + CHAN7]
	and a ; music off?
	jr nz, .musicWaitLoop
.skipMusic
	ld hl, FluteWokeUpText
	jp PrintText

; wakes up all party pokemon
; INPUT:
; hl must point to status of first pokemon in party (player's or enemy's)
; b must equal ~SLP
; [wWereAnyMonsAsleep] should be initialized to 0
; OUTPUT:
; [wWereAnyMonsAsleep]: set to 1 if any pokemon were asleep
WakeUpEntireParty:
	ld de, PARTYMON_STRUCT_LENGTH
	ld c, PARTY_LENGTH
.loop
	ld a, [hl]
	push af
	and SLP_MASK
	jr z, .notAsleep
	ld a, 1
	ld [wWereAnyMonsAsleep], a ; indicate that a pokemon had to be woken up
.notAsleep
	pop af
	and b ; remove Sleep status
	ld [hl], a
	add hl, de
	dec c
	jr nz, .loop
	ret

Route12SnorlaxFluteCoords:
	dbmapcoord  9, 62 ; one space West of Snorlax
	dbmapcoord 10, 61 ; one space North of Snorlax
	dbmapcoord 10, 63 ; one space South of Snorlax
	dbmapcoord 11, 62 ; one space East of Snorlax
	db -1 ; end

Route16SnorlaxFluteCoords:
	dbmapcoord 27, 10 ; one space East of Snorlax
	dbmapcoord 25, 10 ; one space West of Snorlax
	db -1 ; end

PlayedFluteNoEffectText:
	text_far _PlayedFluteNoEffectText
	text_end

FluteWokeUpText:
	text_far _FluteWokeUpText
	text_end

PlayedFluteHadEffectText:
	text_far _PlayedFluteHadEffectText
	text_promptbutton
	text_asm
	ldh a, [hIsInBattle]
	and a
	jr nz, .done
; play out-of-battle pokeflute music
	ld a, SFX_STOP_ALL_MUSIC
	call PlaySound
	ld a, SFX_POKEFLUTE
	ld c, BANK(SFX_Pokeflute)
	call PlayMusic
.musicWaitLoop ; wait for music to finish playing
	ld a, [wChannelSoundIDs + CHAN3]
	cp SFX_POKEFLUTE
	jr z, .musicWaitLoop
	call PlayDefaultMusic ; start playing normal music again
.done
	jp TextScriptEnd ; end text
