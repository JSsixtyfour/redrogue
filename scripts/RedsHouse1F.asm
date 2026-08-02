; Dual-purpose room: Red's House 1F remains normally reachable during
; gameplay (Mom heals for free, as always). ONLY when entered as a bridge
; (wWarpedFromWhichMap == INDIGO_PLATEAU_LOBBY) does Mom instead dispatch a
; bridge gift (RedsHouseMomGiftList in bridge_gift_menu.asm); the setup block
; and PatchBridgeExit are likewise gated so normal play is untouched.
RedsHouse1F_Script:
	ld a, [wWarpedFromWhichMap]
	cp INDIGO_PLATEAU_LOBBY
	jr nz, .notBridge
	CheckEvent EVENT_ENTER_ROOM
	jr nz, .afterSetup
	SetEvent EVENT_ENTER_ROOM
	farcall rogue_gift_randomized_batch   ; giver resolved from current map
	ResetEvent EVENT_BRIDGE_RECEIVE_GIFT
	ResetEvent EVENT_BRIDGE_INTRO
	.afterSetup
	farcall PatchBridgeExit   ; route the exit to the next stage
	; wall off the stairs up to 2F during a bridge (stairs block $07 -> wall $05)
    ld hl, wCurrentMapScriptFlags
	bit BIT_CUR_MAP_LOADED_1, [hl]
	res BIT_CUR_MAP_LOADED_1, [hl]
	jr z, .notBridge
	ld a, $05
	ld [wNewTileBlockID], a
	lb bc, 0, 3               ; block col 3 / row 0 = the (7,1) stairs block
	predef ReplaceTileBlock
	.notBridge
	jp EnableAutoTextBoxDrawing

RedsHouse1F_TextPointers:
	def_text_pointers
	dw_const RedsHouse1FMomText, TEXT_REDSHOUSE1F_MOM
	dw_const RedsHouse1FTVText,  TEXT_REDSHOUSE1F_TV
	dw_const RedsHouse1F_Gift_Text, TEXT_REDSHOUSE1F_GIFT_1
	EXPORT TEXT_REDSHOUSE1F_GIFT_1 ; used by engine/events/rogue_reward_menu.asm BridgeGiftMenu

RedsHouse1FMomText:
	text_asm
	ld a, [wWarpedFromWhichMap]
	cp INDIGO_PLATEAU_LOBBY
	jr nz, .normal
; bridge visit: gift dispatch instead of the free heal
	CheckEvent EVENT_BRIDGE_RECEIVE_GIFT
	jr nz, .got_item
	CheckEvent EVENT_BRIDGE_INTRO
	jr nz, .skip_intro
	ld hl, .GiftIntroText
	call PrintText
	SetEvent EVENT_BRIDGE_INTRO
	.skip_intro
	ld a, TEXT_REDSHOUSE1F_GIFT_1
	ldh [hTextID], a
	call DisplayTextID
	call DisableWaitingAfterTextDisplay
	jr .done
.got_item
	ld hl, .LookingGreatText
	call PrintText
	jr .done
.normal
	ld a, [wStatusFlags4]
	bit BIT_GOT_STARTER, a
	jr nz, .heal
	ld hl, .WakeUpText
	call PrintText
	jr .done
.heal
	call RedsHouse1FMomHealScript
.done
	jp TextScriptEnd

.WakeUpText:
	text_far _RedsHouse1FMomWakeUpText
	text_end

.GiftIntroText:
	text_far _RedsHouse1FMomGiftIntroText
	text_end

.LookingGreatText:
	text_far _RedsHouse1FMomLookingGreatText
	text_end

RedsHouse1F_Gift_Text:
	script_bridge_gift

RedsHouse1FMomHealScript:
	ld hl, RedsHouse1FMomYouShouldRestText
	call PrintText
	call GBFadeOutToWhite
	call ReloadMapData
	predef HealParty
	ld a, MUSIC_PKMN_HEALED
	ld [wNewSoundID], a
	call PlaySound
.next
	ld a, [wChannelSoundIDs]
	cp MUSIC_PKMN_HEALED
	jr z, .next
	ld a, [wMapMusicSoundID]
	ld [wNewSoundID], a
	call PlaySound
	call GBFadeInFromWhite
	ld hl, RedsHouse1FMomLookingGreatText
	jp PrintText

RedsHouse1FMomYouShouldRestText:
	text_far _RedsHouse1FMomYouShouldRestText
	text_end
RedsHouse1FMomLookingGreatText:
	text_far _RedsHouse1FMomLookingGreatText
	text_end

RedsHouse1FTVText:
	text_asm
	ld a, [wSpritePlayerStateData1FacingDirection]
	cp SPRITE_FACING_UP
	ld hl, .WrongSideText
	jr nz, .got_text
	ld hl, .StandByMeMovieText
.got_text
	call PrintText
	jp TextScriptEnd

.StandByMeMovieText:
	text_far _RedsHouse1FTVStandByMeMovieText
	text_end

.WrongSideText:
	text_far _RedsHouse1FTVWrongSideText
	text_end
