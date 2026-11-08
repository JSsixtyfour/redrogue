# Red Rogue music test kit: turn the MIDI a music program wrote into the strict
# shape pokemid wants. Dot-sourced by convert.ps1 (needs Say/Fail from there).
#
# pokemid only understands: tracks whose name holds ChN, monophonic notes, and
# begin/end/effect text events. MuseScore, FL Studio and friends write none of
# that by default, so this step:
#   - finds the four tracks by name (Ch1-Ch4), or failing that by order
#     (drums = the MIDI channel 10 track, the rest in file order)
#   - reads a track's timbre from its name ("Ch1 Square 50", "Ch3 Wave 2")
#   - loops the whole song when there are no begin/end markers
#   - turns General MIDI drum notes into Game Boy drums (gm_drums.json) and
#     keeps one drum hit at a time
#   - drops everything pokemid can't use (program changes, controllers, ...)
# A file that is already in the shape pokemid wants (Template.mid) comes out
# equivalent. Must run under Windows PowerShell 5.1.

$script:EffectCommand = '^(note_type|vibrato|duty_cycle|duty_cycle_pattern|volume|stereo_panning|pitch_slide|toggle_perfect_pitch)\b'
$script:Latin1 = [Text.Encoding]::GetEncoding(28591)

function Read-MidiFile([byte[]]$d) {
	$u16 = { param($o) ([int]$d[$o] -shl 8) -bor $d[$o + 1] }
	$u32 = { param($o) ([int]$d[$o] -shl 24) -bor ([int]$d[$o + 1] -shl 16) -bor ([int]$d[$o + 2] -shl 8) -bor $d[$o + 3] }
	$fmt = & $u16 8
	$ntrk = & $u16 10
	$ppq = & $u16 12
	$tracks = New-Object System.Collections.Generic.List[object]
	$cond = New-Object System.Collections.Generic.List[object] # tempo / time signature, from any track
	$pos = 8 + (& $u32 4)
	$seq = 0
	for ($t = 0; $t -lt $ntrk -and $pos + 8 -le $d.Length; $t++) {
		$len = & $u32 ($pos + 4)
		$id = [Text.Encoding]::ASCII.GetString($d, $pos, 4)
		$p = $pos + 8; $end = [Math]::Min($p + $len, $d.Length); $pos = $p + $len
		if ($id -ne 'MTrk') { continue }
		$trk = [pscustomobject]@{ Name = ''; Events = (New-Object System.Collections.Generic.List[object]); EndTick = 0; NoteCount = 0; Channels = @{} }
		$tick = 0; $status = 0
		while ($p -lt $end) {
			$v = 0; do { $b = $d[$p++]; $v = ($v -shl 7) -bor ($b -band 0x7F) } while (($b -band 0x80) -and $p -lt $end)
			$tick += $v
			if ($p -ge $end) { break }
			$b = $d[$p]
			if ($b -band 0x80) { $status = $b; $p++ } elseif ($status -eq 0) { break }
			if ($status -eq 0xFF) {
				$kind = $d[$p++]
				$l = 0; do { $b = $d[$p++]; $l = ($l -shl 7) -bor ($b -band 0x7F) } while (($b -band 0x80) -and $p -lt $end)
				if ($p + $l -gt $d.Length) { break }
				$data = if ($l -gt 0) { [byte[]]$d[$p..($p + $l - 1)] } else { [byte[]]@() }
				switch ($kind) {
					0x03 { $trk.Name = $script:Latin1.GetString($data) }
					0x01 { $trk.Events.Add([pscustomobject]@{ Tick = $tick; Kind = 'text'; Text = $script:Latin1.GetString($data); Marker = $false; Seq = $seq++ }) }
					0x06 { $trk.Events.Add([pscustomobject]@{ Tick = $tick; Kind = 'text'; Text = $script:Latin1.GetString($data); Marker = $true; Seq = $seq++ }) }
					0x51 { $cond.Add([pscustomobject]@{ Tick = $tick; Kind = $kind; Data = $data }) }
					0x58 { $cond.Add([pscustomobject]@{ Tick = $tick; Kind = $kind; Data = $data }) }
					0x2F { $trk.EndTick = $tick }
				}
				$p += $l; $status = 0
			} elseif ($status -eq 0xF0 -or $status -eq 0xF7) {
				$l = 0; do { $b = $d[$p++]; $l = ($l -shl 7) -bor ($b -band 0x7F) } while (($b -band 0x80) -and $p -lt $end)
				$p += $l; $status = 0
			} else {
				$hi = $status -band 0xF0
				if ($hi -eq 0x90 -or $hi -eq 0x80) {
					$on = ($hi -eq 0x90 -and $d[$p + 1] -gt 0)
					$trk.Events.Add([pscustomobject]@{ Tick = $tick; Kind = $(if ($on) { 'on' } else { 'off' }); Ch = ($status -band 0x0F); P = [int]$d[$p]; V = [int]$d[$p + 1]; Seq = $seq++ })
					if ($on) { $trk.NoteCount++; $trk.Channels[($status -band 0x0F)] = 1 }
					$p += 2
				} elseif ($hi -eq 0xC0 -or $hi -eq 0xD0) { $p += 1 } else { $p += 2 }
			}
		}
		$lastTick = 0
		foreach ($e in $trk.Events) { if ($e.Tick -gt $lastTick) { $lastTick = $e.Tick } }
		if ($trk.EndTick -lt $lastTick) { $trk.EndTick = $lastTick }
		$tracks.Add($trk)
	}
	return @{ Format = $fmt; Ppq = $ppq; Tracks = $tracks; Cond = $cond }
}

