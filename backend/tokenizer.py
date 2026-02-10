"""
Byte-level tokenizer (no training required).

This project uses a deliberately simple tokenizer:
- Every UTF-8 byte is a token ID in [0, 255].
- Special tokens:
    BOS = 256  (beginning of sequence)
    EOS = 257  (end of sequence)
    PAD = 258  (padding, unused here but useful for extensions)

Why bytes?
  - Works for any input text without building a vocabulary.
  - Keeps the project fully offline and deterministic.
  - Makes it easy to visualize model behavior at the lowest level.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable, List


BYTE_VOCAB_SIZE = 256
BOS = 256
EOS = 257
PAD = 258
VOCAB_SIZE = 259


@dataclass(frozen=True)
class ByteTokenizer:
    bos_id: int = BOS
    eos_id: int = EOS
    pad_id: int = PAD
    vocab_size: int = VOCAB_SIZE

    def encode(self, text: str) -> List[int]:
        data = text.encode("utf-8", errors="strict")
        return list(data)

    def decode(self, ids: Iterable[int]) -> str:
        data = self.ids_to_generated_bytes(ids)
        return data.decode("utf-8", errors="replace")

    def ids_to_generated_bytes(self, ids: Iterable[int]) -> bytes:
        out = bytearray()
        for token_id in ids:
            if 0 <= int(token_id) <= 255:
                out.append(int(token_id))
        return bytes(out)

    def id_to_piece(self, token_id: int) -> str:
        token_id = int(token_id)
        if token_id == self.bos_id:
            return "<BOS>"
        if token_id == self.eos_id:
            return "<EOS>"
        if token_id == self.pad_id:
            return "<PAD>"

        if not (0 <= token_id <= 255):
            return f"<UNK:{token_id}>"

        # Common whitespace escapes are easier to see in the HUD.
        if token_id == 10:
            return "\\n"
        if token_id == 9:
            return "\\t"
        if token_id == 13:
            return "\\r"
        if token_id == 32:
            return " "

        # Printable ASCII gets displayed as-is.
        if 33 <= token_id <= 126:
            return chr(token_id)

        # Everything else uses a hex escape.
        return f"\\x{token_id:02x}"


