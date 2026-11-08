; Pokedex entries for the form identities (Forms page, custom_functions/form_dex.asm).
; One entry per DEX_FORM_* id, in id order. Same layout as data/pokemon/dex_entries.asm:
;   db "CATEGORY@"        ; at most 10 characters
;   db feet, inches
;   dw weight             ; tenths of a pound
;   text_far _<Name>FormDexEntryText (description: 18 tiles per line, 3 lines per page)
;   text_end
; STATUS 2026-11-07: all 53 entries are real (Checkpoint E, plus Honchkrow and
; Ursaluna added 2026-11-07). Sources and the cuts made to fit
; the page: POKEDEX_FORMS_TEXT_SOURCES.md. Descriptions: data/pokemon/dex_form_text.asm.

FormDexEntryPointers:
	table_width 2
	dw ARattataFormDexEntry
	dw ARaticateFormDexEntry
	dw ARaichuFormDexEntry
	dw ASandshrewFormDexEntry
	dw ASandslashFormDexEntry
	dw AVulpixFormDexEntry
	dw ANinetalesFormDexEntry
	dw ScreamTailFormDexEntry
	dw ADiglettFormDexEntry
	dw WiglettFormDexEntry
	dw ADugtrioFormDexEntry
	dw WugtrioFormDexEntry
	dw AMeowthFormDexEntry
	dw GMeowthFormDexEntry
	dw APersianFormDexEntry
	dw PerrserkerFormDexEntry
	dw HGrowlitheFormDexEntry
	dw HArcanineFormDexEntry
	dw ToedscoolFormDexEntry
	dw ToedscruelFormDexEntry
	dw AGeodudeFormDexEntry
	dw AGravelerFormDexEntry
	dw AGolemFormDexEntry
	dw GPonytaFormDexEntry
	dw GRapidashFormDexEntry
	dw GSlowpokeFormDexEntry
	dw GSlowbroFormDexEntry
	dw SandyShocksFormDexEntry
	dw GFarfetchdFormDexEntry
	dw AGrimerFormDexEntry
	dw AMukFormDexEntry
	dw HVoltorbFormDexEntry
	dw HElectrodeFormDexEntry
	dw AExeggutorFormDexEntry
	dw AMarowakFormDexEntry
	dw GWeezingFormDexEntry
	dw GMrMimeFormDexEntry
	dw PTaurosCombatFormDexEntry
	dw PTaurosBlazeFormDexEntry
	dw PTaurosAquaFormDexEntry
	dw GlaceonFormDexEntry
	dw SylveonFormDexEntry
	dw EspeonFormDexEntry
	dw UmbreonFormDexEntry
	dw LeafeonFormDexEntry
	dw GArticunoFormDexEntry
	dw GZapdosFormDexEntry
	dw GMoltresFormDexEntry
	dw PWooperFormDexEntry
	dw ClodsireFormDexEntry
	dw GSlowkingFormDexEntry
	dw HonchkrowFormDexEntry
	dw UrsalunaFormDexEntry
	assert_table_length NUM_DEX_FORMS

MACRO form_dex_pending
; Placeholder: an honest "not recorded" entry, never another species' text.
	db "UNKNOWN@"
	db 0, 0
	dw 0
	text_far _FormDexPendingText
	text_end
ENDM

ARattataFormDexEntry: ; DEX_FORM_A_RATTATA (RATTATA form 1)
	db "MOUSE@"
	db 1, 0
	dw 84
	text_far _ARattataFormDexEntryText
	text_end

ARaticateFormDexEntry: ; DEX_FORM_A_RATICATE (RATICATE form 1)
	db "MOUSE@"
	db 2, 4
	dw 562
	text_far _ARaticateFormDexEntryText
	text_end

ARaichuFormDexEntry: ; DEX_FORM_A_RAICHU (RAICHU form 1)
	db "MOUSE@"
	db 2, 4
	dw 463
	text_far _ARaichuFormDexEntryText
	text_end

