; Converted from mewtwo.mid by the Red Rogue music test kit (pokemid v0.9, Crystal engine).
; kit-engine: crysaudio pokered-crysaudio 9753183a
; Size-optimized by tools/music_kit/song_optimize.py (2026-11-26): same notes, lengths
; and channel state, verified frame by frame with tools/music_kit/song_audio_compare.py.
Music_MewtwoBattle::
	channel_count 3
	channel 1, Music_MewtwoBattle_Ch1
	channel 2, Music_MewtwoBattle_Ch2
	channel 3, Music_MewtwoBattle_Ch3

Music_MewtwoBattle_Ch1::
	tempo 123
	vibrato 0, 0, 0
	duty_cycle 1
	note_type 4, 10, 0
	octave 3
	note A#, 3
	rest 5
	note F_, 4
	note F_, 2
	rest 2
	note C_, 2
	rest 2
	octave 2
	note G_, 2
	rest 2
	note F_, 2
	rest 2
	note A_, 2
	rest 2
	octave 3
	note G_, 2
	rest 2
	note F_, 2
	rest 2
	note A#, 2
	rest 2
	octave 4
	note F_, 2
	rest 2
	volume_envelope 7, 0
	note E_, 12
	rest 12
	volume_envelope 9, 0
	octave 3
	note E_, 3
	octave 4
	note E_, 3
	note_type 24, 8, 0
	octave 5
	note E_, 10
	rest 1
	note_type 6, 9, 0
	octave 4
	note B_, 2
	rest 2
	octave 3
	note B_, 16
	octave 4
	note E_, 2
	rest 2
	octave 3
	note B_, 2
	rest 2
	note_type 14, 9, 0
	note A#, 15
	note_type 6, 9, 0
	rest 1
	octave 4
	note E_, 4
	rest 12
	note E_, 1
	rest 1
	octave 5
	note E_, 1
	rest 1
	volume_envelope 8, 0
	octave 4
	note E_, 2
	rest 10
	octave 3
	note B_, 1
	rest 1
	octave 4
	note B_, 1
	rest 1
	octave 3
	note A#, 2
	rest 10
	note B_, 2
	octave 4
	note E_, 2
	note B_, 2
	octave 5
	note B_, 1
	octave 6
	note C_, 1
	octave 5
	note B_, 1
	octave 6
	note C_, 1
	sound_call Music_MewtwoBattle_Sub0
	note B_, 1
	octave 6
	note C_, 1
	volume_envelope 7, 0
	octave 5
	note B_, 1
.loop0:
	octave 6
	sound_call Music_MewtwoBattle_Sub0
	sound_loop 6, .loop0
	octave 6
	note C_, 1
	octave 5
	note B_, 1
	volume_envelope 8, 0
.loop1:
	octave 6
	sound_call Music_MewtwoBattle_Sub0
	sound_loop 3, .loop1
	volume_envelope 9, 0
	octave 6
	note C_, 1
	octave 5
	note B_, 1
	octave 6
	note C_, 1
	octave 5
	note B_, 1
	volume_envelope 7, 0
	octave 6
	note C_, 1
