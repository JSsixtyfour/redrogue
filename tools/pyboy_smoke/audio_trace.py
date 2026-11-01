"""Short, build-identified PyBoy audio clips and Crystal channel-state traces.

This is test tooling only. It captures PyBoy's signed 8-bit stereo samples after
each harness frame, plus channel ownership and ROM pointers between frames.
It does not compare waveforms between DMG/CGB or emulator versions.
"""
from __future__ import annotations

from array import array
from collections import deque
from datetime import datetime, timezone
import json
import math
import os
from pathlib import Path
import re
from types import MethodType
import wave


SOUND_CHANNEL_ON = 1 << 0
SOUND_SFX = 1 << 3
SOUND_CRY = 1 << 5
REGISTER_NR50 = 0xFF24
REGISTER_NR51 = 0xFF25
REGISTER_NR52 = 0xFF26
CALL_TRACE_ENV = "REDROGUE_AUDIO_CALL_TRACE"
CALL_TRACE_SYMBOLS = (
    "PlaySound",
    "PlayBattleSound",
    "PlaySFX",
    "_PlayBattleSound",
    "_PlaySFX",
    "GetMoveSound",
    "LoadChannel",
    "TextCommandProcessor",
    "TextCommand_SOUND",
)
DIAGNOSTIC_CONTEXT_SYMBOLS = (
    "wCurSFX",
    "wAnimationID",
    "wAnimSoundID",
    "wCurChannel",
)


