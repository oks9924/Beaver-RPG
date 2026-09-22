#!/usr/bin/env python3
"""장비 드랍·줍기 효과음 합성 (외부 샘플 없음, 표준 라이브러리만).
등급이 높을수록 음이 많고 길다: 일반 = 둔탁한 착지, 고급 = 종 하나, 희귀 = 두 음, 영웅 = 세 음 아르페지오, 전설 = 다섯 음 + 반짝임. 줍기 = 짧은 상승 블립.
사용: python3 tools/gen_drop_sfx.py  → assets/final/audio/sfx_drop_*.wav, sfx_pickup.wav
"""
import math, os, random, struct, wave

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "final", "audio")


def tone(freq, start, dur, amp=0.5, decay=6.0, harmonics=(1.0, 0.45, 0.2, 0.08), attack=0.004):
    """감쇠하는 종 소리 하나를 (시작 초, 길이 초)로 돌려준다."""
    n = int(dur * SR)
    out = []
    for i in range(n):
        t = i / SR
        env = min(1.0, t / attack) * math.exp(-decay * t)
        v = 0.0
        for h, g in enumerate(harmonics, start=1):
            v += g * math.sin(2 * math.pi * freq * h * t)
        out.append(amp * env * v)
    return int(start * SR), out


def thud(start, dur=0.16, amp=0.6):
    rnd = random.Random(7)
    n = int(dur * SR)
    out = []
    for i in range(n):
        t = i / SR
        env = math.exp(-18.0 * t)
        f = 140.0 * (1.0 - 0.5 * t / dur)   # 아래로 미끄러지는 저음
        v = 0.8 * math.sin(2 * math.pi * f * t) + 0.25 * (rnd.random() * 2 - 1) * math.exp(-40.0 * t)
        out.append(amp * env * v)
    return int(start * SR), out


def blip(start, f0=620.0, f1=1240.0, dur=0.11, amp=0.45):
    n = int(dur * SR)
    out = []
    for i in range(n):
        t = i / SR
        f = f0 + (f1 - f0) * (t / dur)
        env = min(1.0, t / 0.003) * (1.0 - t / dur)
        out.append(amp * env * math.sin(2 * math.pi * f * t))
    return int(start * SR), out


def shimmer(start, dur, amp=0.12, seed=3):
    rnd = random.Random(seed)
    n = int(dur * SR)
    out = [0.0] * n
    for k in range(10):
        f = rnd.choice([2093, 2637, 3136, 3520, 4186])
        s = rnd.random() * dur * 0.7
        _, part = tone(f, 0, 0.25, amp=amp, decay=12.0, harmonics=(1.0, 0.2))
        off = int(s * SR)
        for i, v in enumerate(part):
            if off + i < n:
                out[off + i] += v
    return int(start * SR), out


def mix(parts, total):
    n = int(total * SR)
    buf = [0.0] * n
    for off, samples in parts:
        for i, v in enumerate(samples):
            if off + i < n:
                buf[off + i] += v
    peak = max(1e-6, max(abs(v) for v in buf))
    scale = 0.85 / peak if peak > 0.85 else 1.0
    return [v * scale for v in buf]


def write(name, samples):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32767)) for v in samples))
    return path, len(samples) / SR


E5, G5, B5, C6, E6, G6 = 659.25, 783.99, 987.77, 1046.5, 1318.5, 1568.0
SOUNDS = {
    "sfx_drop_common.wav": (0.22, [thud(0.0)]),
    "sfx_drop_uncommon.wav": (0.45, [thud(0.0, amp=0.25), tone(E5, 0.02, 0.4, amp=0.45, decay=7.0)]),
    "sfx_drop_rare.wav": (0.6, [thud(0.0, amp=0.2), tone(E5, 0.02, 0.35, amp=0.42), tone(B5, 0.14, 0.45, amp=0.42, decay=5.0)]),
    "sfx_drop_epic.wav": (0.8, [thud(0.0, amp=0.2), tone(C6, 0.02, 0.3, amp=0.4), tone(E6, 0.13, 0.3, amp=0.4), tone(G6, 0.24, 0.55, amp=0.42, decay=4.5), shimmer(0.25, 0.5, amp=0.08)]),
    "sfx_drop_legendary.wav": (1.3, [thud(0.0, amp=0.2), tone(G5, 0.02, 0.3, amp=0.4), tone(C6, 0.12, 0.3, amp=0.4), tone(E6, 0.22, 0.3, amp=0.4), tone(G6, 0.32, 0.4, amp=0.42), tone(C6 * 2, 0.44, 0.8, amp=0.45, decay=3.5), shimmer(0.4, 0.85, amp=0.12, seed=9)]),
    "sfx_pickup.wav": (0.14, [blip(0.0)]),
}

if __name__ == "__main__":
    for name, (total, parts) in SOUNDS.items():
        path, dur = write(name, mix(parts, total))
        print("%s %.2fs" % (os.path.relpath(path), dur))
