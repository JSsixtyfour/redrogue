SaffronCity_Script:
	call EnableAutoTextBoxDrawing
	ld hl, wCurrentMapScriptFlags
	bit BIT_CUR_MAP_LOADED_1, [hl]
	res BIT_CUR_MAP_LOADED_1, [hl]
	ret z

; First tick after the truck drops the player off. Saffron is only ever entered
; during the intro, so no extra state variable is needed - the NPC movement
; system below holds the rest of the sequence's state itself.
; hJoyIgnore MUST be the d-pad only: it masks hJoyPressed globally
; (engine/joypad.asm), and the text below ends on a prompt whose wait reads A/B
; out of that same masked byte. Including PAD_BUTTONS here would softlock.
	ld a, PAD_CTRL_PAD
	ldh [hJoyIgnore], a

; Palm's screen position has never been computed at this point: this is the
; very first script tick after the map loaded. UpdateNPCSprite bails out to
; NotYetMoving whenever wFontLoaded is set (engine/overworld/movement.asm), so
; InitializeSpriteScreenPosition would be skipped for the entire time the
; textbox below is open and Palm would be drawn at a stale screen position,
; snapping into place only once the escort movement starts. Forcing one sprite
; pass here - while the font is still unloaded - places him correctly first.
	call UpdateSprites

	ld a, TEXT_SAFFRONCITY_PROF_PALM
	ldh [hTextID], a
	call DisplayTextID

; Hand off to the escort movement script.
	ld a, SAFFRONCITY_PROF_PALM
	ldh [hActiveSpriteIndex], a
	xor a
	ld [wNPCMovementScriptFunctionNum], a
	ld a, 1 ; SaffronPalmMovementScriptPointerTable (see home/npc_movement.asm)
	ld [wNPCMovementScriptPointerTableNum], a
; Pallet Town and Pewter City store hLoadedROMBank here, which only works
; because their map scripts happen to share bank $06 with auto_movement.asm.
; SaffronCity_Script is in bank $14, so it must name the bank explicitly or
; RunNPCMovementScript would switch to $14 and jump to $06's table address.
	ld a, BANK(SaffronPalmMovementScriptPointerTable)
	ld [wNPCMovementScriptBank], a
	ret

SaffronCity_TextPointers:
	def_text_pointers
	dw_const SaffronCityProfPalmText,                 TEXT_SAFFRONCITY_PROF_PALM
	dw_const SaffronCitySignText,                     TEXT_SAFFRONCITY_SIGN
	dw_const SaffronCityFightingDojoSignText,         TEXT_SAFFRONCITY_FIGHTING_DOJO_SIGN
	dw_const SaffronCityGymSignText,                  TEXT_SAFFRONCITY_GYM_SIGN
	dw_const MartSignText,                            TEXT_SAFFRONCITY_MART_SIGN
	dw_const SaffronCityTrainerTips1Text,             TEXT_SAFFRONCITY_TRAINER_TIPS1
	dw_const SaffronCityTrainerTips2Text,             TEXT_SAFFRONCITY_TRAINER_TIPS2
	dw_const SaffronCitySilphCoSignText,              TEXT_SAFFRONCITY_SILPH_CO_SIGN
	dw_const PokeCenterSignText,                      TEXT_SAFFRONCITY_POKECENTER_SIGN
	dw_const SaffronCityMrPsychicsHouseSignText,      TEXT_SAFFRONCITY_MR_PSYCHICS_HOUSE_SIGN
	dw_const SaffronCitySilphCoLatestProductSignText, TEXT_SAFFRONCITY_SILPH_CO_LATEST_PRODUCT_SIGN

SaffronCityRocket1Text:
	text_far _SaffronCityRocket1Text
	text_end

SaffronCityRocket2Text:
	text_far _SaffronCityRocket2Text
	text_end

SaffronCityRocket3Text:
	text_far _SaffronCityRocket3Text
	text_end

SaffronCityRocket4Text:
	text_far _SaffronCityRocket4Text
	text_end

SaffronCityRocket5Text:
	text_far _SaffronCityRocket5Text
	text_end

SaffronCityRocket6Text:
	text_far _SaffronCityRocket6Text
	text_end

SaffronCityRocket7Text:
	text_far _SaffronCityRocket7Text
	text_end

SaffronCityScientistText:
	text_far _SaffronCityScientistText
	text_end

SaffronCitySilphWorkerMText:
	text_far _SaffronCitySilphWorkerMText
	text_end

SaffronCitySilphWorkerFText:
	text_far _SaffronCitySilphWorkerFText
	text_end

SaffronCityGentlemanText:
	text_far _SaffronCityGentlemanText
	text_end

SaffronCityPidgeotText:
	text_far _SaffronCityPidgeotText
	sound_cry_pidgeot
	text_end

SaffronCityRockerText:
	text_far _SaffronCityRockerText
	text_end

SaffronCityRocket8Text:
	text_far _SaffronCityRocket8Text
	text_end

SaffronCityRocket9Text:
	text_far _SaffronCityRocket9Text
	text_end

SaffronCityProfPalmText:
	text_far _SaffronCityProfPalmText
	text_end

SaffronCitySignText:
	text_far _SaffronCitySignText
	text_end

SaffronCityFightingDojoSignText:
	text_far _SaffronCityFightingDojoSignText
	text_end

SaffronCityGymSignText:
	text_far _SaffronCityGymSignText
	text_end

SaffronCityTrainerTips1Text:
	text_far _SaffronCityTrainerTips1Text
	text_end

SaffronCityTrainerTips2Text:
	text_far _SaffronCityTrainerTips2Text
	text_end

SaffronCitySilphCoSignText:
	text_far _SaffronCitySilphCoSignText
	text_end

SaffronCityMrPsychicsHouseSignText:
	text_far _SaffronCityMrPsychicsHouseSignText
	text_end

SaffronCitySilphCoLatestProductSignText:
	text_far _SaffronCitySilphCoLatestProductSignText
	text_end