.mainloop:
	note_type 16, 9, 0
	octave 3
	note B_, 15
	note A_, 3
	octave 4
	note D_, 2
	note C_, 2
	octave 3
	note B_, 2
	octave 4
	note D_, 6
	note G_, 2
	note F_, 2
	note E_, 2
	note_type 12, 9, 0
	note D_, 1
	note E_, 1
	octave 3
	note A_, 14
	note_type 8, 9, 0
	rest 12
	note A#, 4
	note A_, 4
	note A#, 4
	octave 4
	note D_, 9
	note C_, 9
	octave 3
	note A#, 6
	note A_, 15
	note A_, 3
	note_type 1, 9, 0
	note G_, 12
	note A_, 12
	rest 12
	note_type 14, 9, 0
	note E_, 14
	note_type 8, 9, 0
	rest 13
	note E_, 4
	note F_, 4
	note G_, 4
	note A_, 4
	note B_, 4
	octave 4
	note C_, 4
	octave 3
	note B_, 4
	note A_, 4
	note G_, 4
	note A_, 15
	note A_, 3
	octave 4
	note C_, 3
	note G_, 9
	note_type 12, 9, 0
	note F_, 1
	note E_, 1
	note D_, 1
	note C_, 1
	note E_, 1
	note D_, 1
	note C_, 1
	octave 3
	note A#, 1
	octave 4
	note D_, 1
	note C_, 1
	octave 3
	note A#, 1
	note G_, 1
	note A_, 16
	volume_envelope 10, 0
	note B_, 16
	note E_, 16
	octave 4
	note D#, 8
	note A#, 4
	volume_envelope 11, 0
	note G#, 1
	note F_, 1
	octave 3
	note G#, 1
	note C_, 1
	volume_envelope 10, 0
	note D_, 4
	rest 16
	rest 12
	volume_envelope 9, 0
	sound_call Music_MewtwoBattle_Sub6
	octave 4
	note C_, 2
	rest 6
	note D_, 2
	rest 6
	note C_, 2
	rest 15
	note_type 4, 9, 0
	octave 3
	note C_, 3
	sound_call Music_MewtwoBattle_Sub15
	note F_, 3
	sound_call Music_MewtwoBattle_Sub16
	octave 4
	note D_, 3
	octave 3
	note D_, 3
	octave 2
	note A_, 3
	octave 3
	note D_, 3
	note A_, 3
	rest 3
	note G_, 3
	note A_, 3
	note A_, 3
	note D_, 3
	note F_, 3
	note A_, 3
	note F_, 3
	note A_, 3
	note G_, 3
	note F_, 3
	sound_call Music_MewtwoBattle_Sub15
	note D#, 6
	note D_, 3
	note C_, 3
	sound_call Music_MewtwoBattle_Sub16
	octave 4
	note D#, 3
	note D_, 2
	note D#, 2
	note D_, 2
	note D#, 2
	note D_, 2
	note D#, 2
	note D_, 3
	note C_, 3
	octave 3
	note A#, 3
	note A_, 3
	octave 4
	note D_, 3
	octave 3
	note A_, 3
	note F_, 3
	note D#, 3
	note D_, 3
	note C_, 3
	note D#, 3
	note D_, 3
