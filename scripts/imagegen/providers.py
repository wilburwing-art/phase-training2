"""Provider adapters.

Every provider exposes the same two calls:
    generate(prompt, size)                 -> PNG bytes
    generate_with_ref(prompt, ref, size)   -> PNG bytes

Model ids and endpoint shapes were checked against each vendor's docs on
2026-09-11. Only the OpenRouter adapters have been exercised against a live
endpoint; the two native adapters are written to the current docs but no key
for either vendor exists on this machine, so their first call is their test.

    or-google   google/gemini-3-pro-image   via OpenRouter /api/v1/images
    or-openai   openai/gpt-5.4-image-2      via OpenRouter /api/v1/images
    openai      gpt-image-2.5-sunburst      native, needs OPENAI_API_KEY
    google      gemini-3-pro-image          native, needs GOOGLE_API_KEY

`native_transparency` says whether the route has a real `background:
transparent` parameter. Only native OpenAI does. Every other route gets a
prompt asking for flat white (see prompts.py), because asked for "transparent"
in prose both gpt-image and gemini-3-pro painted a checkerboard into the
pixels. Keying white out is a post-processing step for production assets and
does not affect what the bake-off measures.
"""

import base64
import io
import os
import time

import requests

# OpenRouter. Newest image-output model per vendor in the catalogue on 2026-09-11.
OPENROUTER_BASE = "https://openrouter.ai/api/v1"
OPENROUTER_GOOGLE_MODEL = "google/gemini-3-pro-image"
OPENROUTER_OPENAI_MODEL = "openai/gpt-5.4-image-2"

# Native OpenAI. developers.openai.com/api/docs/models lists two image models:
# gpt-image-2.5-sunburst ("most capable") and gpt-image-2.5-flare ("fast").
OPENAI_MODEL = "gpt-image-2.5-sunburst"
OPENAI_BASE = "https://api.openai.com/v1"

# Native Gemini. ai.google.dev/gemini-api/docs/image-generation documents only
# the /v1beta/interactions endpoint now; generateContent no longer appears.
GOOGLE_MODEL = "gemini-3-pro-image"
GOOGLE_BASE = "https://generativelanguage.googleapis.com/v1beta"

TIMEOUT = 300
MAX_RETRIES = 3


class ProviderError(RuntimeError):
    pass


def _retry(fn):
    """Retry on transport errors, 429 and 5xx. A 4xx other than 429 is a bad
    request and will not fix itself, so it raises at once with the body."""
    last = None
    for attempt in range(MAX_RETRIES):
        try:
            return fn()
        except requests.HTTPError as exc:
            status = exc.response.status_code if exc.response is not None else 0
            body = exc.response.text[:500] if exc.response is not None else ""
            if 400 <= status < 500 and status != 429:
                raise ProviderError(f"HTTP {status}: {body}") from exc
            last = ProviderError(f"HTTP {status}: {body}")
        except Exception as exc:
            last = exc
        if attempt < MAX_RETRIES - 1:
            time.sleep(2 ** attempt * 3)
    raise ProviderError(str(last))


def _b64_data_url(png_bytes):
    return "data:image/png;base64," + base64.b64encode(png_bytes).decode()


class OpenRouterImages:
    """OpenRouter's dedicated image endpoint: POST /images with prompt,
    aspect_ratio, resolution and optional input_references; the image comes
    back in data[0].b64_json."""

    native_transparency = False

    def __init__(self, name, model):
        self.name = name
        self.model = model
        self.key = os.environ["OPENROUTER_API_KEY"]

    def _post(self, prompt, size, refs=()):
        w, h = (int(x) for x in size.split("x"))
        body = {
            "model": self.model,
            "prompt": prompt,
            "aspect_ratio": "1:1" if w == h else f"{w}:{h}",
            "resolution": "1K",
        }
        if refs:
            body["input_references"] = [
                {"type": "image_url", "image_url": {"url": _b64_data_url(r)}}
                for r in refs
            ]

        def call():
            r = requests.post(
                f"{OPENROUTER_BASE}/images",
                headers={
                    "Authorization": f"Bearer {self.key}",
                    "Content-Type": "application/json",
                },
                json=body,
                timeout=TIMEOUT,
            )
            r.raise_for_status()
            data = r.json().get("data") or []
            if not data or not data[0].get("b64_json"):
                raise ProviderError(f"no image in response: {r.text[:300]}")
            return base64.b64decode(data[0]["b64_json"])

        return _retry(call)

    def generate(self, prompt, size="1024x1024"):
        return self._post(prompt, size)

    def generate_with_ref(self, prompt, ref_bytes, size="1024x1024"):
        return self._post(prompt, size, refs=[ref_bytes])