ASandshrewFormDexEntry: ; DEX_FORM_A_SANDSHREW (SANDSHREW form 1)
	db "MOUSE@"
	db 2, 4
	dw 882
	text_far _ASandshrewFormDexEntryText
	text_end

ASandslashFormDexEntry: ; DEX_FORM_A_SANDSLASH (SANDSLASH form 1)
	db "MOUSE@"
	db 3, 11
	dw 1213
	text_far _ASandslashFormDexEntryText
	text_end

AVulpixFormDexEntry: ; DEX_FORM_A_VULPIX (VULPIX form 1)
	db "FOX@"
	db 2, 0
	dw 218
	text_far _AVulpixFormDexEntryText
	text_end

ANinetalesFormDexEntry: ; DEX_FORM_A_NINETALES (NINETALES form 1)
	db "FOX@"
	db 3, 7
	dw 439
	text_far _ANinetalesFormDexEntryText
	text_end

ScreamTailFormDexEntry: ; DEX_FORM_SCREAM_TAIL (JIGGLYPUFF form 1)
	db "PARADOX@"
	db 3, 11
	dw 176
	text_far _ScreamTailFormDexEntryText
	text_end

ADiglettFormDexEntry: ; DEX_FORM_A_DIGLETT (DIGLETT form 1)
	db "MOLE@"
	db 0, 8
	dw 22
	text_far _ADiglettFormDexEntryText
	text_end

WiglettFormDexEntry: ; DEX_FORM_WIGLETT (DIGLETT form 2)
	db "GARDEN EEL@"
	db 3, 11
	dw 40
	text_far _WiglettFormDexEntryText
	text_end

ADugtrioFormDexEntry: ; DEX_FORM_A_DUGTRIO (DUGTRIO form 1)
	db "MOLE@"
	db 2, 4
	dw 1468
	text_far _ADugtrioFormDexEntryText
	text_end

WugtrioFormDexEntry: ; DEX_FORM_WUGTRIO (DUGTRIO form 2)
	db "GARDEN EEL@"
	db 3, 11
	dw 119
	text_far _WugtrioFormDexEntryText
	text_end

AMeowthFormDexEntry: ; DEX_FORM_A_MEOWTH (MEOWTH form 1)
	db "SCRATCHCAT@"
	db 1, 4
	dw 93
	text_far _AMeowthFormDexEntryText
	text_end

GMeowthFormDexEntry: ; DEX_FORM_G_MEOWTH (MEOWTH form 2)
	db "SCRATCHCAT@"
	db 1, 4
	dw 165
	text_far _GMeowthFormDexEntryText
	text_end

APersianFormDexEntry: ; DEX_FORM_A_PERSIAN (PERSIAN form 1)
	db "CLASSY CAT@"
	db 3, 7
	dw 728
	text_far _APersianFormDexEntryText
	text_end

PerrserkerFormDexEntry: ; DEX_FORM_PERRSERKER (PERSIAN form 2)
	db "VIKING@"
	db 2, 7
	dw 617
	text_far _PerrserkerFormDexEntryText
	text_end

HGrowlitheFormDexEntry: ; DEX_FORM_H_GROWLITHE (GROWLITHE form 1)
	db "SCOUT@"
	db 2, 7
	dw 500
	text_far _HGrowlitheFormDexEntryText
	text_end

HArcanineFormDexEntry: ; DEX_FORM_H_ARCANINE (ARCANINE form 1)
	db "LEGENDARY@"
	db 6, 7
	dw 3704
	text_far _HArcanineFormDexEntryText
	text_end

ToedscoolFormDexEntry: ; DEX_FORM_TOEDSCOOL (TENTACOOL form 1)
	db "WOODEAR@"
	db 2, 11
	dw 728
	text_far _ToedscoolFormDexEntryText
	text_end

ToedscruelFormDexEntry: ; DEX_FORM_TOEDSCRUEL (TENTACRUEL form 1)
	db "WOODEAR@"
	db 6, 3
	dw 1279
	text_far _ToedscruelFormDexEntryText
	text_end

