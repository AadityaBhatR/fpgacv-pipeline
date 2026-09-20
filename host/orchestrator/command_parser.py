"""Splits an LLM reply into (spoken_text, opcode, arg).

Matches the tag format documented in memory.BASE_TEMPLATE and
docs/wire_protocol.md's opcode table: a single `<<CMD:OPCODE:ARG>>` line,
optionally present, anywhere in the reply (in practice the model is told to
put it last, but this doesn't assume that).
"""
import re
from dataclasses import dataclass

import protocol

_TAG_RE = re.compile(r"<<CMD:([A-Z_]+):(-?\d+)>>")

_OPCODE_NAMES = {
    "NOP": protocol.OPCODE_NOP,
    "SET_LED": protocol.OPCODE_SET_LED,
    "SET_SERVO_PAN": protocol.OPCODE_SET_SERVO_PAN,
    "SET_SERVO_TILT": protocol.OPCODE_SET_SERVO_TILT,
    "CLEAR_MEMORY": protocol.OPCODE_CLEAR_MEMORY,
}


@dataclass
class ParsedReply:
    spoken_text: str
    opcode: int | None
    arg: int


def parse_reply(reply_text):
    match = _TAG_RE.search(reply_text)
    spoken_text = _TAG_RE.sub("", reply_text).strip()
    spoken_text = re.sub(r"\n{2,}", "\n", spoken_text).strip()

    if not match:
        return ParsedReply(spoken_text, None, 0)

    name, arg_str = match.group(1), match.group(2)
    opcode = _OPCODE_NAMES.get(name)
    if opcode is None:
        return ParsedReply(spoken_text, None, 0)
    return ParsedReply(spoken_text, opcode, int(arg_str))
