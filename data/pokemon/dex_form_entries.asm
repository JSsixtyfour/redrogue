; Pokedex entries for the form identities (Forms page, custom_functions/form_dex.asm).
; One entry per DEX_FORM_* id, in id order. Same layout as data/pokemon/dex_entries.asm:
;   db "CATEGORY@"        ; at most 10 characters
;   db feet, inches
;   dw weight             ; tenths of a pound
;   text_far _<Name>FormDexEntryText (description: 18 tiles per line, 3 lines per page)
;   text_end
; STATUS 2026-11-03: every entry is a placeholder (FORM_DEX_PENDING). Checkpoint E
; replaces them with sourced text; see POKEDEX_FORMS_TEXT_SPEC_2026-11-03.md.

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
	form_dex_pending

ARaticateFormDexEntry: ; DEX_FORM_A_RATICATE (RATICATE form 1)
	form_dex_pending

ARaichuFormDexEntry: ; DEX_FORM_A_RAICHU (RAICHU form 1)
	form_dex_pending

ASandshrewFormDexEntry: ; DEX_FORM_A_SANDSHREW (SANDSHREW form 1)
	form_dex_pending

ASandslashFormDexEntry: ; DEX_FORM_A_SANDSLASH (SANDSLASH form 1)
	form_dex_pending

AVulpixFormDexEntry: ; DEX_FORM_A_VULPIX (VULPIX form 1)
	form_dex_pending

ANinetalesFormDexEntry: ; DEX_FORM_A_NINETALES (NINETALES form 1)
	form_dex_pending

ScreamTailFormDexEntry: ; DEX_FORM_SCREAM_TAIL (JIGGLYPUFF form 1)
	form_dex_pending

ADiglettFormDexEntry: ; DEX_FORM_A_DIGLETT (DIGLETT form 1)
	form_dex_pending

WiglettFormDexEntry: ; DEX_FORM_WIGLETT (DIGLETT form 2)
	form_dex_pending

ADugtrioFormDexEntry: ; DEX_FORM_A_DUGTRIO (DUGTRIO form 1)
	form_dex_pending

WugtrioFormDexEntry: ; DEX_FORM_WUGTRIO (DUGTRIO form 2)
	form_dex_pending

AMeowthFormDexEntry: ; DEX_FORM_A_MEOWTH (MEOWTH form 1)
	form_dex_pending

GMeowthFormDexEntry: ; DEX_FORM_G_MEOWTH (MEOWTH form 2)
	form_dex_pending

APersianFormDexEntry: ; DEX_FORM_A_PERSIAN (PERSIAN form 1)
	form_dex_pending

PerrserkerFormDexEntry: ; DEX_FORM_PERRSERKER (PERSIAN form 2)
	form_dex_pending

HGrowlitheFormDexEntry: ; DEX_FORM_H_GROWLITHE (GROWLITHE form 1)
	form_dex_pending

HArcanineFormDexEntry: ; DEX_FORM_H_ARCANINE (ARCANINE form 1)
	form_dex_pending

ToedscoolFormDexEntry: ; DEX_FORM_TOEDSCOOL (TENTACOOL form 1)
	form_dex_pending

ToedscruelFormDexEntry: ; DEX_FORM_TOEDSCRUEL (TENTACRUEL form 1)
	form_dex_pending

AGeodudeFormDexEntry: ; DEX_FORM_A_GEODUDE (GEODUDE form 1)
	form_dex_pending

AGravelerFormDexEntry: ; DEX_FORM_A_GRAVELER (GRAVELER form 1)
	form_dex_pending

AGolemFormDexEntry: ; DEX_FORM_A_GOLEM (GOLEM form 1)
	form_dex_pending

GPonytaFormDexEntry: ; DEX_FORM_G_PONYTA (PONYTA form 1)
	form_dex_pending

GRapidashFormDexEntry: ; DEX_FORM_G_RAPIDASH (RAPIDASH form 1)
	form_dex_pending

GSlowpokeFormDexEntry: ; DEX_FORM_G_SLOWPOKE (SLOWPOKE form 1)
	form_dex_pending

GSlowbroFormDexEntry: ; DEX_FORM_G_SLOWBRO (SLOWBRO form 1)
	form_dex_pending

SandyShocksFormDexEntry: ; DEX_FORM_SANDY_SHOCKS (MAGNETON form 1)
	form_dex_pending

GFarfetchdFormDexEntry: ; DEX_FORM_G_FARFETCHD (FARFETCHD form 1)
	form_dex_pending

AGrimerFormDexEntry: ; DEX_FORM_A_GRIMER (GRIMER form 1)
	form_dex_pending

AMukFormDexEntry: ; DEX_FORM_A_MUK (MUK form 1)
	form_dex_pending

HVoltorbFormDexEntry: ; DEX_FORM_H_VOLTORB (VOLTORB form 1)
	form_dex_pending

HElectrodeFormDexEntry: ; DEX_FORM_H_ELECTRODE (ELECTRODE form 1)
	form_dex_pending

AExeggutorFormDexEntry: ; DEX_FORM_A_EXEGGUTOR (EXEGGUTOR form 1)
	form_dex_pending

AMarowakFormDexEntry: ; DEX_FORM_A_MAROWAK (MAROWAK form 1)
	form_dex_pending

GWeezingFormDexEntry: ; DEX_FORM_G_WEEZING (WEEZING form 1)
	form_dex_pending

GMrMimeFormDexEntry: ; DEX_FORM_G_MR_MIME (MR_MIME form 1)
	form_dex_pending

PTaurosCombatFormDexEntry: ; DEX_FORM_P_TAUROS_COMBAT (TAUROS form 1)
	form_dex_pending

PTaurosBlazeFormDexEntry: ; DEX_FORM_P_TAUROS_BLAZE (TAUROS form 2)
	form_dex_pending

PTaurosAquaFormDexEntry: ; DEX_FORM_P_TAUROS_AQUA (TAUROS form 3)
	form_dex_pending

GlaceonFormDexEntry: ; DEX_FORM_GLACEON (VAPOREON form 1)
	form_dex_pending

SylveonFormDexEntry: ; DEX_FORM_SYLVEON (VAPOREON form 2)
	form_dex_pending

EspeonFormDexEntry: ; DEX_FORM_ESPEON (JOLTEON form 1)
	form_dex_pending

UmbreonFormDexEntry: ; DEX_FORM_UMBREON (JOLTEON form 2)
	form_dex_pending

LeafeonFormDexEntry: ; DEX_FORM_LEAFEON (FLAREON form 1)
	form_dex_pending

GArticunoFormDexEntry: ; DEX_FORM_G_ARTICUNO (ARTICUNO form 1)
	form_dex_pending

GZapdosFormDexEntry: ; DEX_FORM_G_ZAPDOS (ZAPDOS form 1)
	form_dex_pending

GMoltresFormDexEntry: ; DEX_FORM_G_MOLTRES (MOLTRES form 1)
	form_dex_pending

PWooperFormDexEntry: ; DEX_FORM_P_WOOPER (WOOPER form 1)
	form_dex_pending

ClodsireFormDexEntry: ; DEX_FORM_CLODSIRE (QUAGSIRE form 1)
	form_dex_pending

GSlowkingFormDexEntry: ; DEX_FORM_G_SLOWKING (SLOWKING form 1)
	form_dex_pending

_FormDexPendingText:
	text "This form's data"
	next "has not been"
	next "recorded yet."
	dex
