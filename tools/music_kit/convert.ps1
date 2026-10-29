# Red Rogue music test kit: MIDI -> pokemid -> Red Rogue song -> test ROM -> emulator.
#
# Composer use (via "DROP YOUR SONG HERE.bat"):  convert.ps1 <song.mid>
# Dev import use (tools/music_kit/import_music.py):
#   convert.ps1 <song.mid> -Label Music_Foo -OutAsm <path> -NoBuild
#
# The game uses the Crystal audio engine (crysaudio/, pokered-crysaudio). pokemid
# writes Red-format song text; the Crystal macros share its command names and
# arguments, so step 3 only adds the song header, the Ch4 drum kit selection
# and the Ch3 rules (CRYSTAL_AUDIO_PHASE3_SPEC.md in Red Rogue Files).
#
# The preview song gets its own floating ROMX section and the Music table's
# title-screen row points at it, so a preview can use the largest free gap
# in the ROM instead of the title song's old slot.
#
# Must run under Windows PowerShell 5.1. Keep it free of PS7-only syntax.

param(
	[Parameter(Position = 0)] [string]$Mid,
	[string]$Label = 'Music_KitPreview',
	[string]$OutAsm,
	[switch]$NoBuild,
	[switch]$NoLaunch,
	[switch]$NoBundle,
	[switch]$SelfTest,
	[string]$Pokemid,
	[string]$EngineId
)

$ErrorActionPreference = 'Stop'
$Engine = $PSScriptRoot
$Src    = Join-Path $Engine 'src'
$Out    = Join-Path $Engine 'output'
$ErrLog = Join-Path $Out 'last-error.txt'
# The Music table row the preview takes over (crysaudio/music_pointers_red.asm).
$TitleRow = 'dba Music_RBYTitleScreen'
$PreviewSection = 'Kit Preview Song'

function Say([string]$msg, [string]$color = 'Gray') { Write-Host $msg -ForegroundColor $color }

. (Join-Path $Engine 'midi_normalize.ps1')

# Print a plain-English failure, log the raw tool output, and stop.
function Fail([string]$plain, [string]$raw = '') {
	Say ''
	Say "PROBLEM: $plain" 'Red'
	if ($raw) {
		Say ''
		Say 'Details (send this file to the dev team if the above does not help):' 'DarkGray'
		Say "  $ErrLog" 'DarkGray'
	}
	try {
		New-Item -ItemType Directory -Force -Path $Out | Out-Null
		Set-Content -LiteralPath $ErrLog -Encoding UTF8 -Value ("$plain`r`n`r`n" + $raw)
	} catch {}
	New-Bundle $null ("$plain`r`n`r`n" + $raw)
	exit 1
}

