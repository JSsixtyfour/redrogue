; Converted from pika_cup.mid by the Red Rogue music test kit (pokemid v0.9, Crystal engine).
; kit-engine: crysaudio pokered-crysaudio 9753183a
; Size-optimized by tools/music_kit/song_optimize.py (2026-11-26): same notes, lengths
; and channel state, verified frame by frame with tools/music_kit/song_audio_compare.py.
Music_PikaCupBattle::
	channel_count 3
	channel 1, Music_PikaCupBattle_Ch1
	channel 2, Music_PikaCupBattle_Ch2
	channel 3, Music_PikaCupBattle_Ch3

Music_PikaCupBattle_Ch1::
	tempo 96
	note_type 12, 0, 0
	rest 16
	rest 16
.mainloop:
	vibrato 0, 0, 0
	duty_cycle 1
	note_type 16, 10, 0
	sound_call Music_PikaCupBattle_Sub7
	note E_, 7
	rest 6
	volume_envelope 6, 0
	octave 3
	note D_, 3
	note C_, 3
	volume_envelope 10, 0
	sound_call Music_PikaCupBattle_Sub7
	note A_, 7
	rest 1
	octave 3
	note G_, 1
	note A#, 1
	octave 4
	note C_, 1
	octave 3
	note A#, 1
	octave 4
	note C_, 1
	note C#, 1
	note D_, 1
	note F_, 1
	note G_, 1
	note F_, 1
	note G_, 1
	note A#, 2
	octave 3
	note A#, 3
	octave 4
	note A#, 4
	note G#, 2
	note G_, 1
	note G#, 2
	note F_, 3
	note G#, 4
	note G_, 2
	note F_, 1
	note G_, 2
	note C_, 3
	note G_, 4
	note F_, 2
	note D#, 1
	note F_, 2
	octave 3
	note B_, 3
	octave 4
	note F_, 4
	note D#, 2
	note D_, 1
	note C_, 4
	note C_, 1
	note D_, 1
	note D#, 6
	rest 9
	note F#, 3
	note F_, 5
	note D#, 1
	note D_, 12
	note D#, 3
	note D_, 3
	note C_, 4
	note C_, 1
	note D_, 1
	note D#, 4
	note D#, 1
	note F_, 1
	note G_, 3
	rest 3
	note A#, 3
	rest 3
	note G#, 5
	note G_, 1
	note F#, 6
	octave 3
	note D_, 3
	note C_, 3
	note C_, 3
	octave 2
	note A#, 3
	rest 3
	volume_envelope 5, 0
	note G_, 3
	rest 3
	note G_, 3
	rest 3
	note G#, 3
	rest 3
	note A#, 3
	octave 3
	note C#, 12
	volume_envelope 6, 0
	note E_, 12
	rest 3
	volume_envelope 5, 0
	octave 2
	note G_, 3
	rest 3
	note G_, 3
	rest 3
	volume_envelope 6, 0
	octave 3
	note C_, 3
	rest 3
	volume_envelope 5, 0
	note C_, 3
	volume_envelope 6, 0
	note G_, 12
	note F_, 12
	volume_envelope 10, 0
	octave 4
	note D#, 4
	octave 3
	note A#, 1
	octave 4
	note D#, 1
	note F#, 5
	note A#, 1
	note A_, 2
	note F_, 1
	note C_, 7
	octave 3
	note A#, 1
	note A_, 1
	octave 4
	note C_, 8
	octave 3
	note A#, 2
	note G#, 2
	note G#, 10
	note F#, 1
	note F_, 1
	volume_envelope 5, 0
	note A_, 15
	rest 12
	volume_envelope 10, 0
	note G#, 3
	rest 3
	note B_, 3
	rest 3
	octave 4
	note D_, 6
	rest 8
	octave 3
	sound_call Music_PikaCupBattle_Sub11
	note G#, 1
	note G_, 1
	volume_envelope 7, 0
	note F_, 15
	rest 3
	volume_envelope 10, 0
	octave 3
	note G_, 3
	rest 2
	sound_call Music_PikaCupBattle_Sub11
	note D#, 1
	note G_, 1
	volume_envelope 8, 0
	note A#, 12
	rest 9
	volume_envelope 10, 0
	note C_, 1
	octave 3
	note A#, 1
	octave 4
	note C_, 1
	note D_, 6
	note E_, 3
	note G_, 3
	note C_, 3
	note E_, 3
	rest 3
	note D_, 1
	note C_, 1
	note D_, 1
	note E_, 6
	note F#, 3
	note B_, 3
	note D_, 3
	note F#, 3
	rest 3
	note E_, 1
	note D_, 1
	note E_, 1
	note F#, 3
	note G#, 3
	note D_, 3
	note E_, 3
	note F#, 6
	rest 3
	note B_, 1
	note F#, 1
	note D_, 1
	note C#, 1
	octave 3
	note B_, 1
	octave 4
	note C#, 1
	note D_, 1
	note F#, 1
	note B_, 1
	volume_envelope 8, 0
	octave 5
	note C_, 9
	rest 3
	sound_loop 0, .mainloop

