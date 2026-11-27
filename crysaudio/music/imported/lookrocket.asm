; Converted from lookrocket.asm by the Red Rogue music test kit (native song file).
; kit-engine: crysaudio pokered-crysaudio 9753183a
; Size-optimized by tools/music_kit/song_optimize.py (2026-11-26): same notes, lengths
; and channel state, verified frame by frame with tools/music_kit/song_audio_compare.py.
; Rocket Theme (rockettheme.asm), which shared this file's phrases, was removed 2026-11-26.
Music_LookRocket::
	channel_count 4
	channel 1, Music_LookRocket_Ch1
	channel 2, Music_LookRocket_Ch2
	channel 3, Music_LookRocket_Ch3
	channel 4, Music_LookRocket_Ch4

Music_LookRocket_Ch1::
	tempo 123
	volume 7, 7
	transpose 0, 2
	stereo_panning FALSE, TRUE
	duty_cycle 3
	vibrato 5, 6, 4
	note_type 3, 10, 8
	octave 4
	note C_, 4
	note D_, 4
	note D#, 4
	rest 4
	note D_, 4
	rest 4
	note C#, 4
	rest 4
	note C_, 4
	rest 12
	octave 2
	note F_, 4
	note G#, 4
	note B_, 4
	octave 3
	note D_, 4
	note F_, 4
	note G#, 4
	duty_cycle 1
.mainloop:
	note_type 12, 10, 8
	rest 2
	octave 3
	note D#, 1
	rest 5
	note D#, 4
	octave 2
	note A_, 2
	octave 3
	note D#, 1
	note F_, 1
	note F#, 6
	note D#, 1
	rest 3
	note F#, 1
	rest 1
	note D#, 1
	rest 1
	octave 4
	note F#, 1
	rest 1
	rest 2
	octave 3
	note G_, 1
	rest 5
	note A_, 8
	note A#, 6
	note A_, 1
	rest 3
	note A#, 1
	rest 1
	note A_, 1
	rest 1
	octave 4
	note F#, 1
	rest 1
	volume_envelope 5, 3
	sound_call Music_LookRocket_Sub3
	volume_envelope 12, 3
	sound_call Music_LookRocket_Sub3
	volume_envelope 14, 3
	sound_call Music_LookRocket_Sub3
	rest 16
	sound_loop 0, .mainloop

Music_LookRocket_Ch2::
	transpose 0, 2
	vibrato 4, 6, 4
	duty_cycle 3
	stereo_panning TRUE, TRUE
	note_type 6, 11, 7
	octave 5
	note C_, 2
	note D_, 2
	note D#, 2
	rest 2
	note D_, 2
	rest 2
	note C#, 2
	rest 2
	note C_, 2
	rest 6
	octave 3
	note B_, 12
	duty_cycle 0
.mainloop:
	note_type 6, 11, 7
	rest 4
	octave 3
	note G_, 2
	rest 10
	note A_, 16
	note A#, 12
	note A_, 2
	rest 6
	note A#, 2
	rest 2
	note A_, 2
	rest 2
	octave 5
	note C_, 2
	rest 2
	rest 4
	octave 4
	note D#, 2
	rest 10
	note F_, 8
	note C_, 2
	note D_, 2
	note D#, 2
	note F_, 2
	note F#, 12
	note D#, 2
	rest 6
	note F#, 2
	rest 2
	note D#, 2
	rest 2
	octave 5
	note D#, 2
	rest 2
	volume_envelope 5, 3
	rest 4
	octave 3
	note F_, 2
	rest 14
	note F#, 2
	rest 10
	volume_envelope 12, 3
	rest 4
	note F_, 2
	rest 14
	note F#, 2
	rest 10
	volume_envelope 14, 3
	rest 4
	note F_, 2
	rest 14
	note F#, 2
	rest 10
	volume_envelope 6, 3
	note G#, 2
	note F_, 2
	note D_, 2
	octave 2
	note B_, 2
	volume_envelope 10, 3
	octave 3
	note A_, 2
	note F#, 2
	note D#, 2
	note C_, 2
	volume_envelope 12, 3
	note A#, 2
	note G_, 2
	note E_, 2
	note C#, 2
	volume_envelope 15, 3
	note B_, 2
	note G#, 2
	note F_, 2
	note D_, 2
	sound_loop 0, .mainloop

