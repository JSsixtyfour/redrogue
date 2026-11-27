; Converted from rocketbattle.asm by the Red Rogue music test kit (native song file).
; kit-engine: crysaudio pokered-crysaudio 9753183a
; Size-optimized by tools/music_kit/song_optimize.py (2026-11-26): same notes, lengths
; and channel state, verified frame by frame with tools/music_kit/song_audio_compare.py.
Music_RocketBattle::
	channel_count 3
	channel 1, Music_RocketBattle_Ch1
	channel 2, Music_RocketBattle_Ch2
	channel 3, Music_RocketBattle_Ch3

Music_RocketBattle_Ch1::
	tempo 101
	volume 7, 7
	duty_cycle 3
	pitch_offset 2
	vibrato 16, 1, 5
	note_type 6, 11, 2
	octave 4
	note E_, 2
	note D#, 2
	note D_, 2
	note C#, 2
	note D_, 2
	note C#, 2
	note C_, 2
	octave 3
	note B_, 2
	octave 4
	note C_, 2
	octave 3
	note B_, 2
	note A#, 2
	note A_, 2
	note A#, 2
	note A_, 2
	note G#, 2
	note G_, 2
	note G#, 2
	note G_, 2
	note F#, 2
	note F_, 2
	note F#, 2
	note F_, 2
	note E_, 2
	note D#, 2
	note E_, 2
	note D#, 2
	note D_, 2
	note C#, 2
	note D_, 2
	note C#, 2
	note C_, 2
	octave 2
	note B_, 2
	octave 3
.loop0:
	sound_call Music_RocketBattle_Sub10
	sound_loop 3, .loop0
	note C_, 12
	note C_, 12
	volume_envelope 11, 7
	note D_, 8
	volume_envelope 11, 2
	octave 4
.loop1:
	sound_call Music_RocketBattle_Sub11
	sound_loop 3, .loop1
	note E_, 12
	note E_, 8
	volume_envelope 11, 7
	note D_, 4
	note D#, 8
	volume_envelope 11, 3
	note C_, 4
	octave 3
	note E_, 4
	note E_, 4
	note A#, 4
	note F_, 4
	note F_, 4
	note A_, 4
	note D_, 4
	note D_, 4
	octave 4
	note C_, 4
	octave 3
	note E_, 4
	note E_, 4
	note A_, 4
	sound_call Music_RocketBattle_Sub12
	note D#, 4
	sound_call Music_RocketBattle_Sub15
