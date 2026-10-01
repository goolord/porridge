# Compares Porridge's global effects with Oatmeal.dll: a dry synth render from the DLL is fed
# through the effects of both (Porridge via the test graph's test input).
# Run with 32-bit Python after tools/test/build.sh:  python tools/re/cmp_fx.py [config ...]
import os, sys, struct, math, subprocess, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vsthost import *

os.makedirs(OUT, exist_ok=True)

def base():
    h = new_host()
    for p in (112, 113, 114, 116, 119): h.setp(p, 0.0)
    h.setp(0, 0.2)       # osc 1 saw
    base_fields = {8776: 1.0}
    h.load_chunk(patch_chunk(h.get_chunk(True), base_fields))
    return h

EVENTS = [(0, 0x90, 57, 100), (9000, 0x90, 64, 90), (20000, 0x80, 57, 0), (26000, 0x80, 64, 0)]
FRAMES = 60000

def render(h, chunk):
    h.load_chunk(chunk)
    return h.render(EVENTS, FRAMES)

def compare(name, cfg, frames=FRAMES):
    h = base()
    dry_chunk = h.get_chunk(True)
    dry = render(h, dry_chunk)
    wet_chunk = patch_chunk(h.get_chunk(True), cfg)
    wet = render(h, wet_chunk)
    dp = os.path.join(OUT, name + "_in.f32"); cp = os.path.join(OUT, name + ".bin"); op = os.path.join(OUT, name + "_out.f32")
    write_f32(dp, [[0.0] * 64 + dry[0], [0.0] * 64 + dry[1]])
    open(cp, "wb").write(wet_chunk)
    subprocess.check_call([HOST, "--program", cp, "--input", dp, "--frames", str(FRAMES + 256), "--out", op])
    mine = load_f32(op)
    err = 0.0; peak = 0.0; first = None
    for ch in range(2):
        for i in range(FRAMES):
            a = wet[ch][i]; b = mine[ch][128 + i]
            e = abs(a - b)
            if e > 1e-4 and first is None: first = (ch, i, a, b)
            err = max(err, e); peak = max(peak, abs(a))
    print("%-12s peak %.4f  max abs err %.3g  (rel %.3g)  first>1e-4: %s" % (name, peak, err, err / max(peak, 1e-9), first))

if __name__ == "__main__":
    cfgs = {
        "delay_A": {8648: ["i", 1], 8652: ["i", 0], 8656: ["i", 0], 8660: ["i", 0], 8664: ["i", 0], 8668: 0.3, 8672: 0.4, 8676: 100.0, 8680: 0.7, 8684: 37.3, 8688: -0.5, 8692: 0.6, 8696: 0.1, 8700: 0.8, 8704: 1.2},
        "delay_B": {8648: ["i", 1], 8652: ["i", 0], 8660: ["i", 1], 8664: ["i", 2], 8668: 0.5, 8672: 0.0, 8676: 68.03, 8680: 0.5, 8684: 45.35, 8688: 0.6, 8692: 1.0, 8696: 0.0, 8700: 1.0, 8704: 1.0},
        "delay_C": {8648: ["i", 1], 8652: ["i", 3], 8656: ["i", 1], 8668: 0.0, 8672: 1.5707963, 8676: 1.3, 8680: 0.9, 8684: 2.6, 8688: 1.2, 8692: 0.3, 8696: 0.5, 8700: 0.5, 8704: 2.0},
        "eq_A": {9292: ["i", 1], 9232: 1000.0, 9252: 12.0, 9272: 2.0, 9296: ["i", 2], 9236: 200.0, 9256: -6.0, 9276: 0.7, 9300: ["i", 3], 9240: 5000.0, 9260: 6.0, 9280: 1.0, 9304: ["i", 1], 9244: 60.0, 9264: -20.0, 9284: 0.3},
        "chorus_A": {8616: ["i", 1], 8620: ["i", 1], 8624: ["i", 4], 8628: 1.3, 8632: 7.0, 8636: 5.0, 8644: 0.4, 8640: 0.6},
        "chorus_B": {8616: ["i", 2], 8620: ["i", 0], 8624: ["i", 3], 8628: 0.5, 8632: 2.0, 8636: 10.0, 8644: -0.7, 8640: 1.0},
        "chorus_C": {8616: ["i", 3], 8620: ["i", 2], 8624: ["i", 16], 8628: 3.9, 8632: 20.0, 8636: 30.0, 8644: 0.9, 8640: 0.5},
        "reverb_A": {8708: ["i", 1], 8712: 30.0, 8716: 1.2, 8720: 0.8, 8724: 0.2, 8728: 1.0, 8732: 0.5, 8736: -0.7225663, 8740: -2.3561945, 8744: 0.84823, 8748: 2.2619467, 8752: 0.0, 8756: 0.5},
        "reverb_B": {8708: ["i", 1], 8712: 100.0, 8716: 5.0, 8720: 0.3, 8724: 0.5, 8728: 0.7, 8732: 1.0, 8736: 0.5, 8740: 1.0, 8744: -2.0, 8748: 0.3, 8752: 50.0, 8756: 0.9},
        "reverb_C": {8708: ["i", 1], 8712: 250.0, 8716: 120.0, 8720: 1.0, 8724: 0.0, 8728: 1.0, 8732: 0.3, 8752: -30.0, 8756: 0.2},
        "all": {8648: ["i", 1], 8676: 50.0, 8684: 75.0, 8680: 0.5, 8688: 0.5, 8704: 0.7, 8616: ["i", 1], 8620: ["i", 1], 8708: ["i", 1], 9292: ["i", 1], 9252: 6.0},
    }
    only = sys.argv[1:]
    for k, v in cfgs.items():
        if not only or k in only:
            compare(k, v)
