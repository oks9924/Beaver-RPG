#!/usr/bin/env python3
"""장비 드랍·줍기 효과음 합성 (외부 샘플 없음, 표준 라이브러리만).
등급이 높을수록 음이 많고 길다: 일반 = 둔탁한 착지, 고급 = 종 하나, 희귀 = 두 음, 영웅 = 세 음 아르페지오, 전설 = 다섯 음 + 반짝임. 줍기 = 짧은 상승 블립.
사용: python3 tools/gen_drop_sfx.py [arpg|chime]  → assets/final/audio/sfx_drop_*.wav, sfx_pickup.wav (기본 arpg)
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


def clink(start, base=2600.0, dur=0.14, amp=0.5, seed=11):
    """금속 동전이 바닥에 떨어지는 '찰칵': 비조화 배음 + 짧은 잡음. ARPG 루트 소리의 기본 재료."""
    rnd = random.Random(seed)
    n = int(dur * SR)
    out = []
    partials = ((1.0, 1.0), (1.42, 0.55), (2.31, 0.3), (3.17, 0.15))
    for i in range(n):
        t = i / SR
        env = min(1.0, t / 0.001) * math.exp(-28.0 * t)
        v = 0.0
        for ratio, g in partials:
            v += g * math.sin(2 * math.pi * base * ratio * t)
        v += 0.5 * (rnd.random() * 2 - 1) * math.exp(-90.0 * t)
        out.append(amp * env * v)
    return int(start * SR), out


def glass(start, freq, dur=0.5, amp=0.42, decay=6.5):
    """유리종 '딩': 살짝 어긋난 두 사인이 맥놀이를 낸다."""
    n = int(dur * SR)
    out = []
    for i in range(n):
        t = i / SR
        env = min(1.0, t / 0.002) * math.exp(-decay * t)
        v = math.sin(2 * math.pi * freq * t) + 0.6 * math.sin(2 * math.pi * freq * 1.004 * t) + 0.25 * math.sin(2 * math.pi * freq * 2.76 * t) * math.exp(-10 * t)
        out.append(amp * env * v)
    return int(start * SR), out


def bell(start, freq, dur=1.4, amp=0.5, decay=2.6):
    """깊은 종(전설): 비조화 배음(1 : 2.0 : 2.4 : 3.0 : 4.5)과 긴 여운."""
    n = int(dur * SR)
    out = []
    partials = ((0.5, 0.35, 1.4), (1.0, 1.0, 2.6), (2.0, 0.5, 3.0), (2.4, 0.35, 3.6), (3.0, 0.25, 4.5), (4.5, 0.12, 6.0))
    for i in range(n):
        t = i / SR
        v = 0.0
        for ratio, g, dc in partials:
            v += g * math.sin(2 * math.pi * freq * ratio * t) * math.exp(-dc * t)
        env = min(1.0, t / 0.003)
        out.append(amp * env * v * math.exp(-decay * 0.35 * t))
    return int(start * SR), out


E5, G5, B5, C6, E6, G6 = 659.25, 783.99, 987.77, 1046.5, 1318.5, 1568.0
SOUNDS_CHIME = {
    "sfx_drop_common.wav": (0.22, [thud(0.0)]),
    "sfx_drop_uncommon.wav": (0.45, [thud(0.0, amp=0.25), tone(E5, 0.02, 0.4, amp=0.45, decay=7.0)]),
    "sfx_drop_rare.wav": (0.6, [thud(0.0, amp=0.2), tone(E5, 0.02, 0.35, amp=0.42), tone(B5, 0.14, 0.45, amp=0.42, decay=5.0)]),
    "sfx_drop_epic.wav": (0.8, [thud(0.0, amp=0.2), tone(C6, 0.02, 0.3, amp=0.4), tone(E6, 0.13, 0.3, amp=0.4), tone(G6, 0.24, 0.55, amp=0.42, decay=4.5), shimmer(0.25, 0.5, amp=0.08)]),
    "sfx_drop_legendary.wav": (1.3, [thud(0.0, amp=0.2), tone(G5, 0.02, 0.3, amp=0.4), tone(C6, 0.12, 0.3, amp=0.4), tone(E6, 0.22, 0.3, amp=0.4), tone(G6, 0.32, 0.4, amp=0.42), tone(C6 * 2, 0.44, 0.8, amp=0.45, decay=3.5), shimmer(0.4, 0.85, amp=0.12, seed=9)]),
    "sfx_pickup.wav": (0.14, [blip(0.0)]),
}

# ARPG(Hero Siege·디아블로 계열) 스타일: 일반은 금속 찰칵, 고급은 찰칵+짧은 딩, 희귀는 유리종 두 번, 영웅은 유리종 세 번 상승, 전설은 깊은 종 + 반짝임
SOUNDS_ARPG = {
    "sfx_drop_common.wav": (0.2, [clink(0.0), clink(0.045, base=2100.0, amp=0.3, seed=5)]),
    "sfx_drop_uncommon.wav": (0.4, [clink(0.0, amp=0.4), glass(0.03, 1760.0, dur=0.35, amp=0.32, decay=9.0)]),
    "sfx_drop_rare.wav": (0.7, [clink(0.0, amp=0.35), glass(0.02, 1318.5, dur=0.4, amp=0.4), glass(0.16, 1760.0, dur=0.5, amp=0.42, decay=5.5)]),
    "sfx_drop_epic.wav": (0.95, [clink(0.0, amp=0.3), glass(0.02, 1046.5, dur=0.4, amp=0.4), glass(0.14, 1318.5, dur=0.4, amp=0.4), glass(0.26, 1760.0, dur=0.65, amp=0.45, decay=4.5), shimmer(0.3, 0.6, amp=0.07)]),
    "sfx_drop_legendary.wav": (1.7, [clink(0.0, amp=0.3), bell(0.02, 440.0, dur=1.65, amp=0.55), glass(0.05, 1760.0, dur=0.5, amp=0.25), glass(0.22, 2637.0, dur=0.6, amp=0.22), shimmer(0.3, 1.2, amp=0.1, seed=21)]),
    "sfx_pickup.wav": (0.14, [clink(0.0, base=3000.0, dur=0.08, amp=0.35), blip(0.01, f0=900.0, f1=1500.0, dur=0.09, amp=0.3)]),
}

STYLE = "arpg"   # "chime"(첫 버전) 또는 "arpg"

if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1:
        STYLE = sys.argv[1]
    SOUNDS = SOUNDS_ARPG if STYLE == "arpg" else SOUNDS_CHIME
    for name, (total, parts) in SOUNDS.items():
        path, dur = write(name, mix(parts, total))
        print("%s %.2fs" % (os.path.relpath(path), dur))