.mainloop:
	note_type 6, 11, 3
	sound_call Music_RocketBattle_Sub18
	note F_, 4
	note F_, 4
	octave 4
	note C_, 4
	octave 3
	note D_, 4
	note D_, 4
	sound_call Music_RocketBattle_Sub18
	sound_call Music_RocketBattle_Sub12
	octave 4
	note C_, 4
	note D_, 4
	note C_, 4
	note D_, 4
	volume_envelope 11, 5
	note F_, 8
	volume_envelope 11, 2
	octave 3
	note F_, 4
	note G_, 4
	note G#, 8
	volume_envelope 11, 5
	note D_, 8
	note C_, 8
	note D_, 8
	note E_, 4
	volume_envelope 11, 2
	note F_, 4
	note A_, 8
	volume_envelope 11, 7
	note A_, 8
	volume_envelope 11, 5
	note A_, 4
	note G_, 4
	note F_, 8
	note D_, 8
	note C_, 8
	note D_, 8
	note E_, 4
	note F_, 4
	note E_, 4
	note D_, 4
	note C_, 4
	note A#, 4
	note G_, 4
	note A_, 4
	note A#, 4
	volume_envelope 11, 7
	octave 4
	note E_, 12
	note D_, 8
	octave 3
	note G_, 4
	note A#, 8
	note A_, 12
	note G_, 8
	note E_, 4
	note F_, 8
	note E_, 12
	note D_, 12
	note D#, 8
	volume_envelope 10, 0
	note E_, 16
	volume_envelope 10, 7
	note E_, 16
	volume_envelope 11, 7
	octave 2
	note A_, 16
	note G_, 16
	note A_, 16
	note A#, 16
	note A_, 16
	note G_, 16
	note A_, 16
	octave 3
	note C#, 16
	note D_, 16
	note C#, 16
	octave 2
	note A#, 16
	note A_, 16
	octave 3
	note D_, 16
	note C#, 16
	note D_, 16
	note E_, 16
	octave 2
	note A#, 12
	octave 3
	note D_, 12
	note C_, 8
	volume_envelope 11, 5
	octave 2
	note A#, 4
	octave 3
	note C_, 4
	note D_, 4
	note E_, 4
	note F_, 4
	note G_, 4
	note A_, 4
	note A#, 4
	note A_, 4
	note E_, 4
	note A_, 4
	note A#, 4
	note A_, 4
	note E_, 4
	note D_, 4
	note E_, 4
	note A_, 4
	note E_, 4
	note A_, 4
	octave 4
	note C#, 4
	note D_, 4
	note C#, 4
	octave 3
	note A#, 4
	note G_, 4
	volume_envelope 11, 2
	note E_, 12
	note E_, 12
	note E_, 8
	sound_call Music_RocketBattle_Sub19
	sound_call Music_RocketBattle_Sub19
	note E_, 12
	octave 4
	note D_, 2
	note D#, 2
	volume_envelope 10, 0
	note E_, 16
	volume_envelope 11, 2
	octave 3
	note F_, 12
	note F_, 8
	volume_envelope 11, 7
	note A#, 4
	sound_call Music_RocketBattle_Sub20
	sound_call Music_RocketBattle_Sub20
	note G_, 8
	volume_envelope 11, 2
	note F_, 12
	octave 4
	note D_, 2
	note E_, 2
	volume_envelope 10, 0
	note F_, 16
	volume_envelope 11, 3
	note D_, 4
	octave 3
	note A_, 4
	note E_, 4
	note A_, 8
	note A_, 4
	volume_envelope 11, 7
	octave 4
	note D_, 8
	volume_envelope 11, 3
	note D#, 4
	octave 3
	note A#, 4
	note G_, 4
	note A#, 8
	note A#, 4
	volume_envelope 11, 7
	octave 4
	note D_, 8
	volume_envelope 11, 3
	note E_, 4
	note C_, 4
	octave 3
	note A_, 4
	octave 4
	note C_, 8
	note C_, 4
	volume_envelope 11, 7
	note D#, 8
	volume_envelope 10, 0
	note E_, 8
	volume_envelope 10, 7
	note E_, 12
	volume_envelope 10, 0
	octave 3
	note G#, 12
	volume_envelope 11, 3
	note C_, 4
	note E_, 4
	note E_, 4
	octave 2
	note A#, 4
	octave 3
	note F_, 4
	note F_, 4
	octave 2
	note A_, 4
	octave 3
	note D_, 4
	note D_, 4
	note C_, 4
	note E_, 4
	note E_, 4
	octave 2
	note A_, 4
	octave 3
	note E_, 4
	note D_, 4
	note C_, 4
	note C_, 4
	octave 2
	note A#, 4
	octave 3
	note C_, 4
	volume_envelope 11, 5
	note D_, 8
	volume_envelope 11, 3
	note D_, 4
	note C_, 4
	octave 2
	note A#, 4
	octave 3
	sound_call Music_RocketBattle_Sub15
	sound_loop 0, .mainloop

Music_RocketBattle_Ch2::
	duty_cycle 3
	vibrato 8, 3, 6
	pitch_offset 1
	note_type 12, 11, 2
	octave 4
	note A_, 4
	note A#, 4
	note B_, 4
	octave 5
	note C_, 1
	volume_envelope 8, 2
	sound_call Music_RocketBattle_Sub9
	note C#, 1
	volume_envelope 9, 2
	sound_call Music_RocketBattle_Sub9
	note D_, 1
	volume_envelope 10, 2
	sound_call Music_RocketBattle_Sub9
	note D#, 1
	volume_envelope 11, 2
	sound_call Music_RocketBattle_Sub9
	note E_, 1
	octave 4
	note G#, 1
	note A_, 1
	note G#, 1
	octave 3
.loop2:
	sound_call Music_RocketBattle_Sub6
	sound_loop 3, .loop2
	note A_, 6
	note A_, 6
	volume_envelope 4, -2
	note G#, 4
	volume_envelope 12, 2
	octave 4
.loop3:
	sound_call Music_RocketBattle_Sub7
	sound_loop 3, .loop3
	note A_, 6
	note A_, 4
	volume_envelope 12, 7
	note G_, 2
	note G#, 4
	volume_envelope 12, 6
	sound_call Music_RocketBattle_Sub13
	note F_, 16
	volume_envelope 11, 7
	note F_, 16
