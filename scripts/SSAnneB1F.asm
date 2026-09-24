; UNIQUE STAGE: SS Anne B1F has custom multi-room door/lock mechanics and a separate
; EVENT_SSANNE_ALL_TRAINERS_DEFEATED gate. Reward trigger handled via custom flow,
; not the standard ALL_TRAINERS_MASK pattern.
DEF SSANNE10_ALL_TRAINERS_MASK EQU (1 << (EVENT_BEAT_SS_ANNE_10_TRAINER_0 % 8)) \
	| (1 << (EVENT_BEAT_SS_ANNE_10_TRAINER_1 % 8)) \
	| (1 << (EVENT_BEAT_SS_ANNE_10_TRAINER_2 % 8)) \
	| (1 << (EVENT_BEAT_SS_ANNE_10_TRAINER_3 % 8)) \
	| (1 << (EVENT_BEAT_SS_ANNE_10_TRAINER_4 % 8))
ASSERT EVENT_BEAT_SS_ANNE_10_TRAINER_0 / 8 == EVENT_BEAT_SS_ANNE_10_TRAINER_4 / 8, \
	"SSAnneB1FRooms beat events must share one event byte"

SSAnneB1F_Script:
	; Reveal the rewards once all five SSAnneB1FRooms trainers are beaten
	; (checked on each return from the rooms). Latched by the event.
	CheckEvent EVENT_SSANNE_ALL_TRAINERS_DEFEATED
	jr nz, .entry
	ld a, [wEventFlags + (EVENT_BEAT_SS_ANNE_10_TRAINER_0 / 8)]
	and SSANNE10_ALL_TRAINERS_MASK
	cp SSANNE10_ALL_TRAINERS_MASK
	jr nz, .entry
	SetEvent EVENT_SSANNE_ALL_TRAINERS_DEFEATED
	farcall RogueShowStageRewards
	ld a, TOGGLE_SS_ANNE_B1F_CAPTAIN
	ld [wToggleableObjectIndex], a
	predef HideObject

.entry
	CheckEvent EVENT_ENTER_ROOM
	jr nz, .afterSetup
	SetEvent EVENT_ENTER_ROOM
	; WarpFound2 clears EVENT_ENTER_ROOM on EVERY warp, including coming back
	; out of the rooms. Only an arrival from outside the ship is a fresh stage;
	; re-running this on a room exit rerolled the rewards and re-hid them.
	ld a, [wWarpedFromWhichMap]
	cp SS_ANNE_B1F_ROOMS
	jr z, .afterSetup
	ld hl, wRogueFlagsBitfield
	set 0, [hl]                 ; gym is next after this route
	ResetEvent EVENT_GOT_ROGUE_POKEMON
	ResetEvent EVENT_ROGUE_POKEMON_OFFERED
	farcall rogue_pokemon_randomized_batch
	farcall Random_Item_Selection
	farcall RogueRefresh
	; Rewards stay hidden until the rooms are cleared (see above).
	ld a, TOGGLE_ROGUE_REWARD_POKEBALL_1
	call .hide
	ld a, TOGGLE_ROGUE_REWARD_POKEBALL_2
	call .hide
	ld a, TOGGLE_ROGUE_REWARD_POKEBALL_3
	call .hide
	ld a, TOGGLE_ROGUE_TRADE_NPC
	call .hide

.afterSetup
	; Offer the reward once, like a normal route's all-trainers offer.
	CheckEvent EVENT_SSANNE_ALL_TRAINERS_DEFEATED
	jr z, .afterRewardCheck
	CheckEvent EVENT_ROGUE_POKEMON_OFFERED
	jr nz, .afterRewardCheck
	; Wait while a scripted step owns input: coming back from the rooms lands
	; on a door tile, and PlayerStepOutFromDoor masks all but A/B until its
	; simulated step ends. Offering then left the reward cursor frozen.
	ldh a, [hJoyIgnore]
	and a
	jr nz, .afterRewardCheck
	SetEvent EVENT_ROGUE_POKEMON_OFFERED
	xor a
	ldh [hJoyHeld], a
	call Delay3
	ld a, TEXT_SSANNEB1F_REWARD_VENDOR_1
	ldh [hTextID], a
	call DisplayTextID
	call DisableWaitingAfterTextDisplay

.afterRewardCheck
	call EnableAutoTextBoxDrawing
	ld hl, SSAnneB1FTrainerHeaders
	ld de, SSAnneB1F_ScriptPointers
	ld a, [wSSAnneB1FCurScript]
	call ExecuteCurMapScriptInTable
	ld [wSSAnneB1FCurScript], a
	ret

.hide
	ld [wToggleableObjectIndex], a
	predef_jump HideObject

	RogueAutoWalkScripts SSAnneB1F, PAD_LEFT, CheckFightingMapTrainers, EVENT_AUTOWALKED_INTO_SS_ANNE_B1F, TEXT_SSANNEB1F_NO_TURNING_BACK, SCRIPT_SSANNEB1F_PLAYER_IS_MOVING, wSSAnneB1FCurScript

; The lobby door lands the player on warp 1, (27,5), at the corridor's east end.
; Column 26 is the only way back to that tile, so it is the "no turning back"
; strip. The arrival tile itself must NOT be in NoCoords (checked first).
SSAnneB1FEntranceCoords:
	dbmapcoord 27, 5
	db -1

