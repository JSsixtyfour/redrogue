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

DEF TEXT_DELAY_INSTANT EQU %000 ; 0 (Shin Red import Phase 8; see extra_options.asm)
DEF TEXT_DELAY_FAST    EQU %001 ; 1
DEF TEXT_DELAY_MEDIUM  EQU %011 ; 3
DEF TEXT_DELAY_SLOW    EQU %101 ; 5

; wOptions2 bits 0-2: enemy level difficulty (LEVELS row, extra options menu)
DEF DIFFICULTY_MASK EQU %00000111
	const_def
	const DIFFICULTY_NORMAL     ; 0 - must stay 0; InitOptions' xor a defaults here
	const DIFFICULTY_EASY       ; 1
	const DIFFICULTY_VERY_EASY  ; 2
	const DIFFICULTY_HARD       ; 3
	const DIFFICULTY_VERY_HARD  ; 4

; wOptions2 persistent CGB options. Both default on in InitOptions_.
DEF BIT_ENHANCED_COLORS EQU 6
DEF BIT_60_FPS         EQU 7

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
	const BIT_DEBUG2_MODE         ; 7 - Debug 2 new game (Indigo lobby spawn, Porygon rival, battle-count prompt)

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
	const BIT_VICTORY_ROAD_CLEARED ; 2 - set for the rest of the run once the Victory Road Rival is beaten; gates the final-sequence Lobby doors and the permanent Indigo Plateau lobby music switch

; wMovementFlags
	const_def
	const BIT_STANDING_ON_DOOR ; 0
	const BIT_EXITING_DOOR     ; 1
	const BIT_STANDING_ON_WARP ; 2
	const BIT_RUNNING          ; 3 ; current step uses running speed/graphics
	const_skip 2               ; 4-5 ; unused
	const BIT_LEDGE_OR_FISHING ; 6
	const BIT_SPINNING         ; 7

; wRogueFlagsBitfield
	const_def
	const BIT_ROGUE_GYM_NEXT        ; 0 — set on route entry, cleared on badge receipt
	const BIT_ROGUE_FINAL_TRAINER   ; 1 — final trainer of tier (level/class bonus)
	const BIT_ROGUE_TRADE_ACTIVE    ; 2 — trade offer is live for this reward batch
	const BIT_WITCH_ACCEPTED        ; 3 — player accepted the active witch challenge
	const_skip 2                    ; 4-5 — mini-boss offered type (MINIBOSS_TYPE_MASK/SHIFT)
	const BIT_MINIBOSS_DOOR         ; 6 — which lobby door holds the mini-boss (0 = door 1, 1 = door 2)
	const BIT_MINIBOSS_ACTIVE       ; 7 — a mini-boss is active on the stage being entered

; wRogueFlagsBitfield bits 4-5 encode the offered mini-boss type (see MINIBOSS_* below).
; Read/written as a 2-bit field: (flags & MINIBOSS_TYPE_MASK) >> MINIBOSS_TYPE_SHIFT.
DEF MINIBOSS_TYPE_SHIFT EQU 4
DEF MINIBOSS_TYPE_MASK  EQU %00110000

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

; Gambler's Paradise fields fully-evolved mons with high-level movesets
; (Fissure/Horn Drill/etc.). PCWitchSetup rerolls it if wBattleCount is below
; this, so it only appears once the run's levels/species make sense. round =
; wBattleCount/10; 40 = round 5 start, whose trainers roll levels 28-34
; (min 0x1C + range 6) - i.e. the ~level 30 bracket. Tune freely.
DEF GAMBLERS_PARADISE_MIN_BATTLES   EQU 40

; wWitchPrize values
DEF PRIZE_RARITY_POKEMON EQU 1 ; a: bonus added to reward mon class roll
DEF PRIZE_RARITY_ITEM    EQU 2 ; b: bonus added to item tier roll
DEF PRIZE_MONEY          EQU 3 ; c: multiplies wAmountMoneyWon
DEF PRIZE_EXP_BOOST      EQU 4 ; d: extra BoostExp pass
DEF PRIZE_CRIT_BOOST     EQU 5 ; e: +25% to the player's crit threshold
DEF PRIZE_ACC_BOOST      EQU 6 ; f: +10 percentage points to the player's move accuracy, capped at 255
DEF NUM_WITCH_PRIZES     EQU 6