.mainloop:
	note_type 12, 12, 6
	octave 4
	sound_call Music_RocketBattle_Sub13
	note F_, 8
	volume_envelope 11, 7
	note F_, 8
	volume_envelope 11, 0
	note A#, 8
	volume_envelope 11, 7
	note A#, 8
	volume_envelope 12, 4
	octave 3
	note A_, 2
	note G_, 2
	note A_, 2
	volume_envelope 12, 7
	octave 4
	note C_, 4
	octave 3
	note A#, 2
	note A_, 2
	note G_, 2
	volume_envelope 12, 2
	note A_, 2
	octave 4
	note C_, 4
	volume_envelope 11, 0
	note C_, 6
	volume_envelope 11, 7
	note C_, 4
	volume_envelope 12, 4
	octave 3
	note A#, 2
	note A_, 2
	note A#, 2
	volume_envelope 12, 7
	octave 4
	note D_, 4
	note C_, 2
	octave 3
	note A#, 2
	note A_, 2
	volume_envelope 12, 2
	note A#, 2
	octave 4
	note D_, 4
	volume_envelope 11, 0
	note D_, 4
	volume_envelope 11, 7
	note D_, 6
	volume_envelope 4, -7
	note A_, 6
	volume_envelope 10, 0
	note G_, 6
	note F_, 4
	note E_, 6
	note F_, 6
	note G_, 4
	note A_, 6
	note A#, 6
	note G#, 4
	note A_, 6
	volume_envelope 10, 7
	note A_, 10
	volume_envelope 3, -7
	octave 3
	note D_, 8
	volume_envelope 11, 7
	note D_, 8
	volume_envelope 3, -7
	note C#, 8
	volume_envelope 11, 7
	note C#, 8
	volume_envelope 3, -7
	note D_, 8
	volume_envelope 11, 7
	note D_, 8
	volume_envelope 3, -7
	note E_, 8
	volume_envelope 11, 7
	note E_, 8
	volume_envelope 4, -6
	note F_, 8
	volume_envelope 10, 0
	note F_, 8
	note E_, 16
	note F_, 16
	note A_, 16
	volume_envelope 3, -7
	note F_, 16
	volume_envelope 12, 7
	octave 4
	note D_, 8
	note C#, 8
	volume_envelope 11, 0
	note E_, 8
	volume_envelope 11, 7
	note E_, 8
	volume_envelope 3, -4
	note A_, 6
	volume_envelope 12, 7
	note A_, 10
	volume_envelope 12, 2
	octave 3
	note A_, 6
	note A_, 6
	note A_, 4
	sound_call Music_RocketBattle_Sub16
	sound_call Music_RocketBattle_Sub16
	note A_, 6
	volume_envelope 12, 7
	octave 4
	note G_, 1
	note G#, 1
	note A_, 8
.loop4:
	sound_call Music_RocketBattle_Sub8
	sound_loop 3, .loop4
	volume_envelope 12, 2
	octave 3
	note A#, 6
	volume_envelope 12, 7
	octave 4
	note G_, 1
	note A_, 1
	note A#, 8
	note A_, 6
	note G_, 6
	note A_, 4
	note A#, 6
	octave 5
	note D_, 6
	octave 4
	note A#, 4
	note A_, 6
	note G_, 6
	volume_envelope 12, 5
	note A_, 4
	volume_envelope 11, 0
	note A_, 8
	volume_envelope 11, 7
	note A_, 8
	volume_envelope 12, 6
	octave 3
	sound_call Music_RocketBattle_Sub13
	note F_, 8
	volume_envelope 11, 7
	note F_, 8
	volume_envelope 3, -5
	note A#, 8
	volume_envelope 12, 7
	note A#, 8
	sound_loop 0, .mainloop

Music_RocketBattle_Ch3::
	note_type 2, 1, 9
	octave 3
	note A_, 12
	octave 4
	note E_, 12
	octave 3
	note G#, 12
	octave 4
	note E_, 12
	octave 3
	note G_, 12
	octave 4
	note E_, 12
	octave 3
	note F#, 12
	octave 4
	note E_, 12
	octave 3
	note F_, 12
	octave 4
	note E_, 12
	octave 3
	note E_, 12
	octave 4
	note E_, 12
	octave 2
	note B_, 12
	octave 3
	note C_, 12
	octave 2
	note B_, 12
	note A#, 12
.loop5:
	sound_call Music_RocketBattle_Sub3
	sound_loop 3, .loop5
	sound_call Music_RocketBattle_Sub21
	note F_, 12
	note E_, 12
	note D_, 12
	octave 2
.loop6:
	sound_call Music_RocketBattle_Sub3
	sound_loop 3, .loop6
	sound_call Music_RocketBattle_Sub21
	octave 2
	note G_, 12
	note A_, 12
	note A#, 12
	sound_call Music_RocketBattle_Sub14
	note E_, 12
	octave 2
	sound_call Music_RocketBattle_Sub14
	note D_, 12
