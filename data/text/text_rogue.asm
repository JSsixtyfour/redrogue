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

_RecoilChallengeText::
	text "The bargain burns!"
	line "<TARGET> was hit"
	cont "by recoil!"
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
	text "INSERT GIOVANNI"
	line "DEFEAT QUOTE"
	cont "HERE"
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