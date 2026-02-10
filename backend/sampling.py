"""
Sampling utilities for next-token generation.

The model produces logits (unnormalized scores) for each token ID.
Sampling turns these logits into a probability distribution and draws ONE token.
"""

from __future__ import annotations

from typing import List, Tuple

import torch


def _safe_temperature(temperature: float) -> float:
    try:
        t = float(temperature)
    except Exception:
        return 1.0
    return max(t, 1e-5)


def apply_temperature(logits: torch.Tensor, temperature: float) -> torch.Tensor:
    return logits / _safe_temperature(temperature)


def top_k_filter(logits: torch.Tensor, top_k: int) -> torch.Tensor:
    """
    Keep only the top_k tokens by logit value.
    """
    k = int(top_k)
    if k <= 0 or k >= logits.numel():
        return logits
    values, _ = torch.topk(logits, k)
    threshold = values[-1]
    return torch.where(logits >= threshold, logits, torch.tensor(float("-inf"), device=logits.device))


def top_p_filter(logits: torch.Tensor, top_p: float) -> torch.Tensor:
    """
    Nucleus (top-p) filtering:
    Keep the smallest set of tokens whose cumulative probability >= p.
    """
    p = float(top_p)
    if p >= 1.0:
        return logits
    p = max(p, 0.0)

    sorted_logits, sorted_idx = torch.sort(logits, descending=True)
    sorted_probs = torch.softmax(sorted_logits, dim=-1)
    cumprobs = torch.cumsum(sorted_probs, dim=-1)

    # Mask tokens that push cumulative prob over p.
    sorted_mask = cumprobs > p
    # Always keep at least one token.
    sorted_mask[..., 0] = False

    filtered_sorted_logits = torch.where(
        sorted_mask, torch.tensor(float("-inf"), device=logits.device), sorted_logits
    )
    out = torch.full_like(logits, float("-inf"))
    out.scatter_(0, sorted_idx, filtered_sorted_logits)
    return out


def sample_next_token(
    logits: torch.Tensor,
    temperature: float = 1.0,
    top_k: int = 0,
    top_p: float = 1.0,
    generator: torch.Generator | None = None,
) -> Tuple[int, float, torch.Tensor]:
    """
    Returns: (token_id, token_probability, probs_distribution)
    """
    if logits.dim() != 1:
        raise ValueError(f"logits must be 1D [vocab], got shape {tuple(logits.shape)}")

    filtered = apply_temperature(logits, temperature)
    filtered = top_k_filter(filtered, top_k)
    filtered = top_p_filter(filtered, top_p)

    probs = torch.softmax(filtered, dim=-1)
    token_id = int(torch.multinomial(probs, 1, generator=generator).item())
    token_prob = float(probs[token_id].item())
    return token_id, token_prob, probs


def topk_probs(probs: torch.Tensor, k: int = 12) -> List[Tuple[int, float]]:
    """
    Return top-k (token_id, prob) pairs sorted by probability descending.
    """
    kk = int(k)
    kk = max(1, min(kk, probs.numel()))
    values, indices = torch.topk(probs, kk)
    return [(int(i.item()), float(v.item())) for v, i in zip(values, indices)]


