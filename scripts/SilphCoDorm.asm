SilphCoDorm_Script:
	call EnableAutoTextBoxDrawing
	ld hl, wCurrentMapScriptFlags
	bit BIT_CUR_MAP_LOADED_1, [hl]
	ret z
	res BIT_CUR_MAP_LOADED_1, [hl]

	; Stage Lance's global toggle while still in the Dorm, before B1F loads its
	; object data. This prevents the final-opening actor from appearing a frame
	; late. Normalize it off for every non-qualifying Dorm visit.
	CheckEvent EVENT_INTRO_TOUR_COMPLETE
	jr z, .hideLance
	CheckEvent EVENT_OAK_CHAMPION_DEFEATED
	jr z, .hideLance
	CheckEvent EVENT_FINAL_BRIEFING_COMPLETE
	jr nz, .hideLance
	CheckEvent EVENT_PALMS_ROOM_OPEN
	jr nz, .hideLance
	ld a, TOGGLE_SILPH_CO_B1F_LANCE
	ld [wToggleableObjectIndex], a
	predef_jump ShowObject
.hideLance
	ld a, TOGGLE_SILPH_CO_B1F_LANCE
	ld [wToggleableObjectIndex], a
	predef_jump HideObject

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
	ld a, [hl]                  ; a = decoration id (0 = empty, 1-45 = decoration)
	ld b, a
	xor a
	ld [rRAMB], a               ; restore the ambient bank-0 selection (room_decor.asm header)
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
	dw .DoduoText           ; 12
	dw .PsyduckText         ; 13
	dw .NidorinoText        ; 14
	dw .KabutoText          ; 15
	dw .SpearowText         ; 16
	dw .CuboneText          ; 17
	dw .ArticunoText        ; 18
	dw .ZapdosText          ; 19
	dw .MoltresText         ; 20
	dw .MewtwoText          ; 21
	dw .FearowText          ; 22
	dw .KangaskhanText      ; 23
	dw .LaprasText          ; 24
	dw .MachopText          ; 25
	dw .MewText             ; 26
	dw .NidoranFText        ; 27
	dw .PidgeyYLText        ; 28
	dw .SlowpokeText        ; 29
	dw .VaporeonText        ; 30
	dw .BulbasaurText       ; 31
	dw .ClefairyYLText      ; 32
	dw .JigglypuffText      ; 33
	dw .MachokeText         ; 34
	dw .MeowthText          ; 35
	dw .MrMimeText          ; 36
	dw .NidoranMText        ; 37
	dw .OddishText          ; 38
	dw .PidgeotText         ; 39
	dw .PoliwrathText       ; 40
	dw .SandshrewText       ; 41
	dw .Seel2Text           ; 42
	dw .JolteonText         ; 43
	dw .FlareonText         ; 44
	dw .WigglytuffText      ; 45

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
.DoduoText:
	text_far _SilphCoDormDoduoText
	text_end
.PsyduckText:
	text_far _SilphCoDormPsyduckText
	text_end
.NidorinoText:
	text_far _SilphCoDormNidorinoText
	text_end
.KabutoText:
	text_far _SilphCoDormKabutoText
	text_end
.SpearowText:
	text_far _SilphCoDormSpearowText
	text_end
.CuboneText:
	text_far _SilphCoDormCuboneText
	text_end
.ArticunoText:
	text_far _SilphCoDormArticunoText
	text_end
.ZapdosText:
	text_far _SilphCoDormZapdosText
	text_end
.MoltresText:
	text_far _SilphCoDormMoltresText
	text_end
.MewtwoText:
	text_far _SilphCoDormMewtwoText
	text_end
.FearowText:
	text_far _SilphCoDormFearowText
	text_end
.KangaskhanText:
	text_far _SilphCoDormKangaskhanText
	text_end
.LaprasText:
	text_far _SilphCoDormLaprasText
	text_end
.MachopText:
	text_far _SilphCoDormMachopText
	text_end
.MewText:
	text_far _SilphCoDormMewText
	text_end
.NidoranFText:
	text_far _SilphCoDormNidoranFText
	text_end
.PidgeyYLText:
	text_far _SilphCoDormPidgeyYLText
	text_end
.SlowpokeText:
	text_far _SilphCoDormSlowpokeText
	text_end
.VaporeonText:
	text_far _SilphCoDormVaporeonText
	text_end
.BulbasaurText:
	text_far _SilphCoDormBulbasaurText
	text_end
.ClefairyYLText:
	text_far _SilphCoDormClefairyYLText
	text_end
.JigglypuffText:
	text_far _SilphCoDormJigglypuffText
	text_end
.MachokeText:
	text_far _SilphCoDormMachokeText
	text_end
.MeowthText:
	text_far _SilphCoDormMeowthText
	text_end
.MrMimeText:
	text_far _SilphCoDormMrMimeText
	text_end
.NidoranMText:
	text_far _SilphCoDormNidoranMText
	text_end
.OddishText:
	text_far _SilphCoDormOddishText
	text_end
.PidgeotText:
	text_far _SilphCoDormPidgeotText
	text_end
.PoliwrathText:
	text_far _SilphCoDormPoliwrathText
	text_end
.SandshrewText:
	text_far _SilphCoDormSandshrewText
	text_end
.Seel2Text:
	text_far _SilphCoDormSeel2Text
	text_end
.JolteonText:
	text_far _SilphCoDormJolteonText
	text_end
.FlareonText:
	text_far _SilphCoDormFlareonText
	text_end
.WigglytuffText:
	text_far _SilphCoDormWigglytuffText
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
