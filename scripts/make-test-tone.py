#!/usr/bin/env python3
"""產生實機驗收用的測試音 WAV（只用標準函式庫）。

用法：python3 scripts/make-test-tone.py [頻率 Hz] [秒數] [輸出檔]
預設：442 Hz、30 秒、build/test-tone-442.wav

音色為基音加遞減泛音（近似弓弦），在另一支手機或電腦播放，作為三種音訊路由比對的 A4 音源。
"""
import math
import struct
import sys
import wave
from pathlib import Path

frequency = float(sys.argv[1]) if len(sys.argv) > 1 else 442.0
seconds = float(sys.argv[2]) if len(sys.argv) > 2 else 30.0
output = Path(sys.argv[3]) if len(sys.argv) > 3 else Path(f"build/test-tone-{frequency:g}.wav")
sample_rate = 48000

output.parent.mkdir(parents=True, exist_ok=True)
with wave.open(str(output), "w") as wav:
    wav.setnchannels(1)
    wav.setsampwidth(2)
    wav.setframerate(sample_rate)
    frames = bytearray()
    fade = int(0.02 * sample_rate)
    total = int(seconds * sample_rate)
    for i in range(total):
        t = i / sample_rate
        value = sum(math.sin(2 * math.pi * frequency * h * t) / h for h in range(1, 6)) * 0.25
        envelope = min(1.0, i / fade, (total - i) / fade)
        frames += struct.pack("<h", int(max(-1.0, min(1.0, value * envelope)) * 32767))
    wav.writeframes(bytes(frames))
print(output)
