#!/usr/bin/env python3
"""참고 소리(wav)를 분석해 비슷한 소리를 다시 합성한다 (표준 라이브러리만).
원본을 복사하지 않고, 프레임마다 강한 주파수 성분(최대 12개)을 뽑아 사인 합성으로 재구성한 뒤 잡음 성분을 얹는다.
사용: python3 tools/match_sfx.py <참고.wav> <출력.wav> [--gain=1.0] [--max-sec=2.5]
   예: python3 tools/match_sfx.py ref_legendary.wav assets/final/audio/sfx_drop_legendary.wav
"""
import cmath, math, struct, sys, wave

FRAME = 2048
HOP = 256
PEAKS = 16


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
        # 봉우리를 뺀 나머지(잡음) 에너지를 저·중·고 대역으로 나눠 기록한다
        covered = set()
        for f, _ in peaks:
            k0 = int(f * FRAME / sr)
            for k in range(k0 - 2, k0 + 3):
                covered.add(k)
        band_e = [0.0, 0.0, 0.0]
        edges = (int(300 * FRAME / sr), int(2000 * FRAME / sr))
        for k in range(1, FRAME // 2):
            if k in covered:
                continue
            b = 0 if k < edges[0] else (1 if k < edges[1] else 2)
            band_e[b] += mags[k] * mags[k]
        noise_rms = [math.sqrt(e / (FRAME // 2)) for e in band_e]
        frames.append((pos / sr, peaks, noise_rms, math.sqrt(total / (FRAME // 2))))
        pos += HOP
    return frames


def band_rms(sr, mono):
    """전체 파일의 저·중·고 대역 RMS (보정용)"""
    F = 2048
    acc = [0.0, 0.0, 0.0]
    cnt = 0
    win = [0.5 - 0.5 * math.cos(2 * math.pi * i / F) for i in range(F)]
    edges = (int(300 * F / sr), int(2000 * F / sr))
    for t in range(0, max(1, len(mono) - F), F // 2):
        seg = [mono[t + i] * win[i] for i in range(F)]
        sp = fft([complex(v, 0.0) for v in seg])
        for k in range(1, F // 2):
            b = 0 if k < edges[0] else (1 if k < edges[1] else 2)
            acc[b] += (abs(sp[k]) / F * 2) ** 2
        cnt += 1
    return [math.sqrt(a / max(cnt, 1)) for a in acc]


def resynth(sr, frames, total_len, gain, band_gain=(1.0, 1.0, 1.0)):
    import random
    rnd = random.Random(1)
    n = int(total_len * sr)
    out = [0.0] * n
    # 프레임 사이를 선형 보간하며 사인 성분을 이어 붙인다 (주파수는 가까운 것끼리 이어진다고 보고 프레임 단위로 페이드)
    prev_lo = 0.0
    prev_hi = 0.0
    for fi, (t0, peaks, noise_rms, rms) in enumerate(frames):
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
        # 대역별 잡음: 저역은 평활(둥근 울림), 중역은 그대로, 고역은 차분(날카로운 타격·쉭 소리)
        lo_g, mid_g, hi_g = [v * 2.2 * g for v, g in zip(noise_rms, band_gain)]
        if lo_g + mid_g + hi_g > 0.002:
            for i in range(length):
                idx = start + i
                if idx >= n:
                    break
                env = math.sin(math.pi * i / length)
                w = rnd.random() * 2 - 1
                prev_lo = prev_lo * 0.92 + w * 0.08
                hi = w - prev_hi
                prev_hi = w
                out[idx] += env * (lo_g * prev_lo * 6.0 + mid_g * w * 0.5 + hi_g * hi * 0.5)
    return out


def normalize(out, gain):
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
    ref_b = band_rms(sr, mono)
    bg = [1.0, 1.0, 1.0]
    out = []
    for it in range(3):
        # 분석-합성 반복: 대역별 잡음 이득을 참고 소리의 대역 RMS 에 맞춘다
        out = resynth(sr, frames, len(mono) / sr + 0.05, float(opts.get("gain", 1.0)), tuple(bg))
        got = band_rms(sr, out)
        for b in range(3):
            if got[b] > 1e-6 and ref_b[b] > 1e-6:
                bg[b] = max(0.2, min(12.0, bg[b] * ref_b[b] / got[b]))
    out = normalize(out, float(opts.get("gain", 1.0)))
    write_wav(args[1], sr, out)
    print("band rms ref=%s out=%s gains=%s" % (["%.3f" % v for v in ref_b], ["%.3f" % v for v in band_rms(sr, out)], ["%.2f" % v for v in bg]))
    top = {}
    for _, peaks, _, _ in frames:
        for f, a in peaks[:3]:
            key = int(round(f / 20.0) * 20)
            top[key] = top.get(key, 0.0) + a
    dom = sorted(top.items(), key=lambda kv: -kv[1])[:6]
    print("matched %s -> %s: %.2fs, %d frames, dominant Hz %s" % (args[0], args[1], len(mono) / sr, len(frames), [k for k, _ in dom]))