.loop7:
	octave 2
	note A#, 12
	octave 3
	note F_, 12
	note A#, 12
	sound_loop 2, .loop7
	octave 2
	note A#, 12
	octave 3
	note F_, 12
	octave 2
	note A#, 12
	octave 3
	note F_, 12
	note A#, 12
	note F_, 12
	note A#, 12
	note F_, 12
	octave 2
	note A#, 12
	octave 3
	note F_, 12
.mainloop:
	note_type 3, 1, 9
	sound_call Music_RocketBattle_Sub0
	note D#, 8
	note E_, 8
	sound_call Music_RocketBattle_Sub0
	note D#, 8
	note D_, 8
	sound_call Music_RocketBattle_Sub4
	note A#, 8
	octave 2
	note A#, 8
	octave 3
	sound_call Music_RocketBattle_Sub17
	octave 2
	note A#, 8
	octave 3
	note F_, 8
	note E_, 8
	note D_, 8
	sound_call Music_RocketBattle_Sub0
	octave 2
	note A_, 8
	octave 3
	note E_, 8
	sound_call Music_RocketBattle_Sub5
	note E_, 8
	sound_call Music_RocketBattle_Sub2
	note A#, 8
	octave 2
	note A#, 8
	octave 3
	note F_, 8
	note A#, 8
	octave 2
	note A#, 8
	octave 3
	note A#, 8
	sound_call Music_RocketBattle_Sub0
	sound_call Music_RocketBattle_Sub0
	octave 2
	note A_, 8
	octave 3
	note F_, 8
	note E_, 8
	note D_, 8
.loop8:
	sound_call Music_RocketBattle_Sub0
	sound_loop 3, .loop8
.loop9:
	sound_call Music_RocketBattle_Sub1
	sound_loop 7, .loop9
	note D_, 8
	octave 2
	note A#, 8
	note A_, 8
	octave 3
	note A_, 8
	note G_, 8
	note F_, 8
	sound_call Music_RocketBattle_Sub2
	note G_, 8
	note F_, 8
	note E_, 8
	note D_, 8
	note C#, 8
	note D_, 8
.loop10:
	sound_call Music_RocketBattle_Sub0
	sound_loop 4, .loop10
	octave 2
	note A_, 8
	octave 3
	note E_, 8
	octave 2
	note A_, 8
	octave 3
	note E_, 16
	note D_, 8
	note C_, 8
	octave 2
	note A#, 8
	note A_, 8
	octave 3
	note E_, 8
	sound_call Music_RocketBattle_Sub0
	octave 2
	note A_, 8
	octave 4
	note D_, 8
	octave 3
	note A_, 8
	note A#, 16
	note A_, 8
	note G_, 8
	note A#, 8
	sound_call Music_RocketBattle_Sub2
	octave 2
	note A#, 8
	octave 3
	sound_call Music_RocketBattle_Sub17
	note E_, 8
	note F_, 8
	sound_call Music_RocketBattle_Sub2
	note A#, 8
	octave 4
	note D_, 16
	note C_, 8
	octave 3
	note A#, 8
	note G_, 8
	sound_call Music_RocketBattle_Sub5
	note E_, 8
	sound_call Music_RocketBattle_Sub4
	note F_, 8
	sound_call Music_RocketBattle_Sub5
	note A_, 8
	sound_call Music_RocketBattle_Sub0
	sound_call Music_RocketBattle_Sub0
	octave 2
	note A_, 8
	octave 3
	note E_, 8
	note D#, 8
	note E_, 8
	sound_call Music_RocketBattle_Sub0
	note D#, 8
	note D_, 8
	sound_call Music_RocketBattle_Sub4
	sound_call Music_RocketBattle_Sub17
	note A#, 8
	note F_, 8
	note A#, 8
	sound_call Music_RocketBattle_Sub17
	sound_loop 0, .mainloop

Music_RocketBattle_Sub0:
	octave 2
	note A_, 8
	octave 3
	note E_, 8
	octave 2
	note A_, 8
	octave 3
	note E_, 8
	octave 2
	note A_, 8
	octave 3
	note E_, 8
	sound_ret

Music_RocketBattle_Sub1:
	note D_, 8
	octave 2
	note A#, 8
	note A_, 8
	octave 3
	note D_, 8
	note G_, 8
	note F_, 8
	octave 2
	note A_, 8
	octave 3
	note E_, 8
	sound_ret

