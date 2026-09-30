# Minimal 32-bit VST2 host for driving Oatmeal.dll from Python (run with a 32-bit Python 3).
# The DLL is taken from $OATMEAL_DLL, or F:\VST32\Oatmeal.dll by default.
import ctypes, struct, os, sys
from ctypes import c_int32, c_void_p, c_float, c_char_p, POINTER, CFUNCTYPE, Structure, byref, create_string_buffer

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
DLL = os.environ.get("OATMEAL_DLL", r"F:\VST32\Oatmeal.dll")
OUT = os.path.join(HERE, "out")

intptr = ctypes.c_ssize_t
Dispatcher = CFUNCTYPE(intptr, c_void_p, c_int32, c_int32, intptr, c_void_p, c_float)
Process = CFUNCTYPE(None, c_void_p, POINTER(POINTER(c_float)), POINTER(POINTER(c_float)), c_int32)
SetParam = CFUNCTYPE(None, c_void_p, c_int32, c_float)
GetParam = CFUNCTYPE(c_float, c_void_p, c_int32)
HostCb = CFUNCTYPE(intptr, c_void_p, c_int32, c_int32, intptr, c_void_p, c_float)

class AEffect(Structure):
    _fields_ = [("magic", c_int32), ("dispatcher", Dispatcher), ("process", c_void_p),
                ("setParameter", SetParam), ("getParameter", GetParam),
                ("numPrograms", c_int32), ("numParams", c_int32), ("numInputs", c_int32),
                ("numOutputs", c_int32), ("flags", c_int32), ("resvd1", intptr), ("resvd2", intptr),
                ("initialDelay", c_int32), ("realQualities", c_int32), ("offQualities", c_int32),
                ("ioRatio", c_float), ("object", c_void_p), ("user", c_void_p), ("uniqueID", c_int32),
                ("version", c_int32), ("processReplacing", Process), ("processDoubleReplacing", c_void_p),
                ("future", ctypes.c_char * 56)]

class VstTimeInfo(Structure):
    _fields_ = [("samplePos", ctypes.c_double), ("sampleRate", ctypes.c_double), ("nanoSeconds", ctypes.c_double),
                ("ppqPos", ctypes.c_double), ("tempo", ctypes.c_double), ("barStartPos", ctypes.c_double),
                ("cycleStartPos", ctypes.c_double), ("cycleEndPos", ctypes.c_double),
                ("timeSigNumerator", c_int32), ("timeSigDenominator", c_int32), ("smpteOffset", c_int32),
                ("smpteFrameRate", c_int32), ("samplesToNextClock", c_int32), ("flags", c_int32)]

class VstMidiEvent(Structure):
    _fields_ = [("type", c_int32), ("byteSize", c_int32), ("deltaFrames", c_int32), ("flags", c_int32),
                ("noteLength", c_int32), ("noteOffset", c_int32), ("midiData", ctypes.c_ubyte * 4),
                ("detune", ctypes.c_byte), ("noteOffVelocity", ctypes.c_ubyte), ("reserved1", ctypes.c_byte),
                ("reserved2", ctypes.c_byte)]

def make_events_struct(n):
    class VstEvents(Structure):
        _fields_ = [("numEvents", c_int32), ("reserved", intptr), ("events", c_void_p * max(n, 2))]
    return VstEvents

