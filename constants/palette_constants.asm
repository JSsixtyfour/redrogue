; pal/blk packets
; SetPalFunctions indexes (see engine/gfx/palettes.asm)
	const_def
	const SET_PAL_BATTLE_BLACK         ; $00
	const SET_PAL_BATTLE               ; $01
	const SET_PAL_TOWN_MAP             ; $02
	const SET_PAL_STATUS_SCREEN        ; $03
	const SET_PAL_POKEDEX              ; $04
	const SET_PAL_SLOTS                ; $05
	const SET_PAL_TITLE_SCREEN         ; $06
	const SET_PAL_NIDORINO_INTRO       ; $07
	const SET_PAL_GENERIC              ; $08
	const SET_PAL_OVERWORLD            ; $09
	const SET_PAL_PARTY_MENU           ; $0A
	const SET_PAL_POKEMON_WHOLE_SCREEN ; $0B
	const SET_PAL_GAME_FREAK_INTRO     ; $0C
	const SET_PAL_TRAINER_CARD         ; $0D

DEF SET_PAL_PARTY_MENU_HP_BARS EQU $fc
DEF SET_PAL_DEFAULT EQU $ff

; sgb palettes
; SuperPalettes indexes (see data/sgb/sgb_palettes.asm)
	const_def
	const PAL_ROUTE     ; $00
	const PAL_PALLET    ; $01
	const PAL_VIRIDIAN  ; $02
	const PAL_PEWTER    ; $03
	const PAL_CERULEAN  ; $04
	const PAL_LAVENDER  ; $05
	const PAL_VERMILION ; $06
	const PAL_CELADON   ; $07
	const PAL_FUCHSIA   ; $08
	const PAL_CINNABAR  ; $09
	const PAL_INDIGO    ; $0A
	const PAL_SAFFRON   ; $0B
	const PAL_TOWNMAP   ; $0C
	const PAL_LOGO1     ; $0D
	const PAL_LOGO2     ; $0E
	const PAL_0F        ; $0F
	const PAL_MEWMON    ; $10
	const PAL_BLUEMON   ; $11
	const PAL_REDMON    ; $12
	const PAL_CYANMON   ; $13
	const PAL_PURPLEMON ; $14
	const PAL_BROWNMON  ; $15
	const PAL_GREENMON  ; $16
	const PAL_PINKMON   ; $17
	const PAL_YELLOWMON ; $18
	const PAL_GRAYMON   ; $19
	const PAL_SLOTS1    ; $1A
	const PAL_SLOTS2    ; $1B
	const PAL_SLOTS3    ; $1C
	const PAL_SLOTS4    ; $1D
	const PAL_BLACK     ; $1E
	const PAL_GREENBAR  ; $1F
	const PAL_YELLOWBAR ; $20
	const PAL_REDBAR    ; $21
	const PAL_BADGE     ; $22
	const PAL_CAVE      ; $23
	const PAL_GAMEFREAK ; $24
    ;gbcnote - added from yellow
	const PAL_25        ; $25
	; PAL_26 had no callers; Yume uses this slot for the Bill's PC icon palette.
	const PAL_BILLS_PC  ; $26
	const PAL_27        ; $27
DEF NUM_SGB_PALS EQU const_value
	const PAL_BW        ; $28, CGB only
	const PAL_UBALL     ; $29, CGB only

; --- Phase 4 (procedural stage palette variants) ---------------------------
; Readable aliases for two spare rows claimed by the procedural cave, rather
; than appended rows. Appending would cost 16 bytes each across SuperPalettes
; and CGBPalettes in bank $1C (345 bytes free) AND would shift PAL_BW/PAL_UBALL,
; which sit past NUM_SGB_PALS. These two rows shift nothing:
;   PAL_0F has NO references anywhere in the tree.
;   PAL_27 is referenced only by UnknownPalPacket_72821 (data/sgb/sgb_packets.asm),
;          which is itself referenced by nothing - vanilla dead data. Its own
;          name is kept above so that dead row still assembles.
; The aliases are defined here, not in either palette file, so the SGB path
; (engine/gfx/palettes.asm) and the CGB enhanced path
; (custom_functions/func_enhancedcolor.asm) name the same thing.
DEF PAL_CAVE_COLD EQU PAL_0F
; PAL_CAVE_DARK (was PAL_27) was built and CUT 2026-09-16 - the darkened cavern
; is unreadable as a normal-navigation cave. PAL_27 is back to its original
; colours.

; 2B (2026-09-22): the Procedural Forest's SGB/CGB-non-enhanced seasonal rows,
; claiming the last two spare slots (PAL_25 and PAL_27) the same way
; PAL_CAVE_COLD claimed PAL_0F. There are no spare SGB rows left after this.
DEF PAL_FOREST_SPRING EQU PAL_25
DEF PAL_FOREST_FALL   EQU PAL_27

; How many palette variants the procedural cave rolls. Shared, because BOTH
; colour paths range-check against it: fresh SRAM powers up $ff, so
; sProcCavePalette can legitimately be out of range on a save that predates the
; field, and neither path may index a table with it unchecked.
; func_enhancedcolor.asm ASSERTs its ProcCavePalSets table against this.
DEF PROC_CAVE_PAL_COUNT EQU 2

; How many palette variants the Procedural Forest and Facility roll (2B,
; 2026-09-22). Same reasoning as PROC_CAVE_PAL_COUNT: fresh SRAM powers up
; $ff, so both the CGB enhanced path (func_enhancedcolor.asm) and the
; SGB/DMG path range-check against these before indexing a table.
DEF PROC_FOREST_PAL_COUNT   EQU 2 ; sProcForestPalette: 0 spring, 1 fall
DEF PROC_FACILITY_PAL_COUNT EQU 2 ; sProcFacilityPalette: 0 PowerPlant, 1 Mansion

; SHINY CHARM adds NO palettes here. Shin Red's system (which this is ported
; from) remaps a shiny mon onto another EXISTING mon palette rather than
; defining new ones - see ShinyPaletteConvert in engine/gfx/palettes.asm.
