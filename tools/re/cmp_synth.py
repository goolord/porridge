# Compares Porridge (native test host) with Oatmeal.dll on whole patches built from the Init
# program. Random sources are switched off so the outputs can match sample by sample.
# Run with 32-bit Python after tools/test/build.sh:  python tools/re/cmp_synth.py [test ...]
import os, sys, struct, math, subprocess
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vsthost import *

os.makedirs(OUT, exist_ok=True)

DETERMINISTIC = {112: 0.0, 113: 0.0, 114: 0.0, 116: 0.0, 119: 0.0, 122: 0.0}

def rms_windows(x, w=2205):
    return [math.sqrt(sum(v * v for v in x[i:i + w]) / w) for i in range(0, len(x) - w, w)]

def compare(name, chunk, events, frames, sr=44100.0, quiet=False):
    """chunk: v38 program; events: [(frame, status, d1, d2)] with frames on the 64 grid."""
    h = Host(sr=sr, block=64)
    h.flush(640)
    h.load_chunk(chunk)
    dll = h.render(events, frames)
    cp = os.path.join(OUT, name + ".bin"); ep = os.path.join(OUT, name + "_ev.txt"); op = os.path.join(OUT, name + "_out.f32")
    open(cp, "wb").write(h.get_chunk(True))
    with open(ep, "w") as f:
        for e in sorted(events): f.write("%d %d %d %d\n" % e)   # same order the DLL harness sends them
    subprocess.check_call([HOST, "--program", cp, "--events", ep, "--frames", str(frames), "--rate", str(int(sr)), "--out", op, "--preroll", "128"])
    mine = load_f32(op)
    write_f32(os.path.join(OUT, name + "_dll.f32"), dll)
    err = 0.0; peak = 0.0
    for ch in range(2):
        for i in range(frames):
            err = max(err, abs(dll[ch][i] - mine[ch][i])); peak = max(peak, abs(dll[ch][i]))
    ra = rms_windows(dll[0]); rb = rms_windows(mine[0])
    ddb = [abs(20 * math.log10((a + 1e-9) / (b + 1e-9))) for a, b in zip(ra, rb) if max(a, b) > 1e-4]
    worst = max(ddb) if ddb else 0.0
    if not quiet:
        print("%-24s peak %.4f  max err %.3g (rel %.2g)  worst 50ms-RMS diff %.2f dB" % (name, peak, err, err / max(peak, 1e-9), worst))
    return err / max(peak, 1e-9), worst

def init_chunk(params=None, fields=None):
    h = new_host()
    for p, v in DETERMINISTIC.items(): h.setp(p, v)
    h.setp(107, 0.666667)
    for p, v in (params or {}).items(): h.setp(p, v)
    c = h.get_chunk(True)
    if fields: c = patch_chunk(c, fields)
    return c

NOTE = [(0, 0x90, 57, 100), (22016, 0x80, 57, 0)]
CHORD = [(0, 0x90, 57, 100), (4096, 0x90, 64, 90), (8192, 0x90, 69, 110), (30016, 0x80, 57, 0), (30016, 0x80, 64, 0), (30016, 0x80, 69, 0)]