Music_PikaCupBattle_Ch2::
	note_type 12, 0, 0
	rest 16
	rest 16
.mainloop:
	vibrato 0, 0, 0
	duty_cycle 2
	note_type 2, 10, 0
	octave 3
	sound_call Music_PikaCupBattle_Sub1
	note A_, 15
	note_type 6, 10, 0
	rest 16
	note_type 1, 10, 0
	rest 7
	note_type 3, 6, 0
	note G_, 15
	rest 1
	note F_, 15
	rest 1
	note_type 2, 10, 0
	sound_call Music_PikaCupBattle_Sub1
	octave 4
	note F_, 15
	note_type 1, 10, 0
	rest 12
	rest 11
	octave 3
	note D_, 16
	note F_, 16
	note G_, 16
	note F_, 16
	note G_, 16
	note A_, 16
	note A#, 16
	octave 4
	note D_, 16
	note C_, 16
	octave 3
	note A#, 16
	octave 4
	note C_, 16
	note_type 5, 10, 0
	sound_call Music_PikaCupBattle_Sub12
	sound_call Music_PikaCupBattle_Sub12
	note C_, 15
	rest 1
	note_type 7, 5, 0
	note C_, 15
	rest 1
	note_type 5, 5, 0
	octave 3
	note B_, 15
	rest 1
	note_type 7, 6, 0
	note B_, 15
	rest 1
	note_type 4, 7, 0
	note C_, 15
	rest 1
	note C_, 4
	note C_, 4
	note_type 3, 7, 0
	note C_, 15
	rest 1
	volume_envelope 8, 0
	note F#, 15
	rest 1
	note_type 7, 8, 0
	note F_, 13
	sound_call Music_PikaCupBattle_Sub4
	note D#, 13
	sound_call Music_PikaCupBattle_Sub4
	note D_, 13
	sound_call Music_PikaCupBattle_Sub4
	note G#, 13
	sound_call Music_PikaCupBattle_Sub4
	note B_, 13
	sound_call Music_PikaCupBattle_Sub4
	note F_, 13
	note_type 1, 8, 0
	rest 5
	note_type 4, 8, 0
	note G#, 15
	rest 1
	volume_envelope 10, 0
	note G#, 4
	volume_envelope 8, 0
	note A#, 4
	note B_, 15
	rest 1
	note B_, 4
	octave 4
	note C#, 4
	note_type 3, 8, 0
	note D#, 15
	rest 16
	rest 1
	note G_, 15
	note_type 9, 8, 0
	rest 16
	note_type 1, 8, 0
	rest 3
	volume_envelope 10, 0
	octave 3
	note D_, 16
	note F#, 16
	note G_, 16
	note A#, 16
	octave 4
	note C_, 16
	note C#, 16
	note_type 3, 10, 0
	note D_, 15
	rest 1
	note C_, 15
	rest 1
	note C_, 15
	rest 1
	octave 3
	note A#, 15
	rest 1
	note_type 4, 10, 0
	note G_, 15
	rest 1
	note D_, 4
	note G_, 4
	note_type 5, 10, 0
	note A#, 15
	rest 1
	note_type 2, 10, 0
	octave 4
	note D_, 8
	note C#, 15
	rest 1
	octave 3
	note G#, 8
	note_type 7, 10, 0
	note A#, 15
	rest 1
	note_type 16, 10, 0
	note G#, 1
	note G_, 1
	note F#, 15
	rest 9
	note_type 4, 10, 0
	note A#, 15
	rest 1
	note G_, 4
	note A#, 4
	note_type 5, 10, 0
	octave 4
	note C#, 15
	rest 1
	note_type 2, 10, 0
	note F#, 8
	note F_, 15
	rest 1
	note C_, 8
	note_type 7, 10, 0
	note C#, 15
	rest 1
	note_type 16, 10, 0
	note D_, 1
	note C#, 1
	note C_, 15
	rest 9
	note_type 7, 10, 0
	octave 3
	note F#, 13
	note_type 1, 10, 0
	rest 5
	note_type 2, 10, 0
	note F_, 15
	rest 1
	note D#, 15
	rest 1
	note_type 4, 10, 0
	note C_, 15
	rest 1
	octave 2
	note A#, 4
	note_type 7, 10, 0
	note A_, 13
	rest 3
	note_type 1, 10, 0
	octave 3
	note C_, 16
	octave 2
	note A#, 16
	note_type 3, 10, 0
	note A_, 15
	note_type 1, 10, 0
	rest 12
	rest 7
	octave 3
	note F_, 16
	note A_, 16
	note_type 5, 10, 0
	octave 4
	note C_, 15
	rest 1
	note_type 2, 10, 0
	note F#, 8
	note F_, 15
	rest 1
	note C_, 15
	rest 1
	note_type 11, 10, 0
	octave 3
	note G#, 11
	note_type 1, 10, 0
	rest 7
	note_type 5, 10, 0
	octave 4
	note C#, 15
	note_type 1, 10, 0
	rest 5
	octave 3
	sound_call Music_PikaCupBattle_Sub13
	note_type 7, 10, 0
	octave 3
	note F_, 13
	note_type 2, 10, 0
	rest 12
	note_type 1, 10, 0
	rest 13
	note_type 2, 10, 0
	octave 4
	note D#, 15
	rest 1
	note E_, 15
	rest 1
	note_type 3, 10, 0
	note F_, 15
	rest 1
	note D_, 15
	rest 1
	note_type 16, 10, 0
	note G#, 15
	rest 8
	octave 3
	note G_, 1
	sound_call Music_PikaCupBattle_Sub0
	note_type 5, 10, 0
	note E_, 9
	rest 7
	note_type 1, 10, 0
	octave 3
	note G_, 16
	sound_call Music_PikaCupBattle_Sub0
	note_type 3, 10, 0
	note D_, 15
	note_type 1, 10, 0
	rest 3
	octave 3
	note A_, 16
	note G_, 16
	note A_, 16
	note_type 7, 10, 0
	note A#, 13
	note_type 1, 10, 0
	rest 5
	note_type 3, 10, 0
	octave 4
	note C_, 15
	rest 1
	note E_, 15
	rest 1
	octave 3
	note G_, 15
	rest 1
	octave 4
	note C_, 15
	rest 16
	note_type 1, 10, 0
	rest 3
	octave 3
	note B_, 16
	note A_, 16
	sound_call Music_PikaCupBattle_Sub13
	note_type 3, 10, 0
	note D_, 15
	rest 1
	note F#, 15
	rest 1
	octave 3
	note B_, 15
	rest 1
	octave 4
	note D_, 15
	rest 16
	note_type 1, 10, 0
	rest 3
	note C_, 16
	octave 3
	note A#, 16
	octave 4
	note C_, 16
	note_type 3, 10, 0
	note D_, 15
	rest 1
	note E_, 15
	note_type 1, 10, 0
	rest 3
	note F#, 16
	note E_, 16
	note F#, 16
	note_type 3, 10, 0
	note G#, 15
	rest 1
	note A#, 15
	note_type 1, 10, 0
	rest 3
	octave 5
	note C_, 16
	octave 4
	note A#, 16
	octave 5
	note C_, 15
	note_type 7, 10, 0
	rest 7
	note_type 1, 10, 0
	octave 4
	note F#, 16
	note D_, 16
	octave 3
	note B_, 16
	note F#, 16
	note D_, 16
	note F#, 16
	note B_, 16
	octave 4
	note C#, 16
	note D_, 16
	note_type 9, 8, 0
	note F#, 15
	note_type 3, 8, 0
	rest 16
	rest 3
	sound_loop 0, .mainloop

