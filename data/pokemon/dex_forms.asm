; Pokedex form identities: DEX_FORM_* id -> (base species, form index).
; Order IS the id (constants/pokedex_constants.asm), which is saved: append only.
; Each (species, form) must name a record in FormOverrides (data/pokemon/forms.asm);
; tools/pyboy_smoke/test_dex_forms.py checks that against the built ROM.

MACRO dex_form
; \1 = DEX_FORM_* id, \2 = base species, \3 = form index 1..NUM_FORM_SLOTS
	ASSERT (@ - DexFormKeys) / 2 == \1, "dex_form entries out of DEX_FORM_* order"
	ASSERT \3 >= 1 && \3 <= NUM_FORM_SLOTS
	db \2, \3
ENDM

DexFormKeys::
	dex_form DEX_FORM_A_RATTATA,        RATTATA,    1
	dex_form DEX_FORM_A_RATICATE,       RATICATE,   1
	dex_form DEX_FORM_A_RAICHU,         RAICHU,     1
	dex_form DEX_FORM_A_SANDSHREW,      SANDSHREW,  1
	dex_form DEX_FORM_A_SANDSLASH,      SANDSLASH,  1
	dex_form DEX_FORM_A_VULPIX,         VULPIX,     1
	dex_form DEX_FORM_A_NINETALES,      NINETALES,  1
	dex_form DEX_FORM_SCREAM_TAIL,      JIGGLYPUFF, 1
	dex_form DEX_FORM_A_DIGLETT,        DIGLETT,    1
	dex_form DEX_FORM_WIGLETT,          DIGLETT,    2
	dex_form DEX_FORM_A_DUGTRIO,        DUGTRIO,    1
	dex_form DEX_FORM_WUGTRIO,          DUGTRIO,    2
	dex_form DEX_FORM_A_MEOWTH,         MEOWTH,     1
	dex_form DEX_FORM_G_MEOWTH,         MEOWTH,     2
	dex_form DEX_FORM_A_PERSIAN,        PERSIAN,    1
	dex_form DEX_FORM_PERRSERKER,       PERSIAN,    2
	dex_form DEX_FORM_H_GROWLITHE,      GROWLITHE,  1
	dex_form DEX_FORM_H_ARCANINE,       ARCANINE,   1
	dex_form DEX_FORM_TOEDSCOOL,        TENTACOOL,  1
	dex_form DEX_FORM_TOEDSCRUEL,       TENTACRUEL, 1
	dex_form DEX_FORM_A_GEODUDE,        GEODUDE,    1
	dex_form DEX_FORM_A_GRAVELER,       GRAVELER,   1
	dex_form DEX_FORM_A_GOLEM,          GOLEM,      1
	dex_form DEX_FORM_G_PONYTA,         PONYTA,     1
	dex_form DEX_FORM_G_RAPIDASH,       RAPIDASH,   1
	dex_form DEX_FORM_G_SLOWPOKE,       SLOWPOKE,   1
	dex_form DEX_FORM_G_SLOWBRO,        SLOWBRO,    1
	dex_form DEX_FORM_SANDY_SHOCKS,     MAGNETON,   1
	dex_form DEX_FORM_G_FARFETCHD,      FARFETCHD,  1
	dex_form DEX_FORM_A_GRIMER,         GRIMER,     1
	dex_form DEX_FORM_A_MUK,            MUK,        1
	dex_form DEX_FORM_H_VOLTORB,        VOLTORB,    1
	dex_form DEX_FORM_H_ELECTRODE,      ELECTRODE,  1
	dex_form DEX_FORM_A_EXEGGUTOR,      EXEGGUTOR,  1
	dex_form DEX_FORM_A_MAROWAK,        MAROWAK,    1
	dex_form DEX_FORM_G_WEEZING,        WEEZING,    1
	dex_form DEX_FORM_G_MR_MIME,        MR_MIME,    1
	dex_form DEX_FORM_P_TAUROS_COMBAT,  TAUROS,     1
	dex_form DEX_FORM_P_TAUROS_BLAZE,   TAUROS,     2
	dex_form DEX_FORM_P_TAUROS_AQUA,    TAUROS,     3
	dex_form DEX_FORM_GLACEON,          VAPOREON,   1
	dex_form DEX_FORM_SYLVEON,          VAPOREON,   2
	dex_form DEX_FORM_ESPEON,           JOLTEON,    1
	dex_form DEX_FORM_UMBREON,          JOLTEON,    2
	dex_form DEX_FORM_LEAFEON,          FLAREON,    1
	dex_form DEX_FORM_G_ARTICUNO,       ARTICUNO,   1
	dex_form DEX_FORM_G_ZAPDOS,         ZAPDOS,     1
	dex_form DEX_FORM_G_MOLTRES,        MOLTRES,    1
	dex_form DEX_FORM_P_WOOPER,         WOOPER,     1
	dex_form DEX_FORM_CLODSIRE,         QUAGSIRE,   1
	dex_form DEX_FORM_G_SLOWKING,       SLOWKING,   1
	dex_form DEX_FORM_HONCHKROW,        MURKROW,    1
	dex_form DEX_FORM_URSALUNA,         URSARING,   1
	dex_form DEX_FORM_H_QWILFISH,       QWILFISH,   1
	dex_form DEX_FORM_OVERQWIL,         QWILFISH,   2
	ASSERT (@ - DexFormKeys) / 2 == NUM_DEX_FORMS, "DexFormKeys is missing entries"
	db 0 ; terminator