TESTS = {
    "sine":      ({}, NOTE),
    "saw":       ({0: 0.2}, NOTE),
    "tri":       ({0: 0.6}, NOTE),
    "pulse":     ({0: 0.4, 3: 0.3}, NOTE),
    "pwm":       ({0: 0.4, 4: 0.3, 5: 0.8}, NOTE),
    "saw_hi":    ({0: 0.2}, [(0, 0x90, 100, 100), (22016, 0x80, 100, 0)]),
    "saw_lo":    ({0: 0.2}, [(0, 0x90, 30, 100), (22016, 0x80, 30, 0)]),
    "osc2":      ({0: 0.2, 6: 0.6, 7: 0.6, 12: 0.55, 13: 0.52}, NOTE),
    "sync":      ({0: 0.2, 6: 0.2, 7: 0.666667, 1: 0.0, 341: 0.5, 12: 0.6}, NOTE),
    "fm":        ({0: 0.0, 6: 0.0, 7: 0.666667, 1: 0.6, 341: 1.0}, NOTE),
    "lp2":       ({0: 0.2, 41: 2 / 15, 43: 0.4, 44: 0.6}, NOTE),
    "lp4env":    ({0: 0.2, 41: 3 / 15, 43: 0.3, 44: 0.5, 57: 0.7, 49: 0.3, 50: 0.5}, NOTE),
    "hp2":       ({0: 0.2, 41: 5 / 15, 43: 0.5, 44: 0.4}, NOTE),
    "bp4":       ({0: 0.2, 41: 9 / 15, 43: 0.5, 44: 0.7}, NOTE),
    "nl4":       ({0: 0.2, 41: 12 / 15, 43: 0.45, 44: 0.8}, NOTE),
    "phaser12":  ({0: 0.2, 41: 14 / 15, 43: 0.4, 44: 0.8}, NOTE),
    "double_par":({0: 0.2, 41: 2 / 15, 42: 5 / 15, 53: 0.5, 54: 0.4, 55: 0.3, 43: 0.4}, NOTE),
    "double_ser":({0: 0.2, 41: 3 / 15, 42: 6 / 15, 53: 1.0, 54: 0.7, 43: 0.5}, NOTE),
    "ampenv":    ({0: 0.2, 60: 0.1, 61: 0.05, 62: 0.2, 63: 0.8, 64: 0.3, 65: 0.6, 66: 0.2}, NOTE),
    "chord":     ({0: 0.2, 41: 2 / 15, 43: 0.5}, CHORD),
    "pitchenv":  ({0: 0.2, 164: 1.0, 165: 0.45, 166: 0.1, 167: 0.6, 168: 0.1}, NOTE),
    "lfo_pitch": ({0: 0.2, 27: 0.5, 21: 0.45}, NOTE),
    "lfo_cut":   ({0: 0.2, 41: 2 / 15, 43: 0.3, 24: 0.8, 21: 0.45, 23: 0.0}, NOTE),
    "modenv":    ({0: 0.2, 41: 2 / 15, 250: 0.1 * 1 / 3 * 3 / 3, 246: 0.9}, NOTE),
    "dist_post": ({0: 0.2, 172: 0.5, 173: 1 / 3, 175: 0.6}, NOTE),
    "dist_glob": ({0: 0.2, 172: 0.25, 173: 0.0, 175: 0.7, 177: 2 / 3}, CHORD),
    "unison3":   ({0: 0.2, 124: 2 / 15, 125: 0.1}, NOTE),
    "unison4s":  ({0: 0.2, 124: 3 / 15, 125: 0.1, 126: 0.7}, NOTE),
    "noise":     ({1: 0.0, 15: 0.6}, NOTE),
    "noise_bp":  ({1: 0.0, 15: 0.7, 17: 0.6}, NOTE),
    "glide":     ({0: 0.2, 103: 1.0, 105: 0.4}, [(0, 0x90, 57, 100), (11008, 0x90, 64, 100), (11008, 0x80, 57, 0), (22016, 0x80, 64, 0)]),
    "arp":       ({0: 0.2, 129: 0.2, 130: 0.47, 66: 0.02}, [(0, 0x90, 57, 100), (0, 0x90, 60, 100), (0, 0x90, 64, 100), (44032, 0x80, 57, 0), (44032, 0x80, 60, 0), (44032, 0x80, 64, 0)]),
}

if __name__ == "__main__":
    only = sys.argv[1:]
    for name, (params, ev) in TESTS.items():
        if only and name not in only: continue
        c = init_chunk(params)
        compare(name, c, ev, max(e[0] for e in ev) + 22050)