class OpenAIImages:
    name = "openai"
    native_transparency = True

    def __init__(self):
        self.key = os.environ["OPENAI_API_KEY"]

    def _headers(self):
        return {"Authorization": f"Bearer {self.key}"}

    def generate(self, prompt, size="1024x1024"):
        def call():
            r = requests.post(
                f"{OPENAI_BASE}/images/generations",
                headers={**self._headers(), "Content-Type": "application/json"},
                json={
                    "model": OPENAI_MODEL,
                    "prompt": prompt,
                    "size": size,
                    "n": 1,
                    "background": "transparent",
                    "output_format": "png",
                },
                timeout=TIMEOUT,
            )
            r.raise_for_status()
            return base64.b64decode(r.json()["data"][0]["b64_json"])

        return _retry(call)

    def generate_with_ref(self, prompt, ref_bytes, size="1024x1024"):
        def call():
            files = [("image[]", ("ref.png", io.BytesIO(ref_bytes), "image/png"))]
            r = requests.post(
                f"{OPENAI_BASE}/images/edits",
                headers=self._headers(),
                data={
                    "model": OPENAI_MODEL,
                    "prompt": prompt,
                    "size": size,
                    "n": 1,
                    "background": "transparent",
                    "output_format": "png",
                },
                files=files,
                timeout=TIMEOUT,
            )
            r.raise_for_status()
            return base64.b64decode(r.json()["data"][0]["b64_json"])

        return _retry(call)


class GoogleImages:
    name = "google"
    native_transparency = False

    def __init__(self):
        self.key = os.environ["GOOGLE_API_KEY"]

    @staticmethod
    def _find_image(node):
        """The docs show the image via the SDK (interaction.output_image.data)
        and do not print the raw JSON, so walk the response for the first
        block shaped {type: image, data: <b64>} rather than guess a path."""
        if isinstance(node, dict):
            if node.get("type") == "image" and node.get("data"):
                return node["data"]
            for v in node.values():
                found = GoogleImages._find_image(v)
                if found:
                    return found
        elif isinstance(node, list):
            for v in node:
                found = GoogleImages._find_image(v)
                if found:
                    return found
        return None

    def _post(self, inputs, size):
        w, h = (int(x) for x in size.split("x"))

        def call():
            r = requests.post(
                f"{GOOGLE_BASE}/interactions",
                headers={
                    "x-goog-api-key": self.key,
                    "Content-Type": "application/json",
                },
                json={
                    "model": GOOGLE_MODEL,
                    "input": inputs,
                    "response_format": {
                        "type": "image",
                        "mime_type": "image/png",
                        "aspect_ratio": "1:1" if w == h else f"{w}:{h}",
                        "image_size": "1K",
                    },
                },
                timeout=TIMEOUT,
            )
            r.raise_for_status()
            data = self._find_image(r.json())
            if not data:
                raise ProviderError(f"no image part in response: {r.text[:300]}")
            return base64.b64decode(data)

        return _retry(call)

    def generate(self, prompt, size="1024x1024"):
        return self._post([{"type": "text", "text": prompt}], size)

    def generate_with_ref(self, prompt, ref_bytes, size="1024x1024"):
        return self._post([
            {"type": "text", "text": prompt},
            {
                "type": "image",
                "mime_type": "image/png",
                "data": base64.b64encode(ref_bytes).decode(),
            },
        ], size)


PROVIDERS = {
    "or-google": lambda: OpenRouterImages("or-google", OPENROUTER_GOOGLE_MODEL),
    "or-openai": lambda: OpenRouterImages("or-openai", OPENROUTER_OPENAI_MODEL),
    "openai": OpenAIImages,
    "google": GoogleImages,
}
