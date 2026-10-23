"""Servidor de voz local da Ava: transcrição (Whisper na GPU via MLX) e fala (Kokoro).

POST /v1/speech/transcribe   corpo = WAV, resposta {"text": ...}
POST /v1/speech/synthesize   corpo = {"text": ..., "voice_id": ...}, resposta = WAV
GET  /v1/speech/health

Desliga sozinho após 10 min sem pedidos, para liberar memória.
"""

import io
import json
import os
import threading
import time
import warnings
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import mlx.core as mx
import mlx_whisper
import numpy as np
import soundfile as sf
from kokoro import KPipeline

warnings.filterwarnings("ignore")

PORT = 8000
IDLE_LIMIT = 10 * 60
MAX_TEXT = 5000
WHISPER = "mlx-community/whisper-small-mlx"

mx.set_cache_limit(0)  # sem cache de buffers da GPU: num Mac de 8 GB a memória vale mais que o ganho
voice = KPipeline(lang_code="p", repo_id="hexgrad/Kokoro-82M")  # "p" = português do Brasil
lock = threading.Lock()  # os modelos não são thread-safe
last_request = time.monotonic()


def to_16k_mono(audio: np.ndarray, sr: int) -> np.ndarray:
    if audio.ndim > 1:
        audio = audio.mean(axis=1)
    if sr % 16000 == 0:  # 48 kHz do Mac: média de 3 em 3 (filtra e reduz de uma vez)
        k = sr // 16000
        audio = audio[: len(audio) // k * k].reshape(-1, k).mean(axis=1)
    elif sr != 16000:
        n = int(len(audio) * 16000 / sr)
        audio = np.interp(np.linspace(0, len(audio) - 1, n), np.arange(len(audio)), audio)
    return audio.astype(np.float32)


def transcribe(wav: bytes) -> str:
    audio, sr = sf.read(io.BytesIO(wav), dtype="float32")
    result = mlx_whisper.transcribe(
        to_16k_mono(audio, sr), path_or_hf_repo=WHISPER, language="pt", condition_on_previous_text=False
    )
    return result["text"].strip()


def synthesize(text: str, voice_id: str) -> bytes:
    audio = [chunk.audio.numpy() for chunk in voice(text, voice=voice_id) if chunk.audio is not None]
    buf = io.BytesIO()
    sf.write(buf, np.concatenate(audio) if audio else np.zeros(1), 24000, format="WAV")
    return buf.getvalue()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def reply(self, status: int, body: bytes, content_type: str = "application/json"):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/v1/speech/health":
            self.reply(200, b'{"available": true}')
        else:
            self.reply(404, b"{}")

    def do_POST(self):
        global last_request
        last_request = time.monotonic()
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        try:
            if self.path == "/v1/speech/transcribe":
                with lock:
                    text = transcribe(body)
                self.reply(200, json.dumps({"text": text}).encode())
            elif self.path == "/v1/speech/synthesize":
                req = json.loads(body)
                text = str(req.get("text", "")).strip()[:MAX_TEXT]
                if not text:
                    return self.reply(400, b'{"error": "texto vazio"}')
                with lock:
                    wav = synthesize(text, req.get("voice_id") or "pf_dora")
                self.reply(200, wav, "audio/wav")
            else:
                self.reply(404, b"{}")
        except Exception as exc:  # devolve o erro em vez de derrubar o servidor
            self.reply(500, json.dumps({"error": str(exc)}).encode())
        last_request = time.monotonic()


def shutdown_when_idle(server: ThreadingHTTPServer):
    while True:
        time.sleep(30)
        if time.monotonic() - last_request > IDLE_LIMIT:
            server.shutdown()
            return


if __name__ == "__main__":
    transcribe(synthesize("Olá.", "pm_alex"))  # aquece os dois modelos antes do primeiro pedido
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    threading.Thread(target=shutdown_when_idle, args=(server,), daemon=True).start()
    print(f"Ava backend pronto em http://127.0.0.1:{PORT} (pid {os.getpid()})", flush=True)
    server.serve_forever()
