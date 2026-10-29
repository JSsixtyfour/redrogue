; Red Rogue music kit: native Crystal-engine song template.
; Drag this file onto "DROP YOUR SONG HERE" to hear it. Edit it, drag again.
;
; Rules the kit checks for you:
;   * One song label ending in :: that is followed by channel_count. Name it anything.
;   * Every "channel n, X" and every sound_call / sound_jump / sound_loop target
;     must be a label in THIS file (the whole song is stored in one place).
;   * Only commands from the engine's macro list. No load_wave, INCLUDE or INCBIN.
; Ch1/Ch2 = square waves, Ch3 = wave (note_type's third number picks wave 0-14),
; Ch4 = drums. "toggle_noise 0" selects drum kit 0 (indexes 1-12), "toggle_noise 1" kit 1
; (indexes 1-12 = the kit's drums 8-19). A bare "toggle_noise" turns drums off.

Music_Template::
	channel_count 4
	channel 1, Music_Template_Ch1
	channel 2, Music_Template_Ch2
	channel 3, Music_Template_Ch3
	channel 4, Music_Template_Ch4

Music_Template_Ch1::
	tempo 144
	volume 7, 7
	duty_cycle 2
	note_type 12, 11, 3
Music_Template_Ch1_loop::
	sound_call Music_Template_Ch1_phrase
	sound_call Music_Template_Ch1_phrase
	sound_loop 0, Music_Template_Ch1_loop
Music_Template_Ch1_phrase::
	octave 4
	note C_, 4
	note E_, 4
	note G_, 4
	note E_, 4
	sound_ret

Music_Template_Ch2::
	duty_cycle 1
	note_type 12, 10, 3
Music_Template_Ch2_loop::
	sound_call Music_Template_Ch2_phrase
	sound_call Music_Template_Ch2_phrase
	sound_loop 0, Music_Template_Ch2_loop
Music_Template_Ch2_phrase::
	octave 3
	note C_, 8
	note G_, 8
	sound_ret

Music_Template_Ch3::
	note_type 12, 1, 0
Music_Template_Ch3_loop::
	sound_call Music_Template_Ch3_phrase
	sound_call Music_Template_Ch3_phrase
	sound_loop 0, Music_Template_Ch3_loop
Music_Template_Ch3_phrase::
	octave 2
	note C_, 8
	note G_, 8
	sound_ret

Music_Template_Ch4::
	toggle_noise 0
	drum_speed 12
Music_Template_Ch4_loop::
	sound_call Music_Template_Ch4_phrase
	sound_call Music_Template_Ch4_phrase
	sound_loop 0, Music_Template_Ch4_loop
Music_Template_Ch4_phrase::
	drum_note 1, 4
	drum_note 2, 4
	drum_note 1, 4
	drum_note 2, 4
	sound_ret
