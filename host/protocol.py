"""Wire format (de)serialization matching docs/wire_protocol.md exactly.

Single source of truth for packet layout so the receiver, sender, and any
future FPGA-side reference implementation can't silently drift apart.
"""
import struct
from dataclasses import dataclass

VIDEO_PORT = 5001
AUDIO_PORT = 5002
TELEMETRY_PORT = 5003
RETURN_PORT = 5004

PKT_VIDEO_CHUNK = 0x01
PKT_MIC_AUDIO = 0x02
PKT_TELEMETRY = 0x03
PKT_TTS_AUDIO = 0x10
PKT_COMMAND = 0x20

OPCODE_NOP = 0x00
OPCODE_SET_LED = 0x01
OPCODE_SET_SERVO_PAN = 0x02
OPCODE_SET_SERVO_TILT = 0x03
OPCODE_CLEAR_MEMORY = 0x04

_VIDEO_HDR = struct.Struct(">BIHHHHB")   # type, frame_id, chunk_idx, total_chunks, width, height, format
_MIC_HDR = struct.Struct(">BI")          # type, seq_num
_TTS_HDR = struct.Struct(">BIHH")        # type, utterance_id, chunk_idx, total_chunks
_CMD_PKT = struct.Struct(">BBI")         # type, opcode, arg


@dataclass
class VideoChunk:
    frame_id: int
    chunk_index: int
    total_chunks: int
    width: int
    height: int
    format: int
    data: bytes


@dataclass
class MicAudioPacket:
    seq_num: int
    pcm: bytes


def pack_video_chunk(frame_id, chunk_index, total_chunks, width, height, fmt, data):
    return _VIDEO_HDR.pack(PKT_VIDEO_CHUNK, frame_id, chunk_index, total_chunks, width, height, fmt) + data


def unpack_video_chunk(packet):
    ptype, frame_id, chunk_index, total_chunks, width, height, fmt = _VIDEO_HDR.unpack_from(packet)
    if ptype != PKT_VIDEO_CHUNK:
        raise ValueError(f"not a video chunk packet (type=0x{ptype:02x})")
    return VideoChunk(frame_id, chunk_index, total_chunks, width, height, fmt, packet[_VIDEO_HDR.size:])


def pack_mic_audio(seq_num, pcm_bytes):
    return _MIC_HDR.pack(PKT_MIC_AUDIO, seq_num) + pcm_bytes


def unpack_mic_audio(packet):
    ptype, seq_num = _MIC_HDR.unpack_from(packet)
    if ptype != PKT_MIC_AUDIO:
        raise ValueError(f"not a mic audio packet (type=0x{ptype:02x})")
    return MicAudioPacket(seq_num, packet[_MIC_HDR.size:])


def pack_tts_chunk(utterance_id, chunk_index, total_chunks, pcm_bytes):
    return _TTS_HDR.pack(PKT_TTS_AUDIO, utterance_id, chunk_index, total_chunks) + pcm_bytes


def unpack_tts_chunk(packet):
    ptype, utterance_id, chunk_index, total_chunks = _TTS_HDR.unpack_from(packet)
    if ptype != PKT_TTS_AUDIO:
        raise ValueError(f"not a TTS audio packet (type=0x{ptype:02x})")
    return utterance_id, chunk_index, total_chunks, packet[_TTS_HDR.size:]


def pack_command(opcode, arg=0):
    return _CMD_PKT.pack(PKT_COMMAND, opcode, arg & 0xFFFFFFFF)


def unpack_command(packet):
    ptype, opcode, arg = _CMD_PKT.unpack_from(packet)
    if ptype != PKT_COMMAND:
        raise ValueError(f"not a command packet (type=0x{ptype:02x})")
    return opcode, arg
