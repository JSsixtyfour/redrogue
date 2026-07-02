; wSlotMachineFlags
	const_def 6
	const BIT_SLOTS_CAN_WIN               ; 6
	const BIT_SLOTS_CAN_WIN_WITH_7_OR_BAR ; 7

; wMiscFlags
	const_def
	const BIT_SEEN_BY_TRAINER      ; 0
	const BIT_BOULDER_DUST         ; 1
	const BIT_TURNING              ; 2
	const BIT_USING_GENERIC_PC     ; 3
	const BIT_NO_SPRITE_UPDATES    ; 4
	const BIT_NO_MENU_BUTTON_SOUND ; 5
	const BIT_TRIED_PUSH_BOULDER   ; 6
	const BIT_PUSHED_BOULDER       ; 7

; wAutoTextBoxDrawingControl
DEF BIT_NO_AUTO_TEXT_BOX EQU 0

; wTextPredefFlag
DEF BIT_TEXT_PREDEF EQU 0

; wFontLoaded
DEF BIT_FONT_LOADED EQU 0

; wCurrentMapScriptFlags
	const_def 5
	const BIT_CUR_MAP_LOADED_1 ; 5
	const BIT_CUR_MAP_LOADED_2 ; 6
	const BIT_CUR_MAP_USED_ELEVATOR ; 7

; wOptions
DEF TEXT_DELAY_MASK EQU %111
	const_def 6
	const BIT_BATTLE_SHIFT     ; 6
	const BIT_BATTLE_ANIMATION ; 7

DEF TEXT_DELAY_FAST   EQU %001 ; 1
DEF TEXT_DELAY_MEDIUM EQU %011 ; 3
DEF TEXT_DELAY_SLOW   EQU %101 ; 5

; wLetterPrintingDelayFlags
	const_def
	const BIT_FAST_TEXT_DELAY ; 0
	const BIT_TEXT_DELAY      ; 1

; wCurMapTileset
DEF BIT_NO_PREVIOUS_MAP EQU 7

; wCurrentBoxNum
DEF BIT_HAS_CHANGED_BOXES EQU 7
DEF BOX_NUM_MASK EQU %01111111

; wObtainedBadges, wBeatGymFlags
	const_def
	const BIT_BOULDERBADGE ; 0
	const BIT_CASCADEBADGE ; 1
	const BIT_THUNDERBADGE ; 2
	const BIT_RAINBOWBADGE ; 3
	const BIT_SOULBADGE    ; 4
	const BIT_MARSHBADGE   ; 5
	const BIT_VOLCANOBADGE ; 6
	const BIT_EARTHBADGE   ; 7
DEF NUM_BADGES EQU const_value

; wStatusFlags1
	const_def
	const BIT_STRENGTH_ACTIVE           ; 0
	const BIT_SURF_ALLOWED              ; 1
	const_skip                          ; 2 ; unused
	const BIT_GOT_OLD_ROD               ; 3
	const BIT_GOT_GOOD_ROD              ; 4
	const BIT_GOT_SUPER_ROD             ; 5
	const BIT_GAVE_SAFFRON_GUARDS_DRINK ; 6
	const BIT_UNUSED_CARD_KEY           ; 7

; wStatusFlags2
	const_def
	const BIT_WILD_ENCOUNTER_COOLDOWN ; 0
	const BIT_NO_AUDIO_FADE_OUT       ; 1

; wStatusFlags3
	const_def
	const BIT_INIT_TRADE_CENTER_FACING ; 0
	const_skip 2                       ; 1-2 ; unused
	const BIT_WARP_FROM_CUR_SCRIPT     ; 3
	const BIT_ON_DUNGEON_WARP          ; 4
	const BIT_NO_NPC_FACE_PLAYER       ; 5
	const BIT_TALKED_TO_TRAINER        ; 6
	const BIT_PRINT_END_BATTLE_TEXT    ; 7

