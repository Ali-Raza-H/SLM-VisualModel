"""
Tiny decoder-only Transformer (GPT-style), randomly initialized.

This is intentionally *untrained* so the generated text is nonsense, but the
internal signals (attention patterns, MLP activations, residual energy) are
real and meaningful for learning how Transformers work.

Core ideas:
  - Token/position embeddings produce a sequence of vectors ("residual stream")
  - Each block mixes information with causal self-attention
  - Each block transforms features with an MLP
  - Residual connections accumulate features across layers
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Dict, List, Tuple

import torch
import torch.nn as nn
import torch.nn.functional as F


@dataclass(frozen=True)
class ModelConfig:
    vocab_size: int = 259
    d_model: int = 128
    n_layers: int = 4
    n_heads: int = 4
    d_ff: int = 256
    max_seq_len: int = 128


class CausalSelfAttention(nn.Module):
    """
    Multi-head causal self-attention implemented from scratch so we can expose
    attention weights [n_heads, T, T] for visualization.

    For each token position i, attention produces a weighted mixture over all
    previous positions j <= i. The causal mask enforces "no peeking" at future
    tokens, which is what makes this decoder-only (GPT-style) model autoregressive.
    """

    def __init__(self, cfg: ModelConfig):
        super().__init__()
        if cfg.d_model % cfg.n_heads != 0:
            raise ValueError("d_model must be divisible by n_heads")

        self.n_heads = cfg.n_heads
        self.head_dim = cfg.d_model // cfg.n_heads

        self.qkv = nn.Linear(cfg.d_model, 3 * cfg.d_model, bias=False)
        self.proj = nn.Linear(cfg.d_model, cfg.d_model, bias=False)

        # True above the diagonal => mask out "future" tokens.
        causal_mask = torch.triu(torch.ones(cfg.max_seq_len, cfg.max_seq_len, dtype=torch.bool), diagonal=1)
        self.register_buffer("causal_mask", causal_mask, persistent=False)

    def forward(self, x: torch.Tensor) -> Tuple[torch.Tensor, torch.Tensor]:
        """
        x: [B, T, d_model]
        returns:
          - y: [B, T, d_model]
          - attn_weights: [B, n_heads, T, T] (after softmax)
        """
        bsz, t, d_model = x.shape

        qkv = self.qkv(x)  # [B, T, 3*d_model]
        q, k, v = qkv.chunk(3, dim=-1)

        # Split heads:
        #   [B, T, d_model] -> [B, n_heads, T, head_dim]
        q = q.view(bsz, t, self.n_heads, self.head_dim).transpose(1, 2)
        k = k.view(bsz, t, self.n_heads, self.head_dim).transpose(1, 2)
        v = v.view(bsz, t, self.n_heads, self.head_dim).transpose(1, 2)

        # Scaled dot-product attention: scores [B, n_heads, T, T]
        scores = (q @ k.transpose(-2, -1)) / math.sqrt(self.head_dim)
        scores = scores.masked_fill(self.causal_mask[:t, :t], float("-inf"))

        attn = torch.softmax(scores, dim=-1)
        y = attn @ v  # [B, n_heads, T, head_dim]

        # Merge heads: [B, n_heads, T, head_dim] -> [B, T, d_model]
        y = y.transpose(1, 2).contiguous().view(bsz, t, d_model)
        y = self.proj(y)
        return y, attn


class MLP(nn.Module):
    """
    GPT-style feed-forward network:
      Linear(d_model -> d_ff) -> GELU -> Linear(d_ff -> d_model)

    We expose the post-GELU activations [T, d_ff] for visualization.
    """

    def __init__(self, cfg: ModelConfig):
        super().__init__()
        self.fc1 = nn.Linear(cfg.d_model, cfg.d_ff)
        self.fc2 = nn.Linear(cfg.d_ff, cfg.d_model)

    def forward(self, x: torch.Tensor) -> Tuple[torch.Tensor, torch.Tensor]:
        pre = self.fc1(x)
        act = F.gelu(pre)
        out = self.fc2(act)
        return out, act


class TransformerBlock(nn.Module):
    """
    Pre-LN Transformer block:
      x = x + Attn(LN(x))
      x = x + MLP(LN(x))

    The "residual stream" x is the main signal that flows through the network.
    Its per-position L2 norm is a useful proxy for activation energy.
    """

    def __init__(self, cfg: ModelConfig):
        super().__init__()
        self.ln1 = nn.LayerNorm(cfg.d_model)
        self.attn = CausalSelfAttention(cfg)
        self.ln2 = nn.LayerNorm(cfg.d_model)
        self.mlp = MLP(cfg)

    def forward(self, x: torch.Tensor) -> Tuple[torch.Tensor, torch.Tensor, torch.Tensor, torch.Tensor]:
        attn_out, attn_w = self.attn(self.ln1(x))
        x = x + attn_out

        mlp_out, mlp_act = self.mlp(self.ln2(x))
        x = x + mlp_out

        resid_norm = x.norm(dim=-1)  # [B, T]
        return x, attn_w, mlp_act, resid_norm


class TinyGPT(nn.Module):
    """
    Minimal GPT-like language model.

    Forward returns both logits and a cache of internal activations:
      cache["attn"][layer]  -> [n_heads, T, T]
      cache["mlp"][layer]   -> [T, d_ff]  (post-GELU activations)
      cache["resid"][layer] -> [T]        (residual L2 norms)
    """

    def __init__(self, cfg: ModelConfig):
        super().__init__()
        self.cfg = cfg

        self.tok_emb = nn.Embedding(cfg.vocab_size, cfg.d_model)
        self.pos_emb = nn.Embedding(cfg.max_seq_len, cfg.d_model)

        self.blocks = nn.ModuleList([TransformerBlock(cfg) for _ in range(cfg.n_layers)])
        self.ln_f = nn.LayerNorm(cfg.d_model)

        self.lm_head = nn.Linear(cfg.d_model, cfg.vocab_size, bias=False)
        # Weight tying is common in GPT-like models.
        self.lm_head.weight = self.tok_emb.weight

    @torch.no_grad()
    def forward(self, input_ids: torch.Tensor) -> Tuple[torch.Tensor, Dict[str, List[torch.Tensor]]]:
        if input_ids.dim() != 2:
            raise ValueError(f"input_ids must be [B, T], got {tuple(input_ids.shape)}")
        if input_ids.size(0) != 1:
            raise ValueError("This educational HUD demo expects batch size 1.")

        _, t = input_ids.shape
        if t > self.cfg.max_seq_len:
            input_ids = input_ids[:, -self.cfg.max_seq_len :]
            t = self.cfg.max_seq_len

        positions = torch.arange(t, device=input_ids.device).unsqueeze(0)  # [1, T]
        x = self.tok_emb(input_ids) + self.pos_emb(positions)  # [1, T, d_model]

        attn_cache: List[torch.Tensor] = []
        mlp_cache: List[torch.Tensor] = []
        resid_cache: List[torch.Tensor] = []

        for block in self.blocks:
            x, attn_w, mlp_act, resid_norm = block(x)
            attn_cache.append(attn_w[0].detach())  # [n_heads, T, T]
            mlp_cache.append(mlp_act[0].detach())  # [T, d_ff]
            resid_cache.append(resid_norm[0].detach())  # [T]

        x = self.ln_f(x)
        logits = self.lm_head(x)  # [1, T, vocab]

        cache = {"attn": attn_cache, "mlp": mlp_cache, "resid": resid_cache}
        return logits, cache


