"""Qwen2.5-VL client via Ollama's REST API.

Ollama is the path of least resistance for running Qwen2.5-VL locally: one
`ollama pull qwen2.5vl:7b`, no separate inference-server setup. If you swap
to vLLM's OpenAI-compatible server instead, only this file needs to change
(same request shape, different base_url/endpoint -- see the commented
alternative below).
"""
import base64

import httpx


class VLMClient:
    def __init__(self, base_url="http://localhost:11434", model="qwen2.5vl:7b", timeout=60.0):
        self._base_url = base_url.rstrip("/")
        self._model = model
        self._client = httpx.Client(timeout=timeout)

    def generate(self, system_prompt, user_text, image_rgb=None):
        """image_rgb: HxWx3 uint8 numpy array, or None for text-only turns."""
        payload = {
            "model": self._model,
            "system": system_prompt,
            "prompt": user_text,
            "stream": False,
        }
        if image_rgb is not None:
            payload["images"] = [base64.b64encode(_encode_png(image_rgb)).decode("ascii")]

        resp = self._client.post(f"{self._base_url}/api/generate", json=payload)
        resp.raise_for_status()
        return resp.json()["response"]

    def close(self):
        self._client.close()


def _encode_png(rgb_array):
    import io

    from PIL import Image

    buf = io.BytesIO()
    Image.fromarray(rgb_array, mode="RGB").save(buf, format="PNG")
    return buf.getvalue()


# --- vLLM / OpenAI-compatible alternative -----------------------------------
# If you're running `vllm serve Qwen/Qwen2.5-VL-7B-Instruct` instead of Ollama,
# swap VLMClient.generate's body for the OpenAI chat-completions shape:
#
#   payload = {
#       "model": "Qwen/Qwen2.5-VL-7B-Instruct",
#       "messages": [
#           {"role": "system", "content": system_prompt},
#           {"role": "user", "content": [
#               {"type": "text", "text": user_text},
#               {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{b64_png}"}},
#           ]},
#       ],
#   }
#   resp = self._client.post(f"{self._base_url}/v1/chat/completions", json=payload)
#   return resp.json()["choices"][0]["message"]["content"]