.loop2:
	note D#, 3
	note G_, 3
	octave 2
	note A#, 3
	octave 3
	note G_, 3
	sound_loop 2, .loop2
	note A#, 3
	note A_, 3
	note G_, 3
	note F_, 3
	note G_, 3
	note F_, 3
	note D#, 3
	note G_, 3
	note D_, 3
	note C_, 3
	note D_, 6
	note C_, 3
	octave 2
	note A_, 3
	octave 3
	note D_, 3
	note C_, 3
	note D_, 3
	octave 2
	note A_, 3
	octave 3
	note D_, 3
	octave 2
	note A_, 3
	octave 3
	note F_, 3
	note G_, 3
	note A_, 3
	note A#, 3
	octave 4
	note C_, 3
	octave 3
	note A#, 3
	note A_, 3
	note A#, 3
	octave 4
	sound_call Music_MewtwoBattle_Sub16
	note A#, 3
	note A_, 3
	note G_, 3
	note A#, 3
	note G_, 3
	note G_, 3
	note F_, 3
	note D#, 3
	note G_, 3
	note A_, 3
	note A#, 3
	note A_, 3
	note F_, 3
	note G_, 3
	note F_, 3
	note D#, 3
	note G_, 3
	note A_, 3
	octave 4
	note D#, 3
	note F_, 3
	note D#, 3
	note D_, 3
	note C_, 3
	note D#, 3
	octave 3
	note D#, 3
	note A#, 3
	note G_, 3
	note A#, 3
	octave 4
	note D#, 3
	note D_, 3
	note C_, 3
	note D#, 3
	sound_call Music_MewtwoBattle_Sub16
	note A#, 2
	octave 4
	note C_, 2
	note D_, 2
	note D#, 2
	note F_, 2
	note G_, 2
	octave 3
	note D_, 12
	note A_, 12
	octave 4
	note D_, 12
	note A_, 12
	note_type 12, 9, 0
	note G_, 6
	note F_, 2
	note D#, 4
	rest 4
	volume_envelope 8, 0
	sound_call Music_MewtwoBattle_Sub17
	note A#, 6
	note A_, 2
	note G_, 4
	rest 4
	sound_call Music_MewtwoBattle_Sub17
	note G_, 6
	note F_, 2
	note D#, 4
	rest 4
	sound_call Music_MewtwoBattle_Sub17
	octave 5
	note D#, 6
	note D_, 2
	volume_envelope 9, 0
	note C_, 4
	octave 4
	note A#, 4
	volume_envelope 8, 0
	octave 3
	note A_, 12
	note G_, 2
	note A_, 2
	note B_, 6
	note G_, 6
	note B_, 4
	note A_, 6
	note G_, 6
	note E_, 4
	note D_, 6
	octave 2
	note B_, 5
	rest 5
	octave 3
	note A_, 12
	note G_, 2
	note A_, 2
	note B_, 6
	octave 4
	note D_, 6
	octave 3
	note B_, 4
	note B_, 6
	octave 4
	note E_, 5
	rest 1
	volume_envelope 9, 0
	octave 3
	note B_, 4
	octave 4
	note D_, 6
	octave 3
	note B_, 5
	rest 9
	octave 2
	note A_, 4
	octave 3
	note C_, 4
	note E_, 4
	note D_, 12
	note C_, 2
	octave 2
	note B_, 2
	note A_, 8
	octave 3
	note C_, 4
	note E_, 4
	note D_, 6
	octave 2
	note A_, 6
	note B_, 2
	octave 3
	note C_, 6
	octave 2
	note A_, 4
	octave 3
	note C_, 4
	note E_, 4
	note D_, 12
	note E_, 2
	note F_, 2
	note E_, 8
	note C_, 4
	note E_, 4
	note F#, 12
	note E_, 1
	volume_envelope 10, 0
	note F#, 1
	volume_envelope 9, 0
	note G_, 1
	note A_, 1
	sound_loop 0, .mainloop

Music_MewtwoBattle_Ch2::
	vibrato 0, 0, 0
	duty_cycle 3
	note_type 2, 7, 0
	octave 4
	note D#, 6
	rest 10
	octave 3
	note A#, 8
	note A#, 4
	rest 4
	note F_, 4
	rest 4
	note C_, 4
	rest 4
	octave 2
	note A#, 4
	rest 4
	octave 3
	note D_, 4
	rest 4
	octave 4
	note C_, 4
	rest 4
	octave 3
	note A#, 4
	rest 4
	octave 4
	note D#, 4
	rest 4
	note A#, 4
	rest 4
	note_type 12, 7, 0
	octave 3
	note E_, 16
	note E_, 16
	note E_, 16
	note E_, 14
	note_type 3, 6, 0
	note E_, 1
	volume_envelope 7, 0
	note F_, 1
	note F#, 1
	note G_, 1
	note A_, 1
	note B_, 1
	octave 4
	note C_, 1
	note D_, 1
	volume_envelope 8, 0
	note E_, 8
	note_type 12, 10, 0
	octave 3
	note E_, 14
	volume_envelope 7, 0
	note E_, 12
	note_type 1, 7, 0
	note D_, 7
	note E_, 3
	note F#, 11
	note G_, 3
	note A_, 3
	note A#, 4
	note B_, 3
	octave 4
	note C_, 7
	note D_, 7
	note_type 6, 7, 0
	note E_, 8
	octave 2
	sound_call Music_MewtwoBattle_Sub18
	octave 3
	note C_, 1
	note D_, 1
	note E_, 8
	octave 4
	sound_call Music_MewtwoBattle_Sub18
	octave 5
	note C_, 1
	note D_, 1
	note E_, 8
	octave 3
	sound_call Music_MewtwoBattle_Sub18
	octave 4
	note C_, 1
	note D_, 1
	note E_, 16