Music_PikaCupBattle_Ch3::
	vibrato 0, 0, 0
	note_type 2, 3, 6
	octave 2
.loop0:
	note G_, 16
	note G_, 8
	sound_loop 6, .loop0
	note F_, 8
	note G_, 8
	octave 3
	note D_, 8
	octave 2
	note E_, 8
	note F_, 8
	note F#, 8
.mainloop:
	note_type 4, 3, 6
	octave 2
	sound_call Music_PikaCupBattle_Sub3
	note A#, 12
	octave 3
	note C_, 12
	octave 2
	sound_call Music_PikaCupBattle_Sub3
	note F_, 8
	note D_, 4
	note F_, 8
	note F#, 4
	sound_call Music_PikaCupBattle_Sub3
	note A#, 12
	octave 3
	note C_, 12
	octave 2
	sound_call Music_PikaCupBattle_Sub3
	note F_, 8
	note D_, 4
	note G_, 8
	note A_, 4
	sound_call Music_PikaCupBattle_Sub8
	sound_call Music_PikaCupBattle_Sub5
	octave 3
.loop1:
	note C_, 8
	note C_, 4
	sound_loop 4, .loop1
	octave 2
	sound_call Music_PikaCupBattle_Sub5
	sound_call Music_PikaCupBattle_Sub8
	sound_call Music_PikaCupBattle_Sub14
	sound_call Music_PikaCupBattle_Sub9
