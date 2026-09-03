_GreedyText::
    text "Better not get"
	line "greedy..."
	done

_RogueTradeOfferText::
	text "Your @"
	text_ram wNameBuffer
	text "@"
	line "for a @"
	text_ram wroguenpctradename
	text "?@"
	done

_PickPokeBallText::
	text "You want"
	line "@"
	text_ram wNameBuffer
	text "?@"
	text_end

_NoTurningBackText::
	text "There's no"
	line "turning back!"
	done

_PartyHPRecoveredText::
	text "Party HP"
	line "partly recovered!"
	prompt

_PartyPPRecoveredText::
	text "Party PP"
	line "partly recovered!"
	prompt

_PartyHPAndPPRecoveredText::
	text "Party HP/PP"
	line "partly recovered!"
	prompt

_LeftoversText::
	text "Your party"
	line "was healed!"
	prompt

_LeftoversDescriptionText::
	text "Heals your"
	line "team a bit"
	cont "after each"
	cont "battle!"
	done

_PPTonicText::
	text "Your party's"
	line "PP was"
	cont "restored!"
	prompt

; Shared by CHALLENGE_RECOIL_ATTACKS, _RECOIL_PHYSICAL and _RECOIL_SPECIAL.
; <USER>, not <TARGET>: this damage lands on the PLAYER'S OWN mon, and
; PlaceMoveTargetsName (home/text.asm) is hWhoseTurn XOR 1 - at this seam
; hWhoseTurn is always 0 (ExecutePlayerMove sets it and nothing after restores
; it before the hook), so <TARGET> printed "Enemy <foe> was hit by recoil!"
; while the player's own mon lost the HP. Pre-existing bug, fixed 2026-09-02.
_RecoilChallengeText::
	text "The bargain burns!"
	line "<USER> was hit"
	cont "by recoil!"
	done

_SameMovePenaltyText::
	text "The bargain hates"
	line "repetition! <USER>"
	cont "was hurt!"
	done

_TurnLimitDrainText::
	text "Time's running"
	line "out! <TARGET> lost"
	cont "some HP!"
	done

_PPTonicDescriptionText::
	text "Restores PP"
	line "slightly after"
	cont "each battle."
	done

_ExpAllDescriptionText::
	text "Shares EXP"
	line "with the whole"
	cont "party after"
	cont "each battle."
	done

_KODefianceDescriptionText::
	text "Revives your"
	line "last mon if"
	cont "it would"
	cont "faint!"
	done

_KODefianceActivatedText::
	text "KO DEFIANCE"
	line "activated!"
	done

_ShinyCharmDescriptionText::
	text "Ups the odds"
	line "of finding"
	cont "shiny Pokémon."
	done

_AmuletCoinDescriptionText::
	text "Increases"
	line "money earned"
	cont "from battles."
	done

_TurnRewindDescriptionText::
	text "Rewinds to"
	line "the prior turn"
	cont "in battle."
	done

; Battle menu handler (engine/battle/core.asm HandleTurnRewindMenuSelection).
; Covers both refusal cases (no snapshot yet, switched since the snapshot).
_TurnRewindRefuseText::
	text "Can't rewind"
	line "right now!"
	done

_RareScopeDescriptionText::
	text "Increases the"
	line "rarity of wild"
	cont "Pokémon."
	done

_RareLensDescriptionText::
	text "Increases the"
	line "rarity of"
	cont "items found."
	done

_DVBoosterDescriptionText::
	text "Increases DVs"
	line "of caught"
	cont "Pokémon."
	done

_StatBoosterDescriptionText::
	text "Increases stat"
	line "experience"
	cont "gained."
	done

_DoorDiceDescriptionText::
	text "Lets you"
	line "reroll lobby"
	cont "doors."
	done

_MonDiceDescriptionText::
	text "Lets you"
	line "reroll a wild"
	cont "Pokémon."
	done

_ItemDiceDescriptionText::
	text "Lets you"
	line "reroll a"
	cont "found item."
	done

_ElementPrismDescriptionText::
	text "Boosts one"
	line "type's damage"
	cont "and odds."
	done

; ELEMENT PRISM cartridge system (custom_functions/element_prism.asm).
_ElementPrismSetText::
	text "CARTRIDGE"
	line "installed!"
	done

; text_ram reads the equipped type's name out of wStringBuffer.
_ElementPrismStatusText::
	text "PRISM holds"
	line "the "
	text_ram wStringBuffer
	text " CARTRIDGE."
	done

_PrismNoCartridgesText::
	text "No CARTRIDGE"
	line "installed."
	done

; One-time grant messages (custom_functions/element_prism.asm), gated on
; persistent per-grantor events - shown once ever, never again, even across
; runs. text_ram reads the granted type's name out of wStringBuffer.
_PrismFirstGrantText::
	text "Take this"
	line "PRISM and a "
	text_ram wStringBuffer
	text " CARTRIDGE!"
	done

_PrismCartridgeGrantText::
	text "Received a "
	text_ram wStringBuffer
	text " CARTRIDGE!"
	done

_PrismChampionGrantText::
	text "Received the"
	line "NORMAL, FLYING"
	cont "and BUG"
	cont "CARTRIDGES!"
	done

_PrismCartridgeReceivedText::
	text "Received a"
	line "CARTRIDGE!"
	done

