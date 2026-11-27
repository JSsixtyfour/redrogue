; Converted from suicunebattle.asm by the Red Rogue music test kit (native song file).
; kit-engine: crysaudio pokered-crysaudio 9753183a
; Size-optimized by tools/music_kit/song_optimize.py (2026-11-26): same notes, lengths
; and channel state, verified frame by frame with tools/music_kit/song_audio_compare.py.
Music_SuicuneBattle::
	channel_count 3
	channel 1, Music_SuicuneBattle_Ch1
	channel 2, Music_SuicuneBattle_Ch2
	channel 3, Music_SuicuneBattle_Ch3

Music_SuicuneBattle_Ch1::
	tempo 101
	volume 7, 7
	duty_cycle 3
	pitch_offset 2
	vibrato 18, 1, 5
	note_type 3, 11, 7
	octave 4
	note A_, 4
	note G#, 4
	note G_, 16
	note E_, 8
	note D#, 4
	note D_, 4
	note C#, 16
	octave 3
	note A#, 8
	note A_, 4
	note G#, 4
	note G_, 16
	note E_, 8
	note D#, 4
	note D_, 4
	note C#, 16
	octave 2
	note A#, 8
	volume_envelope 11, 2
	note A_, 8
.loop0:
	sound_call Music_SuicuneBattle_Sub6
	sound_loop 3, .loop0
.loop1:
	note A_, 16
	note A_, 8
	note A_, 8
	sound_loop 3, .loop1
	note A_, 8
	note A_, 4
	note B_, 4
	octave 3
	note E_, 4
	note G#, 4
.mainloop:
	note_type 12, 11, 4
	sound_call Music_SuicuneBattle_Sub1
	note G_, 2
	note E_, 2
	octave 2
	note G_, 2
	octave 3
	note E_, 2
	note G_, 2
	note A_, 6
	note G_, 4
	note F_, 4
	note E_, 2
	note D_, 6
	sound_call Music_SuicuneBattle_Sub1
	octave 4
	note C_, 2
	octave 3
	note G_, 2
	note C_, 2
	note A_, 4
	note G_, 2
	note F_, 2
	note A_, 2
	note G_, 2
	note A_, 2
	note C_, 2
	octave 4
	note C_, 4
	octave 3
	note A_, 2
	note G_, 2
	note C_, 2
	sound_call Music_SuicuneBattle_Sub12
	note C_, 2
	octave 2
	note G_, 2
	rest 2
	volume_envelope 11, 6
	octave 3
	note G_, 10
	volume_envelope 11, 3
	note C_, 2
	octave 2
	note G_, 2
	rest 2
	volume_envelope 11, 7
	octave 3
	note G_, 10
	sound_call Music_SuicuneBattle_Sub12
	note G_, 2
	note C_, 2
	octave 4
	note C_, 2
	octave 3
	note G_, 2
	note F#, 2
	octave 2
	note B_, 2
	octave 3
	note B_, 2
	note F#, 2
	note E_, 2
	octave 2
	note A_, 2
	octave 3
	note A_, 2
	note E_, 2
	note C_, 2
	note G_, 2
	octave 4
	note C_, 2
	octave 3
	note G_, 2
	volume_envelope 11, 2
	octave 2
	note B_, 2
	note B_, 6
	note B_, 2
	note B_, 6
	note B_, 2
	note B_, 6
	note B_, 2
	volume_envelope 11, 4
	octave 3
	note C_, 6
	volume_envelope 11, 2
.loop2:
	octave 2
	sound_call Music_SuicuneBattle_Sub9
	sound_loop 3, .loop2
	octave 2
	note B_, 2
	octave 3
	note C_, 2
	octave 2
	note B_, 1
	octave 3
	note F#, 1
	note A_, 1
	octave 4
	note C_, 1
.loop3:
	octave 3
	sound_call Music_SuicuneBattle_Sub9
	sound_loop 3, .loop3
	octave 3
	note B_, 2
	volume_envelope 11, 5
	octave 4
	note C_, 6
