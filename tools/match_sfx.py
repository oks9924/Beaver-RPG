#!/usr/bin/env python3
"""참고 소리(wav)를 분석해 비슷한 소리를 다시 합성한다 (표준 라이브러리만).
원본을 복사하지 않고, 프레임마다 강한 주파수 성분(최대 12개)을 뽑아 사인 합성으로 재구성한 뒤 잡음 성분을 얹는다.
사용: python3 tools/match_sfx.py <참고.wav> <출력.wav> [--gain=1.0] [--max-sec=2.5]
   예: python3 tools/match_sfx.py ref_legendary.wav assets/final/audio/sfx_drop_legendary.wav
"""
import cmath, math, struct, sys, wave

FRAME = 2048
HOP = 512
PEAKS = 12


def read_wav(path, max_sec):
    with wave.open(path, "rb") as w:
        sr = w.getframerate()
        ch = w.getnchannels()
        sw = w.getsampwidth()
        n = min(w.getnframes(), int(max_sec * sr))
        raw = w.readframes(n)
    fmt = {1: "b", 2: "h", 4: "i"}[sw]
    data = struct.unpack("<%d%s" % (n * ch, fmt), raw)
    scale = float(2 ** (8 * sw - 1))
    mono = [sum(data[i * ch:(i + 1) * ch]) / ch / scale for i in range(n)]
    return sr, mono


def fft(x):
    n = len(x)
    if n == 1:
        return x
    even = fft(x[0::2])
    odd = fft(x[1::2])
    out = [0j] * n
    for k in range(n // 2):
        t = cmath.exp(-2j * math.pi * k / n) * odd[k]
        out[k] = even[k] + t
        out[k + n // 2] = even[k] - t
    return out


def analyze(sr, mono):
    """프레임별 (시간, [(주파수, 진폭)...], 잡음 비율)"""
    win = [0.5 - 0.5 * math.cos(2 * math.pi * i / FRAME) for i in range(FRAME)]
    frames = []
    pos = 0
    while pos + FRAME <= len(mono):
        seg = [mono[pos + i] * win[i] for i in range(FRAME)]
        spec = fft([complex(v, 0.0) for v in seg])
        mags = [abs(spec[k]) / FRAME * 2 for k in range(FRAME // 2)]
        total = sum(m * m for m in mags) + 1e-12
        peaks = []
        for k in range(2, FRAME // 2 - 2):
            if mags[k] > mags[k - 1] and mags[k] >= mags[k + 1] and mags[k] > 0.002:
                # 포물선 보간으로 주파수 정밀화
                a, b, c = mags[k - 1], mags[k], mags[k + 1]
                d = 0.5 * (a - c) / (a - 2 * b + c) if (a - 2 * b + c) != 0 else 0.0
                peaks.append(((k + d) * sr / FRAME, b))
        peaks.sort(key=lambda p: -p[1])
        peaks = peaks[:PEAKS]
        peak_energy = sum(m * m for _, m in peaks)
        noise = max(0.0, 1.0 - peak_energy / total)
        frames.append((pos / sr, peaks, noise, math.sqrt(total / (FRAME // 2))))
        pos += HOP
    return frames


def resynth(sr, frames, total_len, gain):
    import random
    rnd = random.Random(1)
    n = int(total_len * sr)
    out = [0.0] * n
    # 프레임 사이를 선형 보간하며 사인 성분을 이어 붙인다 (주파수는 가까운 것끼리 이어진다고 보고 프레임 단위로 페이드)
    for fi, (t0, peaks, noise, rms) in enumerate(frames):
        start = int(t0 * sr)
        length = HOP * 2
        for f, a in peaks:
            if f < 40 or f > sr * 0.45:
                continue
            for i in range(length):
                idx = start + i
                if idx >= n:
                    break
                env = math.sin(math.pi * i / length)   # 겹치는 창
                out[idx] += a * env * math.sin(2 * math.pi * f * idx / sr)
        if noise > 0.35 and rms > 0.01:
            for i in range(length):
                idx = start + i
                if idx >= n:
                    break
                env = math.sin(math.pi * i / length)
                out[idx] += rms * noise * 0.6 * env * (rnd.random() * 2 - 1)
    peak = max(1e-6, max(abs(v) for v in out))
    scale = min(gain * 0.9 / peak, 4.0)
    return [v * scale for v in out]


def write_wav(path, sr, samples):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32767)) for v in samples))


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    opts = dict(a[2:].split("=", 1) for a in sys.argv[1:] if a.startswith("--") and "=" in a)
    if len(args) < 2:
        print(__doc__)
        sys.exit(2)
    sr, mono = read_wav(args[0], float(opts.get("max-sec", 2.5)))
    frames = analyze(sr, mono)
    out = resynth(sr, frames, len(mono) / sr + 0.05, float(opts.get("gain", 1.0)))
    write_wav(args[1], sr, out)
    top = {}
    for _, peaks, _, _ in frames:
        for f, a in peaks[:3]:
            key = int(round(f / 20.0) * 20)
            top[key] = top.get(key, 0.0) + a
    dom = sorted(top.items(), key=lambda kv: -kv[1])[:6]
    print("matched %s -> %s: %.2fs, %d frames, dominant Hz %s" % (args[0], args[1], len(mono) / sr, len(frames), [k for k, _ in dom]))
