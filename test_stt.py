import sounddevice as sd
import numpy as np
from faster_whisper import WhisperModel

SAMPLE_RATE = 16000
DURATION = 4  # Seconds to record

print("Loading Whisper model...")
model = WhisperModel("large-v3-turbo", device="cpu", compute_type="int8")

print(f"\nRecording {DURATION} seconds of audio... Speak a command now!")
audio = sd.rec(
    int(DURATION * SAMPLE_RATE),
    samplerate=SAMPLE_RATE,
    channels=1,
    dtype=np.float32,
)
sd.wait()
audio = audio.flatten()

print("Transcribing...")
segments, info = model.transcribe(audio, beam_size=1)

transcription = " ".join([segment.text for segment in segments]).strip()

print("\n--- Result ---")
print(f"Detected Language: {info.language} ({info.language_probability:.2f})")
print(f"Transcript: \"{transcription}\"")