.mainloop:
	note_type 16, 6, 0
	octave 3
	note E_, 15
	note C_, 3
	note G_, 2
	note F_, 2
	note E_, 2
	note C_, 6
	note D_, 2
	note C_, 2
	octave 2
	note B_, 2
	note_type 6, 6, 0
	octave 3
	note C_, 2
	note D_, 2
	volume_envelope 9, 0
	note C_, 10
	rest 2
	note C_, 2
	note D_, 2
	note C_, 2
	octave 2
	note B_, 2
	octave 3
	note C_, 2
	octave 2
	note B_, 2
	note A_, 2
	note G_, 2
	note F_, 16
	note_type 8, 6, 0
	octave 3
	note D_, 4
	note C_, 4
	note D_, 4
	note F_, 9
	note D_, 9
	note C_, 6
	note E_, 15
	note_type 6, 6, 0
	note D_, 4
	note C_, 2
	note D_, 2
	rest 2
	octave 2
	note A_, 16
	rest 2
	volume_envelope 7, 0
	note A_, 2
	volume_envelope 8, 0
	note B_, 2
	octave 3
	note C_, 2
	note D_, 2
	note E_, 2
	note D_, 2
	note C_, 2
	octave 2
	note A_, 2
	note F_, 16
	note_type 8, 6, 0
	note A_, 4
	note B_, 4
	octave 3
	note C_, 4
	note D_, 4
	note E_, 4
	note F_, 4
	note E_, 4
	note D_, 4
	note C_, 4
	note D_, 15
	note D_, 3
	note E_, 3
	octave 4
	note C_, 9
	note_type 12, 6, 0
	octave 3
	note F_, 1
	note E_, 1
	note D_, 1
	note C_, 1
	note E_, 1
	note D_, 1
	note C_, 1
	octave 2
	note A#, 1
	octave 3
	note D_, 1
	note C_, 1
	octave 2
	note A#, 1
	note G_, 1
	volume_envelope 7, 0
	octave 3
	note E_, 8
	note A_, 16
	octave 4
	note F#, 8
	note C#, 8
	octave 3
	note G#, 8
	volume_envelope 8, 0
	note G#, 8
	note D#, 4
	octave 4
	note D#, 1
	octave 3
	note A#, 1
	note D#, 1
	octave 2
	note A#, 1
	note A_, 4
	rest 16
	rest 12
	volume_envelope 9, 0
	octave 4
	sound_call Music_MewtwoBattle_Sub6
	octave 5
	note C_, 2
	rest 6
	note D_, 2
	rest 6
	note C_, 2
	rest 16
	rest 14
	octave 3
	sound_call Music_MewtwoBattle_Sub19
	octave 3
	note A#, 2
	note A_, 2
	octave 4
	note C_, 2
	octave 3
	note A#, 2
	note A_, 2
	note G_, 2
	note A#, 2
	sound_call Music_MewtwoBattle_Sub19
	note D#, 2
	note D_, 2
	note C_, 2
	note D_, 2
	note C_, 2
	octave 3
	note A#, 2
	note G_, 2
	sound_call Music_MewtwoBattle_Sub19
	octave 3
	note A#, 2
	note A_, 2
	note G_, 2
	note A#, 2
	note A_, 2
	note G_, 2
	note D#, 2
	note D_, 2
	note D#, 2
	note F_, 2
	note G_, 2
	note A_, 2
	note G_, 2
	note G_, 2
	note D_, 2
	note D#, 1
	note G_, 3
	note G_, 6
	note D#, 2
	note C_, 2
	note D#, 2
	note_type 16, 6, 0
	sound_call Music_MewtwoBattle_Sub13
	note E_, 1
	note F_, 1
	note_type 10, 6, 0
	note A_, 16
	note_type 1, 6, 0
	rest 2
	note_type 16, 6, 0
	note G_, 3
	volume_envelope 7, 0
	octave 4
	note C_, 2
	octave 3
	note A#, 2
	note G_, 2
	volume_envelope 6, 0
	octave 4
	sound_call Music_MewtwoBattle_Sub13
	volume_envelope 7, 0
	note E_, 1
	note F_, 1
	note_type 10, 7, 0
	note A_, 16
	note_type 1, 7, 0
	rest 2
	note_type 4, 7, 0
	note A_, 12
	volume_envelope 9, 0
	note G_, 8
	note F_, 8
	note E_, 8
	note_type 12, 9, 0
	note F_, 12
	note E_, 2
	note F_, 2
	note G_, 6
	note D_, 6
	note G_, 4
	note F_, 6
	note E_, 6
	note C_, 4
	octave 3
	note B_, 6
	note G_, 5
	rest 5
	octave 4
	note F_, 12
	note E_, 2
	note F_, 2
	note G_, 6
	note B_, 6
	octave 5
	note D_, 4
	note D_, 6
	octave 4
	note B_, 6
	note A_, 4
	note G#, 6
	note G#, 1
	note A_, 1
	note B_, 8
	octave 5
	sound_call Music_MewtwoBattle_Sub10
	octave 5
	note C_, 2
	note D_, 6
	note E_, 6
	note D_, 4
	sound_call Music_MewtwoBattle_Sub10
	note A_, 2
	octave 5
	note E_, 6
	note D_, 1
	note C_, 1
	note D_, 1
	octave 4
	note B_, 1
	note G_, 1
	note E_, 1
	note B_, 1
	note G_, 1
	note E_, 1
	note D_, 1
	sound_loop 0, .mainloop