.loop2:
	note G_, 8
	note G_, 4
	sound_loop 4, .loop2
	sound_call Music_PikaCupBattle_Sub9
	sound_call Music_PikaCupBattle_Sub6
	sound_call Music_PikaCupBattle_Sub15
	note G_, 12
	note C_, 12
	note F_, 12
	octave 1
	note A#, 12
	note G_, 12
	octave 2
	note G_, 12
	octave 1
	note G_, 12
	octave 2
	note G_, 12
	octave 1
	note G#, 12
	octave 2
	note G#, 12
	octave 1
	note G#, 12
	octave 2
	note G#, 12
	sound_call Music_PikaCupBattle_Sub6
	note C#, 8
	note C#, 4
	note D#, 8
	note D#, 4
	note E_, 8
	note E_, 4
	note C#, 8
	note C#, 4
	octave 1
	note G_, 12
	octave 2
	note G_, 12
	octave 1
	note G_, 12
	octave 2
	note G_, 12
	note C_, 12
	octave 3
	note C_, 12
	octave 2
	note C_, 12
	octave 3
	note C_, 12
	octave 2
	sound_call Music_PikaCupBattle_Sub10
	note F_, 8
	note F_, 4
	note G_, 8
	note G_, 4
	note G#, 8
	note G#, 4
	note F_, 8
	note F_, 4
.loop3:
	note D#, 8
	note D#, 4
	sound_loop 4, .loop3
	sound_call Music_PikaCupBattle_Sub10
.loop4:
	note F#, 8
	note F#, 4
	sound_loop 4, .loop4
	sound_call Music_PikaCupBattle_Sub9
	octave 1
	sound_call Music_PikaCupBattle_Sub14
	octave 2
	sound_call Music_PikaCupBattle_Sub10
	sound_call Music_PikaCupBattle_Sub16
	sound_call Music_PikaCupBattle_Sub16
	octave 2
.loop5:
	sound_call Music_PikaCupBattle_Sub2
	sound_call Music_PikaCupBattle_Sub6
	sound_loop 2, .loop5
	octave 1
	sound_call Music_PikaCupBattle_Sub8
	octave 2
	note C_, 8
	note C_, 4
	note E_, 8
	note E_, 4
	note C_, 8
	note C_, 4
	note C_, 8
	note C_, 4
	octave 1
	sound_call Music_PikaCupBattle_Sub5
	sound_call Music_PikaCupBattle_Sub5
	octave 2
	sound_call Music_PikaCupBattle_Sub2
	sound_call Music_PikaCupBattle_Sub15
	sound_loop 0, .mainloop

Music_PikaCupBattle_Sub0:
	note_type 3, 10, 0
	note A_, 15
	rest 1
	note B_, 15
	rest 1
	octave 4
	note C_, 15
	rest 1
	note D_, 15
	rest 1
	note_type 2, 10, 0
	note E_, 15
	rest 1
	note F_, 8
	note G_, 15
	rest 1
	note A_, 8
	note_type 11, 10, 0
	note A#, 11
	note_type 1, 10, 0
	rest 7
	note_type 2, 10, 0
	note F_, 15
	rest 1
	note A#, 15
	rest 1
	octave 5
	note C#, 15
	rest 1
	octave 4
	note A#, 15
	rest 1
	note F_, 15
	rest 1
	note A#, 15
	rest 1
	note F_, 15
	rest 1
	note C#, 15
	rest 1
	sound_ret