; wStatusFlags4
	const_def
	const BIT_GOT_LAPRAS              ; 0
	const BIT_UNKNOWN_4_1             ; 1
	const BIT_USED_POKECENTER         ; 2
	const BIT_GOT_STARTER             ; 3
	const BIT_NO_BATTLES              ; 4
	const BIT_BATTLE_OVER_OR_BLACKOUT ; 5
	const BIT_LINK_CONNECTED          ; 6
	const BIT_INIT_SCRIPTED_MOVEMENT  ; 7

; wStatusFlags5
	const_def
	const BIT_SCRIPTED_NPC_MOVEMENT   ; 0
	const BIT_UNKNOWN_5_1             ; 1
	const BIT_UNKNOWN_5_2             ; 2
	const_skip                        ; 3 ; unused
	const BIT_UNKNOWN_5_4             ; 4
	const BIT_DISABLE_JOYPAD          ; 5
	const BIT_NO_TEXT_DELAY           ; 6
	const BIT_SCRIPTED_MOVEMENT_STATE ; 7

; wStatusFlags6
	const_def
	const BIT_GAME_TIMER_COUNTING ; 0
	const BIT_DEBUG_MODE          ; 1
	const BIT_FLY_OR_DUNGEON_WARP ; 2
	const BIT_FLY_WARP            ; 3
	const BIT_DUNGEON_WARP        ; 4
	const BIT_ALWAYS_ON_BIKE      ; 5
	const BIT_ESCAPE_WARP         ; 6

; wStatusFlags7
	const_def
	const BIT_TEST_BATTLE        ; 0
	const BIT_NO_MAP_MUSIC       ; 1
	const BIT_FORCED_WARP        ; 2
	const BIT_TRAINER_BATTLE     ; 3
	const BIT_USE_CUR_MAP_SCRIPT ; 4
	const_skip 2                 ; 5-6 ; unused
	const BIT_USED_FLY           ; 7

; wElite4Flags
	const_def
	const BIT_UNUSED_BEAT_ELITE_4 ; 0
	const BIT_STARTED_ELITE_4     ; 1

; wMovementFlags
	const_def
	const BIT_STANDING_ON_DOOR ; 0
	const BIT_EXITING_DOOR     ; 1
	const BIT_STANDING_ON_WARP ; 2
	const_skip 3               ; 3-5 ; unused
	const BIT_LEDGE_OR_FISHING ; 6
	const BIT_SPINNING         ; 7

; wRogueFlagsBitfield
	const_def
	const BIT_ROGUE_GYM_NEXT        ; 0 — set on route entry, cleared on badge receipt
	const BIT_ROGUE_FINAL_TRAINER   ; 1 — final trainer of tier (level/class bonus)
	const BIT_ROGUE_TRADE_ACTIVE    ; 2 — trade offer is live for this reward batch
	const BIT_WITCH_ACCEPTED        ; 3 — player accepted the active witch challenge

; wWitchChallenge values (1-NUM_WITCH_CHALLENGES; challenge and prize are
; rolled independently in PCWitchSetup, no fixed pairing)
DEF CHALLENGE_NO_REWARD_POKEMON     EQU 1  ; tier: low
DEF CHALLENGE_NO_RANDOM_ITEM        EQU 2  ; tier: low
DEF CHALLENGE_NO_MONEY              EQU 3  ; tier: low
DEF CHALLENGE_REDUCED_RARITY        EQU 4  ; tier: low
DEF CHALLENGE_INCREASED_LEVELS      EQU 5  ; tier: medium
DEF CHALLENGE_INCREASED_RARITY_FOES EQU 6  ; tier: medium
DEF CHALLENGE_PARTY_LIMIT           EQU 7  ; tier: medium
DEF CHALLENGE_SLOWED_POKEMON        EQU 8  ; tier: medium
DEF CHALLENGE_ALL_POISONED          EQU 9  ; tier: hard
DEF CHALLENGE_TURN_LIMIT            EQU 10 ; tier: hard
DEF CHALLENGE_LEGENDARY_BOSS        EQU 11 ; tier: hard
DEF CHALLENGE_RECOIL_ATTACKS        EQU 12 ; tier: hard
DEF CHALLENGE_GAMBLERS_PARADISE     EQU 13 ; tier: special
DEF NUM_WITCH_CHALLENGES            EQU 13

