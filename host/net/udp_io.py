"""UDP sockets for the three FPGA->PC streams plus the PC->FPGA return path.

Each receiver runs its own thread and pushes decoded packets onto a
queue.Queue, so the orchestrator's main loop never blocks on socket recv.
"""
import queue
import socket
import threading

import protocol


class UdpReceiver:
    def __init__(self, port, unpack_fn, bind_addr="0.0.0.0", queue_size=256):
        self._sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self._sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._sock.bind((bind_addr, port))
        self._unpack = unpack_fn
        self.queue = queue.Queue(maxsize=queue_size)
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._run, daemon=True)

    def start(self):
        self._thread.start()
        return self

    def stop(self):
        self._stop.set()
        self._sock.close()

    def _run(self):
        while not self._stop.is_set():
            try:
                raw, _addr = self._sock.recvfrom(2048)
            except OSError:
                break
            try:
                item = self._unpack(raw)
            except ValueError:
                continue
            try:
                self.queue.put_nowait(item)
            except queue.Full:
                try:
                    self.queue.get_nowait()
                except queue.Empty:
                    pass
                self.queue.put_nowait(item)


class ReturnSender:
    """Sends TTS audio + command packets back to the FPGA (port 5004)."""

    def __init__(self, fpga_ip, port=protocol.RETURN_PORT):
        self._addr = (fpga_ip, port)
        self._sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

    def send_command(self, opcode, arg=0):
        self._sock.sendto(protocol.pack_command(opcode, arg), self._addr)

    def send_tts_audio(self, utterance_id, pcm_bytes, chunk_size=1400):
        total_chunks = max(1, (len(pcm_bytes) + chunk_size - 1) // chunk_size)
        for i in range(total_chunks):
            chunk = pcm_bytes[i * chunk_size:(i + 1) * chunk_size]
            pkt = protocol.pack_tts_chunk(utterance_id, i, total_chunks, chunk)
            self._sock.sendto(pkt, self._addr)

    def close(self):
        self._sock.close()


def make_video_receiver(bind_addr="0.0.0.0"):
    return UdpReceiver(protocol.VIDEO_PORT, protocol.unpack_video_chunk, bind_addr)


def make_audio_receiver(bind_addr="0.0.0.0"):
    return UdpReceiver(protocol.AUDIO_PORT, protocol.unpack_mic_audio, bind_addr)
