#!/usr/bin/env python3
"""The silent sound of W7's pre-alarm (build 14b1): 10 s of digital silence, mono, 44.1 kHz, 16-bit linear PCM –
the same CAF format as the alarm files. The AlarmKit pre-alarm plays it so the iPhone stays quiet while an Apple
Watch may still buzz. Written byte by byte (no ffmpeg, no randomness): the output is identical on every run.

    python3 tools/audio/make_silence.py      # writes assets/audio/prealarm_silent.caf
"""
import os
import struct

SR = 44100
SECONDS = 10
OUT = "assets/audio/prealarm_silent.caf"


def caf(frames: int) -> bytes:
    desc = struct.pack(">dIIIIII", float(SR), int.from_bytes(b"lpcm", "big"),
                       2,          # kCAFLinearPCMFormatFlagIsLittleEndian
                       2, 1, 1, 16)  # bytes per packet, frames per packet, channels, bits per channel
    chan = struct.pack(">III", (100 << 16) | 1, 0, 0)    # a mono channel layout, like the other CAFs
    data = b"\x00" * (frames * 2)
    return (b"caff" + struct.pack(">HH", 1, 0)
            + b"desc" + struct.pack(">q", len(desc)) + desc
            + b"chan" + struct.pack(">q", len(chan)) + chan
            + b"data" + struct.pack(">q", 4 + len(data)) + struct.pack(">I", 0) + data)


if __name__ == "__main__":
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "wb") as f:
        f.write(caf(SR * SECONDS))
    print(OUT, f"{SECONDS} s")