AGeodudeFormDexEntry: ; DEX_FORM_A_GEODUDE (GEODUDE form 1)
	db "ROCK@"
	db 1, 4
	dw 448
	text_far _AGeodudeFormDexEntryText
	text_end

AGravelerFormDexEntry: ; DEX_FORM_A_GRAVELER (GRAVELER form 1)
	db "ROCK@"
	db 3, 3
	dw 2425
	text_far _AGravelerFormDexEntryText
	text_end

AGolemFormDexEntry: ; DEX_FORM_A_GOLEM (GOLEM form 1)
	db "MEGATON@"
	db 5, 7
	dw 6967
	text_far _AGolemFormDexEntryText
	text_end

GPonytaFormDexEntry: ; DEX_FORM_G_PONYTA (PONYTA form 1)
	db "UNIQUEHORN@"
	db 2, 7
	dw 529
	text_far _GPonytaFormDexEntryText
	text_end

GRapidashFormDexEntry: ; DEX_FORM_G_RAPIDASH (RAPIDASH form 1)
	db "UNIQUEHORN@"
	db 5, 7
	dw 1764
	text_far _GRapidashFormDexEntryText
	text_end

GSlowpokeFormDexEntry: ; DEX_FORM_G_SLOWPOKE (SLOWPOKE form 1)
	db "DOPEY@"
	db 3, 11
	dw 794
	text_far _GSlowpokeFormDexEntryText
	text_end

GSlowbroFormDexEntry: ; DEX_FORM_G_SLOWBRO (SLOWBRO form 1)
	db "HERMITCRAB@"
	db 5, 3
	dw 1554
	text_far _GSlowbroFormDexEntryText
	text_end

SandyShocksFormDexEntry: ; DEX_FORM_SANDY_SHOCKS (MAGNETON form 1)
	db "PARADOX@"
	db 7, 7
	dw 1323
	text_far _SandyShocksFormDexEntryText
	text_end

GFarfetchdFormDexEntry: ; DEX_FORM_G_FARFETCHD (FARFETCHD form 1)
	db "WILD DUCK@"
	db 2, 7
	dw 926
	text_far _GFarfetchdFormDexEntryText
	text_end

AGrimerFormDexEntry: ; DEX_FORM_A_GRIMER (GRIMER form 1)
	db "SLUDGE@"
	db 2, 4
	dw 926
	text_far _AGrimerFormDexEntryText
	text_end

AMukFormDexEntry: ; DEX_FORM_A_MUK (MUK form 1)
	db "SLUDGE@"
	db 3, 3
	dw 1146
	text_far _AMukFormDexEntryText
	text_end

HVoltorbFormDexEntry: ; DEX_FORM_H_VOLTORB (VOLTORB form 1)
	db "SPHERE@"
	db 1, 8
	dw 287
	text_far _HVoltorbFormDexEntryText
	text_end

HElectrodeFormDexEntry: ; DEX_FORM_H_ELECTRODE (ELECTRODE form 1)
	db "SPHERE@"
	db 3, 11
	dw 1565
	text_far _HElectrodeFormDexEntryText
	text_end

AExeggutorFormDexEntry: ; DEX_FORM_A_EXEGGUTOR (EXEGGUTOR form 1)
	db "COCONUT@"
	db 35, 9
	dw 9162
	text_far _AExeggutorFormDexEntryText
	text_end

AMarowakFormDexEntry: ; DEX_FORM_A_MAROWAK (MAROWAK form 1)
	db "BONEKEEPER@"
	db 3, 3
	dw 750
	text_far _AMarowakFormDexEntryText
	text_end

GWeezingFormDexEntry: ; DEX_FORM_G_WEEZING (WEEZING form 1)
	db "POISON GAS@"
	db 9, 10
	dw 353
	text_far _GWeezingFormDexEntryText
	text_end

GMrMimeFormDexEntry: ; DEX_FORM_G_MR_MIME (MR_MIME form 1)
	db "DANCING@"
	db 4, 7
	dw 1252
	text_far _GMrMimeFormDexEntryText
	text_end