Music_MewtwoBattle_Ch3::
	vibrato 0, 0, 0
	note_type 12, 1, 6
	octave 2
	note F_, 16
.loop3:
	sound_call Music_MewtwoBattle_Sub5
	sound_loop 4, .loop3
.mainloop:
	note_type 3, 1, 6
	octave 2
	sound_call Music_MewtwoBattle_Sub7
	octave 2
	note B_, 4
	note A_, 8
	note E_, 4
	sound_call Music_MewtwoBattle_Sub7
	note A_, 4
	note G_, 4
	note F_, 4
	note E_, 4
	sound_call Music_MewtwoBattle_Sub20
	octave 2
	note F_, 4
	note F_, 4
	note F_, 4
	octave 3
	note C_, 4
	note C_, 12
	sound_call Music_MewtwoBattle_Sub20
	octave 2
	note F_, 4
	note F_, 4
	sound_call Music_MewtwoBattle_Sub11
	note A_, 4
	note A#, 4
	octave 3
	note D_, 4
	note C_, 8
	octave 2
	note G_, 4
	note A#, 12
	note A#, 12
	note A#, 4
	note A#, 4
	rest 4
	note A#, 4
	note A_, 4
	note A#, 4
	octave 3
	note D_, 4
	note C_, 4
	octave 2
	note A#, 4
