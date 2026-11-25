_GreedyText::
    text "Better not get"
	line "greedy..."
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

_LeftoversDescriptionText::
	text "Heals your"
	line "team a bit"
	cont "after each"
	cont "battle!"
	prompt


; Shared by CHALLENGE_RECOIL_ATTACKS, _RECOIL_PHYSICAL and _RECOIL_SPECIAL.
; <USER>, not <TARGET>: this damage lands on the PLAYER'S OWN mon, and
; PlaceMoveTargetsName (home/text.asm) is hWhoseTurn XOR 1 - at this seam
; hWhoseTurn is always 0 (ExecutePlayerMove sets it and nothing after restores
; it before the hook), so <TARGET> printed "Enemy <foe> was hit by recoil!"
; while the player's own mon lost the HP. Pre-existing bug, fixed 2026-09-02.
_RecoilChallengeText::
	text "The challenge"
	line "punishes that"
	cont "move."
    
	para "<USER> was hit"
	cont "by recoil!"
	prompt

; <USER> expands to the player's mon nick, up to 10 characters, so it needs a
; line largely to itself - "repetition! <USER>" reached 21 with a long nick.
_SameMovePenaltyText::
	text "The challenge"
	line "punishes"
	cont "repetition."
	
    para "<USER> hurt!"
	prompt

_NoHealingChallengeText::
	text "The challenge"
	line "prevents healing"
	cont "outside battle."
	prompt

_TurnLimitDrainText::
	text "The challenge"
	line "drains your"
	cont "#MON's HP."
	prompt

_PPTonicDescriptionText::
	text "Restores PP"
	line "slightly after"
	cont "each battle."
	prompt

; EXP_ALL is an option now (BIT_EXP_SHARE); its bag description is unused.
;_ExpAllDescriptionText::
;	text "Shares EXP"
;	line "with the whole"
;	cont "party after"
;	cont "each battle."
;	done

_KODefianceDescriptionText::
	text "Revives your"
	line "last mon if"
	cont "it would"
	cont "faint!"
	prompt

_KODefianceActivatedText::
	text "KO DEFIANCE"
	line "activated!"
	prompt

_ShinyCharmDescriptionText::
	text "Ups the odds"
	line "of finding"
	cont "shiny Pokémon."
	prompt

_AmuletCoinDescriptionText::
	text "Increases"
	line "money earned"
	cont "from battles."
	prompt

_TurnRewindDescriptionText::
	text "Rewinds to"
	line "the prior turn"
	cont "in battle."
	prompt

_RareScopeDescriptionText::
	text "Increases the"
	line "rarity of reward"
	cont "#MON."
	prompt

_RareLensDescriptionText::
	text "Increases the"
	line "rarity of"
	cont "items found."
	prompt

_DVBoosterDescriptionText::
	text "Increases DVs"
	line "of reward"
	cont "Pokémon."
	prompt

_StatBoosterDescriptionText::
	text "Increases stat"
	line "experience"
	cont "gained."
	prompt

_DoorDiceDescriptionText::
	text "Lets you"
	line "reroll lobby"
	cont "doors."
	done

_MonDiceDescriptionText::
	text "Lets you"
	line "reroll reward"
	cont "#MON"
	done

_ItemDiceDescriptionText::
	text "Lets you reroll"
	line "reward items."
	done

_ElementPrismDescriptionText::
	text "Boosts that type's"
	line "damage and reward"
	cont "chances."
	done

; ELEMENT BOY cartridge system (custom_functions/element_prism.asm).
_ElementPrismSetText::
	text "CARTRIDGE"
	line "installed!"
	prompt

; text_ram reads the equipped type's name out of wStringBuffer.
_ElementPrismStatusText::
	text "CARTRIDGE:"
	line "@"
	text_ram wStringBuffer
	text ""
	prompt

_PrismNoCartridgesText::
	text "No CARTRIDGE"
	line "installed."
	prompt

; One-time grant messages (custom_functions/element_prism.asm), gated on
; persistent per-grantor events - shown once ever, never again, even across
; runs. text_ram reads the granted type's name out of wStringBuffer.
; The two grant announcements below all end in `prompt`, because they are
; shown from two contexts that both need the text to wait for A itself:
;   - the gym leader's, from TrainerBattleVictory mid-battle, where nothing
;     waits afterwards - with `done` the "defeated"/prize-money boxes drew
;     straight over it and it flashed for one frame
;   - the Elite Four ones, from a DisplayTextID text_asm that calls
;     DisableWaitingAfterTextDisplay so the prompt is the only wait
; The type name (wStringBuffer, up to 8 chars: FIGHTING, ELECTRIC) goes on its
; own line: "ELECTRIC CARTRIDGE!" is 19 columns against the box's 18, and the
; old one-line layouts ran to 30.
_PrismFirstGrantText::
	text "Received the"
	line "ELEMENT BOY!"

	para "It came with a"
	line "@"
	text_ram wStringBuffer
	text " type"
	cont "CARTRIDGE!"
	prompt

_PrismCartridgeGrantText::
	text "Received a"
	line "@"
	text_ram wStringBuffer
	text " type"
	cont "CARTRIDGE!"
	prompt

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
	prompt

_DoorDiceRefuseText::
	text "Can only be"
	line "used in the"
	cont "lobby."
	prompt

_DoorDiceRerolledText::
	text "Doors"
	line "rerolled!"
	prompt

_MonDiceRefuseText::
	text "Nothing to"
	line "reroll here."
	prompt

_MonDiceRerolledText::
	text "#MON"
	line "rerolled!"
	prompt

_ItemDiceRefuseText::
	text "Nothing to"
	line "reroll here."
	prompt

_ItemDiceRerolledText::
	text "Item"
	line "rerolled!"
	prompt

; Credit Exchange vendors (engine/events/credit_mart.asm)
_CreditVendorGreetingText::
	text "Take your time."
	done

_CreditBuyConfirmText::
	text "So, you want"
	line "@"
	text_ram wNameBuffer
	text "?"
	done

_CreditBoughtText::
	text "Here you are!"
	line "Thank you!"
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
	cont "have. Thanks!"
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
	text "No pulls left. Try"
	line "again after your"
	cont "next run."
	done
    
; Mini-boss framework (MINIBOSS_FRAMEWORK.md): the Rival and Giovanni mini-boss
; lines are vanilla's own, so the route scripts text_far the vanilla copies
; instead of duplicating them here:
;   Rival battle  _CeruleanCityRivalPreBattleText  (text/CeruleanCity.asm)
;   Rival defeat  _Route22Rival1DefeatedText       (text/Route22.asm)
;   Giovanni      _RocketHideoutB4FGiovanniImpressedYouGotHereText
; Their after-battle lines are in custom_functions/rogue_boss_after_battle.asm.

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
; here. Placeholder text - TODO author the real quote.
_LancesRoomLanceNormalAfterBattleText::
	text "I still can't"
	line "believe my"
	cont "dragons lost to"
	cont "you, <PLAYER>!"

	para "Go forth and do"
	line "not lose!"
	done

_GiovanniMiniBossEndBattleText::
	text "No..."
	line "This cannot be!"
	prompt
    
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
	text "Its second type"
	line "is now WATER."
	prompt

_BridgeRockVariantText::
	text "Its second type"
	line "is now ROCK."
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
	line "that."
	done