function Add-VarLen($list, [int]$n) {
	$bytes = @($n -band 0x7F)
	$n = $n -shr 7
	while ($n -gt 0) { $bytes = @(($n -band 0x7F) -bor 0x80) + $bytes; $n = $n -shr 7 }
	foreach ($b in $bytes) { $list.Add([byte]$b) }
}

function Get-TrackChunk($events, [int]$endTick) {
	# events: Tick, Order, Seq, Bytes. note-offs sort before text before note-ons.
	$body = New-Object System.Collections.Generic.List[byte]
	$last = 0
	foreach ($e in ($events | Sort-Object Tick, Order, Seq)) {
		Add-VarLen $body ([int]($e.Tick - $last))
		$last = $e.Tick
		foreach ($b in $e.Bytes) { $body.Add([byte]$b) }
	}
	Add-VarLen $body ([int][Math]::Max(0, $endTick - $last))
	foreach ($b in @(0xFF, 0x2F, 0x00)) { $body.Add([byte]$b) }
	$n = $body.Count
	$chunk = New-Object System.Collections.Generic.List[byte]
	foreach ($b in [Text.Encoding]::ASCII.GetBytes('MTrk')) { $chunk.Add($b) }
	foreach ($sh in 24, 16, 8, 0) { $chunk.Add([byte](($n -shr $sh) -band 0xFF)) }
	$chunk.AddRange($body)
	return ,$chunk.ToArray()
}

# Where a tick falls, for messages. $sigs: time signatures as @(tick, numerator,
# denominator), sorted by tick (4/4 when empty). Returns @(bar, beat), both 1-based.
function Get-BarBeat([double]$tk, [int]$ppq, $sigs) {
	$bar = 1; $t0 = 0; $num = 4; $den = 4
	foreach ($s in $sigs) {
		if ($s[0] -gt $tk) { break }
		$tpb = $ppq * 4 / $den
		$bar += [Math]::Floor(($s[0] - $t0) / ($tpb * $num))
		$t0 = $s[0]; $num = $s[1]; $den = $s[2]
	}
	$tpb = $ppq * 4 / $den
	$bar += [Math]::Floor(($tk - $t0) / ($tpb * $num))
	$beat = 1 + [Math]::Floor((($tk - $t0) % ($tpb * $num)) / $tpb)
	return @([int]$bar, [int]$beat)
}

# The first bar line at or after a tick.
function Get-BarLine([double]$tk, [int]$ppq, $sigs) {
	$t0 = 0; $num = 4; $den = 4
	foreach ($s in $sigs) { if ($s[0] -gt $tk) { break }; $t0 = $s[0]; $num = $s[1]; $den = $s[2] }
	$len = $ppq * 4 / $den * $num
	return [int]($t0 + [Math]::Ceiling(($tk - $t0) / $len) * $len)
}

function Format-BarBeat([double]$tk, [int]$ppq, $sigs) {
	$bb = Get-BarBeat $tk $ppq $sigs
	if ($bb[1] -eq 1) { return "the start of bar $($bb[0])" }
	return "bar $($bb[0]), beat $($bb[1])"
}