Music_PikaCupBattle_Sub1:
	note A#, 15
	rest 1
	note_type 3, 10, 0
	note F_, 15
	rest 1
	note_type 7, 10, 0
	note A#, 15
	note_type 6, 10, 0
	rest 16
	note_type 1, 10, 0
	rest 7
	note_type 2, 10, 0
	note A#, 15
	rest 1
	note G_, 8
	note_type 3, 10, 0
	octave 4
	note C_, 15
	rest 1
	octave 3
	note A#, 10
	note_type 1, 10, 0
	rest 2
	note_type 3, 10, 0
	note G_, 15
	rest 1
	note_type 7, 10, 0
	sound_ret

Music_PikaCupBattle_Sub2:
	note C_, 8
	note C_, 4
	note C_, 8
	note C_, 4
	note C_, 8
	note C_, 4
	note C_, 8
	note C_, 4
	note C_, 8
	note C_, 4
	note C_, 8
	note C_, 4
	note C_, 8
	note C_, 4
	note C_, 8
	note C_, 4
	note C#, 8
	note C#, 4
	note C#, 8
	note C#, 4
	note C#, 8
	note C#, 4
	note C#, 8
	note C#, 4
	sound_ret

Music_PikaCupBattle_Sub3:
	note G_, 8
	note G_, 4
	note G_, 8
	note G_, 4
	note G_, 8
	note G_, 4
	note G_, 8
	note G_, 4
	note G_, 8
	note G_, 4
	note G_, 8
	note G_, 4
	sound_ret

Music_PikaCupBattle_Sub4:
	note_type 1, 8, 0
	rest 5
	note_type 7, 8, 0
	sound_ret

Music_PikaCupBattle_Sub5:
	note B_, 8
	note B_, 4
	note B_, 8
	note B_, 4
	note B_, 8
	note B_, 4
	note B_, 8
	note B_, 4
	sound_ret

Music_PikaCupBattle_Sub6:
	note C#, 8
	note C#, 4
	note C#, 8
	note C#, 4
	note C#, 8
	note C#, 4
	note C#, 8
	note C#, 4
	sound_ret

Music_PikaCupBattle_Sub7:
	octave 4
	note D_, 2
	octave 3
	note G_, 3
	octave 4
	note D_, 7
	rest 6
	note E_, 2
	octave 3
	note A#, 1
	octave 4
	note G_, 3
	note F_, 2
	note D_, 3
	sound_ret

Music_PikaCupBattle_Sub8:
	note A#, 8
	note A#, 4
	note A#, 8
	note A#, 4
	note A#, 8
	note A#, 4
	note A#, 8
	note A#, 4
	sound_ret

Music_PikaCupBattle_Sub9:
	note G#, 8
	note G#, 4
	note G#, 8
	note G#, 4
	note G#, 8
	note G#, 4
	note G#, 8
	note G#, 4
	sound_ret

Music_PikaCupBattle_Sub10:
	note F_, 8
	note F_, 4
	note F_, 8
	note F_, 4
	note F_, 8
	note F_, 4
	note F_, 8
	note F_, 4
	sound_ret

Music_PikaCupBattle_Sub11:
	note D#, 1
	note F_, 3
	note G_, 3
	note A_, 3
	note B_, 3
	octave 4
	note C#, 2
	note D_, 1
	note E_, 2
	note F#, 1
	note G_, 4
	sound_ret

Music_PikaCupBattle_Sub12:
	note D_, 15
	rest 1
	note_type 7, 6, 0
	note D_, 15
	rest 1
	note_type 5, 6, 0
	sound_ret

Music_PikaCupBattle_Sub13:
	note B_, 16
	note_type 7, 10, 0
	octave 4
	note C#, 13
	note_type 1, 10, 0
	rest 5
	sound_ret

Music_PikaCupBattle_Sub14:
	note A_, 8
	note A_, 4
	note A_, 8
	note A_, 4
	note A_, 8
	note A_, 4
	note A_, 8
	note A_, 4
	sound_ret

Music_PikaCupBattle_Sub15:
	note D_, 8
	note D_, 4
	note D_, 8
	note D_, 4
	note D_, 8
	note D_, 4
	note D_, 8
	note D_, 4
	sound_ret

Music_PikaCupBattle_Sub16:
	octave 1
	note B_, 12
	octave 3
	note F_, 12
	octave 1
	note B_, 12
	octave 3
	note F_, 12
	sound_ret