; Dice items (custom_functions §3f-3h, KEY_ITEM_EFFECTS_PLAN_PC.md). One
; shared out-of-charges text; distinct refuse/success texts per item, since
; each has its own location/state gate.
_DiceOutOfChargesText::
	text "No rerolls"
	line "left!"
	done

_DoorDiceRefuseText::
	text "Can only be"
	line "used in the"
	cont "lobby."
	done

_DoorDiceRerolledText::
	text "Doors"
	line "rerolled!"
	done

_MonDiceRefuseText::
	text "Nothing to"
	line "reroll here."
	done

_MonDiceRerolledText::
	text "Pokémon"
	line "rerolled!"
	done

_ItemDiceRefuseText::
	text "Nothing to"
	line "reroll here."
	done

_ItemDiceRerolledText::
	text "Item"
	line "rerolled!"
	done

; Credit Exchange vendors (engine/events/credit_mart.asm)
_CreditVendorGreetingText::
	text "What'll it be?"
	done

_CreditBuyConfirmText::
	text "So, you want"
	line "@"
	text_ram wNameBuffer
	text "?"
	done

_CreditBoughtText::
	text "Thanks! Enjoy"
	line "it out there."
	done

; Text-box lines fit 18 characters. Item names run to 12 (ITEM_NAME_LENGTH-1),
; so the name has to start its own line - "Upgrade " + a 12-char name is
; already 20 and wrapped mid-word on screen.
_CreditUpgradeConfirmText::
	text "@"
	text_ram wNameBuffer
	text ":"
	line "@"
	text_bcd hCoins, 2 | LEADING_ZEROES | LEFT_ALIGN
	text " CREDITS. OK?"
	done

_CreditUpgradedText::
	text "Done! Now at"
	line "TIER @"
	text_bcd wCreditItemList + 17, 1 | LEFT_ALIGN
	text "!"
	done
; credit_mart.asm stores internal tier + 1 there, so this prints the same
; 1-based number the bag and the vendor list show.

_CreditNotEnoughText::
	text "You don't have"
	line "enough CREDITS."
	done

_CreditSentToPCText::
	text "Your bag was"
	line "full, so it was"
	cont "sent to your PC!"
	done

_CreditNothingToSellText::
	text "You've bought"
	line "everything I"
	cont "have. Nice."
	done

_CreditNothingToUpgradeText::
	text "Nothing of yours"
	line "can be upgraded"
	cont "right now."
	done

_CreditRoomVendorClosedText::
	text "Room upgrades?"
	line "Not open yet."
	cont "Check back."
	done

_NoSlotPullsLeftText::
	text "No pulls left."
	line "Try again next"
	cont "run."
	done

; Mini-boss framework (see MINIBOSS_FRAMEWORK.md): shared Rival mini-boss
; dialogue, callable from any route's 5th-trainer encounter, not tied to a
; specific map's text file.
_RivalMiniBossBattleText::
	text "Smell ya later!"
	line "I'm gonna show"
	cont "you how a real"
	cont "trainer battles!"
	done

_RivalMiniBossEndBattleText::
	text "Feh! You got"
	line "lucky this time."
	done

; Mini-boss framework: shared Giovanni mini-boss dialogue, callable from any
; of his 3 dungeon maps' 5th-trainer encounter. Placeholder text - user will
; author the real quotes.
_GiovanniMiniBossBattleText::
	text "INSERT GIOVANNI"
	line "QUOTE HERE"
	done

; Final sequence: shared "go to the Champion" dialogue, shown as the
; AFTER-battle text (re-talk) of whichever Elite Four member ends up last
; (order[3]) in this run's shuffled order - mirrors vanilla Lance's role,
; but any of the 4 members can be the one to say it.
_Elite4GoToChampionText::
	text "That's the last"
	line "of us!"

	para "Go now and face"
	line "the CHAMPION!"
	done

; Final sequence: Lance's after-battle text when he is NOT the last (order[3])
; member this run. Vanilla's _LancesRoomLanceAfterBattleText always assumed
; Lance was last and directs the player to the Champion, so it can't be reused
; here. Placeholder text - user will author the real quote.
_LancesRoomLanceNormalAfterBattleText::
	text "INSERT LANCE"
	line "DIALOGUE HERE"
	done

_GiovanniMiniBossEndBattleText::
	text "No..."
	line "This cannot be!"
	done
    
_BridgeByeText::
	text "Until next time"
	prompt
    
_ReceivedItemText::
	text "<PLAYER> received"
	line "@"
	text_ram wNameBuffer
	text "!"        ; no '@' terminator: leave the string open so PlaceString
    prompt          ; reads the <PROMPT> char and actually waits for a button
	text_end
    
_Empty::
    text ""
	done

_BridgeTypeVariantFailText::
	text "That #MON can't"
	line "take on that"
	cont "type!"
	prompt

_BridgeWaterVariantText::
	text "It's now part"
	line "WATER type!"
	prompt

_BridgeRockVariantText::
	text "It's now part"
	line "ROCK type!"
	prompt

; Room Decoration System - Credit Exchange room vendor
; (custom_functions/room_vendor.asm)
_RoomVendorConfirmText::
	text "Buy for @"
	text_bcd hCoins, 2 | LEADING_ZEROES | LEFT_ALIGN
	text " CREDITS?"
	done

_RoomVendorBoughtText::
	text "Got it! Check"
	line "the room PC."
	done

_RoomVendorNotEnoughText::
	text "You don't have"
	line "enough CREDITS."
	done

_RoomVendorAlreadyOwnedText::
	text "You already own"
	line "this piece."
	done
