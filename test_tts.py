import wave
import sounddevice as sd
import numpy as np
from piper import PiperVoice

# 1. Load the model and configuration
voice = PiperVoice.load(
    "en_US-lessac-medium.onnx", 
    config_path="en_US-lessac-medium.onnx.json"
)

output_path = "test_output.wav"
text = "Face tracking engaged. Pointing camera up."

# 2. Synthesize using synthesize_wav
print("Synthesizing audio...")
with wave.open(output_path, "wb") as wav_file:
    voice.synthesize_wav(text, wav_file)

# 3. Read back and play through your PC speakers
with wave.open(output_path, "rb") as wf:
    frame_count = wf.getnframes()
    sample_rate = wf.getframerate()
    print(f"Generated {frame_count} frames ({frame_count / sample_rate:.2f}s) at {sample_rate} Hz.")
    
    pcm_bytes = wf.readframes(frame_count)
    audio_data = np.frombuffer(pcm_bytes, dtype=np.int16)

print("Playing through speakers...")
sd.play(audio_data, samplerate=sample_rate)
sd.wait()
print("Done!")