.loop4:
	note G_, 4
	sound_call Music_MewtwoBattle_Sub7
	octave 2
	note A_, 4
	note E_, 8
	sound_loop 2, .loop4
	note G_, 4
	sound_call Music_MewtwoBattle_Sub20
	note F_, 4
	note F_, 4
	note F_, 4
	octave 3
	note C_, 4
	note C_, 12
	octave 2
	sound_call Music_MewtwoBattle_Sub20
	octave 3
	note C_, 4
	octave 2
	note A_, 4
	sound_call Music_MewtwoBattle_Sub11
	note A#, 4
	note A#, 4
	octave 3
	note F_, 4
	octave 2
	note A#, 8
	note A_, 4
	note A#, 12
	note A#, 12
	note A#, 4
	note A#, 4
	rest 4
	note A#, 4
	note A#, 4
	note A#, 4
	octave 3
	note D_, 4
	note C_, 4
	octave 2
	note A#, 4
	note G_, 4
.loop5:
	sound_call Music_MewtwoBattle_Sub7
	octave 2
	note A_, 4
	note G_, 8
	note E_, 4
	sound_loop 3, .loop5
	note A_, 12
	note A_, 12
	note A_, 8
	note A#, 4
	note A#, 4
	note A#, 8
	note A#, 4
	note A#, 8
	note A#, 4
	note E_, 8
	sound_call Music_MewtwoBattle_Sub9
	sound_call Music_MewtwoBattle_Sub9
	note A_, 8
.loop6:
	note A#, 8
	note G#, 8
	note F_, 8
	sound_loop 5, .loop6
	note A#, 8
	sound_call Music_MewtwoBattle_Sub9
	note A_, 8
	sound_call Music_MewtwoBattle_Sub2
	sound_call Music_MewtwoBattle_Sub2
	sound_call Music_MewtwoBattle_Sub14
	sound_call Music_MewtwoBattle_Sub14
	note F_, 8
	note A_, 8
	note A#, 8
	octave 3
	note C_, 8
.loop7:
	sound_call Music_MewtwoBattle_Sub3
	sound_call Music_MewtwoBattle_Sub12
	sound_loop 3, .loop7
	sound_call Music_MewtwoBattle_Sub3
	note C_, 4
	note C_, 4
	octave 2
	note G_, 4
	octave 3
	note C_, 4
	note C_, 4
	octave 2
	note A#, 4
	octave 3
	note C_, 4
	note D_, 16
	octave 4
	sound_call Music_MewtwoBattle_Sub1
	rest 8
	octave 4
	note D_, 8
	sound_call Music_MewtwoBattle_Sub1
	octave 3
	sound_call Music_MewtwoBattle_Sub4
	note D_, 12
.loop8:
	sound_call Music_MewtwoBattle_Sub4
	octave 2
	note G_, 4
	note B_, 4
	octave 3
	note D_, 4
	sound_loop 2, .loop8
	octave 2
	note B_, 6
	rest 6
	note B_, 6
	rest 6
	note B_, 8
	rest 4
	note B_, 4
	note A_, 4
	note B_, 4
	octave 3
	note E_, 16
	octave 2
	note E_, 6
	rest 6
	note E_, 6
	rest 6
	note E_, 8
	rest 4
	note E_, 4
	note G#, 4
	note A_, 4
	note B_, 4
	note E_, 4
	note G#, 4
	note B_, 4
	sound_call Music_MewtwoBattle_Sub8
	note D_, 4
	note C_, 4
	note D_, 4
	octave 2
	note G_, 8
	note G_, 8
	note A_, 6
	rest 6
	note A_, 6
	rest 6
	note A_, 12
	note A_, 4
	note G_, 4
	note A_, 4
	octave 3
	note E_, 16
	note D_, 6
	rest 6
	note D_, 6
	rest 6
	note D_, 8
	rest 4
.loop9:
	note D_, 4
	note C_, 4
	note D_, 4
	octave 2
	note G_, 4
	note G_, 12
	sound_call Music_MewtwoBattle_Sub8
	sound_loop 2, .loop9
	note E_, 4
	note D_, 4
	note C_, 4
	note E_, 4
	note D_, 4
	note C_, 4
	octave 2
	note B_, 4
	sound_loop 0, .mainloop

