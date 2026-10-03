// A minimal CLAP host for checking the plugin's parameters and state from outside (Windows):
// it loads the .clap, creates and activates the plugin, then runs its commands in order.
//
//   claphost <Porridge.clap> [command ...]
//     list               every parameter: "id<TAB>name<TAB>module<TAB>min<TAB>max<TAB>default<TAB>value"
//     load <file>        loads a state (what save wrote, or any plugin's saved state)
//     save <file>        saves the state
//     set <id> <value>   sends a parameter value event (CLAP id, plain value) through flush
//     text <id> <value>  prints the value's text
//     wait <ms>          pumps the message loop and on_main_thread for that long (the patch worker)
//
// Build (from a VS 2022 developer prompt):
//   cl /std:c++17 /EHsc /I <clap>/include tools/test/claphost.cpp /Fe:claphost.exe
// tools/test/clap-ids.mjs uses it to compare two builds' parameter ids.

#define NOMINMAX
#include <windows.h>
#include <clap/clap.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <fstream>
#include <iterator>
#include <atomic>

static std::atomic<bool> callbackRequested { false };

static const void* hostGetExtension (const clap_host_t*, const char*)   { return nullptr; }
static void hostRequestRestart (const clap_host_t*)                     {}
static void hostRequestProcess (const clap_host_t*)                     {}
static void hostRequestCallback (const clap_host_t*)                    { callbackRequested = true; }

static const clap_host_t host
{
    CLAP_VERSION, nullptr, "porridge claphost", "porridge", "", "1.0",
    hostGetExtension, hostRequestRestart, hostRequestProcess, hostRequestCallback
};

static void pump (const clap_plugin_t* plugin, DWORD ms)
{
    const auto end = GetTickCount64() + ms;

    do
    {
        MSG msg;
        while (PeekMessageW (&msg, nullptr, 0, 0, PM_REMOVE))
        {
            TranslateMessage (&msg);
            DispatchMessageW (&msg);
        }

        if (callbackRequested.exchange (false))
            plugin->on_main_thread (plugin);

        Sleep (5);
    }
    while (GetTickCount64() < end);
}

// event lists for flush
struct InEvents
{
    std::vector<clap_event_param_value_t> events;
    clap_input_events_t list { this, size, get };

    static uint32_t size (const clap_input_events_t* l)   { return (uint32_t) static_cast<InEvents*> (l->ctx)->events.size(); }
    static const clap_event_header_t* get (const clap_input_events_t* l, uint32_t i)
    {
        return &static_cast<InEvents*> (l->ctx)->events[i].header;
    }
};

static bool tryPush (const clap_output_events_t*, const clap_event_header_t* e)
{
    if (e->type == CLAP_EVENT_PARAM_VALUE)
    {
        auto& v = *reinterpret_cast<const clap_event_param_value_t*> (e);
        printf ("out value %u %g\n", v.param_id, v.value);
    }
    else if (e->type == CLAP_EVENT_PARAM_GESTURE_BEGIN || e->type == CLAP_EVENT_PARAM_GESTURE_END)
    {
        auto& g = *reinterpret_cast<const clap_event_param_gesture_t*> (e);
        printf ("out gesture %s %u\n", e->type == CLAP_EVENT_PARAM_GESTURE_BEGIN ? "begin" : "end", g.param_id);
    }
    return true;
}

static const clap_output_events_t outEvents { nullptr, tryPush };

static int64_t writeStream (const clap_ostream_t* s, const void* data, uint64_t size)
{
    auto& out = *static_cast<std::string*> (s->ctx);
    out.append (static_cast<const char*> (data), size);
    return (int64_t) size;
}

struct ReadStream
{
    std::string data;
    size_t pos = 0;
    clap_istream_t stream { this, read };

    static int64_t read (const clap_istream_t* s, void* buffer, uint64_t size)
    {
        auto& r = *static_cast<ReadStream*> (s->ctx);
        auto n = std::min<uint64_t> (size, r.data.size() - r.pos);
        memcpy (buffer, r.data.data() + r.pos, n);
        r.pos += n;
        return (int64_t) n;
    }
};

