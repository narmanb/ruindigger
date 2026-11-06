"""Deterministic xorshift RNG so asset generation is byte-for-byte reproducible."""
from __future__ import annotations


class Rng:
    def __init__(self, seed: int):
        s = int(seed) & 0xFFFFFFFF
        self.s = s if s != 0 else 0x9E3779B9

    def next_u32(self) -> int:
        x = self.s
        x ^= (x << 13) & 0xFFFFFFFF
        x ^= x >> 17
        x ^= (x << 5) & 0xFFFFFFFF
        self.s = x & 0xFFFFFFFF
        return self.s

    def unit(self) -> float:
        return self.next_u32() / 4294967296.0

    def uniform(self, a: float, b: float) -> float:
        return a + (b - a) * self.unit()

    def randint(self, a: int, b: int) -> int:
        if b <= a:
            return a
        return a + self.next_u32() % (b - a + 1)

    def chance(self, p: float) -> bool:
        return self.unit() < p

    def choice(self, seq):
        return seq[self.next_u32() % len(seq)]

    def pick_weighted(self, items, weights):
        total = sum(weights)
        r = self.unit() * total
        acc = 0.0
        for it, w in zip(items, weights):
            acc += w
            if r <= acc:
                return it
        return items[-1]