PTaurosCombatFormDexEntry: ; DEX_FORM_P_TAUROS_COMBAT (TAUROS form 1)
	db "WILD BULL@"
	db 4, 7
	dw 2535
	text_far _PTaurosCombatFormDexEntryText
	text_end

PTaurosBlazeFormDexEntry: ; DEX_FORM_P_TAUROS_BLAZE (TAUROS form 2)
	db "WILD BULL@"
	db 4, 7
	dw 1874
	text_far _PTaurosBlazeFormDexEntryText
	text_end

PTaurosAquaFormDexEntry: ; DEX_FORM_P_TAUROS_AQUA (TAUROS form 3)
	db "WILD BULL@"
	db 4, 7
	dw 2425
	text_far _PTaurosAquaFormDexEntryText
	text_end

GlaceonFormDexEntry: ; DEX_FORM_GLACEON (VAPOREON form 1)
	db "FRESH SNOW@"
	db 2, 7
	dw 571
	text_far _GlaceonFormDexEntryText
	text_end

SylveonFormDexEntry: ; DEX_FORM_SYLVEON (VAPOREON form 2)
	db "TWINING@"
	db 3, 3
	dw 518
	text_far _SylveonFormDexEntryText
	text_end

EspeonFormDexEntry: ; DEX_FORM_ESPEON (JOLTEON form 1)
	db "SUN@"
	db 2, 11
	dw 584
	text_far _EspeonFormDexEntryText
	text_end

UmbreonFormDexEntry: ; DEX_FORM_UMBREON (JOLTEON form 2)
	db "MOONLIGHT@"
	db 3, 3
	dw 595
	text_far _UmbreonFormDexEntryText
	text_end

LeafeonFormDexEntry: ; DEX_FORM_LEAFEON (FLAREON form 1)
	db "VERDANT@"
	db 3, 3
	dw 562
	text_far _LeafeonFormDexEntryText
	text_end

GArticunoFormDexEntry: ; DEX_FORM_G_ARTICUNO (ARTICUNO form 1)
	db "CRUEL@"
	db 5, 7
	dw 1122
	text_far _GArticunoFormDexEntryText
	text_end

GZapdosFormDexEntry: ; DEX_FORM_G_ZAPDOS (ZAPDOS form 1)
	db "STRONGLEGS@"
	db 5, 3
	dw 1283
	text_far _GZapdosFormDexEntryText
	text_end

GMoltresFormDexEntry: ; DEX_FORM_G_MOLTRES (MOLTRES form 1)
	db "MALEVOLENT@"
	db 6, 7
	dw 1455
	text_far _GMoltresFormDexEntryText
	text_end

PWooperFormDexEntry: ; DEX_FORM_P_WOOPER (WOOPER form 1)
	db "POISONFISH@"
	db 1, 4
	dw 243
	text_far _PWooperFormDexEntryText
	text_end

ClodsireFormDexEntry: ; DEX_FORM_CLODSIRE (QUAGSIRE form 1)
	db "SPINY FISH@"
	db 5, 11
	dw 4916
	text_far _ClodsireFormDexEntryText
	text_end

GSlowkingFormDexEntry: ; DEX_FORM_G_SLOWKING (SLOWKING form 1)
	db "HEXPERT@"
	db 5, 11
	dw 1753
	text_far _GSlowkingFormDexEntryText
	text_end

HonchkrowFormDexEntry: ; DEX_FORM_HONCHKROW (MURKROW form 1)
	db "BIG BOSS@"
	db 2, 11
	dw 602
	text_far _HonchkrowFormDexEntryText
	text_end

UrsalunaFormDexEntry: ; DEX_FORM_URSALUNA (URSARING form 1)
	db "PEAT@"
	db 7, 10
	dw 6393
	text_far _UrsalunaFormDexEntryText
	text_end

_FormDexPendingText:
	text "This form's data"
	next "has not been"
	next "recorded yet."
	dex