.loop4:
	sound_call Music_SuicuneBattle_Sub21
	sound_loop 3, .loop4
	volume_envelope 11, 2
	octave 3
	note B_, 2
	volume_envelope 11, 5
	octave 4
	note C_, 6
	volume_envelope 11, 7
	octave 2
	note B_, 8
	note E_, 8
	octave 3
	note C_, 8
	octave 2
	note A_, 8
	note B_, 8
	note E_, 8
	note F_, 10
	note C_, 2
	note D_, 2
	note C_, 2
	volume_envelope 10, 0
	octave 1
	note F#, 8
	note B_, 8
	note G_, 8
	octave 2
	note C_, 8
	octave 1
	note B_, 8
	note E_, 8
	note F_, 8
	volume_envelope 10, 7
	note F_, 8
	sound_call Music_SuicuneBattle_Sub29
	rest 16
	rest 16
	volume_envelope 11, 2
	rest 4
	octave 3
.loop5:
	note D_, 8
	sound_loop 8, .loop5
.loop6:
	note F_, 8
	sound_loop 7, .loop6
	note F_, 4
	note E_, 8
	sound_call Music_SuicuneBattle_Sub29
	vibrato 8, 2, 4
	duty_cycle 2
	volume_envelope 9, 6
	octave 4
	note E_, 6
	note F#, 6
	octave 3
	note A_, 4
	octave 4
	note A_, 16
	vibrato 18, 1, 5
	duty_cycle 3
	sound_loop 0, .mainloop

Music_SuicuneBattle_Ch2::
	duty_cycle 3
	vibrato 20, 3, 4
	pitch_offset 1
	note_type 6, 12, 3
.loop7:
	sound_call Music_SuicuneBattle_Sub16
	note A_, 4
	sound_loop 3, .loop7
	sound_call Music_SuicuneBattle_Sub16
	note A_, 12
	volume_envelope 12, 2
	sound_call Music_SuicuneBattle_Sub26
	sound_call Music_SuicuneBattle_Sub26
	note E_, 16
	note E_, 16
	note E_, 16
	volume_envelope 12, 3
	note A#, 8
	volume_envelope 12, 2
	note A_, 8
	note E_, 16
	note E_, 16
	note E_, 16
	note E_, 8
.mainloop:
	note_type 8, 12, 7
	octave 3
	note A_, 12
	note B_, 12
	note D_, 12
	volume_envelope 11, 0
	octave 4
	note D_, 12
	volume_envelope 11, 6
	note D_, 12
	vibrato 16, 2, 4
	sound_call Music_SuicuneBattle_Sub11
	volume_envelope 11, 0
	note E_, 15
	volume_envelope 11, 7
	note E_, 9
	volume_envelope 10, 5
	octave 2
	note G_, 6
	note A_, 6
	note G_, 6
	note B_, 6
	volume_envelope 12, 7
	octave 3
	note A_, 12
	note B_, 12
	note D_, 12
	octave 4
	note D_, 12
	volume_envelope 4, -4
	note D_, 6
	volume_envelope 12, 6
	note D_, 6
	vibrato 8, 2, 4
	sound_call Music_SuicuneBattle_Sub11
	volume_envelope 4, -4
	note E_, 12
	volume_envelope 12, 7
	note E_, 12
	volume_envelope 12, 6
	note C_, 12
	note G_, 12
	volume_envelope 12, 2
	octave 3
	sound_call Music_SuicuneBattle_Sub22
	note G_, 3
	note C_, 3
	rest 3
	volume_envelope 12, 7
	octave 4
	note C_, 15
	volume_envelope 12, 3
	note G_, 3
	note C_, 3
	rest 3
	volume_envelope 12, 7
	octave 5
	note C_, 15
	volume_envelope 12, 3
	octave 4
	sound_call Music_SuicuneBattle_Sub22
	volume_envelope 12, 7
	note G_, 12
	note F#, 12
	note E_, 12
	note G_, 12
	volume_envelope 12, 2
	octave 3
	note F#, 3
	note F#, 9
	note F#, 3
	note F#, 9
	note F#, 3
	note F#, 9
	note F#, 3
	volume_envelope 11, 7
	note G_, 9
	volume_envelope 12, 2