int main (int argc, char** argv)
{
    if (argc < 2)
    {
        fprintf (stderr, "usage: claphost <plugin.clap> [list | load <file> | save <file> | set <id> <value> | text <id> <value> | wait <ms>] ...\n");
        return 1;
    }

    auto module = LoadLibraryA (argv[1]);
    if (! module) { fprintf (stderr, "can't load %s\n", argv[1]); return 1; }

    auto entry = reinterpret_cast<const clap_plugin_entry_t*> (GetProcAddress (module, "clap_entry"));
    if (! entry || ! entry->init (argv[1])) { fprintf (stderr, "no clap_entry\n"); return 1; }

    auto factory = static_cast<const clap_plugin_factory_t*> (entry->get_factory (CLAP_PLUGIN_FACTORY_ID));
    auto descriptor = factory->get_plugin_descriptor (factory, 0);
    auto plugin = factory->create_plugin (factory, &host, descriptor->id);

    if (! plugin || ! plugin->init (plugin)) { fprintf (stderr, "can't create the plugin\n"); return 1; }

    auto params = static_cast<const clap_plugin_params_t*> (plugin->get_extension (plugin, CLAP_EXT_PARAMS));
    auto state = static_cast<const clap_plugin_state_t*> (plugin->get_extension (plugin, CLAP_EXT_STATE));

    if (! plugin->activate (plugin, 44100.0, 32, 1024)) { fprintf (stderr, "can't activate\n"); return 1; }

    pump (plugin, 200);

    for (int i = 2; i < argc; ++i)
    {
        std::string command = argv[i];
        auto next = [&] { return i + 1 < argc ? std::string (argv[++i]) : std::string(); };

        if (command == "list")
        {
            for (uint32_t k = 0; k < params->count (plugin); ++k)
            {
                clap_param_info_t info {};
                params->get_info (plugin, k, &info);
                double value = 0;
                params->get_value (plugin, info.id, &value);
                printf ("%u\t%s\t%s\t%g\t%g\t%g\t%g\n", info.id, info.name, info.module, info.min_value, info.max_value,
                        info.default_value, value);
            }
        }
        else if (command == "save")
        {
            std::string out;
            clap_ostream_t stream { &out, writeStream };
            if (! state->save (plugin, &stream)) { fprintf (stderr, "save failed\n"); return 1; }
            std::ofstream (next(), std::ios::binary) << out;
        }
        else if (command == "load")
        {
            ReadStream r;
            std::ifstream f (next(), std::ios::binary);
            r.data.assign (std::istreambuf_iterator<char> (f), std::istreambuf_iterator<char>());
            if (! state->load (plugin, &r.stream)) { fprintf (stderr, "load failed\n"); return 1; }
        }
        else if (command == "set")
        {
            auto id = (clap_id) std::strtoul (next().c_str(), nullptr, 10);
            auto value = std::atof (next().c_str());
            InEvents in;
            clap_event_param_value_t e {};
            e.header = { sizeof (e), 0, CLAP_CORE_EVENT_SPACE_ID, CLAP_EVENT_PARAM_VALUE, 0 };
            e.param_id = id;
            e.note_id = -1; e.port_index = -1; e.channel = -1; e.key = -1;
            e.value = value;
            in.events.push_back (e);
            params->flush (plugin, &in.list, &outEvents);
        }
        else if (command == "text")
        {
            auto id = (clap_id) std::strtoul (next().c_str(), nullptr, 10);
            auto value = std::atof (next().c_str());
            char text[256] = {};
            if (params->value_to_text (plugin, id, value, text, sizeof (text))) printf ("text %u %s\n", id, text);
            else printf ("text %u (none)\n", id);
        }
        else if (command == "wait")
        {
            pump (plugin, (DWORD) std::atoi (next().c_str()));
        }
        else
        {
            fprintf (stderr, "unknown command %s\n", command.c_str());
            return 1;
        }

        fflush (stdout);
    }

    plugin->deactivate (plugin);
    plugin->destroy (plugin);
    entry->deinit();
    return 0;
}
