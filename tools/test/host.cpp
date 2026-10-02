// Offline test host for the Porridge patch, built from `cmaj generate --target=cpp`.
// Loads an Oatmeal v38 program chunk into the patch's parameter endpoints (+ shapes),
// plays MIDI events at exact frames and writes the stereo output as raw float32.
//
//   host --program prog.bin --events events.txt --frames 88200 --rate 44100 --out out.f32
//        [--tempo 120] [--set Endpoint=value ...] [--input in.f32] [--preroll n] [--latency n]
//        [--voices voices.txt] [--time] [--timefrom n]
//
// --input feeds a recorded signal to the effects instead of the voices. --preroll renders n
// frames before frame 0 and drops them (the DLL harness renders 128 after loading a program).
// --latency (default 64, the synth's) drops that many frames from the start of the output, as
// a host compensating for the plugin's latency would, so frame 0 is the first one that hears
// frame 0's MIDI. (Cmajor's C++ generator reports a latency of 0 whatever the patch declares.)
// --voices asks for the view's reports of the sounding notes (VoiceView) and writes one line per
// report: the frame, then the struct's 450 words as it's laid out (ints, bools as ints, floats);
// "--voices -" asks for them and drops them (what the open view costs).
// --time renders 64 frames a call and prints how long the render loop took ("render_seconds
// 0.123"), every call slower than 120 µs ("slow_block <frame> <µs>"; a 64-frame block has 1333 µs
// at 48 kHz) and the slowest ("render_worst_us"), for CPU measurements: on
// Windows the time the thread itself ran (its cycles over the TSC's rate), which other busy
// processes don't add to; elsewhere, wall time. --timefrom starts the clock at that frame (after
// the notes' attacks, say), and --time also prints the patch's size and how long constructing
// and initialising it took.
//
// events.txt: one event per line: "frame status data1 data2" (decimal), or "frame Endpoint value"
// to set a parameter at that frame (the rack's slots moving while effects ring, say).
// Output format (same as tools/re/vsthost.py write_f32): int32 channels, int32 frames,
// then channel-major float32 samples.

#include "build/porridge_gen.h"
#include "build/fields_gen.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <cctype>
#include <string>
#include <vector>
#include <fstream>
#include <sstream>
#include <algorithm>
#include <memory>
#include <chrono>
#ifdef _WIN32
 #define NOMINMAX
 #include <windows.h>
 #include <intrin.h>
#endif

// the seconds this thread has run (Windows), or wall seconds
struct ThreadClock
{
#ifdef _WIN32
    ULONG64 cycles0 = 0; unsigned long long tsc0 = 0; LARGE_INTEGER qpc0 {};
    void start() { QueryThreadCycleTime (GetCurrentThread(), &cycles0); tsc0 = __rdtsc(); QueryPerformanceCounter (&qpc0); }
    double seconds()
    {
        ULONG64 cycles; QueryThreadCycleTime (GetCurrentThread(), &cycles);
        LARGE_INTEGER qpc, f; QueryPerformanceCounter (&qpc); QueryPerformanceFrequency (&f);
        const double wall = double (qpc.QuadPart - qpc0.QuadPart) / double (f.QuadPart);
        const double tscHz = double (__rdtsc() - tsc0) / wall;
        return double (cycles - cycles0) / tscHz;
    }
#else
    std::chrono::steady_clock::time_point t0;
    void start() { t0 = std::chrono::steady_clock::now(); }
    double seconds() { return std::chrono::duration<double> (std::chrono::steady_clock::now() - t0).count(); }
#endif
};

using Patch = PorridgeTest;

static std::vector<uint8_t> readFile (const std::string& path)
{
    std::ifstream f (path, std::ios::binary);
    if (! f) { fprintf (stderr, "can't open %s\n", path.c_str()); exit (1); }
    return std::vector<uint8_t> ((std::istreambuf_iterator<char> (f)), std::istreambuf_iterator<char>());
}

struct Event { long frame; int status, d1, d2; std::string param, value; };

// sends a float or an int32
template <typename T>
static void send (Patch& p, const char* id, T v)
{
    static_assert (sizeof (T) == 4);
    auto h = Patch::getEndpointHandleForName (id);
    if (h == 0) { fprintf (stderr, "no endpoint %s\n", id); return; }
    unsigned char buf[4]; memcpy (buf, &v, 4);
    p.addEvent (h, 0, buf);
}

static void sendShape (Patch& p, const char* endpoint, int which, const float* data, int n)
{
    auto h = Patch::getEndpointHandleForName (endpoint);
    std::vector<unsigned char> buf (4 + 4 * n);
    memcpy (buf.data(), &which, 4);
    memcpy (buf.data() + 4, data, 4 * n);
    p.addEvent (h, 0, buf.data());
}

