"""Reassembles video chunks (protocol.VideoChunk) into full frames.

Unpacks the 12bpp RGB444 packing described in docs/wire_protocol.md:
2 pixels per 3 bytes, [RRRRGGGG][BBBBRRRR][GGGGBBBB].
"""
import numpy as np


class FrameReassembler:
    def __init__(self, on_frame):
        """on_frame(frame_id, rgb_array_uint8_HxWx3) called once per completed frame."""
        self._on_frame = on_frame
        self._frame_id = None
        self._total_chunks = None
        self._width = None
        self._height = None
        self._chunks = {}

    def add_chunk(self, vc):
        if vc.frame_id != self._frame_id:
            self._frame_id = vc.frame_id
            self._total_chunks = vc.total_chunks
            self._width = vc.width
            self._height = vc.height
            self._chunks = {}

        self._chunks[vc.chunk_index] = vc.data

        if len(self._chunks) == self._total_chunks:
            raw = b"".join(self._chunks[i] for i in range(self._total_chunks))
            rgb = unpack_rgb444(raw, self._width, self._height)
            self._on_frame(self._frame_id, rgb)
            self._frame_id = None
            self._chunks = {}


def unpack_rgb444(raw, width, height):
    n_pixels = width * height
    n_bytes_needed = (n_pixels * 3 + 1) // 2
    if len(raw) < n_bytes_needed:
        raise ValueError(f"short frame: got {len(raw)} bytes, need {n_bytes_needed}")

    b = np.frombuffer(raw[:n_bytes_needed], dtype=np.uint8)
    pairs = n_pixels // 2
    b0 = b[0:pairs * 3:3].astype(np.uint16)
    b1 = b[1:pairs * 3:3].astype(np.uint16)
    b2 = b[2:pairs * 3:3].astype(np.uint16)

    r0 = (b0 >> 4) & 0xF
    g0 = b0 & 0xF
    b0v = (b1 >> 4) & 0xF
    r1 = b1 & 0xF
    g1 = (b2 >> 4) & 0xF
    b1v = b2 & 0xF

    out = np.empty((pairs * 2, 3), dtype=np.uint8)
    out[0::2, 0] = (r0 * 17).astype(np.uint8)  # scale 4-bit -> 8-bit (0..15 -> 0..255)
    out[0::2, 1] = (g0 * 17).astype(np.uint8)
    out[0::2, 2] = (b0v * 17).astype(np.uint8)
    out[1::2, 0] = (r1 * 17).astype(np.uint8)
    out[1::2, 1] = (g1 * 17).astype(np.uint8)
    out[1::2, 2] = (b1v * 17).astype(np.uint8)

    if pairs * 2 < n_pixels:
        out = np.vstack([out, np.zeros((n_pixels - pairs * 2, 3), dtype=np.uint8)])

    return out.reshape(height, width, 3)