Music_LookRocket_Ch3::
	transpose 0, 2
	vibrato 4, 2, 2
	stereo_panning TRUE, FALSE
	note_type 6, 1, 4
	rest 4
	octave 3
	note F_, 2
	rest 2
	note G#, 2
	rest 2
	octave 4
	note C_, 2
	rest 2
	note D_, 2
	rest 6
	octave 3
	note D_, 12
.mainloop:
	note_type 1, 1, 4
	octave 3
	sound_call Music_LookRocket_Sub0
	sound_call Music_LookRocket_Sub0
	volume_envelope 2, 4
	sound_call Music_LookRocket_Sub2
	note G#, 12
	note F#, 12
	note D#, 12
	note C_, 12
	volume_envelope 1, 4
	sound_call Music_LookRocket_Sub2
	note C_, 12
	rest 12
	note F#, 12
	rest 12
	sound_call Music_LookRocket_Sub2
	note G#, 12
	note F#, 12
	note D#, 12
	note C_, 12
	volume_envelope 2, 4
	octave 2
	note G#, 12
	rest 12
	octave 3
	note F_, 12
	rest 12
	octave 2
	note A_, 12
	rest 12
	octave 3
	note F#, 12
	rest 12
	volume_envelope 1, 4
	octave 2
	note A#, 12
	rest 12
	octave 3
	note G_, 12
	rest 12
	octave 2
	note B_, 12
	rest 12
	octave 3
	note G#, 12
	rest 12
	sound_loop 0, .mainloop

Music_LookRocket_Ch4::
	toggle_noise 3
	drum_speed 6
	rest 4
	drum_note 1, 16
	drum_note 3, 4
	drum_note 4, 4
	drum_note 2, 2
	drum_note 2, 2
	drum_note 3, 2
	drum_note 3, 2
.mainloop:
	drum_speed 6
.loop0:
	sound_call Music_LookRocket_Sub1
	sound_loop 7, .loop0
	drum_note 1, 16
	drum_note 3, 4
	drum_note 4, 4
	drum_note 2, 2
	drum_note 2, 2
	drum_note 3, 2
	drum_note 3, 2
	sound_loop 0, .mainloop

Music_LookRocket_Sub0:
	note C_, 12
	rest 12
	octave 4
	note C_, 12
	rest 12
	octave 3
	note C_, 12
	rest 12
	note C_, 12
	rest 12
	octave 4
	note C_, 12
	rest 12
	octave 3
	note C_, 12
	rest 12
	note D#, 12
	rest 12
	note G_, 12
	rest 12
	note C_, 12
	rest 12
	note C_, 12
	rest 12
	note C_, 12
	rest 12
	note C_, 12
	rest 12
	note C_, 12
	rest 12
	note C_, 12
	rest 12
	note F#, 12
	rest 12
	note A_, 12
	rest 12
	sound_ret

Music_LookRocket_Sub1:
	drum_note 4, 4
	drum_note 7, 4
	drum_note 3, 4
	drum_note 7, 4
	drum_note 4, 4
	drum_note 7, 4
	drum_note 3, 4
	drum_note 7, 4
	sound_ret

Music_LookRocket_Sub2:
	octave 2
	note G#, 12
	rest 12
	octave 3
	note G#, 12
	rest 12
	octave 2
	note G#, 12
	rest 12
	note G#, 12
	rest 12
	note A_, 12
	rest 12
	octave 3
	note A_, 12
	rest 12
	sound_ret

Music_LookRocket_Sub3:
	rest 2
	octave 2
	note B_, 1
	rest 7
	octave 3
	note C_, 1
	rest 5
	sound_ret