; wWitchPrize values
DEF PRIZE_RARITY_POKEMON EQU 1 ; a: bonus added to reward mon class roll
DEF PRIZE_RARITY_ITEM    EQU 2 ; b: bonus added to item tier roll
DEF PRIZE_MONEY          EQU 3 ; c: multiplies wAmountMoneyWon
DEF PRIZE_EXP_BOOST      EQU 4 ; d: extra BoostExp pass
DEF PRIZE_CRIT_BOOST     EQU 5 ; e: halves speed threshold in crit check
DEF PRIZE_ACC_BOOST      EQU 6 ; f: re-rolls once on a miss
DEF NUM_WITCH_PRIZES     EQU 6

; hFindPathFlags
	const_def
	const BIT_PATH_FOUND_Y ; 0
	const BIT_PATH_FOUND_X ; 1

; hNPCPlayerRelativePosFlags
	const_def
	const BIT_PLAYER_LOWER_Y ; 0
	const BIT_PLAYER_LOWER_X ; 1
    
    ; wBagPocketsFlags: bits 0-2 = pocket index (0-4), bits 3-4 = flags
	; Pocket indices:
	DEF POCKET_RECOVERY     EQU 0   ; potions/status/PP/drinks/revives/flute
	DEF POCKET_KEY_ITEMS    EQU 1   ; passive items (owned via sKeyItemsBitfield)
	DEF POCKET_TM_PACK      EQU 2   ; TMs/HMs (owned via sTMBitfield)
	DEF POCKET_STAT         EQU 3   ; vitamins, candy, stones
	DEF POCKET_VALUABLE     EQU 4   ; nuggets, pearls (sell-only)
	DEF NUM_POCKETS         EQU 5
	DEF POCKET_INDEX_MASK   EQU $07 ; bits 0-2 hold the pocket index
	; Legacy flag aliases kept for code that still checks specific bits 0-1
	DEF BIT_KEY_ITEMS_POCKET EQU 0  ; bit 0 set → pocket index has bit 0 set (= key items = 1)
	DEF BIT_TM_POCKET        EQU 1  ; bit 1 set → pocket index has bit 1 set (= TM = 2)
	; Higher flags (bits 3-4, moved up to make room for 3-bit pocket index)
	DEF BIT_PRINT_INFO_BOX   EQU 3  ; was bit 2; print pocket name info box
	DEF BIT_PC_WITHDRAWING   EQU 4  ; was bit 3; prevent pocket switching during PC withdraw
	DEF NUM_RECOVERY_ITEMS  EQU 21
	DEF NUM_STAT_ITEMS      EQU 12
	DEF NUM_VALUABLE_ITEMS  EQU 4

; sKeyItemsBitfield bit indices (must remain stable once save data exists)
DEF KEY_ITEM_BIT_LEFTOVERS   EQU 0
DEF KEY_ITEM_BIT_PP_TONIC    EQU 1
DEF KEY_ITEM_BIT_KO_DEFIANCE EQU 2
DEF KEY_ITEM_BIT_EXP_ALL     EQU 3
; 4 = Mom's Allowance (planned)
; 5 = First Aid Kit (planned)
; 6-31 = per-type attack boosters (planned, ~18 types)

; rLCDC
DEF LCDC_DEFAULT EQU LCDC_ON | LCDC_WIN_9C00 | LCDC_WIN_ON | LCDC_BLOCK21 | LCDC_BG_9800 | LCDC_OBJ_8 | LCDC_OBJ_ON | LCDC_BG_ON
