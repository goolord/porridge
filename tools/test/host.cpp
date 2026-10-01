// Offline test host for the Porridge patch, built from `cmaj generate --target=cpp`.
// Loads an Oatmeal v38 program chunk into the patch's parameter endpoints (+ shapes),
// plays MIDI events at exact frames and writes the stereo output as raw float32.
//
//   host --program prog.bin --events events.txt --frames 88200 --rate 44100 --out out.f32
//        [--tempo 120] [--set Endpoint=value ...] [--input in.f32] [--preroll n]
//
// --input feeds a recorded signal to the effects instead of the voices. --preroll renders n
// frames before frame 0 and drops them (the DLL harness renders 128 after loading a program).
//
// events.txt: one event per line: "frame status data1 data2" (decimal).
// Output format (same as tools/re/vsthost.py write_f32): int32 channels, int32 frames,
// then channel-major float32 samples.

#include "build/porridge_gen.h"
#include "build/fields_gen.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <string>
#include <vector>
#include <fstream>
#include <sstream>
#include <algorithm>
#include <memory>

using Patch = PorridgeTest;

static std::vector<uint8_t> readFile (const std::string& path)
{
    std::ifstream f (path, std::ios::binary);
    if (! f) { fprintf (stderr, "can't open %s\n", path.c_str()); exit (1); }
    return std::vector<uint8_t> ((std::istreambuf_iterator<char> (f)), std::istreambuf_iterator<char>());
}

struct Event { long frame; int status, d1, d2; };

static void sendFloat (Patch& p, const char* id, float v)
{
    auto h = Patch::getEndpointHandleForName (id);
    if (h == 0) { fprintf (stderr, "no endpoint %s\n", id); return; }
    unsigned char buf[4]; memcpy (buf, &v, 4);
    p.addEvent (h, 0, buf);
}

static void sendInt (Patch& p, const char* id, int32_t v)
{
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
    std::string programPath, eventsPath, inputPath, outPath = "out.f32";
    long frames = 44100, preroll = 0;
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
        else if (a == "--preroll") preroll = atol (next().c_str());
        else if (a == "--set")
        {
            auto s = next(); auto eq = s.find ('=');
            overrides.push_back ({ s.substr (0, eq), s.substr (eq + 1) });
        }
    }

    auto patch = std::make_unique<Patch>();
    patch->initialise (1, rate);

    // tempo
    {
        auto h = Patch::getEndpointHandleForName ("tempoIn");
        if (h) { float bpm = (float) tempo; unsigned char b[4]; memcpy (b, &bpm, 4); patch->addEvent (h, 0, b); }
    }

    if (! programPath.empty())
    {
        auto prog = readFile (programPath);
        if (prog.size() < 10376) { fprintf (stderr, "program too short\n"); return 1; }
        auto f32 = [&] (int off) { float v; memcpy (&v, prog.data() + off, 4); return v; };
        auto i32 = [&] (int off) { int32_t v; memcpy (&v, prog.data() + off, 4); return v; };
        auto u32 = [&] (int off) { uint32_t v; memcpy (&v, prog.data() + off, 4); return v; };

        for (auto& f : porridgeFields)
        {
            switch (f.type)
            {
                case FieldType::f32:     sendFloat (*patch, f.id, f32 (f.offset)); break;
                case FieldType::i32:     sendInt (*patch, f.id, i32 (f.offset)); break;
                case FieldType::filter1: sendInt (*patch, f.id, i32 (8428) & 0xffff); break;
                case FieldType::filter2: sendInt (*patch, f.id, (i32 (8428) >> 16) & 0xffff); break;
                case FieldType::pw:      sendFloat (*patch, f.id, (float) (u32 (f.offset) / 4294967296.0)); break;
            }
        }

        std::vector<float> tmp (512);
        const int waveOffsets[4] = { 32, 2080, 4136, 6184 };
        for (int w = 0; w < 4; ++w)
        {
            memcpy (tmp.data(), prog.data() + waveOffsets[w], 512 * 4);
            sendShape (*patch, "shapeIn", w, tmp.data(), 512);
        }
        const int curveOffsets[2] = { 9596, 9852 };
        for (int c = 0; c < 2; ++c)
        {
            memcpy (tmp.data(), prog.data() + curveOffsets[c], 64 * 4);
            sendShape (*patch, "curveIn", c, tmp.data(), 64);
        }
    }

    for (auto& [id, val] : overrides)
    {
        bool isInt = false;
        for (auto& f : porridgeFields)
            if (id == f.id) isInt = (f.type == FieldType::i32 || f.type == FieldType::filter1 || f.type == FieldType::filter2);
        for (auto& f : porridgeExtras)
            if (id == f.id) isInt = f.isInt;
        if (isInt) sendInt (*patch, id.c_str(), atoi (val.c_str()));
        else sendFloat (*patch, id.c_str(), (float) atof (val.c_str()));
    }

    std::vector<Event> events;
    if (! eventsPath.empty())
    {
        std::ifstream f (eventsPath);
        std::string line;
        while (std::getline (f, line))
        {
            std::istringstream ss (line);
            Event e;
            if (ss >> e.frame >> e.status >> e.d1 >> e.d2) events.push_back (e);
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
        sendInt (*patch, "testMode", 1);
    }
    const auto inHandle = Patch::getEndpointHandleForName ("testIn");
    std::vector<float> inBlock (2 * Patch::maxFramesPerBlock);

    const auto outHandle = Patch::getEndpointHandleForName ("out");
    const auto midiHandle = Patch::getEndpointHandleForName ("midiIn");
    const long totalFrames = frames + preroll;
    std::vector<float> L (totalFrames), R (totalFrames), block (2 * Patch::maxFramesPerBlock);

    long pos = 0;
    size_t ei = 0;
    while (pos < totalFrames)
    {
        while (ei < events.size() && events[ei].frame <= pos)
        {
            int32_t msg = (events[ei].status << 16) | (events[ei].d1 << 8) | events[ei].d2;
            unsigned char b[4]; memcpy (b, &msg, 4);
            patch->addEvent (midiHandle, 0, b);
            ++ei;
        }
        long n = std::min<long> ((long) Patch::maxFramesPerBlock, totalFrames - pos);
        if (ei < events.size()) n = std::min<long> (n, events[ei].frame - pos);
        n = std::max<long> (n, 1);
        if (! inL.empty())
        {
            for (long k = 0; k < n; ++k)
            {
                long q = pos + k;
                inBlock[2 * k]     = q < (long) inL.size() ? inL[q] : 0.0f;
                inBlock[2 * k + 1] = q < (long) inR.size() ? inR[q] : 0.0f;
            }
            patch->setInputFrames (inHandle, inBlock.data(), (uint32_t) n, 0);
        }
        patch->advance ((int32_t) n);
        patch->copyOutputFrames (outHandle, block.data(), (uint32_t) n);
        for (long k = 0; k < n; ++k) { L[pos + k] = block[2 * k]; R[pos + k] = block[2 * k + 1]; }
        pos += n;
    }

    FILE* o = fopen (outPath.c_str(), "wb");
    int32_t hdr[2] = { 2, (int32_t) frames };
    fwrite (hdr, 4, 2, o);
    fwrite (L.data() + preroll, 4, frames, o);
    fwrite (R.data() + preroll, 4, frames, o);
    fclose (o);
    return 0;
}
