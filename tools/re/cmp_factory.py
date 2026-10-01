# Renders the factory programs through Oatmeal.dll and Porridge and compares them. Sources of
# randomness (random LFO shapes, free-running global LFOs, irregular chorus, XY random walk,
# noise) are replaced by deterministic equivalents first.
# Run with 32-bit Python after tools/test/build.sh:  python tools/re/cmp_factory.py [program ...]
import sys, struct
from cmp_synth import *
h0 = Host(); h0.flush(640)
SEQ = [(0, 0x90, 48, 100), (0, 0x90, 55, 90), (0, 0x90, 64, 110), (44032, 0x80, 48, 0), (44032, 0x80, 55, 0), (44032, 0x80, 64, 0),
       (66048, 0x90, 60, 100), (88064, 0x80, 60, 0)]
only = [int(a) for a in sys.argv[1:]] or list(range(17))
for i in only:
    h0.d(2, 0, i); h0.flush(128)
    name = h0.dstr(5)
    for p, v in DETERMINISTIC.items(): h0.setp(p, v)
    c = bytearray(h0.get_chunk(True))
    def gi(o): return struct.unpack_from("<i", c, o)[0]
    def si(o, v): struct.pack_into("<i", c, o, v)
    def sf(o, v): struct.pack_into("<f", c, o, v)
    for so in (8548, 8584):                 # random LFO shapes -> sine
        if gi(so) in (4, 5): si(so, 0)
    for mo in (8552, 8588):                 # global free -> global reset on note
        if gi(mo) == 2: si(mo, 1)
    if gi(8616) == 4: si(8616, 1)           # irregular chorus -> sine
    sf(9216, 0.0)                           # XY random radius
    sf(8528, 0.0)                           # noise off
    rel, worst = compare("fd%02d" % i, bytes(c), SEQ, 110080, quiet=True)
    print("%2d %-24s rel err %8.3g   worst RMS diff %6.2f dB" % (i, name, rel, worst))
    sys.stdout.flush()
