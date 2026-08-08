SilphCoVR_Script:
	jp EnableAutoTextBoxDrawing

SilphCoVR_TextPointers:
	def_text_pointers
    dw_const SilphCoVR_ProfPalmText,    TEXT_SILPHCOVR_PROF_PALM
    

SilphCoVR_ProfPalmText:
	text_far _SilphCoVR_ProfPalmText
	text_end
