SilphCo1F_Script:

    CheckEvent EVENT_ENTER_ROOM
    jr nz, .normal

    SetEvent EVENT_ENTER_ROOM

    ResetEvent EVENT_GOT_ROGUE_POKEMON

    farcall rogue_pokemon_randomized_batch
    farcall Random_Item_Selection
    farcall RogueRefresh

    .normal
	call EnableAutoTextBoxDrawing
	CheckEvent EVENT_BEAT_SILPH_CO_GIOVANNI
	jr z, .noReceptionist
	CheckAndSetEvent EVENT_SILPH_CO_RECEPTIONIST_AT_DESK
	jr nz, .noReceptionist
	ld a, TOGGLE_SILPH_CO_1F_RECEPTIONIST
	ld [wToggleableObjectIndex], a
	predef ShowObject
.noReceptionist
	ld hl, SilphCo1FTrainerHeaders
	ld de, SilphCo1F_ScriptPointers
	ld a, [wSilphCo1FCurScript]
	call ExecuteCurMapScriptInTable
	ld [wSilphCo1FCurScript], a
	ret

SilphCo1F_ScriptPointers:
	def_script_pointers
	dw_const CheckFightingMapTrainers,              SCRIPT_SILPHCO1F_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_SILPHCO1F_START_BATTLE
	dw_const EndTrainerBattle,                      SCRIPT_SILPHCO1F_END_BATTLE

SilphCo1F_TextPointers:
	def_text_pointers
	dw_const SilphCo1FScientist1Text, TEXT_SILPHCO1F_SCIENTIST1
	dw_const SilphCo1FScientist2Text, TEXT_SILPHCO1F_SCIENTIST2
	dw_const SilphCo1FScientist3Text, TEXT_SILPHCO1F_SCIENTIST3
	dw_const SilphCo1FScientist4Text,       TEXT_SILPHCO1F_SCIENTIST4
	dw_const SilphCo1FScientist5Text,       TEXT_SILPHCO1F_SCIENTIST5
	dw_const SilphCo1FLinkReceptionistText, TEXT_SILPHCO1F_LINK_RECEPTIONIST
    dw_const RandomPickUpItemText,           TEXT_SILPHCO1F_RANDOM
    dw_const SilphCo1F_Rogue_Reward_Script_PokeballText_1, TEXT_SILPHCO1F_ROGUE_REWARD_POKEBALL_1
    dw_const SilphCo1F_Rogue_Reward_Script_PokeballText_2, TEXT_SILPHCO1F_ROGUE_REWARD_POKEBALL_2
    dw_const SilphCo1F_Rogue_Reward_Script_PokeballText_3, TEXT_SILPHCO1F_ROGUE_REWARD_POKEBALL_3
    dw_const Rogue_SilphCo1F_Reward_Text, TEXT_SILPHCO1F_REWARD_VENDOR_1
    EXPORT TEXT_SILPHCO1F_REWARD_VENDOR_1 ; used by engine/events/rogue_reward_menu.asm

SilphCo1FTrainerHeaders:
	def_trainers 1
SilphCo1FTrainerHeader0:
	trainer EVENT_BEAT_SILPH_CO_1F_TRAINER_0, 1, SilphCo1FScientist1BattleText, SilphCo1FScientist1EndBattleText, SilphCo1FScientist1AfterBattleText
SilphCo1FTrainerHeader1:
	trainer EVENT_BEAT_SILPH_CO_1F_TRAINER_1, 1, SilphCo1FScientist2BattleText, SilphCo1FScientist2EndBattleText, SilphCo1FScientist2AfterBattleText
SilphCo1FTrainerHeader2:
	trainer EVENT_BEAT_SILPH_CO_1F_TRAINER_2, 1, SilphCo1FScientist3BattleText, SilphCo1FScientist3EndBattleText, SilphCo1FScientist3AfterBattleText
SilphCo1FTrainerHeader3:
	trainer EVENT_BEAT_SILPH_CO_1F_TRAINER_3, 1, SilphCo1FScientist4BattleText, SilphCo1FScientist4EndBattleText, SilphCo1FScientist4AfterBattleText