; ============================================================
; Mini-boss framework (see K:\...\Red Rogue Files\MINIBOSS_FRAMEWORK.md)
; ============================================================
; Offered mini-boss type, stored in wRogueFlagsBitfield bits 4-5 (0-3).
DEF MINIBOSS_NONE     EQU 0
DEF MINIBOSS_RIVAL    EQU 1
DEF MINIBOSS_GIOVANNI EQU 2
DEF MINIBOSS_KARATE   EQU 3   ; future: own FightingDojo stage (PLACE_OWN_STAGE)
DEF NUM_MINIBOSS_TYPES EQU 3  ; number of *real* bosses (excludes NONE), = highest type id

; Registry placement modes
DEF PLACE_REPLACE_5TH EQU 0   ; swap the route's 5th trainer in place
DEF PLACE_OWN_STAGE   EQU 1   ; boss IS a dedicated stage (routed to via its own map)

; Registry team-selection modes
DEF TEAM_STARTER_BASED EQU 0  ; wTrainerNo from the player's starter (Rival)
DEF TEAM_RANDOM_3_SET  EQU 1  ; 1-of-3 teams per tier chosen at random (Giovanni, Karate)

; Party-data marker: fills the remaining team slots with rarer-random mons.
; Distinct from any real species id and from RIVAL_STARTER_PLACEHOLDER ($1F).
DEF MINIBOSS_RANDOM_FILL EQU $FE

; Chance tuning (out of 256). Base 25% ~= 64; +25% per non-mini-boss route.
DEF MINIBOSS_BASE_CHANCE EQU 64   ; ~25% at wRoutesSinceSpecial = 0
DEF MINIBOSS_STEP        EQU 64    ; +~25% per non-mini-boss route (guaranteed by the 4th)
DEF MINIBOSS_MIN_PER_RUN EQU 2    ; forced-roll floor: at least this many per run
DEF MINIBOSS_FIRST_BATTLECOUNT EQU 10 ; not eligible until wBattleCount >= this (skips route 1)
DEF MINIBOSS_TOTAL_ROUTES EQU 8   ; ~routes per run (one before each gym); used by the >=2 guarantee

; --- Wild Area door integration ---
; Rollable wild-area types (Facility is shelved, never rolled).
DEF WILD_AREA_CAVE      EQU 0
DEF WILD_AREA_FOREST    EQU 1
DEF WILD_AREA_CEMETERY  EQU 2
DEF NUM_WILD_AREA_TYPES EQU 3
DEF WILD_AREA_MIN_PER_RUN EQU 2          ; >=2 wild areas guaranteed per run
; Not eligible until wBattleCount >= this (skips route 1), same as miniboss.
DEF WILD_AREA_FIRST_BATTLECOUNT EQU 10

; wWildAreaState bit layout:
;   bits 0-2 = "offered this cycle" mask (bit WILD_AREA_CAVE/FOREST/CEMETERY)
;   bits 3-4 = saturating count of wild areas offered this run (0-3)
DEF WILD_AREA_MASK        EQU %00000111
DEF WILD_AREA_COUNT_SHIFT EQU 3
DEF WILD_AREA_COUNT_MASK  EQU %00011000

; --- Bridge System (twice-per-run gift-room interludes) ---
; Bridges sit ON TOP of the door randomization: when one fires, BOTH lobby doors
; become two different bridge rooms; entering either gives a gift, then the room's
; exit routes straight to the pre-decided next route/gym (no lobby return / choice).
; They do NOT consume a route/gym/special slot. See custom_functions/bridge_selection.asm.
DEF BRIDGE_PER_RUN           EQU 2   ; target bridges per run (also the hard cap)
DEF BRIDGE_FIRST_BATTLECOUNT EQU 10  ; not eligible until wBattleCount >= this (skips route 1)
DEF BRIDGE_CHANCE_RANGE      EQU 6   ; ~1-in-N per eligible visit before the guarantee kicks in
; wBridgeState bit layout: bits 0-5 = offered-this-run mask for room indices 8-13;
; bits 6-7 = saturating bridge count (0-3). (Rooms 0-7 live in wBridgeOfferedLo.)
DEF BRIDGE_HI_ROOM_MASK   EQU %00111111
DEF BRIDGE_COUNT_SHIFT    EQU 6
DEF BRIDGE_COUNT_MASK     EQU %11000000

