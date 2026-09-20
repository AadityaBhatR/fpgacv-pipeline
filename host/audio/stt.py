"""Turns a stream of 20ms mic PCM chunks (arriving over UDP from the FPGA)
into transcribed utterances.

Two-stage approach:
  1. A cheap RMS-energy endpoint detector decides WHEN a full utterance has
     been spoken (voice, then enough trailing silence) -- this has to be
     cheap because it runs on every 20ms chunk, continuously, forever.
  2. Only once an utterance is captured does the (expensive) Whisper model
     get called, once, on the accumulated buffer -- with vad_filter=True so
     Whisper's own (Silero-based) VAD trims any residual silence/noise at
     the edges before transcribing. faster-whisper bundles this VAD, no
     separate model/download needed beyond faster-whisper itself.

Endpointing thresholds are in raw int16 RMS units, not dB -- tune
SPEECH_RMS_THRESHOLD against your actual mic/gain if it's over- or
under-triggering.
"""
import numpy as np

SAMPLE_RATE = 16000
FRAME_SAMPLES = 320  # 20ms at 16kHz, matches docs/wire_protocol.md's audio framing
SPEECH_RMS_THRESHOLD = 500
TRAILING_SILENCE_MS = 600
MAX_UTTERANCE_MS = 15000

TRAILING_SILENCE_FRAMES = TRAILING_SILENCE_MS // 20
MAX_UTTERANCE_FRAMES = MAX_UTTERANCE_MS // 20


class Endpointer:
    """Pure logic, no model -- feed it int16 PCM frames, get back complete
    utterances (as int16 numpy arrays) whenever one finishes."""

    def __init__(self):
        self._buffer = []
        self._voiced = False
        self._silence_run = 0

    def feed(self, pcm_bytes):
        frame = np.frombuffer(pcm_bytes, dtype=np.int16)
        rms = float(np.sqrt(np.mean(frame.astype(np.float64) ** 2)))
        is_speech = rms >= SPEECH_RMS_THRESHOLD

        if is_speech:
            self._voiced = True
            self._silence_run = 0
            self._buffer.append(frame)
        elif self._voiced:
            self._silence_run += 1
            self._buffer.append(frame)

        if self._voiced and (
            self._silence_run >= TRAILING_SILENCE_FRAMES
            or len(self._buffer) >= MAX_UTTERANCE_FRAMES
        ):
            return self._flush()
        return None

    def _flush(self):
        utterance = np.concatenate(self._buffer) if self._buffer else np.array([], dtype=np.int16)
        self._buffer = []
        self._voiced = False
        self._silence_run = 0
        return utterance


class StreamingSTT:
    def __init__(self, model_size="large-v3-turbo", device="cpu", compute_type="int8"):
        from faster_whisper import WhisperModel  # deferred: slow import, avoid paying it in tests

        self._model = WhisperModel(model_size, device=device, compute_type=compute_type)
        self._endpointer = Endpointer()

    def feed(self, pcm_bytes):
        """Returns a transcript string once an utterance completes, else None."""
        utterance = self._endpointer.feed(pcm_bytes)
        if utterance is None or len(utterance) < SAMPLE_RATE // 4:  # skip <250ms blips
            return None

        audio = utterance.astype(np.float32) / 32768.0
        segments, _info = self._model.transcribe(audio, beam_size=1, vad_filter=True)
        text = " ".join(seg.text for seg in segments).strip()
        return text or None