# Submission bundle: everything the dev team needs, in one zip in "SEND THESE TO
# US" next to the .bat (only in the shipped kit, only for a real song). Holds the
# composer's original file, the converted song when there is one, a manifest of
# the exact kit and engine used, an attribution form, and the error text when
# the run failed. Never fatal.
function New-Bundle([string]$converted, [string]$errorText) {
	try {
		if (-not $script:kit -or $NoBundle -or $SelfTest -or -not $Mid -or -not (Test-Path -LiteralPath $Mid -PathType Leaf)) { return }
		$root = Split-Path $Engine
		$dest = Join-Path $root 'SEND THESE TO US'
		$base = [IO.Path]::GetFileNameWithoutExtension($Mid) -replace '[^\w\- ]', '_'
		$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
		$stage = Join-Path $Out ("bundle_" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
		New-Item -ItemType Directory -Force -Path $stage, $dest | Out-Null
		Copy-Item -LiteralPath $Mid -Destination (Join-Path $stage ('original' + [IO.Path]::GetExtension($Mid)))
		if ($converted) { [IO.File]::WriteAllText((Join-Path $stage 'converted-song.asm'), $converted) }
		if ($errorText) { [IO.File]::WriteAllText((Join-Path $stage 'error-log.txt'), $errorText) }
		$manifest = [ordered]@{
			input = [IO.Path]::GetFileName($Mid); builtOk = [bool]$converted; when = (Get-Date -Format 'o')
			kitSchema = $script:kit.kitSchema; kitDate = $script:kit.kitDate; buildHash = $script:kit.buildHash
			engine = $script:kit.engine; engineHashes = $script:kit.engineHashes; romSha256 = $script:kit.romSha256
			importBudget = $script:kit.importBudget
		}
		[IO.File]::WriteAllText((Join-Path $stage 'manifest.json'), ($manifest | ConvertTo-Json -Depth 4))
		[IO.File]::WriteAllText((Join-Path $stage 'ATTRIBUTION.txt'),
			"Fill this in before you send the zip. Open it in Notepad.`r`n`r`nSong title:`r`nYour name (as it should be credited):`r`nOriginal tune or source (write 'original' if it is yours):`r`nAnything we should know (where it should play, what to change):`r`n")
		$zip = Join-Path $dest ("${base}_$stamp.zip")
		Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -Force
		Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
		Say ''
		Say "A zip to send us is ready: $zip" 'Cyan'
		Say '(Open ATTRIBUTION.txt inside it first and fill in your name and the song title.)' 'DarkGray'
	} catch {}
}

# Run a native tool, capturing stdout+stderr as one string. Avoids PS 5.1's
# habit of turning native stderr into error records.
function Invoke-Tool([string]$exe, [string[]]$toolArgs, [string]$workDir) {
	$psi = New-Object System.Diagnostics.ProcessStartInfo
	$psi.FileName = $exe
	$psi.Arguments = ($toolArgs | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join ' '
	$psi.WorkingDirectory = $workDir
	$psi.UseShellExecute = $false
	$psi.RedirectStandardOutput = $true
	$psi.RedirectStandardError = $true
	$psi.CreateNoWindow = $true
	$p = [System.Diagnostics.Process]::Start($psi)
	$stdout = $p.StandardOutput.ReadToEndAsync()
	$stderr = $p.StandardError.ReadToEndAsync()
	$p.WaitForExit()
	return @{ Code = $p.ExitCode; Text = ($stdout.Result + $stderr.Result).Trim() }
}

# Read a Standard MIDI File just far enough to check what pokemid doesn't:
# it maps every Ch4 pitch above 18 to drum 1 without complaint, and its
# overlap error doesn't say which track or tell a chord from a marker.
# Returns a list of plain-English problems (empty = fine).
function Test-Midi([byte[]]$d) {
	$problems = New-Object System.Collections.Generic.List[string]
	if ($d.Length -lt 14 -or [Text.Encoding]::ASCII.GetString($d, 0, 4) -ne 'MThd') { $problems.Add('That file isn''t a valid MIDI file. Export it from your music program as .mid.'); return ,$problems }
	$u16 = { param($o) ([int]$d[$o] -shl 8) -bor $d[$o + 1] }
	$u32 = { param($o) ([int]$d[$o] -shl 24) -bor ([int]$d[$o + 1] -shl 16) -bor ([int]$d[$o + 2] -shl 8) -bor $d[$o + 3] }
	$ntrk = & $u16 10
	$ppq = & $u16 12
	if ($ppq -band 0x8000) { return ,$problems } # SMPTE timing: leave it to pokemid
	$pos = 8 + (& $u32 4)
	$tracks = @()
	$timesigs = New-Object System.Collections.Generic.List[object]
	for ($t = 0; $t -lt $ntrk -and $pos + 8 -le $d.Length; $t++) {
		$len = & $u32 ($pos + 4)
		$p = $pos + 8; $end = [Math]::Min($p + $len, $d.Length); $pos = $p + $len
		$tick = 0; $status = 0; $name = ''
		$notes = New-Object System.Collections.Generic.List[object] # @(tick, pitch, on)
		while ($p -lt $end) {
			$v = 0; do { $b = $d[$p++]; $v = ($v -shl 7) -bor ($b -band 0x7F) } while ($b -band 0x80)
			$tick += $v
			$b = $d[$p]
			if ($b -band 0x80) { $status = $b; $p++ }
			if ($status -eq 0xFF) {
				$kind = $d[$p++]
				$l = 0; do { $b = $d[$p++]; $l = ($l -shl 7) -bor ($b -band 0x7F) } while ($b -band 0x80)
				if ($kind -eq 0x03) { $name = [Text.Encoding]::ASCII.GetString($d, $p, $l) }
				if ($kind -eq 0x58 -and $l -ge 2) { $timesigs.Add(@($tick, [int]$d[$p], [int][Math]::Pow(2, $d[$p + 1]))) }
				$p += $l; $status = 0
			} elseif ($status -eq 0xF0 -or $status -eq 0xF7) {
				$l = 0; do { $b = $d[$p++]; $l = ($l -shl 7) -bor ($b -band 0x7F) } while ($b -band 0x80)
				$p += $l; $status = 0
			} else {
				$hi = $status -band 0xF0
				if ($hi -eq 0x90 -or $hi -eq 0x80) {
					$pitch = $d[$p]; $vel = $d[$p + 1]; $p += 2
					$notes.Add(@($tick, [int]$pitch, ($hi -eq 0x90 -and $vel -gt 0)))
				} elseif ($hi -eq 0xC0 -or $hi -eq 0xD0) { $p += 1 } else { $p += 2 }
			}
		}
		if ($name -match 'Ch([1-4])') { $tracks += ,@("Ch$($Matches[1])", $notes) }
	}
	if ($timesigs.Count -eq 0) { $timesigs.Add(@(0, 4, 4)) }
	$sigs = @($timesigs | Sort-Object { $_[0] })
	$where = {
		param($tk)
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
		"bar $bar, beat $beat"
	}
	foreach ($tr in $tracks) {
		$ch = $tr[0]; $active = @{}; $reported = @{}
		# offs before ons at the same tick, so back-to-back notes aren't chords
		$evs = @($tr[1] | Sort-Object @{ Expression = { $_[0] } }, @{ Expression = { [int]$_[2] } })
		foreach ($e in $evs) {
			$tk = $e[0]; $pitch = $e[1]
			if (-not $e[2]) { $active.Remove($pitch); continue }
			if ($ch -eq 'Ch4' -and $pitch -gt 18 -and -not $reported['drum']) {
				$problems.Add("Ch4 has a note at $(& $where $tk) that isn't one of the kit's 19 drums. Ch4 only uses MIDI notes 0-18 (lowest notes on the keyboard); see the drum list in READ ME FIRST.")
				$reported['drum'] = 1
			}
			# pokemid writes Ch3 an octave up (the wave channel's period is twice
			# the squares'), so Ch3 sounds as written but its range sits an
			# octave lower: Ch1/Ch2 MIDI 36-127, Ch3 MIDI 24-119.
			$lo = if ($ch -eq 'Ch3') { 24 } else { 36 }
			$hi = if ($ch -eq 'Ch3') { 119 } else { 127 }
			if ($ch -ne 'Ch4' -and $pitch -lt $lo -and -not $reported['low']) {
				$problems.Add("$ch has a note at $(& $where $tk) lower than the Game Boy can play on that track (lowest is MIDI note $lo, $(if ($lo -eq 24) { 'C1' } else { 'C2' })). Move it up an octave.")
				$reported['low'] = 1
			}
			if ($ch -ne 'Ch4' -and $pitch -gt $hi -and -not $reported['high']) {
				$problems.Add("$ch has a note at $(& $where $tk) higher than the Game Boy can play on that track (highest is MIDI note $hi). Move it down an octave.")
				$reported['high'] = 1
			}
			if ($active.Count -gt 0 -and -not $reported['chord']) {
				$problems.Add("$ch has two notes playing at once at $(& $where $tk). Each track can only play one note at a time. Spread chords across Ch1, Ch2 and Ch3, or shorten the earlier note.")
				$reported['chord'] = 1
			}
			$active[$pitch] = 1
		}
	}
	return ,$problems
}

# ---------------------------------------------------------------- setup

$kit = $null
$kitJson = Join-Path $Engine 'kit.json'
if (Test-Path -LiteralPath $kitJson) { $kit = Get-Content -LiteralPath $kitJson -Raw | ConvertFrom-Json }
# Which engine this kit was built for (kit.json when shipped, -EngineId from the dev importer).
$EngineName = if ($kit -and $kit.engine) { [string]$kit.engine } elseif ($EngineId) { $EngineId } else { 'unknown' }
$SchemaName = if ($kit -and $kit.kitSchema) { [string]$kit.kitSchema } else { 'dev' }
Say "Kit schema $SchemaName, engine: $EngineName" 'DarkGray'

New-Item -ItemType Directory -Force -Path $Out | Out-Null
if (Test-Path -LiteralPath $ErrLog) { Remove-Item -LiteralPath $ErrLog -Force }

# Steps 1-3: MIDI in, finished song text out. Every failure exits via Fail.
function ConvertMidi {
	# ---------------------------------------------------------------- 1. input

	if (-not $Mid) { Fail "No song given. Drag your .mid file onto 'DROP YOUR SONG HERE'." }
	if (-not (Test-Path -LiteralPath $Mid -PathType Leaf)) { Fail "Can't find the file: $Mid" }
	if ([IO.Path]::GetExtension($Mid) -notmatch '^\.midi?$') {
		Fail "That isn't a MIDI file. Export your song as .mid and drag that onto 'DROP YOUR SONG HERE'."
	}
	if ($Label -notmatch '^Music_[A-Za-z0-9]+$') { Fail "Bad -Label '$Label' (expected Music_SomeName)." }


	Say "Converting: $([IO.Path]::GetFileName($Mid))" 'Cyan'

	# Fit whatever the music program wrote to what pokemid needs (track names,
	# loop markers, General MIDI drums), then check the Game Boy's limits.
	$gm = @{}
	$gmFile = Join-Path $Engine 'gm_drums.json'
	if (Test-Path -LiteralPath $gmFile) {
		foreach ($e in (Get-Content -LiteralPath $gmFile -Raw | ConvertFrom-Json).PSObject.Properties) { $gm[[int]$e.Name] = [int]$e.Value }
	}
	$clean = ConvertTo-CleanMidi ([IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Mid).ProviderPath)) $gm
	if ($clean.Problems.Count) { Fail ($clean.Problems -join "`r`n         ") }
	foreach ($n in $clean.Notes) { Say "  Note: $n" 'Yellow' }
	$problems = Test-Midi $clean.Bytes
	if ($problems.Count) { Fail ($problems -join "`r`n         ") }

	# ---------------------------------------------------------------- 2. pokemid
	# Work on a copy with a plain ASCII path: spaces, apostrophes and accents in
	# the composer's path never reach the tools.

	$tmp = Join-Path ([IO.Path]::GetTempPath()) ("rrmusic_" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
	New-Item -ItemType Directory -Force -Path $tmp | Out-Null
	try {
		[IO.File]::WriteAllBytes((Join-Path $tmp 'in.mid'), $clean.Bytes)
		$exe = if ($Pokemid) { $Pokemid } else { Join-Path $Engine 'pokemid.exe' }
		$r = Invoke-Tool $exe @('in.mid', 'out.asm') $tmp
		$rawAsm = Join-Path $tmp 'out.asm'
		if ($r.Code -ne 0 -or -not (Test-Path -LiteralPath $rawAsm)) {
			# pokemid errors look like "pokemid.exe: Measure 3, beat 1: encode: ..."
			# followed by a Haskell call stack; keep only the first line.
			$t = $r.Text
			$first = ($t -split "`r?`n")[0] -replace '^pokemid(\.exe)?:\s*', ''
			$plain = "The converter couldn't read your MIDI. It said: $first"
			if ($first -match '(?i)Measure (\d+), beat (\d+).*overlaps') {
				# Test-Midi already ruled out chords, so this is a marker inside a note.
				$plain = "At bar $($Matches[1]), beat $($Matches[2]) a note has a begin/end marker or effect inside it. Markers must sit at the start of a note or in a rest."
			} elseif ($first -match '(?i)no tracks found') {
				$plain = 'Couldn''t find tracks named Ch1, Ch2, Ch3, Ch4. Rename your tracks (start from Template.mid).'
			}
			Fail $plain $t
		}
		$lines = Get-Content -LiteralPath $rawAsm
	} finally {
		Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
	}

	# ---------------------------------------------------------------- 3. rewrite
	# pokemid emits one global block per channel: "ChN::", then "ChN_loop:",
	# "ChN_loop_sub_K:" etc. Each becomes <Label>_ChN:: with local labels under
	# it. Anything we don't recognise fails loudly: an unrenamed global label
	# collides as soon as two songs are imported.

	$blocks = [ordered]@{}
	$cur = $null
	$n = 0
	foreach ($line in $lines) {
		$n++
		if ($line -match '^\s*$' -or $line -match '^\s*;') { if ($cur) { $blocks[$cur].Add($line) }; continue }
		if ($line -match '^(Ch[1-4])::\s*$') {
			$cur = $Matches[1]
			if ($blocks.Contains($cur)) { Fail "The MIDI has two tracks named $cur. Each of Ch1-Ch4 can be used once." }
			$blocks[$cur] = New-Object System.Collections.Generic.List[string]
			$blocks[$cur].Add("${Label}_${cur}::")
			continue
		}
		if (-not $cur) { Fail "Unexpected converter output before the first channel (line $n)." ($lines -join "`r`n") }
		if ($line -match '^(Ch[1-4])_(\w+):\s*$') {
			if ($Matches[1] -ne $cur) { Fail "Converter label $($Matches[1])_$($Matches[2]) appeared inside $cur (line $n)." ($lines -join "`r`n") }
			$blocks[$cur].Add(".$($Matches[2]):")
			continue
		}
		if ($line -match '^\S') { Fail "Unrecognised converter label '$line' (line $n)." ($lines -join "`r`n") }
		# operands: ChN_xxx references become .xxx (only within their own channel)
		$fixed = [regex]::Replace($line, '\b(Ch[1-4])_(\w+)\b', {
			param($m)
			if ($m.Groups[1].Value -ne $cur) { Fail "Cross-channel reference '$($m.Value)' in $cur (line $n)." ($lines -join "`r`n") }
			'.' + $m.Groups[2].Value
		})
		if ($fixed -match '\bCh[1-4]\b') { Fail "Unrecognised channel reference '$fixed' (line $n)." ($lines -join "`r`n") }
		$blocks[$cur].Add($fixed)
	}
	if ($blocks.Count -eq 0) {
		Fail 'Couldn''t find tracks named Ch1, Ch2, Ch3, Ch4. Rename your tracks (start from Template.mid).' ($lines -join "`r`n")
	}

	# Range checks the assembler would NOT catch. "octave 0" assembles to $E8,
	# which is toggle_perfect_pitch, so a too-low note silently becomes garbage.
	foreach ($ch in @($blocks.Keys)) {
		foreach ($l in $blocks[$ch]) {
			if ($l -match '^\s*octave\s+(-?\d+)') {
				$o = [int]$Matches[1]
				if ($o -lt 1) { Fail "$ch has a note lower than the Game Boy can play on that track. Move it up an octave." }
				if ($o -gt 8) { Fail "$ch has a note higher than the Game Boy can play. Move it down an octave." }
			}
		}
	}

	# Ch3 (wave) volume: the engine writes (volume nibble << 5) to NR32, so only
	# its low two bits count: 0=mute 1=100% 2=50% 3=25% (crysaudio/engine.asm
	# .load_wave_pattern: and $f0, sla a). pokemid writes velocity-derived 0-15
	# there, which mutes most notes. Force full volume. Waves 0-14 are real
	# (crysaudio/wave_samples.asm; 0-4 are Red's five); 15 means "keep the
	# loaded wave", so clamp to 0-14. Kit v1 (old engine) clamped to 0-4.
	if ($blocks.Contains('Ch3')) {
		$b = $blocks['Ch3']
		$newWaves = @{}
		for ($i = 0; $i -lt $b.Count; $i++) {
			if ($b[$i] -match '^(\s*)note_type\s+(\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*$') {
				$wave = [Math]::Max(0, [Math]::Min(14, [int]$Matches[4]))
				if ($wave -ge 5) { $newWaves[$wave] = 1 }
				$b[$i] = "$($Matches[1])note_type $($Matches[2]), 1, $wave"
			}
		}
		if ($newWaves.Count) {
			Say "  Note: Ch3 uses wave $((@($newWaves.Keys) | Sort-Object) -join ', '). Kit versions before 2 played waves above 4 as wave 4." 'Yellow'
		}
		# Velocity changes used to differ only in volume; now they're identical
		# repeats. Drop a note_type equal to the last one, but only within straight
		# runs: labels and flow commands reset what "last" means.
		$last = $null
		$kept = New-Object System.Collections.Generic.List[string]
		foreach ($l in $b) {
			if ($l -match '^\S' -or $l -match '^\s*(sound_call|sound_loop|sound_ret)\b') { $last = $null }
			elseif ($l -match '^\s*note_type\b') {
				$norm = ($l -replace '\s+', '')
				if ($norm -eq $last) { continue }
				$last = $norm
			}
			$kept.Add($l)
		}
		$blocks['Ch3'] = $kept
	}

	# Ch4 drums: pokemid writes Red's drum ids 1-19 (MIDI note + 1). A Crystal
	# drum note holds a 4-bit index into the current drumkit, and the kits that
	# hold Red's drums are kit 0 = drums 1-12 and kit 1 = drums 8-19 at index
	# (drum - 7) (crysaudio/drumkits.asm; the donor's own RBY conversions map
	# them this way). Invariant: at every label, call, loop, jump and return the
	# channel is on kit 0, so the kit is right whatever the control flow does.
	# A drum from 13-19 switches to kit 1 inside a straight run ("toggle_noise"
	# alone turns noise off, then "toggle_noise 1" back on with kit 1), and the
	# next boundary switches back. Drums 8-12 play in either kit. The first
	# toggle sits before pokemid's loop label: inside the loop it would turn the
	# noise off on every pass.
	if ($blocks.Contains('Ch4')) {
		$b = $blocks['Ch4']
		$drums = New-Object System.Collections.Generic.List[string]
		$drums.Add($b[0])
		$drums.Add("`ttoggle_noise 0")
		$kit = 0
		for ($i = 1; $i -lt $b.Count; $i++) {
			$l = $b[$i]
			if ($kit -ne 0 -and ($l -match '^\S' -or $l -match '^\s*(sound_call|sound_loop|sound_jump|sound_ret)\b')) {
				$drums.Add("`ttoggle_noise")
				$drums.Add("`ttoggle_noise 0")
				$kit = 0
			}
			if ($l -match '^(\s*)drum_note\s+(\d+)\s*,\s*(\d+)\s*$') {
				$d = [int]$Matches[2]
				if ($d -lt 1 -or $d -gt 19) { Fail "Ch4 has a drum the game doesn't have (drum $d)." ($lines -join "`r`n") }
				$want = if ($d -le 7) { 0 } elseif ($d -ge 13) { 1 } else { $kit }
				if ($want -ne $kit) {
					$drums.Add("`ttoggle_noise")
					$drums.Add("`ttoggle_noise $want")
					$kit = $want
				}
				$index = if ($kit -eq 0) { $d } else { $d - 7 }
				$drums.Add("$($Matches[1])drum_note $index, $($Matches[3])")
				continue
			}
			if ($l -match '^\s*drum_note\b') { Fail "Unrecognised drum line '$l'." ($lines -join "`r`n") }
			$drums.Add($l)
		}
		$blocks['Ch4'] = $drums
	}

	# Crystal song header: one row per channel the MIDI has. A missing channel
	# is simply left out (the old engine's header needed all four).
	$order = @('Ch1', 'Ch2', 'Ch3', 'Ch4')
	$present = @($order | Where-Object { $blocks.Contains($_) })
	$text = New-Object System.Collections.Generic.List[string]
	$text.Add("; Converted from $([IO.Path]::GetFileName($Mid)) by the Red Rogue music test kit (pokemid v0.9, Crystal engine).")
	$text.Add("; kit-engine: $EngineName")
	$text.Add("${Label}::")
	$text.Add("`tchannel_count $($present.Count)")
	foreach ($ch in $present) { $text.Add("`tchannel $($ch.Substring(2)), ${Label}_${ch}") }
	foreach ($ch in $present) {
		$text.Add('')
		$text.AddRange($blocks[$ch])
	}
	while ($text[$text.Count - 1] -match '^\s*$') { $text.RemoveAt($text.Count - 1) }
	$songText = ($text -join "`n") + "`n"

	$missing = @($order | Where-Object { -not $blocks.Contains($_) })
	if ($missing.Count) { Say "  Note: no $($missing -join ', ') track in your MIDI, so that channel stays silent." 'Yellow' }
	return $songText
}

# Native mode: a hand-written (or Crystal Tracker) .asm song in the engine's own
# format. No MIDI steps. Validate, then rename only the global labels the file
# defines, as whole words, so two songs never collide. Plain-English failures.
function ConvertAsm {
	if (-not (Test-Path -LiteralPath $Mid -PathType Leaf)) { Fail "Can't find the file: $Mid" }
	if ($Label -notmatch '^Music_[A-Za-z0-9]+$') { Fail "Bad -Label '$Label' (expected Music_SomeName)." }
	Say "Converting: $([IO.Path]::GetFileName($Mid)) (native song file)" 'Cyan'

	# The macro list comes from the engine files, never hardcoded: staged src in
	# the kit, the repo's crysaudio/ in a dev checkout.
	$macroFile = Join-Path $Src 'crysaudio\macros.asm'
	if (-not (Test-Path -LiteralPath $macroFile)) { $macroFile = Join-Path (Split-Path (Split-Path $Engine)) 'crysaudio\macros.asm' }
	if (-not (Test-Path -LiteralPath $macroFile)) { Fail 'Can''t find the engine''s macro list. Ask the dev team for a fresh kit.' }
	$macros = @{}
	foreach ($l in (Get-Content -LiteralPath $macroFile)) {
		if ($l -match '^\s*MACRO\s+(\w+)') { $macros[$Matches[1].ToLower()] = 1 }
		elseif ($l -match '^\s*DEF\s+(\w+)\s+EQUS') { $macros[$Matches[1].ToLower()] = 1 }
	}

	$raw = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $Mid).ProviderPath)
	$src = @($raw -split "`r?`n")
	$globals = [ordered]@{}   # every global label the file defines
	$locals = @{}
	$cmds = New-Object System.Collections.Generic.List[object]   # @{ n; cmd; args }
	for ($i = 0; $i -lt $src.Count; $i++) {
		$code = ($src[$i] -replace ';.*$', '').TrimEnd()
		$n = $i + 1
		if ($code -eq '') { continue }
		if ($code -match '^([A-Za-z_]\w*)(::?)$') {
			$globals[$Matches[1]] = 1
			continue
		}
		if ($code -match '^\.(\w+)(::?)?$') { $locals[$Matches[1]] = 1; continue }
		if ($code -match '^\s+([A-Za-z_]\w*)\s*(.*)$') {
			$cmds.Add(@{ n = $n; cmd = $Matches[1]; args = $Matches[2].Trim() })
			continue
		}
		Fail "Line ${n}: I can't read '$($src[$i].Trim())'. Commands must be indented, labels start in the first column and end in ::"
	}

	# (a) exactly one entry label, followed by channel_count
	$entryNames = @()
	for ($i = 0; $i -lt $src.Count; $i++) {
		$code = ($src[$i] -replace ';.*$', '').TrimEnd()
		if ($code -notmatch '^([A-Za-z_]\w*)::?$') { continue }
		$name = $Matches[1]
		for ($j = $i + 1; $j -lt $src.Count; $j++) {
			$next = ($src[$j] -replace ';.*$', '').Trim()
			if ($next -eq '') { continue }
			if ($next -match '^channel_count\b') { $entryNames += $name }
			break
		}
	}
	if ($entryNames.Count -ne 1) {
		Fail "I need exactly one song label (ending in : or ::) followed by 'channel_count', and found $($entryNames.Count). Start from Template.asm."
	}
	$entry = $entryNames[0]

	foreach ($c in $cmds) {
		$name = $c.cmd.ToLower()
		# (e) dependencies the kit does not carry
		if ($name -eq 'load_wave') { Fail "Line $($c.n): load_wave needs a wave table that isn't in the kit. Use note_type's third number (waves 0-14) instead." }
		if ($name -in @('include', 'incbin')) { Fail "Line $($c.n): $($c.cmd) isn't allowed: the kit only takes one self-contained file." }
		# (d) must be an engine command
		if (-not $macros.ContainsKey($name)) { Fail "Line $($c.n): '$($c.cmd)' isn't a command the music engine knows." }
		$ops = @($c.args -split '\s*,\s*' | Where-Object { $_ -ne '' })
		if ($name -eq 'channel') {
			# (b)
			if ($ops.Count -ne 2) { Fail "Line $($c.n): 'channel' needs a number and a label." }
			if (-not $globals.Contains($ops[1])) { Fail "Line $($c.n): channel $($ops[0]) points at '$($ops[1])', which isn't defined in this file." }
		} elseif ($name -in @('sound_call', 'sound_jump', 'sound_loop', 'sound_jump_if')) {
			# (c)
			if ($ops.Count -lt 1) { Fail "Line $($c.n): $($c.cmd) needs a target label." }
			$target = $ops[$ops.Count - 1]
			if ($target -match '^\.(\w+)$') {
				if (-not $locals.ContainsKey($Matches[1])) { Fail "Line $($c.n): $($c.cmd) points at '$target', which isn't defined in this file." }
			} elseif (-not $globals.Contains($target)) {
				Fail "Line $($c.n): $($c.cmd) points at '$target', which isn't defined in this file. Songs are stored in one piece, so every call, jump and loop must stay inside the file."
			}
		}
	}

	# Rename: entry -> $Label; <entry>_X -> ${Label}_X; anything else -> ${Label}_name.
	$map = @{}
	foreach ($g in $globals.Keys) {
		$map[$g] = if ($g -eq $entry) { $Label } elseif ($g.StartsWith($entry + '_')) { $Label + $g.Substring($entry.Length) } else { "${Label}_$g" }
	}
	$alt = (@($globals.Keys) | Sort-Object { $_.Length } -Descending | ForEach-Object { [regex]::Escape($_) }) -join '|'
	$rx = New-Object System.Text.RegularExpressions.Regex ("(?<![\w.])(" + $alt + ")(?!\w)")
	$text = New-Object System.Collections.Generic.List[string]
	$text.Add("; Converted from $([IO.Path]::GetFileName($Mid)) by the Red Rogue music test kit (native song file).")
	$text.Add("; kit-engine: $EngineName")
	foreach ($l in $src) {
		if ($l -match '^\s*;\s*kit-engine:') { continue }
		$renamed = $rx.Replace($l, { param($m) $map[$m.Groups[1].Value] })
		# The Music table row points at the entry label from another section: export it.
		if ($renamed -match ('^' + [regex]::Escape($Label) + ':(\s*;.*)?$')) { $renamed = "${Label}::" + $Matches[1] }
		$text.Add($renamed)
	}
	while ($text[$text.Count - 1] -match '^\s*$') { $text.RemoveAt($text.Count - 1) }
	return (($text -join "`n") + "`n")
}