.loop8:
	sound_call Music_SuicuneBattle_Sub3
	octave 3
	sound_loop 3, .loop8
	note F#, 3
	volume_envelope 12, 7
	note G_, 9
	volume_envelope 12, 2
.loop9:
	octave 4
	sound_call Music_SuicuneBattle_Sub3
	sound_loop 3, .loop9
	octave 4
	note F#, 3
	volume_envelope 12, 7
	note G_, 9
	volume_envelope 12, 2
.loop10:
	sound_call Music_SuicuneBattle_Sub3
	octave 4
	sound_loop 3, .loop10
	note F#, 3
	volume_envelope 12, 7
	note G_, 9
	volume_envelope 11, 0
	octave 3
	note F#, 12
	octave 2
	note B_, 12
	octave 3
	note G_, 12
	note E_, 12
	note F#, 12
	octave 2
	note B_, 12
	octave 3
	note C_, 12
	volume_envelope 11, 7
	note C_, 12
	volume_envelope 12, 7
	octave 1
	note B_, 12
	octave 2
	note E_, 12
	note C_, 12
	note F_, 12
	note E_, 12
	octave 1
	note B_, 12
	volume_envelope 11, 0
	octave 2
	note C_, 15
	volume_envelope 11, 7
	note C_, 9
	volume_envelope 12, 3
	sound_call Music_SuicuneBattle_Sub13
	sound_call Music_SuicuneBattle_Sub13
	sound_call Music_SuicuneBattle_Sub14
	octave 2
	sound_call Music_SuicuneBattle_Sub14
	sound_call Music_SuicuneBattle_Sub17
	sound_call Music_SuicuneBattle_Sub17
	sound_call Music_SuicuneBattle_Sub15
	octave 3
	sound_call Music_SuicuneBattle_Sub15
	sound_call Music_SuicuneBattle_Sub18
	sound_call Music_SuicuneBattle_Sub18
	volume_envelope 12, 2
	note A_, 12
	volume_envelope 12, 3
	octave 2
	sound_call Music_SuicuneBattle_Sub2
	sound_call Music_SuicuneBattle_Sub2
	octave 3
	sound_call Music_SuicuneBattle_Sub19
	sound_call Music_SuicuneBattle_Sub19
	octave 2
	sound_call Music_SuicuneBattle_Sub2
	sound_call Music_SuicuneBattle_Sub2
	sound_loop 0, .mainloop

Music_SuicuneBattle_Ch3::
	note_type 12, 1, 8
	rest 16
	rest 4
	octave 2
	note A_, 4
	note D_, 2
	note E_, 2
	note A#, 2
	note G_, 2
	sound_call Music_SuicuneBattle_Sub5
	sound_call Music_SuicuneBattle_Sub5
.mainloop:
	note_type 12, 1, 6
	sound_call Music_SuicuneBattle_Sub0
	sound_call Music_SuicuneBattle_Sub20
	note C_, 2
	note G_, 2
	note C_, 2
	note G_, 2
	note C_, 2
	note G_, 2
	note C_, 2
	sound_call Music_SuicuneBattle_Sub27
	note C_, 2
	note G_, 2
	note C_, 2
	octave 3
	note C_, 4
	octave 2
	note G_, 2
	note F_, 2
	note D_, 2
	sound_call Music_SuicuneBattle_Sub0
	sound_call Music_SuicuneBattle_Sub20
.loop11:
	sound_call Music_SuicuneBattle_Sub27
	octave 3
	note C_, 2
	octave 2
	sound_loop 2, .loop11
	note G_, 2
	octave 3
	note C_, 2
	octave 2
	note C_, 2
	note G_, 2
	note C_, 2
	octave 3
	note C_, 4
	octave 2
	note G_, 2
	note C_, 2
	note G_, 2
	sound_call Music_SuicuneBattle_Sub23
	sound_call Music_SuicuneBattle_Sub23
	note C_, 2
	sound_call Music_SuicuneBattle_Sub27
	note C_, 2
	note G_, 2
	note C_, 2
	note G_, 2
	note C_, 2
	note G_, 2
	octave 3
	note C_, 2
	octave 2
	note G_, 4
	note C_, 2
	octave 3
	note C_, 2
	octave 2
	note G_, 2
	sound_call Music_SuicuneBattle_Sub30
	sound_call Music_SuicuneBattle_Sub30
	note C_, 2
	sound_call Music_SuicuneBattle_Sub27
	octave 1
	note B_, 2
	octave 2
	note F#, 2
	octave 1
	note B_, 2
	octave 2
	note F#, 2
	octave 1
	note A_, 2
	octave 2
	note E_, 2
	note A_, 2
	note E_, 2
	note C_, 2
	note G_, 2
	note C_, 2
	note G_, 2
	sound_call Music_SuicuneBattle_Sub28
	sound_call Music_SuicuneBattle_Sub28