function New-MetaBytes([int]$kind, [byte[]]$data) {
	$l = New-Object System.Collections.Generic.List[byte]
	$l.Add(0xFF); $l.Add([byte]$kind)
	Add-VarLen $l $data.Length
	$l.AddRange($data)
	return ,$l.ToArray()
}

# Timbre the track's name asks for, as the text event that selects it, or $null.
# Ch1/Ch2: "Square 12.5|25|50|75" or "Duty 0-3". Ch3: "Wave 0-14".
function Get-NameTimbre([string]$ch, [string]$name) {
	if ($ch -eq 'Ch3') {
		if ($name -match '(?i)wave\s*[:=]?\s*(1[0-4]|[0-9])(?!\d)') { return "note_type 1, $($Matches[1])" }
		return $null
	}
	if ($name -match '(?i)(?:square|pulse)\s*[:=]?\s*(12\.5|12|25|50|75)(?!\d)') {
		$duty = @{ '12.5' = 0; '12' = 0; '25' = 1; '50' = 2; '75' = 3 }[$Matches[1]]
		return "duty_cycle $duty"
	}
	if ($name -match '(?i)duty\s*[:=]?\s*([0-3])(?!\d)') { return "duty_cycle $($Matches[1])" }
	return $null
}

# Returns @{ Bytes; Notes; Problems }. Notes are things worth telling the
# composer (yellow); Problems stop the run.
function ConvertTo-CleanMidi([byte[]]$d, [hashtable]$GmDrums) {
	$notes = New-Object System.Collections.Generic.List[string]
	$problems = New-Object System.Collections.Generic.List[string]
	$unchanged = @{ Bytes = $d; Notes = $notes; Problems = $problems }
	if ($d.Length -lt 14 -or [Text.Encoding]::ASCII.GetString($d, 0, 4) -ne 'MThd') { return $unchanged }
	$ppqRaw = ([int]$d[12] -shl 8) -bor $d[13]
	if ($ppqRaw -band 0x8000) { return $unchanged } # SMPTE timing: leave it to pokemid

	$midi = Read-MidiFile $d
	$tracks = $midi.Tracks

	# ---- the loop point. Two sources, both song-wide (one loop for every channel):
	#   1. a track named "Loop": its 1st note is where the loop starts, an optional
	#      2nd note where it ends. Every program exports notes. MuseScore exports no
	#      text at all (measured 2026-11-08, Mewtwo original.mid: zero text or
	#      marker events), so this is the only way a notation program can set it.
	#   2. begin/end text or marker events on ANY track, conductor included
	#      (DAWs put markers there). They used to count only on ChN tracks, and a
	#      marker on one track looped that channel alone.
	$loopRe = '(?i)(?<![a-z])loop(?![a-z])'
	$loopTracks = @($tracks | Where-Object { $_.Name -match $loopRe })
	if ($loopTracks.Count -gt 1) { $problems.Add("There are $($loopTracks.Count) tracks named Loop. Keep one: its first note is where the song loops back to."); return @{ Bytes = $d; Notes = $notes; Problems = $problems } }
	$loopNotes = @()
	if ($loopTracks.Count -eq 1) {
		$loopNotes = @($loopTracks[0].Events | Where-Object { $_.Kind -eq 'on' } | ForEach-Object { [int]$_.Tick } | Sort-Object -Unique)
		$tracks = @($tracks | Where-Object { $_ -ne $loopTracks[0] })
	}
	$markBegin = New-Object System.Collections.Generic.List[int]
	$markEnd = New-Object System.Collections.Generic.List[int]
	$allTracks = New-Object System.Collections.Generic.List[object]
	foreach ($t in $tracks) { $allTracks.Add($t) }
	foreach ($t in $loopTracks) { $allTracks.Add($t) }
	foreach ($t in $allTracks) {
		foreach ($e in $t.Events) {
			if ($e.Kind -ne 'text') { continue }
			$s = $e.Text.Trim()
			if ($s -ieq 'begin') { $markBegin.Add($e.Tick) } elseif ($s -ieq 'end') { $markEnd.Add($e.Tick) }
		}
	}

	# Format 0 keeps every channel in one track: split it into one track per channel.
	if ($midi.Format -eq 0 -and $tracks.Count -eq 1) {
		$one = $tracks[0]
		$split = New-Object System.Collections.Generic.List[object]
		foreach ($c in @($one.Channels.Keys | Sort-Object)) {
			$t = [pscustomobject]@{ Name = "MIDI channel $($c + 1)"; Events = (New-Object System.Collections.Generic.List[object]); EndTick = $one.EndTick; NoteCount = 0; Channels = @{ $c = 1 } }
			foreach ($e in $one.Events) { if ($e.Kind -eq 'text' -or $e.Ch -eq $c) { $t.Events.Add($e); if ($e.Kind -eq 'on') { $t.NoteCount++ } } }
			$split.Add($t)
		}
		$tracks = $split
	}

	# ---- which source track is which Game Boy channel
	$byName = @{}
	foreach ($t in $tracks) {
		if ($t.Name -match '(?<![A-Za-z])Ch([1-4])(?!\d)') {
			$k = "Ch$($Matches[1])"
			if ($byName.ContainsKey($k)) { $problems.Add("Two tracks are named $k. Each of Ch1-Ch4 can be used once."); continue }
			$byName[$k] = @($t)
		}
	}
	$used = [ordered]@{} # ChN -> @(source tracks)
	if ($byName.Count -gt 0) {
		foreach ($k in 'Ch1', 'Ch2', 'Ch3', 'Ch4') { if ($byName.ContainsKey($k)) { $used[$k] = $byName[$k] } }
		foreach ($t in $tracks) {
			if ($t.NoteCount -gt 0 -and $t.Name -notmatch '(?<![A-Za-z])Ch([1-4])(?!\d)') {
				$notes.Add("Ignored the track '$($t.Name)': only tracks with Ch1, Ch2, Ch3 or Ch4 in their name are used.")
			}
		}
	} else {
		$withNotes = @($tracks | Where-Object { $_.NoteCount -gt 0 })
		if ($withNotes.Count -eq 0) { $problems.Add('There are no notes in that MIDI file.'); return @{ Bytes = $d; Notes = $notes; Problems = $problems } }
		$drumTracks = @($withNotes | Where-Object { $_.Channels.Count -eq 1 -and $_.Channels.ContainsKey(9) })
		$melodic = @($withNotes | Where-Object { -not ($_.Channels.Count -eq 1 -and $_.Channels.ContainsKey(9)) })
		if ($melodic.Count -gt 3) {
			$names = ($melodic | ForEach-Object { "'" + $_.Name + "'" }) -join ', '
			$problems.Add("This MIDI has $($melodic.Count) tracks with notes ($names), but the Game Boy has 3 melody voices and 1 drum voice. Merge or delete some, or name the tracks you want Ch1, Ch2, Ch3 (and Ch4 for drums).")
			return @{ Bytes = $d; Notes = $notes; Problems = $problems }
		}
		$desc = New-Object System.Collections.Generic.List[string]
		for ($i = 0; $i -lt $melodic.Count; $i++) { $used["Ch$($i + 1)"] = @($melodic[$i]); $desc.Add("'$($melodic[$i].Name)' as Ch$($i + 1)") }
		if ($drumTracks.Count -gt 0) { $used['Ch4'] = $drumTracks; $desc.Add('the drum track as Ch4') }
		$notes.Add("Your tracks aren't named Ch1-Ch4, so I used them in order: $($desc -join ', '). (Name a track Ch1, Ch2, Ch3 or Ch4 to choose.)")
	}
	if ($problems.Count) { return @{ Bytes = $d; Notes = $notes; Problems = $problems } }

	# ---- events per channel: [Tick, Order, Seq, Bytes]; Order puts offs, then text, then ons
	$chan = [ordered]@{}
	$seq = 0
	$hasTimbre = @{}
	$typoSeen = 0
	foreach ($ch in $used.Keys) {
		$evs = New-Object System.Collections.Generic.List[object]
		$srcName = ($used[$ch] | ForEach-Object { $_.Name }) -join ' '
		$endTick = 0
		$hits = New-Object System.Collections.Generic.List[object]   # drums only: Tick, End, P, V
		$active = @{}
		$srcEvents = New-Object System.Collections.Generic.List[object]
		foreach ($t in $used[$ch]) { $srcEvents.AddRange($t.Events); if ($t.EndTick -gt $endTick) { $endTick = $t.EndTick } }
		foreach ($e in ($srcEvents | Sort-Object Tick, Seq)) {
			if ($e.Kind -eq 'text') {
				$s = $e.Text.Trim()
				if ($s -ieq 'begin' -or $s -ieq 'end') {
					# collected song-wide above; placed on every channel below
				} elseif ($s -match $script:EffectCommand) {
					if ($s -match '^duty_cycle\b') { $hasTimbre["$ch/duty"] = 1 } elseif ($s -match '^note_type\b') { $hasTimbre["$ch/note_type"] = 1 }
					$evs.Add([pscustomobject]@{ Tick = $e.Tick; Order = 1; Seq = $seq++; Bytes = (New-MetaBytes 0x01 $script:Latin1.GetBytes($s)) })
				} else {
					if ($s -match '^[a-z_]+\s+-?\d' -and $typoSeen -lt 3) {
						$typoSeen++
						$notes.Add("Ignored the text '$s' on ${ch}: it isn't a loop marker (begin, end) or one of the effect markers (see READ ME FIRST). If you meant an effect, check the spelling.")
					}
					if (-not $e.Marker) { $evs.Add([pscustomobject]@{ Tick = $e.Tick; Order = 1; Seq = $seq++; Bytes = (New-MetaBytes 0x01 $script:Latin1.GetBytes($s)) }) }
				}
			} elseif ($ch -eq 'Ch4') {
				# drums: collect whole hits so we can keep one at a time
				if ($e.Kind -eq 'on') {
					if ($active.ContainsKey($e.P)) { $active[$e.P].End = $e.Tick; $active.Remove($e.P) }
					$h = [pscustomobject]@{ Tick = $e.Tick; End = -1; P = $e.P; V = $e.V }
					$hits.Add($h); $active[$e.P] = $h
				} elseif ($active.ContainsKey($e.P)) {
					$active[$e.P].End = $e.Tick; $active.Remove($e.P)
				}
			} elseif ($e.Kind -eq 'on') {
				$evs.Add([pscustomobject]@{ Tick = $e.Tick; Order = 2; Seq = $seq++; Bytes = [byte[]]@(0x90, $e.P, $e.V) })
			} else {
				$evs.Add([pscustomobject]@{ Tick = $e.Tick; Order = 0; Seq = $seq++; Bytes = [byte[]]@(0x80, $e.P, 0) })
			}
		}
		if ($ch -eq 'Ch4') {
			$remapped = 0; $merged = 0
			foreach ($h in $hits) { if ($h.End -lt 0) { $h.End = [Math]::Max($endTick, $h.Tick + 1) } }
			# General MIDI drum -> Game Boy drum, then one hit per onset (loudest, then lowest GM note)
			foreach ($h in $hits) {
				$h | Add-Member -NotePropertyName Gm -NotePropertyValue $h.P
				if ($h.P -gt 18 -and $GmDrums.ContainsKey($h.P)) { $h.P = $GmDrums[$h.P]; $h | Add-Member -NotePropertyName Mapped -NotePropertyValue $true }
			}
			$kept = New-Object System.Collections.Generic.List[object]
			foreach ($grp in ($hits | Group-Object Tick | Sort-Object { [int]$_.Name })) {
				$best = $grp.Group | Sort-Object @{ Expression = { $_.V }; Descending = $true }, Gm | Select-Object -First 1
				$merged += $grp.Count - 1
				$kept.Add($best)
				if ($best.Mapped) { $remapped++ }
			}
			for ($i = 0; $i -lt $kept.Count; $i++) {
				$h = $kept[$i]
				$stop = $h.End
				if ($i + 1 -lt $kept.Count -and $kept[$i + 1].Tick -lt $stop) { $stop = $kept[$i + 1].Tick }
				if ($stop -le $h.Tick) { $stop = $h.Tick + 1 }
				$evs.Add([pscustomobject]@{ Tick = $h.Tick; Order = 2; Seq = $seq++; Bytes = [byte[]]@(0x90, $h.P, $h.V) })
				$evs.Add([pscustomobject]@{ Tick = $stop; Order = 0; Seq = $seq++; Bytes = [byte[]]@(0x80, $h.P, 0) })
			}
			if ($remapped) { $notes.Add("Ch4: turned $remapped General MIDI drum notes into Game Boy drums (a first-guess mapping; check it by ear).") }
			if ($merged) { $notes.Add("Ch4: $merged drum hits landed on the same beat as another hit and were dropped. The Game Boy has one drum voice, so the loudest hit stays.") }
		}
		$chan[$ch] = @{ Events = $evs; EndTick = $endTick; Name = $srcName }
	}

	# ---- pokemid's rhythm grid (measured 2026-10-29, Mewtwo test.mid). pokemid places
	# every event on a 1/48-beat grid and cannot write a rest of 1/48 beat or less, nor
	# a length off that grid: "couldn't make rest with length 1/48 beats" for a note that
	# ends 1-10 ticks (PPQ 480) before the next, "3/160 beats" for 79-tick triplet notes.
	# Notation programs (MuseScore) end every note 1 tick early, so ordinary 16ths failed.
	# Snap every event to the nearest 1/48 beat (rescaling to PPQ 480 first if the file's
	# PPQ is not a multiple of 48), give a note that snapped to zero length one step, then
	# let a note that ends at most one step before the next note on its track touch it.
	# Each change is at most 1/96 or 1/48 beat, far below hearing at any tempo.
	$ppq = [int]$midi.Ppq
	$scale = 1.0
	if ($ppq % 48) { $scale = 480.0 / $ppq; $ppq = 480; $midi.Ppq = 480 }
	$unit = [int]($ppq / 48)
	$snap = { param([double]$t) [int]([Math]::Round($t * $scale / $unit, [MidpointRounding]::AwayFromZero) * $unit) }
	$moved = 0; $closed = 0
	foreach ($c in $midi.Cond) { $c.Tick = & $snap $c.Tick }
	foreach ($ch in $chan.Keys) {
		$evs = $chan[$ch].Events
		foreach ($e in $evs) {
			$t = & $snap $e.Tick
			if (($e.Bytes[0] -eq 0x90 -or $e.Bytes[0] -eq 0x80) -and [Math]::Abs($t - $e.Tick * $scale) -gt 0.001) { $moved++ }
			$e.Tick = $t
		}
		$chan[$ch].EndTick = & $snap $chan[$ch].EndTick
		$open = @{}
		foreach ($e in ($evs | Sort-Object Tick, Order, Seq)) {
			if ($e.Bytes[0] -eq 0x90) { $open[[int]$e.Bytes[1]] = $e }
			elseif ($e.Bytes[0] -eq 0x80 -and $open.ContainsKey([int]$e.Bytes[1])) {
				$on = $open[[int]$e.Bytes[1]]
				$open.Remove([int]$e.Bytes[1])
				if ($e.Tick -le $on.Tick) { $e.Tick = $on.Tick + $unit }
			}
		}
		$ons = @($evs | Where-Object { $_.Bytes[0] -eq 0x90 } | ForEach-Object { $_.Tick } | Sort-Object)
		foreach ($e in $evs) {
			if ($e.Bytes[0] -ne 0x80) { continue }
			$next = $ons | Where-Object { $_ -ge $e.Tick } | Select-Object -First 1
			if ($null -ne $next -and $next - $e.Tick -gt 0 -and $next - $e.Tick -le $unit) { $e.Tick = $next; $closed++ }
		}
	}
	if ($closed -or $moved) {
		$notes.Add("Timing: closed $closed tiny gaps between notes and moved $moved note edges onto the 1/48-beat grid the Game Boy converter needs (your program ends each note a hair early; nothing you can hear changes).")
	}

	# ---- timbre from the track name, unless the track already sets one itself
	foreach ($ch in 'Ch1', 'Ch2', 'Ch3') {
		if (-not $chan.Contains($ch)) { continue }
		$cmd = Get-NameTimbre $ch $chan[$ch].Name
		if ($cmd -and $hasTimbre.ContainsKey("$ch/" + $(if ($ch -eq 'Ch3') { 'note_type' } else { 'duty' }))) { $cmd = $null }
		if ($cmd) { $chan[$ch].Events.Add([pscustomobject]@{ Tick = 0; Order = 1; Seq = $seq++; Bytes = (New-MetaBytes 0x01 $script:Latin1.GetBytes($cmd)) }) }
	}

	# ---- no begin/end anywhere: repeat the whole song
	$songEnd = 0
	foreach ($ch in $chan.Keys) {
		$last = $chan[$ch].EndTick
		foreach ($e in $chan[$ch].Events) { if ($e.Tick -gt $last) { $last = $e.Tick } }
		$chan[$ch].EndTick = $last
		if ($last -gt $songEnd) { $songEnd = $last }
	}
	# ---- one loop for the whole song (sources: see the top of this function)
	$sigs = @($midi.Cond | Where-Object { $_.Kind -eq 0x58 -and $_.Data.Length -ge 2 } | Sort-Object Tick |
		ForEach-Object { ,@([int]$_.Tick, [int]$_.Data[0], [int][Math]::Pow(2, $_.Data[1])) })
	$at = { param($tk) Format-BarBeat $tk $ppq $sigs }
	$lastBar = { param($tk) (Get-BarBeat ([Math]::Max(0, $tk - 1)) $ppq $sigs)[0] }
	# The song ends at the end of its last bar. Programs that stop the file at the
	# last note-off would otherwise cut a closing rest out of the loop, and the
	# loop would come back early (measured 2026-11-08: looptime.mid jumped back
	# half a beat early, its last rest gone).
	$songEnd = Get-BarLine $songEnd $ppq $sigs
	$begin = $null; $end = $null; $how = $null
	if ($loopNotes.Count -gt 0) {
		$begin = & $snap $loopNotes[0]
		if ($loopNotes.Count -gt 1) { $end = & $snap $loopNotes[1] }
		if ($loopNotes.Count -gt 2) { $notes.Add("The Loop track has $($loopNotes.Count) notes. Only the first two count (loop start, loop end); the rest were ignored.") }
		if ($markBegin.Count -or $markEnd.Count) { $notes.Add('The song has begin/end markers and a Loop track. The Loop track wins; the markers were ignored.') }
		$how = 'set by the Loop track'
	} elseif ($markBegin.Count -or $markEnd.Count) {
		$bs = @($markBegin | ForEach-Object { & $snap $_ } | Sort-Object -Unique)
		$es = @($markEnd | ForEach-Object { & $snap $_ } | Sort-Object -Unique)
		if ($bs.Count -gt 1) { $problems.Add("Found 'begin' markers at different places ($(($bs | ForEach-Object { & $at $_ }) -join ' and ')). The whole song loops back to one place, so keep one.") }
		if ($es.Count -gt 1) { $problems.Add("Found 'end' markers at different places ($(($es | ForEach-Object { & $at $_ }) -join ' and ')). Keep one.") }
		if ($problems.Count) { return @{ Bytes = $d; Notes = $notes; Problems = $problems } }
		if ($bs.Count) { $begin = $bs[0] }
		if ($es.Count) { $end = $es[0] }
		$how = 'set by begin/end markers'
	}
	if ($null -ne $end -and $end -ge $songEnd) { $end = $null } # at or past the last note = the song's end
	$stop = if ($null -ne $end) { $end } else { $songEnd }
	if ($null -ne $begin -and $begin -ge $stop) {
		$problems.Add("The loop starts at $(& $at $begin), which is at or after where it ends ($(& $at $stop)). Put the Loop track's first note earlier.")
		return @{ Bytes = $d; Notes = $notes; Problems = $problems }
	}
	if ($null -eq $begin -and $null -eq $end -and $null -eq $how) { $begin = 0; $how = 'nothing set it, so the whole song repeats' }

	# A note held across the loop start would be half inside the loop: pokemid
	# can't write that ("overlaps other events"). Split it there (drums: end the
	# hit there). At the loop end, cut held notes; pokemid drops everything after
	# 'end' without a word (measured 2026-11-08), so say how much that is.
	$cuts = @()
	if ($null -ne $begin -and $begin -gt 0) { $cuts += ,@($begin, $true) }
	if ($null -ne $end) { $cuts += ,@($end, $false) }
	foreach ($ch in $chan.Keys) {
		$evs = $chan[$ch].Events
		foreach ($cut in $cuts) {
			$x = $cut[0]; $split = $cut[1]
			$open = @{}
			$held = New-Object System.Collections.Generic.List[object]
			foreach ($e in ($evs | Sort-Object Tick, Order, Seq)) {
				if ($e.Tick -ge $x) { break }
				if ($e.Bytes[0] -eq 0x90) { $open[[int]$e.Bytes[1]] = $e }
				elseif ($e.Bytes[0] -eq 0x80) { $open.Remove([int]$e.Bytes[1]) }
			}
			foreach ($on in $open.Values) {
				$off = $evs | Where-Object { $_.Bytes[0] -eq 0x80 -and $_.Bytes[1] -eq $on.Bytes[1] -and $_.Tick -ge $x } | Sort-Object Tick | Select-Object -First 1
				if (-not $off -or $off.Tick -eq $x) { continue }
				$held.Add($on)
				$evs.Add([pscustomobject]@{ Tick = $x; Order = 0; Seq = $seq++; Bytes = [byte[]]@(0x80, $on.Bytes[1], 0) })
				if ($split -and $ch -ne 'Ch4') { $evs.Add([pscustomobject]@{ Tick = $x; Order = 2; Seq = $seq++; Bytes = [byte[]]@(0x90, $on.Bytes[1], $on.Bytes[2]) }) }
			}
			if ($held.Count) {
				$what = if ($split -and $ch -ne 'Ch4') { 'split it in two there (you may hear it start again)' } else { 'cut it short there' }
				$notes.Add("${ch}: a note started at $(& $at $held[0].Tick) is still playing at the loop $(if ($split) { 'start' } else { 'end' }) ($(& $at $x)), so I $what.")
			}
		}
		$chan[$ch].Events = $evs
	}
	if ($null -ne $end) {
		$after = 0
		foreach ($ch in $chan.Keys) { $after += @($chan[$ch].Events | Where-Object { $_.Bytes[0] -eq 0x90 -and $_.Tick -ge $end }).Count }
		if ($after) { $notes.Add("$after notes come after the loop end ($(& $at $end)) and are never played. The game only plays up to there.") }
	}

	foreach ($ch in $chan.Keys) {
		if ($null -ne $begin) { $chan[$ch].Events.Add([pscustomobject]@{ Tick = $begin; Order = 0.9; Seq = $seq++; Bytes = (New-MetaBytes 0x01 $script:Latin1.GetBytes('begin')) }) }
		$chan[$ch].Events.Add([pscustomobject]@{ Tick = $stop; Order = 1; Seq = $seq++; Bytes = (New-MetaBytes 0x01 $script:Latin1.GetBytes('end')) })
	}
	$endBar = & $lastBar $stop
	$bars = if ($endBar -eq 1) { 'bar 1' } else { "bars 1-$endBar" }
	if ($null -eq $begin) {
		$notes.Add("Loop: none. The song plays once and stops after bar $endBar (${how}: there is an end but no begin).")
	} elseif ($begin -eq 0) {
		$tail = if ($how -like 'nothing*') { ' Add a track named Loop with one note where it should restart to loop only part of it (see READ ME FIRST).' } else { '' }
		$notes.Add("Loop: plays $bars, then repeats from bar 1 ($how).$tail")
	} else {
		$notes.Add("Loop: plays $bars once, then goes back to $(& $at $begin) and repeats from there ($how).")
	}

	# ---- write it back out: tempo track, then Ch1-Ch4
	$condEvents = New-Object System.Collections.Generic.List[object]
	$seenCond = @{}
	foreach ($c in ($midi.Cond | Sort-Object Tick)) {
		$key = "$($c.Tick)/$($c.Kind)"
		if ($seenCond.ContainsKey($key)) { continue } # first one at a tick wins
		$seenCond[$key] = 1
		$condEvents.Add([pscustomobject]@{ Tick = $c.Tick; Order = 1; Seq = $seq++; Bytes = (New-MetaBytes $c.Kind $c.Data) })
	}
	$file = New-Object System.Collections.Generic.List[byte]
	foreach ($b in [Text.Encoding]::ASCII.GetBytes('MThd')) { $file.Add($b) }
	foreach ($b in 0, 0, 0, 6, 0, 1) { $file.Add([byte]$b) }
	$n = $chan.Count + 1
	$file.Add([byte]($n -shr 8)); $file.Add([byte]($n -band 0xFF))
	$file.Add([byte]($midi.Ppq -shr 8)); $file.Add([byte]($midi.Ppq -band 0xFF))
	$file.AddRange([byte[]](Get-TrackChunk $condEvents 0))
	foreach ($ch in $chan.Keys) {
		$evs = $chan[$ch].Events
		$evs.Insert(0, [pscustomobject]@{ Tick = 0; Order = -1; Seq = -1; Bytes = (New-MetaBytes 0x03 ([Text.Encoding]::ASCII.GetBytes($ch))) })
		$file.AddRange([byte[]](Get-TrackChunk $evs $chan[$ch].EndTick))
	}
	return @{ Bytes = $file.ToArray(); Notes = $notes; Problems = $problems }
}