Music_MewtwoBattle_Sub0:
	note C_, 1
	octave 5
	note B_, 1
	octave 6
	note C_, 1
	octave 5
	note B_, 1
	octave 6
	note C_, 1
	octave 5
	note B_, 1
	sound_ret

Music_MewtwoBattle_Sub1:
	note D_, 8
	note C_, 4
	octave 3
	note A#, 4
	octave 4
	note C_, 4
	octave 3
	note A#, 4
	note A_, 4
	note G_, 4
	note A_, 4
	note G_, 4
	note F_, 4
	note E_, 4
	note F_, 4
	note E_, 4
	note F_, 4
	note G_, 4
	note A_, 8
	note A_, 8
	note A_, 4
	note G_, 4
	note F_, 4
	note E_, 4
	note F_, 4
	note E_, 4
	note D_, 4
	note C_, 4
	note A_, 8
	note A_, 8
	note A_, 4
	note A_, 4
	note G_, 4
	note F_, 4
	note E_, 4
	note F_, 4
	note E_, 4
	note D_, 4
	note C_, 4
	note D_, 4
	note C_, 4
	octave 2
	note A#, 4
	octave 3
	note A_, 4
	note A_, 12
	note A_, 4
	note G_, 4
	note F_, 4
	note E_, 4
	note F_, 4
	note E_, 4
	note D_, 4
	note C_, 4
	note D_, 4
	note C_, 4
	octave 2
	note A#, 4
	note A_, 4
	sound_ret

Music_MewtwoBattle_Sub2:
	note F_, 8
	octave 3
	note C_, 8
	octave 2
	note A#, 8
	note F_, 8
	octave 3
	note C_, 8
	octave 2
	note A#, 8
	note F_, 8
	octave 3
	note C_, 8
	octave 2
	note A#, 8
	note F_, 8
	octave 3
	note C_, 8
	octave 2
	note A#, 8
	note F_, 8
	octave 3
	note C_, 8
	octave 2
	note A#, 8
	note F_, 8
	octave 3
	note D#, 8
	note C_, 8
	octave 2
	note A#, 8
	octave 3
	note D#, 8
	note C_, 8
	octave 2
	note A#, 8
	octave 3
	note D#, 8
	note C_, 8
	octave 2
	note A#, 8
	octave 3
	note D#, 8
	note C_, 8
	octave 2
	note A#, 8
	octave 3
	note D#, 8
	note C_, 8
	octave 2
	note A#, 8
	note G_, 8
	sound_ret

Music_MewtwoBattle_Sub3:
	note D_, 10
	rest 2
	note D_, 8
	note D_, 14
	rest 2
	note D_, 12
	note D_, 4
	octave 2
	note A_, 4
	octave 3
	note C_, 4
	note D_, 4
	note D#, 10
	rest 2
	note D#, 8
	note D#, 14
	rest 2
	sound_ret

Music_MewtwoBattle_Sub4:
	note D_, 6
	rest 6
	note D_, 6
	rest 6
	note D_, 8
	rest 4
	note D_, 4
	note C_, 4
	note D_, 4
	octave 2
	note A_, 4
	note A_, 12
	note G_, 6
	rest 6
	note G_, 6
	rest 6
	note G_, 8
	rest 4
	note G_, 4
	note F#, 4
	note G_, 4
	octave 3
	note D_, 4
	sound_ret

Music_MewtwoBattle_Sub5:
	note E_, 2
	note D_, 2
	note E_, 2
	note D_, 2
	note E_, 2
	note D_, 2
	note E_, 2
	note D_, 2
	note E_, 2
	note D_, 2
	note E_, 2
	note D_, 2
	note E_, 2
	note D_, 2
	note E_, 2
	note D_, 2
	sound_ret