.loop12:
	note B_, 2
	note B_, 2
	octave 1
	note B_, 4
	octave 2
	sound_loop 3, .loop12
	note B_, 2
	octave 3
	note C_, 6
.loop13:
	note F#, 2
	note F#, 2
	octave 1
	note B_, 4
	octave 3
	sound_loop 3, .loop13
	note F#, 2
	note G_, 6
	octave 2
	note F#, 8
	octave 1
	note B_, 8
	octave 2
	note G_, 8
	note E_, 8
	note F#, 8
	octave 1
	note B_, 8
	octave 2
	note C_, 10
	note C_, 2
	note D_, 2
	note C_, 2
	octave 1
	note B_, 8
	octave 2
	note E_, 8
	note C_, 8
	note F_, 8
	note E_, 8
	octave 1
	note B_, 8
	octave 2
	note C_, 16
	rest 4
	octave 1
	sound_call Music_SuicuneBattle_Sub31
	rest 4
	sound_call Music_SuicuneBattle_Sub31
.loop14:
	sound_call Music_SuicuneBattle_Sub4
	octave 1
	sound_loop 3, .loop14
	note B_, 2
	octave 2
	note F_, 2
	note B_, 2
	note F_, 2
	note B_, 2
	note F_, 2
	octave 1
	note B_, 2
	octave 2
	note F_, 2
	sound_call Music_SuicuneBattle_Sub7
	note D_, 2
	note G#, 2
	octave 3
	note D_, 2
	octave 2
	note D_, 2
	note G#, 2
	sound_call Music_SuicuneBattle_Sub7
	note G#, 2
	octave 3
	note D_, 2
	octave 2
	note G#, 2
	note D_, 2
	note G#, 2
	sound_call Music_SuicuneBattle_Sub25
	sound_call Music_SuicuneBattle_Sub25
	octave 1
	sound_call Music_SuicuneBattle_Sub4
	octave 1
	sound_call Music_SuicuneBattle_Sub4
	sound_call Music_SuicuneBattle_Sub24
	sound_call Music_SuicuneBattle_Sub24
	sound_call Music_SuicuneBattle_Sub7
	note G#, 2
	octave 3
	note D_, 2
	octave 2
	note G#, 2
	note D_, 2
	note G#, 2
	note A_, 4
	rest 4
	sound_call Music_SuicuneBattle_Sub0
	note D_, 2
	octave 1
	note A_, 2
	octave 2
	note D_, 2
.loop15:
	sound_call Music_SuicuneBattle_Sub8
	sound_loop 4, .loop15
.loop16:
	sound_call Music_SuicuneBattle_Sub10
	sound_loop 3, .loop16
	octave 1
	note A_, 2
	octave 2
	note E_, 2
	octave 1
	note A_, 2
	octave 2
	note A_, 4
	note E_, 2
	note D_, 2
	note E_, 2
	sound_loop 0, .mainloop