class PyBoyAudioTrace:
    """Capture bounded audio windows and event snapshots for one harness run."""

    PRE_FRAMES = 18
    POST_FRAMES = 42
    MAX_CLIPS = 10
    MUSIC_SFX_CONTEXT_PRE_FRAMES = 30
    MUSIC_SFX_CONTEXT_POST_FRAMES = 30
    AUDIO_CALL_TRACE_PRE_ENTRIES = 48
    AUDIO_CALL_TRACE_POST_ENTRIES = 64

    def __init__(self, harness, artifacts_dir: Path, test_id: str):
        self.harness = harness
        self.test_id = test_id
        self.sample_rate = int(harness.pyboy.sound.sample_rate)
        # Accessing ndarray raises PyBoyFeatureDisabledError when sound sampling
        # is disabled. This makes the audio lane fail clearly instead of writing
        # an empty "successful" recording.
        sound_buffer = harness.pyboy.sound.ndarray
        if getattr(sound_buffer, "ndim", 0) != 2 or sound_buffer.shape[1] != 2:
            raise AssertionError("PyBoy sound sampling must return stereo frames")

        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S_%fZ")
        mode = harness.hardware_mode.lower()
        self.output_dir = artifacts_dir / "audio_transitions" / (
            f"{mode}_{harness.rom_sha256[:12]}_{stamp}"
        )
        self.output_dir.mkdir(parents=True, exist_ok=True)
        self.rom_bank_count = len(harness.rom_path.read_bytes()) // 0x4000
        # Resolve these exact context symbols against the ROM's matching .sym.
        # Caching the addresses both validates the test artifact and keeps
        # per-frame sampling independent of symbol-table parsing.
        self._context_symbol_addresses = {
            name: harness.address(name) for name in DIAGNOSTIC_CONTEXT_SYMBOLS
        }
        self.events: list[dict[str, object]] = []
        self.clips: list[dict[str, object]] = []
        self._clip_builders: list[dict[str, object]] = []
        self._pre_roll: deque[tuple[int, bytes]] = deque(maxlen=self.PRE_FRAMES)
        self._music_sfx_context_pre: deque[dict[str, object]] = deque(
            maxlen=self.MUSIC_SFX_CONTEXT_PRE_FRAMES
        )
        self._music_sfx_context_diagnostic: dict[str, object] | None = None
        self._music_sfx_context_post_remaining = 0
        self._audio_call_trace_enabled = os.environ.get(CALL_TRACE_ENV) == "1"
        self._audio_call_history: deque[dict[str, object]] = deque(
            maxlen=self.AUDIO_CALL_TRACE_PRE_ENTRIES
        )
        self._audio_call_trace: dict[str, object] | None = None
        self._audio_call_trace_post_remaining = 0
        self._audio_call_symbols: dict[str, tuple[int, int]] = {}
        self._loaded_rom_bank_address: int | None = None
        self._attached_hooks: list[tuple[str, object]] = []
        if self._audio_call_trace_enabled:
            self._enable_audio_call_trace()
        self._audio_frames = 0
        self._audio_values = 0
        self._nonzero_values = 0
        self._signal_frames = 0
        self._active_cry_frames = 0
        self.pointer_error_frames = 0
        self.pointer_error_examples = []
        self.music_sfx_frames = 0
        self._first_active_cry_recorded = False
        self._closed = False
        self._inside_tick = False
        self._pending_events = []
        self._last_music = None
        self._last_sfx = ()
        self._captured_music = set()
        self._captured_sfx = False
        self._original_tick = harness.tick

        def traced_tick(instance, frames: int = 1, *, render: bool = False) -> None:
            for _ in range(frames):
                self._inside_tick = True
                try:
                    self._original_tick(1, render=render)
                finally:
                    self._inside_tick = False
                self._after_frame()

        harness.tick = MethodType(traced_tick, harness)

    def attach(self, label: str, callback) -> None:
        self.harness.register_hook(label, callback)
        self._attached_hooks.append((label, callback))

    def _enable_audio_call_trace(self) -> None:
        """Install opt-in CPU-entry probes; callbacks avoid APU/MMIO reads."""
        self._audio_call_symbols = {
            label: self.harness.symbols.get(label) for label in CALL_TRACE_SYMBOLS
        }
        self._loaded_rom_bank_address = self.harness.address("hLoadedROMBank")
        for label in CALL_TRACE_SYMBOLS:
            self.attach(label, self._audio_call_callback(label))

    def _audio_call_callback(self, label: str):
        def capture(_context) -> None:
            registers = self.harness.pyboy.register_file
            stack_pointer = int(registers.SP)
            memory = self.harness.pyboy.memory
            return_address = int(memory[stack_pointer])
            return_address |= int(memory[(stack_pointer + 1) & 0xFFFF]) << 8
            assert self._loaded_rom_bank_address is not None
            active_bank = int(memory[self._loaded_rom_bank_address])
            caller_bank = 0 if return_address < 0x4000 else active_bank
            caller_symbol = self.harness.symbols.nearest(caller_bank, return_address)
            routine_bank, routine_address = self._audio_call_symbols[label]
            entry = {
                "frame": int(self.harness.pyboy.frame_count),
                "label": label,
                "routine_bank": routine_bank,
                "routine_address": routine_address,
                "registers": {
                    name: int(getattr(registers, name))
                    for name in ("A", "F", "B", "C", "D", "E", "HL", "SP", "PC")
                },
                "active_bank": active_bank,
                "caller_bank": caller_bank,
                "caller_return_address": return_address,
                "caller_symbol": caller_symbol,
            }
            if label in ("TextCommandProcessor", "TextCommand_SOUND"):
                stack_words = []
                for offset in range(0, 8, 2):
                    address = (stack_pointer + offset) & 0xFFFF
                    value = int(memory[address])
                    value |= int(memory[(address + 1) & 0xFFFF]) << 8
                    stack_words.append({"stack_offset": offset, "value": value})
                entry["stack_words"] = stack_words
                if label == "TextCommandProcessor":
                    stream_pointer = int(registers.HL)
                    entry["text_stream_pointer"] = stream_pointer
                    entry["text_stream_bytes"] = [
                        int(memory[(stream_pointer + offset) & 0xFFFF])
                        for offset in range(8)
                    ]
                else:
                    next_pointer = int(registers.HL)
                    command_pointer = (next_pointer - 1) & 0xFFFF
                    entry["text_command_pointer"] = command_pointer
                    entry["text_command"] = int(memory[command_pointer])
                    entry["text_next_pointer"] = next_pointer
                    entry["text_bytes_near_command"] = [
                        int(memory[(command_pointer + offset) & 0xFFFF])
                        for offset in range(-2, 10)
                    ]
            if self._audio_call_trace is None:
                self._audio_call_history.append(entry)
            elif self._audio_call_trace_post_remaining > 0:
                self._audio_call_trace["entries"].append(entry)
                self._audio_call_trace_post_remaining -= 1
                if self._audio_call_trace_post_remaining == 0:
                    self._audio_call_trace["complete"] = True

        return capture

    def mark(
        self,
        label: str,
        details: dict[str, object] | None = None,
        *,
        capture: bool = False,
    ) -> dict[str, object]:
        """Record a state snapshot and optionally open a short audio window."""
        event: dict[str, object] = {
            "label": label,
            "frame": int(self.harness.pyboy.frame_count),
            "details": details or {},
            # MMIO/channel snapshots are sampled outside the CPU hook callback.
            "state": None if self._inside_tick else self.state_snapshot(),
            "state_boundary": "end_of_hook_frame" if self._inside_tick else "between_frames",
        }
        self.events.append(event)
        if self._inside_tick:
            self._pending_events.append(event)
        if capture and len(self._clip_builders) + len(self.clips) < self.MAX_CLIPS:
            builder = {
                "event_index": len(self.events) - 1,
                "label": label,
                "parts": [pcm for _, pcm in self._pre_roll],
                "remaining": self.POST_FRAMES,
            }
            self._clip_builders.append(builder)
        return event

    def state_snapshot(self) -> dict[str, object]:
        h = self.harness
        channels: list[dict[str, int | bool]] = []
        for number in range(1, 9):
            flags = h.read8(f"wChannel{number}Flags1")
            address = h.read8(f"wChannel{number}MusicAddress")
            address |= h.read8(f"wChannel{number}MusicAddress", 1) << 8
            song_id = h.read8(f"wChannel{number}MusicID")
            song_id |= h.read8(f"wChannel{number}MusicID", 1) << 8
            channels.append({
                "channel": number,
                "on": bool(flags & SOUND_CHANNEL_ON),
                "sfx": bool(flags & SOUND_SFX),
                "cry": bool(flags & SOUND_CRY),
                "flags1": flags,
                "song_or_sfx_id": song_id,
                "bank": h.read8(f"wChannel{number}MusicBank"),
                "address": address,
            })
        current_id = h.read8("wChannel1MusicID")
        current_id |= h.read8("wChannel1MusicID", 1) << 8
        return {
            "context": {
                name: h.pyboy.memory[address]
                for name, address in self._context_symbol_addresses.items()
            },
            'music_playing': bool(h.read8('wMusicPlaying')),
            "music_id": current_id if channels[0]["on"] else None,
            "music_bank": channels[0]["bank"] if channels[0]["on"] else None,
            "music_address": channels[0]["address"] if channels[0]["on"] else None,
            "global_sound_id": h.read8("wMusicID") | (h.read8("wMusicID", 1) << 8),
            "global_sound_bank": h.read8("wMusicBank"),
            "sfx_priority": h.read8("wSFXPriority"),
            "nr50": h.pyboy.memory[REGISTER_NR50],
            "nr51": h.pyboy.memory[REGISTER_NR51],
            "nr52": h.pyboy.memory[REGISTER_NR52],
            "channels": channels,
        }

    def active_pointer_errors(self, snapshot: dict[str, object]) -> list[str]:
        """Return active channels whose bank/address does not name this ROM."""
        # _PlayMusic/_PlaySFX call MusicOff while partially replacing channel
        # headers. _UpdateSound returns without consuming pointers in that state.
        # Retain those loading snapshots, but assess pointers only when enabled.
        if not snapshot['music_playing']:
            return []
        errors = []
        for channel in snapshot["channels"]:
            if not channel["on"]:
                continue
            bank = int(channel["bank"])
            address = int(channel["address"])
            bank_ok = 0 <= bank < self.rom_bank_count
            address_ok = (0 <= address < 0x4000) if bank == 0 else (0x4000 <= address < 0x8000)
            if not bank_ok or not address_ok:
                errors.append(
                    f"channel {channel['channel']}: bank=${bank:02x} "
                    f"address=${address:04x} ROM banks={self.rom_bank_count}"
                )
        return errors

    def _after_frame(self) -> None:
        for event in self._pending_events:
            event['state'] = self.state_snapshot()
            event['state_frame'] = int(self.harness.pyboy.frame_count)
        self._pending_events.clear()
        observed = self.state_snapshot()
        self._assess_frame(observed)
        self._sample_music_sfx_context(observed)
        self._capture_audio_call_window(observed)
        music = observed['music_id']
        if observed['music_playing'] and music is not None and music != self._last_music:
            self.mark('music_observed', {'music_id': music}, capture=music not in self._captured_music)
            self._captured_music.add(music)
        if observed['music_playing']:
            self._last_music = music
        active_sfx = tuple((row['channel'], row['song_or_sfx_id'])
                           for row in observed['channels'][4:] if row['on'] and not row['cry'])
        if active_sfx and active_sfx != self._last_sfx:
            self.mark('sfx_active_observed', {'channels_and_ids': active_sfx}, capture=not self._captured_sfx)
            self._captured_sfx = True
        self._last_sfx = active_sfx
        sound = self.harness.pyboy.sound
        head = int(sound.raw_buffer_head)
        pcm = bytes(sound.raw_buffer[:head])
        frame = int(self.harness.pyboy.frame_count)
        self._audio_frames += 1
        self._audio_values += len(pcm)
        has_signal = any(pcm)
        self._signal_frames += int(has_signal)
        self._nonzero_values += sum(value != 0 for value in pcm)

        cry_active = any(
            (self.harness.read8(f"wChannel{number}Flags1") & (SOUND_CHANNEL_ON | SOUND_CRY))
            == (SOUND_CHANNEL_ON | SOUND_CRY)
            for number in range(5, 9)
        )
        if cry_active:
            self._active_cry_frames += 1
            if not self._first_active_cry_recorded:
                self._first_active_cry_recorded = True
                state = self.state_snapshot()
                self.mark('active_cry_channel_observed', capture=True)

        self._pre_roll.append((frame, pcm))
        for builder in tuple(self._clip_builders):
            builder["parts"].append(pcm)
            builder["remaining"] -= 1
            if builder["remaining"] <= 0:
                self._finish_clip(builder)
                self._clip_builders.remove(builder)

    def _assess_frame(self, observed):
        errors = self.active_pointer_errors(observed)
        if errors:
            self.pointer_error_frames += 1
            if len(self.pointer_error_examples) < 16:
                self.pointer_error_examples.append({'frame': int(self.harness.pyboy.frame_count),
                                                    'errors': errors, 'state': observed})
        if observed['music_playing'] and any(row['on'] and row['sfx'] for row in observed['channels'][:4]):
            self.music_sfx_frames += 1

    @staticmethod
    def _channel_source(channel: dict[str, object] | None) -> dict[str, object] | None:
        if channel is None:
            return None
        return {
            "channel": channel["channel"],
            "on": channel["on"],
            "sfx": channel["sfx"],
            "flags1": channel["flags1"],
            "song_or_sfx_id": channel["song_or_sfx_id"],
            "bank": channel["bank"],
            "address": channel["address"],
        }

    def _sample_music_sfx_context(self, observed: dict[str, object]) -> None:
        """Keep a compact frame ring around the first SFX on channels 1-4."""
        if self._music_sfx_context_diagnostic is not None:
            if self._music_sfx_context_post_remaining <= 0:
                return

        frame = int(self.harness.pyboy.frame_count)
        channels = observed["channels"][:4]
        sample = {
            "frame": frame,
            "music_playing": observed["music_playing"],
            "global_sound_id": observed["global_sound_id"],
            "global_sound_bank": observed["global_sound_bank"],
            "context": observed["context"],
            "channels": [self._channel_source(channel) for channel in channels],
        }

        if self._music_sfx_context_diagnostic is None:
            trigger_channel = next(
                (channel for channel in channels if channel["on"] and channel["sfx"]),
                None,
            )
            if trigger_channel is None:
                self._music_sfx_context_pre.append(sample)
                return

            prior_sample = self._music_sfx_context_pre[-1] if self._music_sfx_context_pre else None
            prior_channel = None
            if prior_sample is not None:
                prior_channel = next(
                    (
                        channel
                        for channel in prior_sample["channels"]
                        if channel["channel"] == trigger_channel["channel"]
                    ),
                    None,
                )
            current_channel = self._channel_source(trigger_channel)
            self._music_sfx_context_diagnostic = {
                "trigger_frame": frame,
                "trigger_channel": trigger_channel["channel"],
                "source_pointer_transition": {
                    "previous_frame": prior_sample["frame"] if prior_sample else None,
                    "previous": prior_channel,
                    "current_frame": frame,
                    "current": current_channel,
                },
                "pre_frames_requested": self.MUSIC_SFX_CONTEXT_PRE_FRAMES,
                "post_frames_requested": self.MUSIC_SFX_CONTEXT_POST_FRAMES,
                "complete": False,
                "frames": [*self._music_sfx_context_pre, sample],
            }
            self._music_sfx_context_post_remaining = self.MUSIC_SFX_CONTEXT_POST_FRAMES
            return

        self._music_sfx_context_diagnostic["frames"].append(sample)
        self._music_sfx_context_post_remaining -= 1
        if self._music_sfx_context_post_remaining == 0:
            self._music_sfx_context_diagnostic["complete"] = True

    def _capture_audio_call_window(self, observed: dict[str, object]) -> None:
        if not self._audio_call_trace_enabled or self._audio_call_trace is not None:
            return
        errors = self.active_pointer_errors(observed)
        if not errors:
            return
        self._audio_call_trace = {
            "trigger_frame": int(self.harness.pyboy.frame_count),
            "pointer_errors": errors,
            "pre_entries_requested": self.AUDIO_CALL_TRACE_PRE_ENTRIES,
            "post_entries_requested": self.AUDIO_CALL_TRACE_POST_ENTRIES,
            "complete": False,
            "entries": [*self._audio_call_history],
        }
        self._audio_call_trace_post_remaining = self.AUDIO_CALL_TRACE_POST_ENTRIES

    def _finish_clip(self, builder: dict[str, object]) -> None:
        event_index = int(builder["event_index"])
        event = self.events[event_index]
        label = re.sub(r"[^a-zA-Z0-9]+", "_", str(builder["label"])).strip("_").lower()
        filename = f"{len(self.clips) + 1:02d}_{label or 'audio'}.wav"
        pcm_parts = builder["parts"]
        pcm = b"".join(pcm_parts)
        signed = array("b")
        signed.frombytes(pcm)
        peak = max((abs(value) for value in signed), default=0)
        rms = math.sqrt(sum(value * value for value in signed) / len(signed)) if signed else 0.0
        nonzero_frames = sum(any(part) for part in pcm_parts)

        # PyBoy returns signed 8-bit samples. RIFF/WAVE stores 8-bit PCM as
        # unsigned, so add the standard 128 bias when writing the clip.
        wav_pcm = bytes((value + 128) & 0xFF for value in signed)
        with wave.open(str(self.output_dir / filename), "wb") as wav:
            wav.setnchannels(2)
            wav.setsampwidth(1)
            wav.setframerate(self.sample_rate)
            wav.writeframes(wav_pcm)

        clip = {
            "event_index": event_index,
            "event_frame": event["frame"],
            "label": builder["label"],
            "file": filename,
            "sample_rate": self.sample_rate,
            "channels": 2,
            "sample_width_bits": 8,
            "sample_values": len(signed),
            "duration_seconds": round(len(signed) / (2 * self.sample_rate), 3),
            "peak": peak,
            "rms": round(rms, 3),
            "nonzero_frames": nonzero_frames,
            "captured_frames": len(pcm_parts),
            "window_frames_before": min(self.PRE_FRAMES, len(pcm_parts)),
            "window_frames_after": max(0, len(pcm_parts) - self.PRE_FRAMES),
            "complete": len(pcm_parts) >= self.PRE_FRAMES + self.POST_FRAMES,
        }
        self.clips.append(clip)

    def close(self) -> Path | None:
        if self._closed:
            return self.output_dir / "trace.json"
        self._closed = True
        self.harness.tick = self._original_tick
        for label, callback in reversed(self._attached_hooks):
            try:
                self.harness.unregister_hook(label, callback)
            except (KeyError, ValueError):
                pass
        for builder in tuple(self._clip_builders):
            self._finish_clip(builder)
        self._clip_builders.clear()

        document = {
            "schema_version": 1,
            "test_id": self.test_id,
            "hardware_mode": self.harness.hardware_mode,
            "sound_emulated": True,
            "rom_sha256": self.harness.rom_sha256,
            "sym_sha256": self.harness.sym_sha256,
            "sample_rate": self.sample_rate,
            "capture_format": "PyBoy signed int8 stereo; WAV exported as unsigned PCM8",
            "audio_frames_seen": self._audio_frames,
            "sample_values_seen": self._audio_values,
            "nonzero_sample_values": self._nonzero_values,
            "frames_with_nonzero_audio": self._signal_frames,
            "frames_with_active_cry_channel": self._active_cry_frames,
            'per_frame_assessment': {'pointer_error_frames': self.pointer_error_frames,
                'pointer_error_examples': self.pointer_error_examples,
                'music_channels_with_sfx_frames': self.music_sfx_frames},
            "music_channel_sfx_context_diagnostic": self._music_sfx_context_diagnostic,
            "audio_call_trace": {
                "enabled": self._audio_call_trace_enabled,
                "symbols": {
                    label: {"bank": key[0], "address": key[1]}
                    for label, key in self._audio_call_symbols.items()
                },
                "diagnostic": self._audio_call_trace,
            },
            "events": self.events,
            "final_state": self.state_snapshot(),
            'pointer_assessment': {'rule': 'only when wMusicPlaying enables _UpdateSound',
                'loading_snapshots_retained_unassessed': sum(
                    event.get('state') is not None and not event['state']['music_playing']
                    for event in self.events)},
            "clips": self.clips,
            "interpretation": (
                "Machine state and samples support regression diagnosis; this is not a "
                "listening, BGB, SGB, hardware, or cross-emulator waveform acceptance."
            ),
        }
        path = self.output_dir / "trace.json"
        path.write_text(json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        return path