Music_MewtwoBattle_Sub6:
	note G_, 2
	rest 4
	note D_, 2
	rest 12
	note G_, 2
	rest 2
	note D_, 2
	rest 2
	note G_, 2
	rest 2
	note G#, 2
	rest 16
	rest 14
	note G_, 2
	rest 4
	note D_, 2
	rest 12
	note G_, 2
	rest 2
	note D_, 2
	rest 2
	note G_, 2
	rest 2
	note F_, 2
	rest 16
	rest 14
	note D#, 2
	rest 14
	note A#, 2
	rest 6
	note D#, 2
	rest 6
	note F_, 2
	rest 16
	rest 14
	note D#, 2
	rest 14
	sound_ret

Music_MewtwoBattle_Sub7:
	note A_, 12
	note A_, 12
	note A_, 4
	note A_, 4
	rest 4
	note A_, 4
	octave 3
	note E_, 8
	sound_ret

Music_MewtwoBattle_Sub8:
	note A_, 6
	rest 6
	note A_, 6
	rest 6
	note A_, 8
	rest 4
	note A_, 4
	note G_, 4
	note A_, 4
	octave 3
	note E_, 16
	note D_, 6
	rest 6
	note D_, 6
	rest 6
	note D_, 8
	rest 4
	sound_ret

Music_MewtwoBattle_Sub9:
	note A_, 8
	note G_, 8
	note E_, 8
	note A_, 8
	note G_, 8
	note E_, 8
	note A_, 8
	note G_, 8
	note E_, 8
	note A_, 8
	note G_, 8
	note E_, 8
	note A_, 8
	note G_, 8
	note E_, 8
	sound_ret

Music_MewtwoBattle_Sub10:
	note C_, 12
	octave 4
	note B_, 2
	octave 5
	note C_, 2
	note D_, 6
	octave 4
	note A_, 6
	octave 5
	note D_, 4
	note C_, 12
	octave 4
	note B_, 2
	sound_ret

Music_MewtwoBattle_Sub11:
	octave 3
	note C_, 4
	note F_, 4
	note E_, 4
	note D_, 4
	note C_, 4
	octave 2
	note A#, 12
	note A#, 12
	note A#, 4
	note A#, 4
	rest 4
	note A#, 4
	sound_ret

Music_MewtwoBattle_Sub12:
	note D#, 12
	note D#, 4
	octave 2
	note A#, 4
	octave 3
	note D_, 4
	note D#, 4
	sound_ret

Music_MewtwoBattle_Sub13:
	note D_, 15
	note C_, 3
	note F_, 2
	note D#, 2
	note C_, 2
	note_type 6, 6, 0
	note D_, 10
	rest 1
	sound_ret

Music_MewtwoBattle_Sub14:
	note F_, 8
	octave 3
	note C_, 8
	octave 2
	note A#, 8
	note F_, 8
	octave 3
	note C_, 8
	octave 2
	note A#, 8
	sound_ret

Music_MewtwoBattle_Sub15:
	note D_, 3
	note D#, 3
	note F_, 3
	note G_, 3
	note A_, 3
	note A#, 3
	octave 4
	note C_, 3
	note D_, 3
	sound_ret

Music_MewtwoBattle_Sub16:
	note D#, 3
	note D_, 3
	note C_, 3
	octave 3
	note A#, 3
	sound_ret

Music_MewtwoBattle_Sub17:
	octave 3
	note D_, 4
	note A_, 4
	octave 4
	note D_, 4
	note A_, 4
	sound_ret

Music_MewtwoBattle_Sub18:
	note D_, 1
	note E_, 1
	note F#, 1
	note G_, 1
	note A_, 1
	note B_, 1
	sound_ret

Music_MewtwoBattle_Sub19:
	note A_, 2
	note D_, 2
	note A_, 6
	note G_, 2
	octave 4
	note C_, 6
	sound_ret

Music_MewtwoBattle_Sub20:
	note F_, 12
	note F_, 12
	note F_, 4
	note F_, 4
	rest 4
	sound_ret