Music_SuicuneBattle_Sub0:
	octave 1
	note A_, 2
	octave 2
	note D_, 2
	octave 1
	note A_, 2
	octave 2
	note D_, 2
	octave 1
	note A_, 2
	octave 2
	note A_, 2
	octave 1
	note A_, 2
	octave 2
	note D_, 2
	octave 1
	note A_, 2
	octave 2
	note D_, 2
	octave 1
	note A_, 2
	octave 2
	note D_, 2
	octave 1
	note A_, 2
	octave 2
	note A_, 2
	octave 1
	note A_, 2
	octave 2
	note D_, 2
	octave 1
	note A_, 2
	octave 2
	note D_, 2
	octave 1
	note A_, 2
	octave 2
	note D_, 2
	octave 1
	note A_, 2
	octave 2
	note D_, 2
	note A_, 2
	note D_, 2
	octave 1
	note A_, 2
	octave 2
	note D_, 2
	octave 1
	note A_, 2
	octave 2
	note D_, 2
	octave 1
	note A_, 2
	octave 2
	sound_ret

Music_SuicuneBattle_Sub1:
	octave 2
	note A_, 2
	note B_, 2
	note E_, 2
	octave 3
	note E_, 4
	octave 2
	note B_, 2
	note A_, 2
	note E_, 2
	note D_, 2
	note E_, 2
	note D_, 2
	note A_, 4
	note E_, 2
	note D_, 2
	note E_, 2
	octave 3
	note D_, 2
	octave 2
	note A_, 2
	octave 3
	note D_, 2
	note E_, 2
	note A_, 2
	note E_, 2
	note D_, 2
	octave 2
	note A_, 2
	octave 3
	note D_, 2
	note E_, 2
	note A_, 2
	note E_, 2
	note D_, 2
	octave 2
	note A_, 2
	octave 3
	note D_, 2
	note E_, 2
	note C_, 2
	note D_, 2
	octave 2
	note G_, 2
	octave 3
	note G_, 4
	note D_, 2
	note C_, 2
	octave 2
	note G_, 2
	octave 3
	note C_, 2
	note D_, 2
	octave 2
	note G_, 2
	octave 3
	note F_, 4
	note E_, 2
	note D_, 2
	note F_, 2
	sound_ret

Music_SuicuneBattle_Sub2:
	note A_, 3
	note B_, 3
	note E_, 3
	octave 3
	note E_, 6
	octave 2
	note B_, 3
	note A_, 3
	note E_, 3
	note A_, 3
	note B_, 3
	octave 3
	note E_, 3
	octave 2
	note B_, 3
	note A_, 3
	note E_, 3
	note A_, 3
	note B_, 3
	sound_ret

Music_SuicuneBattle_Sub3:
	note F#, 3
	note F#, 3
	volume_envelope 12, 7
	octave 1
	note B_, 6
	volume_envelope 12, 2
	sound_ret

Music_SuicuneBattle_Sub4:
	note B_, 2
	octave 2
	note F_, 2
	note B_, 2
	octave 1
	note B_, 2
	octave 2
	note F_, 2
	note B_, 2
	octave 1
	note B_, 2
	octave 2
	note F_, 2
	sound_ret

Music_SuicuneBattle_Sub5:
	note D_, 2
	note E_, 2
	octave 1
	note A_, 2
	octave 2
	note A_, 4
	note E_, 2
	note D_, 2
	octave 1
	note A_, 2
	octave 2
	note D_, 2
	note E_, 2
	note A_, 2
	note E_, 2
	note D_, 2
	octave 1
	note A_, 2
	octave 2
	note D_, 2
	note E_, 2
	note D_, 2
	note E_, 2
	octave 1
	note A_, 2
	octave 2
	note A_, 4
	note E_, 2
	note D_, 2
	octave 1
	note A_, 2
	octave 2
	note D_, 2
	note E_, 2
	note A_, 4
	note E_, 2
	octave 1
	note A_, 2
	octave 2
	note D_, 2
	note E_, 2
	sound_ret

Music_SuicuneBattle_Sub6:
	note A_, 16
	note A_, 8
	note A_, 8
	note A_, 16
	note A_, 8
	note A_, 8
	note A_, 16
	note A_, 8
	note A_, 8
	note A_, 8
	volume_envelope 11, 3
	octave 4
	note F_, 16
	note E_, 8
	volume_envelope 11, 2
	octave 2
	sound_ret

Music_SuicuneBattle_Sub7:
	note D_, 2
	note G#, 2
	octave 3
	note D_, 2
	octave 2
	note D_, 2
	note G#, 2
	octave 3
	note D_, 2
	octave 2
	note D_, 2
	note G#, 2
	note D_, 2
	note G#, 2
	octave 3
	note D_, 2
	octave 2
	sound_ret

