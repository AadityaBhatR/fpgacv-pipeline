"""Entry point: FPGA video/audio in -> STT -> VLM (+memory) -> TTS + command out.

Run from inside host/:  python -m orchestrator.main --fpga-ip 192.168.1.100
"""
import argparse
import queue
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))  # so `import protocol` etc. work regardless of cwd

import protocol
from audio.stt import StreamingSTT
from net.udp_io import ReturnSender, make_audio_receiver, make_video_receiver
from orchestrator import command_parser
from orchestrator.memory import Memory, extract_memory_command
from orchestrator.tts import TTS
from orchestrator.vlm_client import VLMClient
from vision.video_reassembler import FrameReassembler


def build_argparser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--fpga-ip", required=True, help="FPGA's IP address, for the return channel")
    p.add_argument("--memory-file", default="jarvis_memory.md")
    p.add_argument("--whisper-model", default="large-v3-turbo")
    p.add_argument("--vlm-base-url", default="http://localhost:11434")
    p.add_argument("--vlm-model", default="qwen2.5vl:7b")
    p.add_argument("--tts-model", default="en_US-lessac-medium.onnx")
    p.add_argument("--tts-config", default="en_US-lessac-medium.onnx.json")
    return p


class Orchestrator:
    def __init__(self, args):
        self.memory = Memory(args.memory_file)
        self.stt = StreamingSTT(model_size=args.whisper_model)
        self.vlm = VLMClient(base_url=args.vlm_base_url, model=args.vlm_model)
        self.tts = TTS(model_path=args.tts_model, config_path=args.tts_config)

        self.video_rx = make_video_receiver().start()
        self.audio_rx = make_audio_receiver().start()
        self.sender = ReturnSender(args.fpga_ip)

        self.frames = FrameReassembler(self._on_frame)
        self._latest_frame = None
        self._utterance_id = 0

    def _on_frame(self, frame_id, rgb):
        self._latest_frame = rgb

    def _drain_video(self):
        while not self.video_rx.queue.empty():
            self.frames.add_chunk(self.video_rx.queue.get_nowait())

    def _handle_utterance(self, transcript):
        print(f"[stt] {transcript!r}")

        kind, fact = extract_memory_command(transcript)
        if kind == "remember":
            self.memory.remember(fact)
            self._speak_and_send(f"Got it, I'll remember {fact}.")
            return
        if kind == "clear":
            self.memory.clear()
            self.sender.send_command(protocol.OPCODE_CLEAR_MEMORY)
            self._speak_and_send("Memory cleared.")
            return

        reply = self.vlm.generate(
            system_prompt=self.memory.system_prompt(),
            user_text=transcript,
            image_rgb=self._latest_frame,
        )
        parsed = command_parser.parse_reply(reply)
        print(f"[vlm] {parsed}")

        if parsed.opcode is not None:
            self.sender.send_command(parsed.opcode, parsed.arg)
        if parsed.spoken_text:
            self._speak_and_send(parsed.spoken_text)

    def _speak_and_send(self, text):
        pcm, _sample_rate = self.tts.synthesize(text)
        self._utterance_id += 1
        self.sender.send_tts_audio(self._utterance_id, pcm)

    def run(self):
        print("Jarvis orchestrator running. Ctrl+C to stop.")
        try:
            while True:
                self._drain_video()
                try:
                    audio_pkt = self.audio_rx.queue.get(timeout=0.1)
                except queue.Empty:
                    continue
                transcript = self.stt.feed(audio_pkt.pcm)
                if transcript:
                    self._handle_utterance(transcript)
        except KeyboardInterrupt:
            pass
        finally:
            self.video_rx.stop()
            self.audio_rx.stop()
            self.sender.close()
            self.vlm.close()


def main():
    args = build_argparser().parse_args()
    Orchestrator(args).run()


if __name__ == "__main__":
    main()
