"""Persistent assistant identity/instructions + a running memory tab.

The whole point (per the original design discussion) is that voice commands
can durably edit what gets prepended to every LLM call, and durably forget
it again, without touching code:
  - "remember X"       -> append a line under MEMORY, saved to disk
  - "clear your memory" -> truncate back to the base template

This is a single text file. No vector DB, no conversation history replay --
just a file the assistant reads and can append one line to.
"""
import re
from pathlib import Path

BASE_TEMPLATE = """\
You are Jarvis, a voice assistant embedded in a webcam-and-microphone rig
built on an FPGA. You see through a camera (a still frame arrives with
roughly every user turn) and hear through a microphone (already
transcribed to text below). Reply concisely -- your reply is spoken aloud
through a speech synthesizer, so avoid formatting, bullet points, or long
tangents.

If your reply should also trigger a physical action (an LED, a servo
move, etc), end your reply with a single command tag on its own line, in
exactly this form:
  <<CMD:OPCODE:ARG>>
Valid OPCODEs: SET_LED, SET_SERVO_PAN, SET_SERVO_TILT, CLEAR_MEMORY.
Only include a command tag when the user actually asked for a physical
action. Never mention the tag itself out loud.

=== MEMORY ===
"""

_MEMORY_HEADER = "=== MEMORY ==="


class Memory:
    def __init__(self, path):
        self.path = Path(path)
        if not self.path.exists():
            self.path.write_text(BASE_TEMPLATE, encoding="utf-8")

    def read(self):
        return self.path.read_text(encoding="utf-8")

    def remember(self, fact):
        fact = fact.strip()
        if not fact:
            return
        text = self.read()
        if not text.endswith("\n"):
            text += "\n"
        text += f"- {fact}\n"
        self.path.write_text(text, encoding="utf-8")

    def clear(self):
        self.path.write_text(BASE_TEMPLATE, encoding="utf-8")

    def system_prompt(self):
        return self.read()


_REMEMBER_RE = re.compile(r"\bremember (?:that )?(.+)", re.IGNORECASE)
_CLEAR_RE = re.compile(r"\b(clear|forget|reset) (?:your |the )?memory\b", re.IGNORECASE)


def extract_memory_command(transcript):
    """Returns ('remember', fact) or ('clear', None) or (None, None)."""
    m = _CLEAR_RE.search(transcript)
    if m:
        return "clear", None
    m = _REMEMBER_RE.search(transcript)
    if m:
        return "remember", m.group(1).strip().rstrip(".")
    return None, None
