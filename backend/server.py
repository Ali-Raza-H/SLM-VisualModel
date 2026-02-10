"""
WebSocket server that runs the tiny SLM and streams internals to the GUI.

The model is intentionally untrained (random weights). The goal is to visualize
real internal signals of a Transformer during generation:
  - attention weights
  - MLP (post-GELU) activations
  - residual stream L2 norms (activation "energy")

One request -> one generated token -> one response (real-time HUD updates).
"""

from __future__ import annotations

import asyncio
import json
import os
from dataclasses import dataclass
from typing import Any, Dict, List, Tuple

import torch
import websockets

from model import ModelConfig, TinyGPT
from sampling import sample_next_token, topk_probs
from tokenizer import BOS, EOS, ByteTokenizer


HOST = "localhost"
PORT = 8765

VIZ_WINDOW = 32
TOPK_TO_SEND = 12
FLOAT_DECIMALS = 4


def _resolve_device() -> torch.device:
    """
    Device selection.

    Default: CUDA if available, else CPU.
    Override via env var:
      - SLM_DEVICE=auto (default)
      - SLM_DEVICE=cpu
      - SLM_DEVICE=cuda
    """
    forced = os.environ.get("SLM_DEVICE", "auto").strip().lower()
    if forced in ("", "auto"):
        return torch.device("cuda" if torch.cuda.is_available() else "cpu")
    if forced in ("cpu",):
        return torch.device("cpu")
    if forced in ("cuda", "gpu"):
        if not torch.cuda.is_available():
            raise RuntimeError(
                "SLM_DEVICE=cuda requested but CUDA is not available. "
                f"(torch={torch.__version__}, cuda_built={torch.backends.cuda.is_built()}, torch.version.cuda={torch.version.cuda}) "
                "Install a CUDA-enabled PyTorch build to use your GPU."
            )
        return torch.device("cuda")
    raise RuntimeError(f"Unknown SLM_DEVICE={forced!r}. Use auto|cpu|cuda.")


def _clamp_int(value: Any, lo: int, hi: int, default: int) -> int:
    try:
        v = int(value)
    except Exception:
        return default
    return max(lo, min(hi, v))


def _clamp_float(value: Any, lo: float, hi: float, default: float) -> float:
    try:
        v = float(value)
    except Exception:
        return default
    if v != v:  # NaN
        return default
    return max(lo, min(hi, v))


def _tensor_to_list(t: torch.Tensor, decimals: int = FLOAT_DECIMALS) -> Any:
    """
    Convert a tensor to JSON-friendly nested lists, rounding floats to reduce payload size.
    """
    tt = t.detach()
    if tt.is_floating_point():
        tt = tt.float()
        scale = float(10**decimals)
        tt = torch.round(tt * scale) / scale
    return tt.cpu().tolist()


def _build_error(message: str) -> str:
    return json.dumps({"error": message}, ensure_ascii=False)


@dataclass
class SessionState:
    token_ids: List[int]
    t: int = 0


def _extract_prompt(req: Dict[str, Any]) -> str:
    prompt = req.get("prompt", "")
    if prompt is None:
        return ""
    return str(prompt)


def _select_window(t_active: int) -> int:
    return min(VIZ_WINDOW, int(t_active))


def _prepare_response(
    *,
    session: SessionState,
    tokenizer: ByteTokenizer,
    cfg: ModelConfig,
    device: torch.device,
    viz_layer: int,
    viz_head: int,
    logits_t: int,
    cache: Dict[str, List[torch.Tensor]],
    sampled_id: int,
    sampled_prob: float,
    probs: torch.Tensor,
) -> Dict[str, Any]:
    w = _select_window(logits_t)

    # Attention: [n_heads, T, T] -> one head window [w, w]
    attn_all = cache["attn"][viz_layer]
    attn_win = attn_all[viz_head, -w:, -w:]

    # MLP: [T, d_ff] -> window [w, d_ff]
    mlp_win = cache["mlp"][viz_layer][-w:, :]

    # Residual norms: [T] -> window [w]
    resid_win = cache["resid"][viz_layer][-w:]

    resid_layers_last = [float(cache["resid"][l][-1].item()) for l in range(cfg.n_layers)]

    topk = topk_probs(probs, k=TOPK_TO_SEND)
    topk_json = [{"id": tid, "token": tokenizer.id_to_piece(tid), "prob": float(p)} for tid, p in topk]

    token_pieces = [tokenizer.id_to_piece(tid) for tid in session.token_ids]
    generated = tokenizer.decode(session.token_ids)

    done = int(sampled_id) == EOS

    resp: Dict[str, Any] = {
        "token_ids": session.token_ids,
        "tokens": token_pieces,
        "generated": generated,
        "sampled": {"id": int(sampled_id), "token": tokenizer.id_to_piece(int(sampled_id)), "prob": float(sampled_prob)},
        "topk": topk_json,
        "attention": {
            "layer": viz_layer,
            "head": viz_head,
            "matrix": _tensor_to_list(attn_win),
        },
        "mlp": {
            "layer": viz_layer,
            "activations": _tensor_to_list(mlp_win),
            "window_start": max(0, len(session.token_ids) - w),
        },
        "residual": {
            "layer": viz_layer,
            "norms": _tensor_to_list(resid_win),
            "window_start": max(0, len(session.token_ids) - w),
        },
        "residual_layers_last": [round(x, FLOAT_DECIMALS) for x in resid_layers_last],
        "meta": {
            "device": str(device),
            "t": session.t,
            "max_seq_len": cfg.max_seq_len,
            "viz_window": VIZ_WINDOW,
            "done": done,
            "cuda_available": torch.cuda.is_available(),
            "cuda_built": torch.backends.cuda.is_built(),
            "torch_cuda": str(torch.version.cuda) if torch.version.cuda is not None else "",
            "gpu_name": torch.cuda.get_device_name(0) if torch.cuda.is_available() else "",
        },
    }
    return resp