SSAnneB1FNoCoords:
	dbmapcoord 26, 4
	dbmapcoord 26, 5
	db -1

; B1F's own objects are plain NPCs (its trainers live in SSAnneB1FRooms), but
; ExecuteCurMapScriptInTable stores hl as wTrainerHeaderPtr and the default
; script runs CheckFightingMapTrainers. Without a real, empty list here it
; walked WRAM as trainer headers and started phantom walk-up battles.
SSAnneB1FTrainerHeaders:
	db -1 ; end

SSAnneB1F_ScriptPointers:
	def_script_pointers
	dw_const SSAnneB1FDefaultScript,                SCRIPT_SSANNEB1F_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_SSANNEB1F_START_BATTLE
	dw_const EndTrainerBattle,                      SCRIPT_SSANNEB1F_END_BATTLE
	dw_const SSAnneB1FPlayerIsMovingScript,         SCRIPT_SSANNEB1F_PLAYER_IS_MOVING

SSAnneB1F_TextPointers:
	; The first 12 entries MUST be the objects' own texts in slot order:
	; DisplayTextID reroutes any id <= wNumSprites through that slot's declared
	; id, so a script-fired id in that range prints another object's text.
	def_text_pointers
	dw_const SSAnneB1FJrTrainerMText, TEXT_SSANNEB1F_JR_TRAINER_M3
	dw_const SSAnneB1FJrTrainerMText, TEXT_SSANNEB1F_JR_TRAINER_M4
	dw_const SSAnneB1FJrTrainerMText, TEXT_SSANNEB1F_JR_TRAINER_M5
	dw_const SSAnneB1FJrTrainerMText, TEXT_SSANNEB1F_JR_TRAINER_M6
	dw_const SSAnneB1FJrTrainerMText, TEXT_SSANNEB1F_JR_TRAINER_M7
	dw_const RandomPickUpItemText,     TEXT_SSANNEB1F_RANDOM
	dw_const SSAnneB1F_Rogue_Reward_Script_PokeballText_1, TEXT_SSANNEB1F_ROGUE_REWARD_POKEBALL_1
	dw_const SSAnneB1F_Rogue_Reward_Script_PokeballText_2, TEXT_SSANNEB1F_ROGUE_REWARD_POKEBALL_2
	dw_const SSAnneB1F_Rogue_Reward_Script_PokeballText_3, TEXT_SSANNEB1F_ROGUE_REWARD_POKEBALL_3
	dw_const SSAnneB1F_Rogue_Reward_Script_PokeballText_1, TEXT_SSANNEB1F_ROGUE_TRADE_NPC
	dw_const SSAnneB1FCaptainText,     TEXT_SSANNEB1F_CAPTAIN
	dw_const SSAnneB1FSailorText,      TEXT_SSANNEB1F_SAILOR
	; script-fired only, past wNumSprites:
	dw_const Rogue_SSAnneB1F_Reward_Text, TEXT_SSANNEB1F_REWARD_VENDOR_1
	EXPORT TEXT_SSANNEB1F_REWARD_VENDOR_1 ; used by engine/events/rogue_reward_menu.asm
	dw_const SSAnneB1FNoTurningBackText, TEXT_SSANNEB1F_NO_TURNING_BACK
	ASSERT TEXT_SSANNEB1F_REWARD_VENDOR_1 > SSANNEB1F_SAILOR ; SAILOR = last slot


SSAnneB1FCaptainText:
	text_far _SSAnneB1FCaptainText
	text_end

SSAnneB1FSailorText:
	; Once the rooms are cleared the sailor opens the reward menu until a
	; pokemon is taken; otherwise (and afterwards) his own line.
	text_asm
	CheckEvent EVENT_SSANNE_ALL_TRAINERS_DEFEATED
	jr z, .normal
	CheckEvent EVENT_GOT_ROGUE_POKEMON
	jr nz, .normal
	ld a, TEXT_SSANNEB1F_REWARD_VENDOR_1
	ldh [hTextID], a
	call DisplayTextID
	call DisableWaitingAfterTextDisplay
	jr .done
.normal
	ld hl, .SSAnneB1FSailorText
	call PrintText
.done
	jp TextScriptEnd

.SSAnneB1FSailorText
text_far _SSAnneB1FSailorText
text_end

Rogue_SSAnneB1F_Reward_Text:
script_rogue_reward

SSAnneB1F_Rogue_Reward_Script_PokeballText_1:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_1
farcall Rogue_Reward_Script_PokeballText_1
jp TextScriptEnd

SSAnneB1F_Rogue_Reward_Script_PokeballText_2:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_2
farcall Rogue_Reward_Script_PokeballText_2
jp TextScriptEnd

SSAnneB1F_Rogue_Reward_Script_PokeballText_3:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_3
farcall Rogue_Reward_Script_PokeballText_3
jp TextScriptEnd

SSAnneB1FNoTurningBackText:
	text_far _NoTurningBackText
	text_end

; Padding objects in slots 1-5 (never drawn, never reachable).
SSAnneB1FJrTrainerMText:
	text_far _SSAnneB1FCaptainText
	text_end
