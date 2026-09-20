"""Piper TTS wrapper -- same PiperVoice API already proven in test_tts.py,
but returns raw PCM bytes for streaming back to the FPGA instead of writing
a .wav file to disk.
"""
import io
import wave


class TTS:
    def __init__(self, model_path="en_US-lessac-medium.onnx", config_path="en_US-lessac-medium.onnx.json"):
        from piper import PiperVoice  # deferred: avoid paying the import cost in tests that don't need it

        self._voice = PiperVoice.load(model_path, config_path=config_path)

    def synthesize(self, text):
        """Returns (pcm_bytes, sample_rate). pcm_bytes is 16-bit signed mono PCM."""
        buf = io.BytesIO()
        with wave.open(buf, "wb") as wav_file:
            self._voice.synthesize_wav(text, wav_file)
        buf.seek(0)
        with wave.open(buf, "rb") as wav_file:
            sample_rate = wav_file.getframerate()
            pcm_bytes = wav_file.readframes(wav_file.getnframes())
        return pcm_bytes, sample_rate