Music_SuicuneBattle_Sub8:
	note C_, 2
	note G_, 2
	octave 3
	note C_, 2
	octave 2
	note C_, 2
	note G_, 2
	octave 3
	note C_, 2
	octave 2
	note C_, 2
	note G_, 2
	sound_ret

Music_SuicuneBattle_Sub9:
	note B_, 2
	note B_, 2
	volume_envelope 11, 5
	octave 1
	note F#, 4
	volume_envelope 11, 2
	sound_ret

Music_SuicuneBattle_Sub10:
	octave 1
	note A_, 2
	octave 2
	note E_, 2
	note A_, 2
	octave 1
	note A_, 2
	octave 2
	note E_, 2
	note A_, 2
	octave 1
	note A_, 2
	octave 2
	note E_, 2
	sound_ret

Music_SuicuneBattle_Sub11:
	duty_cycle 2
	volume_envelope 10, 4
	octave 5
	note A_, 9
	note B_, 9
	note D_, 6
	octave 6
	note D_, 12
	vibrato 20, 3, 4
	duty_cycle 3
	volume_envelope 12, 7
	octave 4
	note C_, 12
	note D_, 12
	octave 3
	note G_, 12
	octave 4
	note F_, 12
	sound_ret

Music_SuicuneBattle_Sub12:
	volume_envelope 11, 3
	octave 2
	note B_, 2
	octave 3
	note C_, 2
	rest 2
	note E_, 4
	note D_, 2
	note C_, 2
	octave 2
	note B_, 2
	note B_, 2
	octave 3
	note C_, 2
	note E_, 2
	note D_, 2
	note C_, 2
	octave 2
	note B_, 2
	note A_, 2
	note B_, 2
	octave 3
	sound_ret

Music_SuicuneBattle_Sub13:
	octave 1
	note B_, 3
	octave 2
	note E_, 3
	octave 1
	note F_, 3
	octave 2
	note F_, 6
	note E_, 3
	octave 1
	note B_, 3
	note F_, 3
	note B_, 3
	octave 2
	note E_, 3
	note F_, 3
	note E_, 3
	octave 1
	note B_, 3
	note F_, 3
	note B_, 3
	octave 2
	note E_, 3
	sound_ret

Music_SuicuneBattle_Sub14:
	note B_, 3
	octave 3
	note E_, 3
	octave 2
	note F_, 3
	octave 3
	note F_, 6
	note E_, 3
	octave 2
	note B_, 3
	note F_, 3
	note B_, 3
	octave 3
	note E_, 3
	note F_, 3
	note E_, 3
	octave 2
	note B_, 3
	note F_, 3
	note B_, 3
	octave 3
	note E_, 3
	sound_ret

Music_SuicuneBattle_Sub15:
	note B_, 3
	octave 4
	note E_, 3
	octave 3
	note F_, 3
	octave 4
	note F_, 6
	note E_, 3
	octave 3
	note B_, 3
	note F_, 3
	note B_, 3
	octave 4
	note E_, 3
	note F_, 3
	note E_, 3
	octave 3
	note B_, 3
	note F_, 3
	note B_, 3
	octave 4
	note E_, 3
	sound_ret

Music_SuicuneBattle_Sub16:
	octave 5
	note E_, 2
	octave 4
	note E_, 2
	note A_, 4
	octave 5
	note E_, 2
	octave 4
	note E_, 2
	sound_ret

Music_SuicuneBattle_Sub17:
	note D_, 3
	note G_, 3
	octave 2
	note G#, 3
	octave 3
	note G#, 6
	note G_, 3
	note D_, 3
	octave 2
	note G#, 3
	octave 3
	note D_, 3
	note G_, 3
	note G#, 3
	note G_, 3
	note D_, 3
	octave 2
	note G#, 3
	octave 3
	note D_, 3
	note G_, 3
	sound_ret