Music_RocketBattle_Sub2:
	octave 2
	note A#, 8
	octave 3
	note F_, 8
	octave 2
	note A#, 8
	octave 3
	note F_, 8
	octave 2
	note A#, 8
	octave 3
	note F_, 8
	octave 2
	note A#, 8
	octave 3
	note F_, 8
	octave 2
	note A#, 8
	octave 3
	note F_, 8
	sound_ret

Music_RocketBattle_Sub3:
	note A_, 12
	octave 3
	note E_, 12
	note D_, 12
	octave 2
	note A_, 12
	note A#, 12
	octave 3
	note E_, 12
	note G_, 12
	note F_, 12
	octave 2
	sound_ret

Music_RocketBattle_Sub4:
	octave 2
	note A#, 8
	octave 3
	note F_, 8
	note A#, 8
	octave 2
	note A#, 8
	octave 3
	note F_, 8
	note A#, 8
	octave 2
	note A#, 8
	octave 3
	sound_ret

Music_RocketBattle_Sub5:
	octave 2
	note A_, 8
	octave 3
	note E_, 8
	note A_, 8
	octave 2
	note A_, 8
	octave 3
	note E_, 8
	note A_, 8
	octave 2
	note A_, 8
	octave 3
	sound_ret

Music_RocketBattle_Sub6:
	note A_, 6
	note A_, 4
	octave 4
	note C_, 2
	volume_envelope 12, 7
	octave 3
	note A#, 4
	volume_envelope 12, 2
	sound_ret

Music_RocketBattle_Sub7:
	note A_, 6
	note A_, 4
	octave 5
	note C_, 2
	volume_envelope 12, 7
	octave 4
	note A#, 4
	volume_envelope 12, 2
	sound_ret

Music_RocketBattle_Sub8:
	volume_envelope 12, 2
	octave 3
	note A#, 6
	note A#, 4
	volume_envelope 12, 7
	octave 4
	note D_, 2
	note C_, 4
	sound_ret

Music_RocketBattle_Sub9:
	octave 4
	note G#, 1
	note A_, 1
	note G#, 1
	volume_envelope 12, 2
	octave 5
	sound_ret

Music_RocketBattle_Sub10:
	note C_, 12
	note C_, 8
	note E_, 4
	volume_envelope 11, 7
	note D_, 8
	volume_envelope 11, 2
	sound_ret

Music_RocketBattle_Sub11:
	note E_, 12
	note E_, 8
	note G_, 4
	volume_envelope 11, 7
	note F_, 8
	volume_envelope 11, 2
	sound_ret

Music_RocketBattle_Sub12:
	note E_, 4
	note D_, 4
	note E_, 4
	note F_, 4
	note E_, 4
	note F_, 4
	volume_envelope 11, 5
	note G_, 8
	volume_envelope 11, 3
	note G_, 4
	note F_, 4
	sound_ret

Music_RocketBattle_Sub13:
	note A_, 6
	note G#, 6
	note E_, 4
	note A_, 6
	note G#, 6
	note E_, 4
	volume_envelope 11, 0
	sound_ret

Music_RocketBattle_Sub14:
	note A_, 12
	octave 3
	note E_, 12
	octave 2
	note A_, 12
	octave 3
	note E_, 12
	octave 2
	note A_, 12
	octave 3
	note E_, 12
	note D#, 12
	sound_ret

Music_RocketBattle_Sub15:
	note D_, 4
	note C#, 4
	note D_, 4
	volume_envelope 11, 5
	note D#, 8
	volume_envelope 11, 3
	note D#, 4
	note D_, 4
	note F_, 4
	sound_ret

Music_RocketBattle_Sub16:
	note A_, 6
	note A_, 4
	volume_envelope 12, 7
	octave 4
	note C_, 2
	octave 3
	note A#, 4
	volume_envelope 12, 2
	sound_ret

Music_RocketBattle_Sub17:
	note F_, 8
	octave 2
	note A#, 8
	octave 3
	note F_, 8
	sound_ret

Music_RocketBattle_Sub18:
	octave 4
	note E_, 4
	octave 3
	note E_, 4
	note E_, 4
	octave 4
	note D_, 4
	octave 3
	sound_ret

Music_RocketBattle_Sub19:
	note E_, 12
	note E_, 8
	volume_envelope 11, 7
	note G_, 4
	note F_, 8
	volume_envelope 11, 2
	sound_ret

Music_RocketBattle_Sub20:
	note G_, 8
	volume_envelope 11, 2
	note F_, 12
	note F_, 8
	volume_envelope 11, 7
	note A_, 4
	sound_ret

Music_RocketBattle_Sub21:
	note A_, 12
	octave 3
	note E_, 12
	note D_, 12
	octave 2
	note A_, 12
	octave 3
	note G_, 12
	sound_ret