async def main() -> None:
    device = _resolve_device()
    tokenizer = ByteTokenizer()
    cfg = ModelConfig()
    model = TinyGPT(cfg).to(device)
    model.eval()

    cuda_available = torch.cuda.is_available()
    cuda_built = torch.backends.cuda.is_built()
    torch_cuda = torch.version.cuda
    gpu_name = torch.cuda.get_device_name(0) if cuda_available else ""

    print(f"[backend] torch={torch.__version__} cuda_built={cuda_built} cuda_available={cuda_available} torch_cuda={torch_cuda}")
    if gpu_name:
        print(f"[backend] gpu0={gpu_name}")
    print(f"[backend] device={device}  model=d_model={cfg.d_model} layers={cfg.n_layers} heads={cfg.n_heads} d_ff={cfg.d_ff}")
    print(f"[backend] serving ws://{HOST}:{PORT}")

    async def handler(conn: websockets.ServerConnection) -> None:
        session = SessionState(token_ids=[])
        print("[backend] client connected")
        try:
            async for raw in conn:
                try:
                    if isinstance(raw, bytes):
                        raw = raw.decode("utf-8", errors="replace")
                    req = json.loads(raw)
                    if not isinstance(req, dict):
                        await conn.send(_build_error("Request must be a JSON object."))
                        continue
                except Exception as e:
                    await conn.send(_build_error(f"Invalid JSON: {e}"))
                    continue

                # Validate / clamp controls.
                step_flag = bool(req.get("step", True))
                if not step_flag:
                    await conn.send(_build_error("Only step=true is supported."))
                    continue

                temperature = _clamp_float(req.get("temperature", 1.0), 0.05, 5.0, 1.0)
                top_k = _clamp_int(req.get("top_k", 0), 0, 200, 0)
                top_p = _clamp_float(req.get("top_p", 1.0), 0.0, 1.0, 1.0)
                viz_layer = _clamp_int(req.get("viz_layer", 0), 0, cfg.n_layers - 1, 0)
                viz_head = _clamp_int(req.get("viz_head", 0), 0, cfg.n_heads - 1, 0)

                # Reset context if a non-empty prompt is provided.
                prompt = _extract_prompt(req)
                if prompt != "":
                    session.token_ids = [BOS] + tokenizer.encode(prompt)
                    session.t = 0

                if not session.token_ids:
                    await conn.send(_build_error("Empty session. Send a non-empty prompt first."))
                    continue

                try:
                    # The model has a fixed context window (max_seq_len). Feeding only the
                    # last tokens keeps generation responsive even if the session grows.
                    active_ids = session.token_ids[-cfg.max_seq_len :]
                    input_ids = torch.tensor([active_ids], dtype=torch.long, device=device)
                    logits, cache = model(input_ids)  # logits: [1, T, vocab]
                    last_logits = logits[0, -1]

                    next_id, next_prob, probs = sample_next_token(
                        last_logits, temperature=temperature, top_k=top_k, top_p=top_p
                    )
                    session.token_ids.append(int(next_id))
                    session.t += 1

                    resp = _prepare_response(
                        session=session,
                        tokenizer=tokenizer,
                        cfg=cfg,
                        device=device,
                        viz_layer=viz_layer,
                        viz_head=viz_head,
                        logits_t=int(logits.shape[1]),
                        cache=cache,
                        sampled_id=int(next_id),
                        sampled_prob=float(next_prob),
                        probs=probs,
                    )
                    await conn.send(json.dumps(resp, ensure_ascii=False))
                except Exception as e:
                    await conn.send(_build_error(f"Server error: {e}"))
        except websockets.exceptions.ConnectionClosed:
            pass
        finally:
            print("[backend] client disconnected")

    async with websockets.serve(handler, HOST, PORT, max_size=2 * 1024 * 1024):
        await asyncio.Future()  # run forever


if __name__ == "__main__":
    asyncio.run(main())