Music_SuicuneBattle_Sub18:
	note D_, 3
	note G_, 3
	octave 3
	note G#, 3
	octave 4
	note G#, 6
	note G_, 3
	note D_, 3
	octave 3
	note G#, 3
	octave 4
	note D_, 3
	note G_, 3
	note G#, 3
	note G_, 3
	note D_, 3
	octave 3
	note G#, 3
	octave 4
	note D_, 3
	note G_, 3
	sound_ret

Music_SuicuneBattle_Sub19:
	note C_, 3
	note D_, 3
	octave 2
	note G_, 3
	octave 3
	note G_, 6
	note D_, 3
	note C_, 3
	octave 2
	note G_, 3
	octave 3
	note C_, 3
	note D_, 3
	note G_, 3
	note D_, 3
	note C_, 3
	octave 2
	note G_, 3
	octave 3
	note C_, 3
	note D_, 3
	sound_ret

Music_SuicuneBattle_Sub20:
	note A_, 2
	note D_, 2
	note A_, 2
	note C_, 2
	note G_, 2
	note C_, 2
	note G_, 2
	note C_, 2
	octave 3
	note C_, 2
	octave 2
	note C_, 2
	note G_, 2
	note C_, 2
	note G_, 2
	note C_, 2
	note G_, 2
	note C_, 2
	octave 3
	note C_, 2
	octave 2
	sound_ret

Music_SuicuneBattle_Sub21:
	volume_envelope 11, 2
	octave 3
	note B_, 2
	note B_, 2
	volume_envelope 11, 4
	octave 1
	note F#, 4
	sound_ret

Music_SuicuneBattle_Sub22:
	note F#, 3
	note G_, 3
	rest 3
	note B_, 6
	note A_, 3
	note G_, 3
	note F#, 3
	note F#, 3
	note G_, 3
	note B_, 3
	note A_, 3
	note G_, 3
	note F#, 3
	note E_, 3
	note F#, 3
	sound_ret

Music_SuicuneBattle_Sub23:
	octave 1
	note B_, 2
	octave 2
	note F#, 2
	note B_, 2
	note F#, 2
	octave 1
	note B_, 2
	octave 2
	note F#, 2
	octave 1
	note B_, 2
	octave 2
	note F#, 2
	sound_ret

Music_SuicuneBattle_Sub24:
	octave 3
	note D_, 2
	octave 2
	note G#, 2
	note D_, 2
	octave 3
	note D_, 2
	octave 2
	note G#, 2
	note D_, 2
	octave 3
	note D_, 2
	octave 2
	note G#, 2
	sound_ret

Music_SuicuneBattle_Sub25:
	note B_, 2
	note F_, 2
	octave 1
	note B_, 2
	octave 2
	note B_, 2
	note F_, 2
	octave 1
	note B_, 2
	octave 2
	note B_, 2
	note F_, 2
	sound_ret

Music_SuicuneBattle_Sub26:
	octave 2
	note E_, 16
	note E_, 16
	note E_, 16
	volume_envelope 12, 3
	octave 4
	note A#, 8
	volume_envelope 12, 2
	note A_, 8
	sound_ret

Music_SuicuneBattle_Sub27:
	note G_, 2
	octave 3
	note C_, 2
	octave 2
	note G_, 2
	sound_ret

Music_SuicuneBattle_Sub28:
	note F#, 2
	note F#, 2
	rest 4
	note F#, 2
	note F#, 2
	rest 4
	note F#, 2
	note F#, 2
	rest 4
	note F#, 2
	note G_, 6
	sound_ret

Music_SuicuneBattle_Sub29:
	rest 16
	rest 16
	rest 16
	rest 16
	rest 16
	rest 16
	rest 16
	rest 16
	rest 16
	rest 16
	sound_ret

Music_SuicuneBattle_Sub30:
	note D_, 2
	note A_, 2
	octave 3
	note D_, 2
	octave 2
	note A_, 2
	note D_, 2
	note A_, 2
	note D_, 2
	note A_, 2
	sound_ret

Music_SuicuneBattle_Sub31:
	note B_, 2
	rest 6
	note B_, 2
	rest 2
	rest 4
	note B_, 2
	rest 6
	note B_, 2
	rest 2
	sound_ret