class Host:
    def __init__(self, sr=44100.0, block=64, tempo=120.0, dll=DLL):
        self.sr = sr; self.block = block
        self.timeinfo = VstTimeInfo()
        self.timeinfo.sampleRate = sr; self.timeinfo.tempo = tempo
        self.timeinfo.timeSigNumerator = 4; self.timeinfo.timeSigDenominator = 4
        self.timeinfo.flags = (1 << 1) | (1 << 9) | (1 << 10) | (1 << 13)  # playing, ppq, tempo, timesig
        self.log = []; self.pos = 0
        self._cb = HostCb(self._host)
        self.lib = ctypes.CDLL(dll)
        main = CFUNCTYPE(POINTER(AEffect), HostCb)(("main", self.lib))
        self.eff = main(self._cb)
        self.e = self.eff.contents
        assert self.e.magic == 0x56737450, hex(self.e.magic)
        self.d(0)  # open
        self.d(10, opt=sr)
        self.d(11, value=block)
        self.d(12, value=1)  # mains on
        self.d(71)
        self.bufs_out = [(c_float * block)() for _ in range(2)]
        self.bufs_in = [(c_float * block)() for _ in range(2)]
        self.pout = (POINTER(c_float) * 2)(*[ctypes.cast(b, POINTER(c_float)) for b in self.bufs_out])
        self.pin = (POINTER(c_float) * 2)(*[ctypes.cast(b, POINTER(c_float)) for b in self.bufs_in])
        self.pos = 0

    def _host(self, eff, opcode, index, value, ptr, opt):
        if opcode == 1: return 2400          # version
        if opcode == 7:                       # get time
            self.timeinfo.samplePos = self.pos
            self.timeinfo.ppqPos = self.pos / self.sr * self.timeinfo.tempo / 60.0
            return ctypes.addressof(self.timeinfo)
        if opcode == 16: return int(self.sr)
        if opcode == 17: return self.block
        if opcode in (6, 0, 13, 15): return 1
        if opcode == 32:                      # vendor string
            ctypes.memmove(ptr, b"py\0", 3); return 1
        if opcode == 33:
            ctypes.memmove(ptr, b"pyhost\0", 7); return 1
        if opcode == 37: return 0             # canDo
        self.log.append(opcode)
        return 0

    def d(self, op, index=0, value=0, ptr=None, opt=0.0):
        return self.e.dispatcher(self.eff, op, index, value, ptr, opt)

    def dstr(self, op, index=0, size=256):
        buf = create_string_buffer(size)
        self.d(op, index, 0, ctypes.cast(buf, c_void_p))
        return buf.value.decode("latin-1")

    def name(self, i): return self.dstr(8, i)
    def display(self, i): return self.dstr(7, i)
    def label(self, i): return self.dstr(6, i)
    def setp(self, i, v): self.e.setParameter(self.eff, i, v)
    def getp(self, i): return self.e.getParameter(self.eff, i)

    def get_chunk(self, preset=True):
        p = c_void_p()
        n = self.d(23, 1 if preset else 0, 0, ctypes.cast(byref(p), c_void_p))
        return ctypes.string_at(p.value, n)

    def set_chunk(self, data, preset=True):
        self._chunkbuf = create_string_buffer(data, len(data))
        return self.d(24, 1 if preset else 0, len(data), ctypes.cast(self._chunkbuf, c_void_p))

    def send_midi(self, msgs):
        # msgs: list of (delta, b0, b1, b2)
        n = len(msgs)
        E = make_events_struct(n)
        evs = [VstMidiEvent() for _ in msgs]
        for ev, (dt, a, b, c) in zip(evs, msgs):
            ev.type = 1; ev.byteSize = ctypes.sizeof(VstMidiEvent); ev.deltaFrames = dt
            ev.midiData[0] = a; ev.midiData[1] = b; ev.midiData[2] = c
        es = E(); es.numEvents = n
        for k, ev in enumerate(evs): es.events[k] = ctypes.addressof(ev)
        self._keep = (evs, es)
        self.d(25, 0, 0, ctypes.cast(byref(es), c_void_p))

    def process(self, nframes, inputs=None):
        out = [[], []]
        done = 0
        while done < nframes:
            n = min(self.block, nframes - done)
            if inputs is not None:
                for ch in range(2):
                    for k in range(n): self.bufs_in[ch][k] = inputs[ch][done + k]
            for ch in range(2):
                for k in range(n): self.bufs_out[ch][k] = 0.0
            self.e.processReplacing(self.eff, self.pin, self.pout, n)
            for ch in range(2): out[ch].extend(self.bufs_out[ch][:n])
            done += n; self.pos += n
        return out

    def render(self, events, nframes):
        """events: list of (frame, b0, b1, b2). Renders nframes; events sent at block starts with delta."""
        out = [[], []]
        evs = sorted(events)
        ei = 0; done = 0
        while done < nframes:
            n = min(self.block, nframes - done)
            batch = []
            while ei < len(evs) and evs[ei][0] < done + n:
                f, a, b, c = evs[ei]; batch.append((f - done, a, b, c)); ei += 1
            if batch: self.send_midi(batch)
            for ch in range(2):
                for k in range(n): self.bufs_out[ch][k] = 0.0
            self.e.processReplacing(self.eff, self.pin, self.pout, n)
            for ch in range(2): out[ch].extend(self.bufs_out[ch][:n])
            done += n; self.pos += n
        return out

def write_wav(path, chans, sr):
    import wave
    n = len(chans[0])
    w = wave.open(path, "wb"); w.setnchannels(len(chans)); w.setsampwidth(4 if False else 2); w.setframerate(int(sr))
    data = bytearray()
    for i in range(n):
        for c in chans:
            v = max(-1.0, min(1.0, c[i])); data += struct.pack("<h", int(v * 32767))
    w.writeframes(bytes(data)); w.close()

def write_f32(path, chans):
    with open(path, "wb") as f:
        f.write(struct.pack("<ii", len(chans), len(chans[0])))
        for c in chans: f.write(struct.pack("<%df" % len(c), *c))

if __name__ == "__main__":
    h = Host()
    e = h.e
    print("numParams", e.numParams, "numPrograms", e.numPrograms, "in", e.numInputs, "out", e.numOutputs,
          "flags", hex(e.flags), "uid", hex(e.uniqueID), struct.pack(">i", e.uniqueID), "ver", e.version)
    print("effect", h.dstr(45), "vendor", h.dstr(47), "product", h.dstr(48))

# ---- convenience helpers ----
def _flush(self, n=128):
    self.render([], n)
Host.flush = _flush

def _load_chunk(self, data):
    self.set_chunk(data, True)
    self.flush()
Host.load_chunk = _load_chunk

def _init_patch(self):
    self.load_chunk(open(os.path.join(HERE, "init_prog.bin"), "rb").read())
Host.init_patch = _init_patch

def _note(self, key=69, vel=100, on=22050, total=44100, extra=None):
    ev = [(0, 0x90, key, vel), (on, 0x80, key, 0)]
    if extra: ev += extra
    return self.render(ev, total)
Host.note = _note

def new_host(sr=44100.0, block=64, tempo=120.0):
    """Host with factory bank loaded, then Init patch applied. Ready for experiments."""
    h = Host(sr=sr, block=block, tempo=tempo)
    h.flush(640)
    h.init_patch()
    return h

def obj_f32(h, off):
    return ctypes.cast(h.e.object + off, POINTER(ctypes.c_float))[0]
def obj_i32(h, off):
    return ctypes.cast(h.e.object + off, POINTER(ctypes.c_int32))[0]
def obj_bytes(h, off, n):
    return ctypes.string_at(h.e.object + off, n)
