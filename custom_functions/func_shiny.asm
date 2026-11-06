; custom_functions/func_shiny.asm
;
; Shiny system (Credit Exchange SHINY CHARM key item, see
; KEY_ITEM_EFFECTS_PLAN_PC.md §3a). A "shiny" mon is a flag on one specific
; mon instance (not a separate species) that swaps its display palette.
; Mirrors func_ghost_variant.asm's shape.
;
; Ported from Shin Red (github.com/jojobear13/shinpokered), which has its own
; custom_functions/func_shiny.asm. Two deliberate differences:
;   - Shininess here is a rolled FLAG (catch-rate bit 4), not Gen 2-style
;     "DVs happen to be 10/10/10/10" as Shin detects it. Red Rogue wanted
;     tunable odds driven by the SHINY CHARM's tier, which a fixed DV pattern
;     cannot express.
;   - The palette side IS Shin's, unchanged in substance: a shiny mon reuses
;     another existing mon palette (see ShinyPaletteConvert in
;     engine/gfx/palettes.asm), so no new SGB palette data is added.
;
; Storage: bit 4 of the repurposed CatchRate byte (MON_CATCH_RATE) - see
; MON_CATCH_RATE_BITFIELD_PC.md. Bits 0-3 are already used (ghost/fusion/
; type-variant/special-form); this claims the next free bit.
;
; The roll + bit-set happens inline at the mon-creation site
; (engine/pokemon/add_mon.asm), not through an ApplyShiny call here - there's
; nothing to share (the roll odds live entirely at that one call site), and
; add_mon.asm already farcalls GetKeyItemPower there for DV_BOOSTER, so the
; SHINY CHARM roll reuses the same farcall shape rather than adding a second
; cross-bank hop through this file. Only the read side (IsShiny) lives here,
; for the two display hooks in engine/gfx/palettes.asm.
;
; Enemy side (2026-09-29): a TRAINER mon keeps its party struct's whole flag
; byte (GetEnemyCatchRateByte, bridge_effects_extended.asm), so trainer mons
; rolled shiny at creation now show it on the HUD. Wild mons still carry only
; their form bits, so a wild mon is never shiny.

DEF BIT_SHINY EQU 4 ; bit within the repurposed CatchRate byte

; DrawBattleVariantMarker moved to bridge_effects_extended.asm: this bank is full.

; Entrance sparkle animation ID (Shin Red import Phase 9.2), shared with
; PlayVariantEntranceAnim below. This is UnusedAnim in data/moves/animations.asm
; (entry #182, counted directly in that table) - shinpokered's $B6, a
; light-screen-palette / balls-upward / reset-palette sparkle that reads as a
; "power up" effect. No re-derivation needed, this fork's animation table has
; the same unused slot at the same index.
DEF SHINY_ENTRANCE_ANIM EQU 182

; ---------------------------------------------------------------------------
; IsShiny
; INPUT: de = pointer to the mon's struct (box_struct/party_struct/
;             battle_struct base - wPartyMonN, wEnemyMonN, wBattleMon,
;             wEnemyMon, wLoadedMon, etc. all qualify)
; OUTPUT: Z set if NOT shiny, Z clear (NZ) if it IS
; CLOBBERS: af, hl
;
; Takes the struct pointer in de, not hl - farcall's Bankswitch overwrites hl
; with its own jump vector on entry, so hl never survives a farcall boundary
; (see IsGhostVariant's comment in func_ghost_variant.asm for the full story).
; ---------------------------------------------------------------------------
IsShiny::
	ld hl, MON_CATCH_RATE
	add hl, de
	bit BIT_SHINY, [hl]
	ret

; ---------------------------------------------------------------------------
; PlayVariantEntranceAnim
; Plays a one-off "power-up" sparkle over a mon that has just been sent out, if
; that mon is a display variant. Shared entry point rather than a shiny-specific
; one so a future ghost/type-variant caller can reuse it with a different
; animation ID - see ShinRed_Import.md Phase 9.2.
; Each send-out calls its entry once, after the cry. Redraws do not replay it.
PlayVariantEntranceAnim::
	ld a, [wBattleMonCatchRate]
	ld d, 0
	jr PlayShinyEntrance
PlayEnemyVariantEntranceAnim::
	ld a, [wEnemyMonCatchRate]
	ld d, 1
PlayShinyEntrance:
	bit BIT_SHINY, a
	ret z
	ld e, SHINY_ENTRANCE_ANIM
	farcall PlaySelectedAnimation
	ld b, SET_PAL_BATTLE
	jp RunPaletteCommand