int main (int argc, char** argv)
{
    std::string programPath, eventsPath, inputPath, tuningPath, voicesPath, outPath = "out.f32";
    bool timing = false;
    double worst = 0;
    long frames = 44100, preroll = 0, latency = 64, timeFrom = 0;
    double rate = 44100.0, tempo = 120.0;
    std::vector<std::pair<std::string, std::string>> overrides;

    for (int i = 1; i < argc; ++i)
    {
        std::string a = argv[i];
        auto next = [&] { return i + 1 < argc ? std::string (argv[++i]) : std::string(); };
        if (a == "--program") programPath = next();
        else if (a == "--events") eventsPath = next();
        else if (a == "--out") outPath = next();
        else if (a == "--frames") frames = atol (next().c_str());
        else if (a == "--rate") rate = atof (next().c_str());
        else if (a == "--tempo") tempo = atof (next().c_str());
        else if (a == "--input") inputPath = next();
        else if (a == "--voices") voicesPath = next();
        else if (a == "--time") timing = true;
        else if (a == "--timefrom") timeFrom = atol (next().c_str());
        else if (a == "--preroll") preroll = atol (next().c_str());
        else if (a == "--latency") latency = atol (next().c_str());
        else if (a == "--tuning") tuningPath = next();
        else if (a == "--set")
        {
            auto s = next(); auto eq = s.find ('=');
            overrides.push_back ({ s.substr (0, eq), s.substr (eq + 1) });
        }
    }

    const auto t0 = std::chrono::steady_clock::now();
    auto patch = std::make_unique<Patch>();
    const auto t1 = std::chrono::steady_clock::now();
    patch->initialise (1, rate);
    const auto t2 = std::chrono::steady_clock::now();

    if (timing)
    {
        printf ("construct_ms %.3f%c", std::chrono::duration<double, std::milli> (t1 - t0).count(), 10);
        printf ("initialise_ms %.3f%c", std::chrono::duration<double, std::milli> (t2 - t1).count(), 10);
        printf ("sizeof_patch %zu%c", sizeof (Patch), 10);
    }

    send (*patch, "tempoIn", (float) tempo);

    if (! programPath.empty())
    {
        auto prog = readFile (programPath);
        if (prog.size() < programSize) { fprintf (stderr, "program too short\n"); return 1; }
        auto f32 = [&] (int off) { float v; memcpy (&v, prog.data() + off, 4); return v; };
        auto i32 = [&] (int off) { int32_t v; memcpy (&v, prog.data() + off, 4); return v; };
        auto u32 = [&] (int off) { uint32_t v; memcpy (&v, prog.data() + off, 4); return v; };

        for (auto& f : porridgeFields)
        {
            if (f.offset < 0) continue;
            switch (f.type)
            {
                case FieldType::f32:     send (*patch, f.id, f32 (f.offset)); break;
                case FieldType::i32:     send (*patch, f.id, i32 (f.offset)); break;
                case FieldType::filter1: send (*patch, f.id, i32 (f.offset) & 0xffff); break;
                case FieldType::filter2: send (*patch, f.id, (i32 (f.offset) >> 16) & 0xffff); break;
                case FieldType::pw:      send (*patch, f.id, (float) (u32 (f.offset) / 4294967296.0)); break;
            }
        }

        std::vector<float> tmp (512);
        for (int w = 0; w < 4; ++w)
        {
            memcpy (tmp.data(), prog.data() + waveOffsets[w], 512 * 4);
            sendShape (*patch, "shapeIn", w, tmp.data(), 512);
        }
        for (int c = 0; c < 2; ++c)
        {
            memcpy (tmp.data(), prog.data() + curveOffsets[c], 64 * 4);
            sendShape (*patch, "curveIn", c, tmp.data(), 64);
        }
    }

    // a parameter by its endpoint ID, as an int or a float as the program's fields say
    auto set = [&] (const std::string& id, const std::string& val)
    {
        bool isInt = false;
        for (auto& f : porridgeFields)
            if (id == f.id) isInt = f.isInt;
        if (isInt) send (*patch, id.c_str(), atoi (val.c_str()));
        else send (*patch, id.c_str(), (float) atof (val.c_str()));
    };

    for (auto& [id, val] : overrides)
        set (id, val);

    // --tuning: 128 numbers, each key's pitch in semitones from 440 Hz
    if (! tuningPath.empty())
    {
        std::ifstream f (tuningPath);
        std::vector<unsigned char> buf (4 + 128 * 4);
        int32_t on = 1;
        memcpy (buf.data(), &on, 4);
        for (int k = 0; k < 128; ++k)
        {
            float s = 0;
            f >> s;
            memcpy (buf.data() + 4 + 4 * k, &s, 4);
        }
        patch->addEvent (Patch::getEndpointHandleForName ("tuningIn"), 0, buf.data());
    }

    std::vector<Event> events;
    if (! eventsPath.empty())
    {
        std::ifstream f (eventsPath);
        std::string line;
        while (std::getline (f, line))
        {
            std::istringstream ss (line);
            Event e {};
            std::string a;
            if (! (ss >> e.frame >> a)) continue;
            if (isdigit ((unsigned char) a[0])) { e.status = atoi (a.c_str()); if (ss >> e.d1 >> e.d2) events.push_back (e); }
            else if (ss >> e.value) { e.param = a; events.push_back (e); }
        }
        std::stable_sort (events.begin(), events.end(), [] (auto& a, auto& b) { return a.frame < b.frame; });
        for (auto& e : events) e.frame += preroll;
    }

    std::vector<float> inL, inR;
    if (! inputPath.empty())
    {
        auto d = readFile (inputPath);
        int32_t ch, n;
        memcpy (&ch, d.data(), 4); memcpy (&n, d.data() + 4, 4);
        inL.resize (n); inR.resize (n);
        memcpy (inL.data(), d.data() + 8, 4 * n);
        memcpy (inR.data(), d.data() + 8 + (ch > 1 ? 4 * n : 0), 4 * n);
        send (*patch, "testMode", 1);
    }
    const auto inHandle = Patch::getEndpointHandleForName ("testIn");
    std::vector<float> inBlock (2 * Patch::maxFramesPerBlock);

    const auto outHandle = Patch::getEndpointHandleForName ("out");
    const auto midiHandle = Patch::getEndpointHandleForName ("midiIn");
    const auto voicesHandle = Patch::getEndpointHandleForName ("voiceViewOut");
    const bool voicesQuiet = voicesPath == "-";
    FILE* voices = voicesPath.empty() || voicesQuiet ? nullptr : fopen (voicesPath.c_str(), "w");
    if (voices || voicesQuiet) send (*patch, "voiceView", (int32_t) 1);
    const long totalFrames = frames + preroll + latency;
    std::vector<float> L (totalFrames), R (totalFrames), block (2 * Patch::maxFramesPerBlock);

    long pos = 0;
    size_t ei = 0;
    ThreadClock clock;
    clock.start();
    bool clockStarted = timeFrom <= 0;
    while (pos < totalFrames)
    {
        if (! clockStarted && pos >= timeFrom) { clock.start(); clockStarted = true; }
        while (ei < events.size() && events[ei].frame <= pos)
        {
            if (! events[ei].param.empty()) { set (events[ei].param, events[ei].value); ++ei; continue; }
            int32_t msg = (events[ei].status << 16) | (events[ei].d1 << 8) | events[ei].d2;
            unsigned char b[4]; memcpy (b, &msg, 4);
            patch->addEvent (midiHandle, 0, b);
            ++ei;
        }
        long n = std::min<long> (timing ? 64L : (long) Patch::maxFramesPerBlock, totalFrames - pos);
        if (ei < events.size()) n = std::min<long> (n, events[ei].frame - pos);
        n = std::max<long> (n, 1);
        if (! inL.empty())
        {
            for (long k = 0; k < n; ++k)
            {
                long q = pos + k - latency;
                inBlock[2 * k]     = q >= 0 && q < (long) inL.size() ? inL[q] : 0.0f;
                inBlock[2 * k + 1] = q >= 0 && q < (long) inR.size() ? inR[q] : 0.0f;
            }
            patch->setInputFrames (inHandle, inBlock.data(), (uint32_t) n, 0);
        }
        const auto callStart = std::chrono::steady_clock::now();
        patch->advance ((int32_t) n);
        if (timing)
        {
            const double us = std::chrono::duration<double, std::micro> (std::chrono::steady_clock::now() - callStart).count() * 64.0 / double (n);
            worst = std::max (worst, us);
            if (us > 120.0) printf ("slow_block %ld %.1f%c", pos, us, 10);
        }
        patch->copyOutputFrames (outHandle, block.data(), (uint32_t) n);

        if (voices)
        {
            for (uint32_t e = 0; e < patch->getNumOutputEvents (voicesHandle); ++e)
            {
                unsigned char data[1800];
                patch->readOutputEvent (voicesHandle, e, data);
                fprintf (voices, "%ld", pos + n);
                for (int w = 0; w < 450; ++w)
                {
                    int32_t i; float f;
                    memcpy (&i, data + 4 * w, 4); memcpy (&f, data + 4 * w, 4);
                    bool isInt = w < 33 || (w >= 177 && w < 194);
                    if (isInt) fprintf (voices, " %d", i); else fprintf (voices, " %g", f);
                }
                fputc (10, voices);
            }
            patch->resetOutputEventCount (voicesHandle);
        }
        else if (voicesQuiet)
        {
            unsigned char data[1800];
            for (uint32_t e = 0; e < patch->getNumOutputEvents (voicesHandle); ++e)
                patch->readOutputEvent (voicesHandle, e, data);
            patch->resetOutputEventCount (voicesHandle);
        }
        for (long k = 0; k < n; ++k) { L[pos + k] = block[2 * k]; R[pos + k] = block[2 * k + 1]; }
        pos += n;
    }

    if (timing)
    {
        printf ("render_seconds %.6f%c", clock.seconds(), 10);
        printf ("render_worst_us %.1f%c", worst, 10);
    }

    FILE* o = fopen (outPath.c_str(), "wb");
    int32_t hdr[2] = { 2, (int32_t) frames };
    fwrite (hdr, 4, 2, o);
    fwrite (L.data() + preroll + latency, 4, frames, o);
    fwrite (R.data() + preroll + latency, 4, frames, o);
    fclose (o);
    if (voices) fclose (voices);
    return 0;
}