; Reward-rarity bonuses while a mini-boss is active (wRogueFlagsBitfield bit 7).
; Stack ADDITIVELY on top of any witch-prize rarity bonus (both can be active
; at once) - same magnitude as the witch prize bump, so a mini-boss during a
; rarity-boosting witch challenge gives very high rarity.
DEF MINIBOSS_POKEMON_RARITY_BONUS EQU 51
DEF MINIBOSS_ITEM_RARITY_BONUS    EQU 51

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
	; Reuses the same PrintBagInfoText cursor-move hook the TM pack's move-name
	; box uses, to draw the room PC's furniture/decoration descriptions.
	DEF BIT_ROOM_DESC_BOX    EQU 5  ; room PC option list open; see room_pc.asm
	DEF NUM_RECOVERY_ITEMS  EQU 21
	DEF NUM_STAT_ITEMS      EQU 14
	DEF NUM_VALUABLE_ITEMS  EQU 4

; sKeyItemsBitfield paired own+active bits (must remain stable once save data exists)
; Each item uses two consecutive bits: even = owned, odd = active (in bag).
DEF KEY_ITEM_BIT_LEFTOVERS_OWNED    EQU 0
DEF KEY_ITEM_BIT_LEFTOVERS_ACTIVE   EQU 1
DEF KEY_ITEM_BIT_PP_TONIC_OWNED     EQU 2
DEF KEY_ITEM_BIT_PP_TONIC_ACTIVE    EQU 3
DEF KEY_ITEM_BIT_KO_DEFIANCE_OWNED  EQU 4
DEF KEY_ITEM_BIT_KO_DEFIANCE_ACTIVE EQU 5
DEF KEY_ITEM_BIT_EXP_ALL_OWNED      EQU 6
DEF KEY_ITEM_BIT_EXP_ALL_ACTIVE     EQU 7
DEF KEY_ITEM_BIT_SHINY_CHARM_OWNED      EQU 8
DEF KEY_ITEM_BIT_SHINY_CHARM_ACTIVE     EQU 9
DEF KEY_ITEM_BIT_AMULET_COIN_OWNED      EQU 10
DEF KEY_ITEM_BIT_AMULET_COIN_ACTIVE     EQU 11
DEF KEY_ITEM_BIT_TURN_REWIND_OWNED      EQU 12
DEF KEY_ITEM_BIT_TURN_REWIND_ACTIVE     EQU 13
DEF KEY_ITEM_BIT_RARE_SCOPE_OWNED       EQU 14
DEF KEY_ITEM_BIT_RARE_SCOPE_ACTIVE      EQU 15
DEF KEY_ITEM_BIT_RARE_LENS_OWNED        EQU 16
DEF KEY_ITEM_BIT_RARE_LENS_ACTIVE       EQU 17
DEF KEY_ITEM_BIT_DV_BOOSTER_OWNED       EQU 18
DEF KEY_ITEM_BIT_DV_BOOSTER_ACTIVE      EQU 19
DEF KEY_ITEM_BIT_STAT_BOOSTER_OWNED     EQU 20
DEF KEY_ITEM_BIT_STAT_BOOSTER_ACTIVE    EQU 21
DEF KEY_ITEM_BIT_DOOR_DICE_OWNED        EQU 22
DEF KEY_ITEM_BIT_DOOR_DICE_ACTIVE       EQU 23
DEF KEY_ITEM_BIT_MON_DICE_OWNED         EQU 24
DEF KEY_ITEM_BIT_MON_DICE_ACTIVE        EQU 25
DEF KEY_ITEM_BIT_ITEM_DICE_OWNED        EQU 26
DEF KEY_ITEM_BIT_ITEM_DICE_ACTIVE       EQU 27
DEF KEY_ITEM_BIT_ELEMENT_PRISM_OWNED    EQU 28
DEF KEY_ITEM_BIT_ELEMENT_PRISM_ACTIVE   EQU 29
; All 15 items × 2 bits = 30 bits = 4 bytes (byte 0-3 of sKeyItemsBitfield).
; Active bit is always own_bit + 1 (by construction — callers may use inc c).
DEF KEY_ITEM_MAX_ACTIVE EQU 3   ; max items in bag at once

; rLCDC
DEF LCDC_DEFAULT EQU LCDC_ON | LCDC_WIN_9C00 | LCDC_WIN_ON | LCDC_BLOCK21 | LCDC_BG_9800 | LCDC_OBJ_8 | LCDC_OBJ_ON | LCDC_BG_ON
