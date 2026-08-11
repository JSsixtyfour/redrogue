SilphCoDorm_Script:
	jp EnableAutoTextBoxDrawing

SilphCoDorm_TextPointers:
	def_text_pointers
	; Object-event texts must be declared first, one dw_const per object
	; (even though all 8 share this same handler), so each stays <=
	; NUM_OBJECT_EVENTS for the def_warps_to assertion in the objects file.
	dw_const RoomDecorationText, TEXT_SILPHCODORM_DECORATION_1
	dw_const RoomDecorationText, TEXT_SILPHCODORM_DECORATION_2
	dw_const RoomDecorationText, TEXT_SILPHCODORM_DECORATION_3
	dw_const RoomDecorationText, TEXT_SILPHCODORM_DECORATION_4
	dw_const RoomDecorationText, TEXT_SILPHCODORM_DECORATION_5
	dw_const RoomDecorationText, TEXT_SILPHCODORM_DECORATION_6
	dw_const RoomDecorationText, TEXT_SILPHCODORM_DECORATION_7
	dw_const RoomDecorationText, TEXT_SILPHCODORM_DECORATION_8
	dw_const SilphCoDormPCText,  TEXT_SILPHCODORM_PC

; Shared handler for all 8 decoration objects. hActiveSpriteIndex holds the
; 1-based object SLOT the player just talked to (set by DisplayTextID before
; any text-id lookup, home/text_script.asm:22-23) - NOT the shared text id
; above, so this still tells the 8 decorations apart individually.
RoomDecorationText:
	text_asm
	ldh a, [hActiveSpriteIndex] ; 1-8
	dec a                       ; 0-7 slot index
	ld c, a
	ld b, 0
	ld hl, sRoomDecorSlots
	add hl, bc

	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ASSERT BANK("Save Data") == 1
	ld a, 1
	ld [rRAMB], a
	ld a, [hl]                  ; a = decoration id (0 = empty, 1-11 = decoration)
	ld b, a
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a
	ld a, b

	add a                       ; *2, dw-sized table entries
	ld c, a
	ld b, 0
	ld hl, RoomDecorationTextTable
	add hl, bc
	ld a, [hli]
	ld h, [hl]
	ld l, a
	call PrintText
	jp TextScriptEnd

RoomDecorationTextTable:
	dw .EmptyText          ; 0 - desync guard, should not normally be reachable
	dw .CharmeleonText      ; 1
	dw .PidgeyText          ; 2
	dw .OmanyteText         ; 3
	dw .VoltorbText         ; 4
	dw .ClefairyText        ; 5
	dw .ChanseyText         ; 6
	dw .SnorlaxText         ; 7
	dw .PikachuText         ; 8
	dw .PokedexText         ; 9
	dw .OldAmberText        ; 10
	dw .SeelText            ; 11

.EmptyText:
	text_far _SilphCoDormEmptyText
	text_end
.CharmeleonText:
	text_far _SilphCoDormCharmeleonText
	text_end
.PidgeyText:
	text_far _SilphCoDormPidgeyText
	text_end
.OmanyteText:
	text_far _SilphCoDormOmanyteText
	text_end
.VoltorbText:
	text_far _SilphCoDormVoltorbText
	text_end
.ClefairyText:
	text_far _SilphCoDormClefairyText
	text_end
.ChanseyText:
	text_far _SilphCoDormChanseyText
	text_end
.SnorlaxText:
	text_far _SilphCoDormSnorlaxText
	text_end
.PikachuText:
	text_far _SilphCoDormPikachuText
	text_end
.PokedexText:
	text_far _SilphCoDormPokedexText
	text_end
.OldAmberText:
	text_far _SilphCoDormOldAmberText
	text_end
.SeelText:
	text_far _SilphCoDormSeelText
	text_end

; The room PC - Key Items / Furniture / Decorations / Hall of Fame.
SilphCoDormPCText:
	text_asm
	farcall RoomPC
	; Without this, DisplayTextID falls through to WaitForTextScrollButtonPress
	; (home/text_script.asm) once this handler returns, leaving the auto-drawn
	; empty text box on screen and the player frozen until A is pressed - the
	; PC menu already consumed the interaction, so there is nothing to read.
	; Vanilla PCs avoid it by dispatching through BankswitchAndContinue's
	; "jp HoldTextDisplayOpen"; this is the text_asm equivalent, matching
	; CeladonMansion3F's DisplayDiploma handler.
	ld a, TRUE
	ldh [hNoWaitAfterText], a
	jp TextScriptEnd