if ($SelfTest) {
	# Rebuild the untouched game: proves the kit's tools, objects and flags
	# still produce the real ROM. make_music_kit.py byte-compares it.
	$songText = $null
	Say 'Self-test: building the game with its original title music.' 'Cyan'
} else {
	$songText = if ($Mid -and [IO.Path]::GetExtension($Mid) -ieq '.asm') { ConvertAsm } else { ConvertMidi }
	if ($NoBuild) {
		if (-not $OutAsm) { Fail '-NoBuild needs -OutAsm.' }
		[IO.File]::WriteAllText($OutAsm, $songText)
		Say "Wrote $OutAsm" 'Green'
		exit 0
	}
}

# ---------------------------------------------------------------- 4. build
# The staged sources are never edited. A preview build assembles generated
# copies instead: kit_audio.asm (audio.asm with the Music table include swapped
# and the preview section appended), kit_music_pointers.asm (the table with the
# title row pointing at the song) and kit_song.asm. All three are rewritten on
# every run, so a failed or repeated run never leaves the kit half-edited.

$asmMain = 'audio.asm'
if ($null -ne $songText) {
	$audioText = [IO.File]::ReadAllText((Join-Path $Src 'audio.asm'))
	$tableInclude = 'INCLUDE "crysaudio/music_pointers_red.asm"'
	$tableText = [IO.File]::ReadAllText((Join-Path $Src 'crysaudio\music_pointers_red.asm'))
	$rows = ([regex]::Matches($tableText, [regex]::Escape($TitleRow) + '\b')).Count
	if ($rows -ne 1 -or ([regex]::Matches($audioText, [regex]::Escape($tableInclude))).Count -ne 1) {
		Fail 'The kit''s engine files are not the ones this script expects. Ask the dev team for a fresh kit.' "title rows: $rows"
	}
	$tableText = [regex]::Replace($tableText, [regex]::Escape($TitleRow) + '\b', "dba $Label")
	$audioText = $audioText.Replace($tableInclude, 'INCLUDE "kit_music_pointers.asm"')
	$audioText += "`n`nSECTION `"$PreviewSection`", ROMX`n`nINCLUDE `"kit_song.asm`"`n"
	[IO.File]::WriteAllText((Join-Path $Src 'kit_music_pointers.asm'), $tableText)
	[IO.File]::WriteAllText((Join-Path $Src 'kit_audio.asm'), $audioText)
	[IO.File]::WriteAllText((Join-Path $Src 'kit_song.asm'), $songText)
	[IO.File]::WriteAllText((Join-Path $Out 'song.asm'), $songText)
	$asmMain = 'kit_audio.asm'
}

$flags = if ($kit -and $kit.flags) { $kit.flags } else {
	[pscustomobject]@{
		asm  = @('-Weverything', '-Wtruncation=1', '-Q8', '-P', 'includes.asm', '-D', '_RED')
		link = @('-Weverything', '-Wtruncation=1', '-d', '-p', '0x00')
		fix  = @('-Weverything', '-cjsv', '-n', '0', '-k', '01', '-l', '0x33', '-m', 'MBC3+RAM+BATTERY', '-r', '03', '-p', '0x00', '-t', 'POKEMON RED')
	}
}

$audioObj = Join-Path $Out 'audio_red.o'
$rom      = Join-Path $Out 'test.gbc'
$map      = Join-Path $Out 'test.map'
foreach ($f in @($audioObj, $rom, $map)) { if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force } }

Say 'Building the game...' 'Cyan'
$r = Invoke-Tool (Join-Path $Engine 'rgbasm.exe') (@($flags.asm) + @('-o', $audioObj, $asmMain)) $Src
if ($r.Code -ne 0) {
	$plain = 'Your song converted, but the game couldn''t build it.'
	if ($r.Text -match '(?i)(note_type|vibrato|duty_cycle|pitch_slide|volume|stereo_panning|drum_note|tempo)') {
		$plain += " One of the values on a '$($Matches[1])' effect marker is out of range. Check your text markers."
	}
	Fail $plain $r.Text
}

$objs = @(Get-ChildItem -LiteralPath (Join-Path $Engine 'prebuilt') -Filter '*.o' | ForEach-Object { $_.FullName })
$r = Invoke-Tool (Join-Path $Engine 'rgblink.exe') (@($flags.link) + @('-l', (Join-Path $Engine 'layout.link'), '-m', $map, '-o', $rom) + $objs + @($audioObj)) $Src
if ($r.Code -ne 0) {
	if ($r.Text -match '(?i)unable to place|exceeds|overflow|not enough') {
		Fail 'Your song is too long to fit. Shorten it, or reuse more repeated sections (identical phrases are stored only once).' $r.Text
	}
	Fail 'The game couldn''t be assembled with your song.' $r.Text
}

$r = Invoke-Tool (Join-Path $Engine 'rgbfix.exe') (@($flags.fix) + @($rom)) $Src
if ($r.Code -ne 0) { Fail 'The final ROM step failed.' $r.Text }

# ---------------------------------------------------------------- 5. size
# Song bytes = the preview section's size (header included), as the map says.
# An import gets a section of its own too, so this is what production pays.

$size = $null
foreach ($l in (Get-Content -LiteralPath $map)) {
	if ($l -match ('\(\$([0-9a-f]+) bytes\) \["' + [regex]::Escape($PreviewSection) + '"\]')) {
		$size = [Convert]::ToInt32($Matches[1], 16)
		break
	}
}

Say ''
Say 'Built!' 'Green'
if ($null -ne $size) {
	$budget = if ($kit -and $kit.importBudget) { [int]$kit.importBudget } else { 0 }
	if ($budget -gt 0 -and $size -gt $budget) {
		Say ("Song size: {0:N0} bytes. It plays here, but it's too big to add to the game. Aim for under {1:N0}." -f $size, $budget) 'Yellow'
	} elseif ($budget -gt 0) {
		Say ("Song size: {0:N0} of {1:N0} bytes (fits)." -f $size, $budget) 'Green'
	} else {
		Say ("Song size: {0:N0} bytes." -f $size)
	}
}
New-Bundle $songText $null

# ---------------------------------------------------------------- 6. play

if ($NoLaunch) { exit 0 }
$emu = Join-Path $Engine 'emulator\mGBA.exe'
Say 'Opening the game... (your song plays on the title screen; press Start to skip the intro)' 'Cyan'
if (Test-Path -LiteralPath $emu) {
	Start-Process -FilePath $emu -ArgumentList ('"' + $rom + '"')
} else {
	Start-Process -FilePath $rom
}
exit 0