SilphCo1FTrainerHeader4:
	trainer EVENT_BEAT_SILPH_CO_1F_TRAINER_4, 1, SilphCo1FScientist5BattleText, SilphCo1FScientist5EndBattleText, SilphCo1FScientist5AfterBattleText
	db -1 ; end

SilphCo1FScientist1Text:
	text_asm
	ld hl, SilphCo1FTrainerHeader0
	call TalkToTrainer
	jp TextScriptEnd

SilphCo1FScientist1BattleText:
	text_far _SilphCo1FScientist1BattleText
	text_end

SilphCo1FScientist1EndBattleText:
	text_far _SilphCo1FScientist1EndBattleText
	text_end

SilphCo1FScientist1AfterBattleText:
	text_far _SilphCo1FScientist1AfterBattleText
	text_end

SilphCo1FScientist2Text:
	text_asm
	ld hl, SilphCo1FTrainerHeader1
	call TalkToTrainer
	jp TextScriptEnd

SilphCo1FScientist2BattleText:
	text_far _SilphCo1FScientist1BattleText
	text_end

SilphCo1FScientist2EndBattleText:
	text_far _SilphCo1FScientist1EndBattleText
	text_end

SilphCo1FScientist2AfterBattleText:
	text_far _SilphCo1FScientist1AfterBattleText
	text_end

SilphCo1FScientist3Text:
	text_asm
	ld hl, SilphCo1FTrainerHeader2
	call TalkToTrainer
	jp TextScriptEnd

SilphCo1FScientist3BattleText:
	text_far _SilphCo1FScientist1BattleText
	text_end

SilphCo1FScientist3EndBattleText:
	text_far _SilphCo1FScientist1EndBattleText
	text_end

SilphCo1FScientist3AfterBattleText:
	text_far _SilphCo1FScientist1AfterBattleText
	text_end

SilphCo1FScientist4Text:
	text_asm
	ld hl, SilphCo1FTrainerHeader3
	call TalkToTrainer
	jp TextScriptEnd

SilphCo1FScientist4BattleText:
	text_far _SilphCo1FScientist1BattleText
	text_end

SilphCo1FScientist4EndBattleText:
	text_far _SilphCo1FScientist1EndBattleText
	text_end

SilphCo1FScientist4AfterBattleText:
	text_far _SilphCo1FScientist1AfterBattleText
	text_end

SilphCo1FScientist5Text:
	text_asm
	ld hl, SilphCo1FTrainerHeader4
	call TalkToTrainer
	jp TextScriptEnd

SilphCo1FScientist5BattleText:
	text_far _SilphCo1FScientist1BattleText
	text_end

SilphCo1FScientist5EndBattleText:
	text_far _SilphCo1FScientist1EndBattleText
	text_end

SilphCo1FScientist5AfterBattleText:
    text_asm
    farcall Delay3
    CheckEvent EVENT_GOT_ROGUE_POKEMON
    jr z, .GetMon

    ld hl, SilphCo1FGreedyText
    call PrintText
    jr .done

    .GetMon
    xor a
    ld a, TEXT_SILPHCO1F_REWARD_VENDOR_1
    ldh [hTextID], a
    call DisplayTextID
    call DisableWaitingAfterTextDisplay
    .done
    jp TextScriptEnd

SilphCo1FLinkReceptionistText:
	text_far _SilphCo1FLinkReceptionistText
	text_end

Rogue_SilphCo1F_Reward_Text:
script_rogue_reward

SilphCo1F_Rogue_Reward_Script_PokeballText_1:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_1
farcall Rogue_Reward_Script_PokeballText_1
jp TextScriptEnd

SilphCo1F_Rogue_Reward_Script_PokeballText_2:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_2
farcall Rogue_Reward_Script_PokeballText_2
jp TextScriptEnd

SilphCo1F_Rogue_Reward_Script_PokeballText_3:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_3
farcall Rogue_Reward_Script_PokeballText_3
jp TextScriptEnd

SilphCo1FGreedyText:
	text_far _GreedyText
	text_end
