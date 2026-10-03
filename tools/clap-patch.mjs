// Patches the CLAP wrapper that `cmaj generate --target=clap` writes, for things Cmajor's
// wrapper doesn't do:
//
//  - Resizing keeps the interface's aspect ratio (resize hints and adjust_size), so the host
//    window scales the whole panel instead of leaving bars around it.
//  - The interface size ("zoom") is a user setting, kept in a settings file that every
//    instance shares: %APPDATA%\Porridge\settings.json, ~/Library/Application Support/Porridge
//    or ~/.config/porridge. New editor windows open at that size.
//  - The view reaches the settings through stored-state requests whose key starts with
//    "porridge:settings?" (?get, ?zoom=<factor>, ?save=<json>). The patch answers every
//    request by broadcasting it to its views; a listener view added here acts on them and
//    replies to the editor with a "porridge:settings" state value
//    { settings: <the file's object>, zoom: <this window's size> }. Nothing is stored in
//    the plugin's state. See ui/Settings.res. The code is in tools/clap/PorridgeBridge.h, which
//    is copied next to the wrapper.
//  - The bank library: the preset browser's bank folders, scanned and cached, and the files
//    opened in it, kept in <settings folder>/banks. The view asks with keys that start with
//    "porridge:library?" and the plugin answers with "porridge:library" values; see
//    tools/clap/PorridgeLibrary.h and ui/BankLibrary.res.
//  - The host's menu for a parameter (CLAP's context-menu extension; in FL Studio it has
//    Create automation clip, Link to controller and so on), which a double right-click on a
//    control opens. The view asks through the same bridge, with keys that start with
//    "porridge:host?": ?get is answered with a "porridge:host" state value
//    { menu: <whether the host can show it> }; ?menu=<json> { id, x, y, scale } shows it for
//    the parameter with that endpoint ID, at a point in the view (CSS pixels, and the view's
//    device pixel ratio); ?dismiss closes it, for a press or Escape in the view, which the
//    menu never hears on Windows. The menu is shown from on_main_thread, once the view's
//    message has been handled; hosts run it modally inside popup(), and the dismiss request
//    arrives while it runs (porridge::dismissHostMenu says how each kind of menu is closed).
//    See ui/HostMenu.res.
//  - Only the transport's tempo reaches the patch, and only when it changes (the rest costs
//    more than a small block's synth work, and the patch doesn't read it).
//  - A CPU diagnostic, off unless PORRIDGE_PERF is set: the process calls of each instance are
//    timed and summarised in porridge-perf.log in the temp folder (tools/clap/PorridgePerf.h).
//  - The latency is the synth's 64 samples (dsp/Synth.cmajor applies MIDI a block late, on
//    its own sample). Cmajor's C++ generator reports 0 whatever the patch declares.
//  - The generated class finds an event's endpoint with a switch instead of trying every
//    parameter's handle in turn, which cost each MIDI message ~1.7 µs (tools/event-switch.mjs).
//
//  - Parameter ids: hosts know a parameter by its id in dsp/param-ids.txt (tools/param-ids.mjs),
//    instead of by its endpoint handle, which counts the endpoints before it, so that endpoints
//    can be removed or reordered without breaking hosts' saved automation. The wrapper keys its
//    parameter tables by that id, so every place an id crosses the CLAP boundary (the info,
//    values and texts, the host's and the editor's value and gesture events, the host's menu)
//    uses it. The table is generated into PorridgeParamIds.h.
//  - A saved state that names parameters the patch no longer has (the custom shapes' points,
//    which became stored state, and the effects' copies, whose values the rack's slots took
//    over) keeps their values under the stored-state key "params", merged with what that holds,
//    where the view and the worker read them (ui/StoredParams.res, worker/PatchWorker.res).
//  - The rack's and the voice lane's slots' knobs (FX3_1 .., VL1_1 ..) are named after the kind
//    each slot holds ("FX 3 delay wet"), with that kind's value texts; the knobs a kind doesn't
//    use, and an empty slot's, are hidden. When a slot's kind changes the host is asked to
//    rescan the parameters' info and texts (CLAP_PARAM_RESCAN_INFO | CLAP_PARAM_RESCAN_TEXT).
//    The tables are generated into PorridgeSlots.h from ui/PorridgeParams.res and ParamDefs.
//
// and to load faster:
//
//  - The patch worker runs in QuickJS, in the plugin, instead of in a hidden web view (with
//    a renderer process) of its own per instance; the web view took half a second or more to
//    start, during which the patch played without its waveforms and a new instance without
//    its bank. choc's QuickJS never ran promise jobs, so it does now
//    (choc_javascript_QuickJS.h).
//  - Activating rebuilds the patch only if the sample rate or block size changed, instead of
//    loading it again from scratch (which built it three times).
//  - Cmajor's Engine keeps the program details it last parsed (cmaj_Engine.h): Porridge's are
//    about 175 kB of JSON, and every build asked for them about five times.
//
//   node tools/clap-patch.mjs [path to the generated project]

import { readFileSync, writeFileSync, copyFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { switchAddEvent } from "./event-switch.mjs";
import { readIds } from "./param-ids.mjs";
import * as PorridgeParams from "../ui/PorridgeParams.res.mjs";
import { makeDefs } from "../ui/ParamDefs.res.mjs";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const project = process.argv[2] ?? join(root, "build", "clap-project");
const marker = "// Porridge:";

// The synth reports one block of latency for sample-accurate MIDI (dsp/Synth.cmajor).
const blockSize = Number(/let blockSize = (\d+);/.exec(readFileSync(join(root, "dsp", "Types.cmajor"), "utf8"))?.[1]);
if (!blockSize) throw new Error("blockSize not found in dsp/Types.cmajor");

// the file being patched
let file, source;

// Starts patching a file; false if it already is.
const open = (path) => {
  file = path;
  source = readFileSync(file, "utf8").replace(/\r\n/g, "\n");
  if (!source.includes(marker)) return true;
  console.log(`${file} is already patched`);
  return false;
};

const save = () => {
  writeFileSync(file, source);
  console.log(`patched ${file}`);
};

const fail = (what) => {
  console.error(`clap-patch: couldn't find ${what} in ${file}; the Cmajor wrapper has changed, so update tools/clap-patch.mjs`);
  process.exit(1);
};

// Replaces the one occurrence of `find`.
const replace = (find, replacement) => {
  const at = source.indexOf(find);
  if (at < 0 || source.indexOf(find, at + 1) >= 0) fail(JSON.stringify(find.slice(0, 80)));
  source = source.slice(0, at) + replacement + source.slice(at + find.length);
};

// Inserts text just before or after the one occurrence of `anchor`.
const insertBefore = (anchor, text) => replace(anchor, text + anchor);
const insertAfter = (anchor, text) => replace(anchor, anchor + text);

//==============================================================================
// Cmajor's Engine

if (open(join(project, "include", "cmajor", "API", "cmaj_Engine.h"))) {
  insertAfter(`#include <functional>\n`, `#include <mutex>\n#include <string>\n`);

  replace(
    `                return choc::json::parse (choc::com::StringPtr (details));\n`,
    `                ${marker} a big patch's details take a while to parse, and loading it asks
                // for them several times, so the last ones parsed are kept (added by
                // tools/clap-patch.mjs)
                static std::mutex lock;
                static std::string lastText;
                static choc::value::Value lastDetails;

                choc::com::StringPtr text (details);
                std::lock_guard<std::mutex> lockForCache (lock);

                if (text.get() != lastText)
                {
                    lastDetails = choc::json::parse (text.get());
                    lastText = std::string (text.get());
                }

                return lastDetails;
`,
  );

  save();
}

//==============================================================================
// choc's QuickJS, which runs the patch worker

if (open(join(project, "include", "choc", "choc", "javascript", "choc_javascript_QuickJS.h"))) {
  insertAfter(
    `    void pumpMessageLoop() override {}\n`,
    `
    ${marker} runs the promise jobs (await, then) that a call into the script queued, as an
    // event loop does after each task; without this, async code stopped at its first await
    // (added by tools/clap-patch.mjs)
    void runPendingJobs()
    {
        JSContext* jobContext = nullptr;

        while (JS_ExecutePendingJob (runtime, &jobContext) > 0)
        {}
    }
`,
  );

  replace(
    `        return takeValue (JS_Eval (context, code.c_str(), code.size(), "", JS_EVAL_TYPE_GLOBAL)).toChocValue();\n`,
    `        auto result = takeValue (JS_Eval (context, code.c_str(), code.size(), "", JS_EVAL_TYPE_GLOBAL)).toChocValue();
        runPendingJobs();
        return result;
`,
  );

  for (const type of ["JS_EVAL_TYPE_MODULE", "JS_EVAL_TYPE_GLOBAL"]) {
    const line = `                auto result = takeValue (JS_Eval (context, code.c_str(), code.size(), "", ${type}));\n`;
    insertAfter(line, `                runPendingJobs();\n`);
  }

  insertBefore(`        return returnVal.toChocValue();\n`, `        runPendingJobs();\n`);

  save();
}

//==============================================================================
// The generated patch class: addEvent's dispatch as a switch (see tools/event-switch.mjs)

if (open(join(project, "entry.cpp"))) {
  source = switchAddEvent(source, marker);
  save();
}

//==============================================================================
// The CLAP wrapper

if (!open(join(project, "helpers", "clap", "cmaj_CLAPPlugin.h"))) process.exit(0);

for (const header of ["PorridgeBridge.h", "PorridgeLibrary.h", "PorridgePerf.h"])
  copyFileSync(join(root, "tools", "clap", header), join(project, "helpers", "clap", header));

// The parameter endpoints' CLAP ids (dsp/param-ids.txt), which every endpoint must have
{
  const endpoints = [
    ...readFileSync(join(root, "dsp", "ParamStore.cmajor"), "utf8").matchAll(/^ {4}input event (?:int|float) (\w+) \[\[/gm),
  ].map((m) => m[1]);
  const ids = readIds(join(root, "dsp", "param-ids.txt"));
  const missing = endpoints.filter((name) => !ids.has(name));

  if (endpoints.length === 0 || missing.length > 0) {
    console.error(
      `clap-patch: ${missing.length ? `no CLAP id for ${missing.join(", ")}` : "no parameters in dsp/ParamStore.cmajor"}; ` +
        `run node tools/gen.mjs, which adds them to dsp/param-ids.txt (commit that file)`,
    );
    process.exit(1);
  }

  writeFileSync(
    join(project, "helpers", "clap", "PorridgeParamIds.h"),
    `// Generated by tools/clap-patch.mjs from dsp/param-ids.txt - do not edit.
// Included inside cmaj_CLAPPlugin.h's cmaj::plugin::clap::detail namespace, after its headers.

#pragma once

namespace porridge::params
{
    struct IdEntry
    {
        std::string_view endpoint;
        clap_id id;
    };

    /// every parameter endpoint and the id hosts know it by
    inline constexpr IdEntry clapIds[] =
    {
${endpoints.map((name) => `        { "${name}", ${ids.get(name)}u },`).join("\n")}
    };

    /// The CLAP id of a parameter endpoint, or CLAP_INVALID_ID if the patch has no such parameter.
    inline clap_id clapIdFor (std::string_view endpoint)
    {
        static const auto byEndpoint = []
        {
            std::unordered_map<std::string_view, clap_id> map;

            for (const auto& entry : clapIds)
                map.emplace (entry.endpoint, entry.id);

            return map;
        }();

        const auto found = byEndpoint.find (endpoint);
        return found != byEndpoint.end() ? found->second : CLAP_INVALID_ID;
    }

    /// The stored-state key that keeps the values of parameters the patch no longer has as
    /// endpoints (a JSON object, name -> value; ui/StoredParams.res).
    inline constexpr std::string_view storedKey = "params";

    /// A state saved when some of its parameters were still endpoints: their values move from
    /// its parameter list to the stored value, unless it has one already. True if it changed.
    inline bool keepRemovedParameters (choc::value::Value& state)
    {
        if (! state.isObject() || ! state.hasObjectMember ("parameters"))
            return false;

        const auto parameters = state["parameters"];
        auto values = state.hasObjectMember ("values") && state["values"].isObject()
                        ? choc::value::Value (state["values"]) : choc::value::createObject ({});

        if (! parameters.isArray())
            return false;

        // (merged into the value the state has, if it has one: what's there wins)
        auto kept = choc::value::createObject ({});

        if (values.hasObjectMember (storedKey))
        {
            try
            {
                auto had = choc::json::parse (values[storedKey].toString());

                if (had.isObject())
                    for (uint32_t i = 0; i < had.size(); ++i)
                        kept.addMember (had.getObjectMemberAt (i).name, had.getObjectMemberAt (i).value);
            }
            catch (...) {}
        }

        bool moved = false;
        auto remaining = choc::value::createEmptyArray();

        for (const auto& parameter : parameters)
        {
            const auto name = parameter.isObject() && parameter.hasObjectMember ("name") ? parameter["name"].toString() : std::string();
            const auto value = parameter.isObject() && parameter.hasObjectMember ("value") ? parameter["value"] : choc::value::ValueView();

            if (! name.empty() && (value.isFloat() || value.isInt()) && clapIdFor (name) == CLAP_INVALID_ID)
            {
                if (! kept.hasObjectMember (name))
                    kept.addMember (name, value.getWithDefault<double> (0.0));

                moved = true;
            }
            else
            {
                remaining.addArrayElement (parameter);
            }
        }

        if (! moved)
            return false;

        if (values.hasObjectMember (storedKey))
            values.setMember (storedKey, choc::json::toString (kept, false));
        else
            values.addMember (storedKey, choc::json::toString (kept, false));
        state = choc::json::create ("parameters", remaining, "values", values);
        return true;
    }
}
`,
  );
}

// The slots' knobs: their names and texts by the kind each slot holds (PorridgeSlots.h)
{
  const defs = new Map(makeDefs().map((d) => [d.id, d]));
  const cs = (x) => JSON.stringify(x);
  const kinds = PorridgeParams.rackKinds;
  const kindOf = PorridgeParams.rackEntries.map((e, v) => (e && v > 4 ? kinds.findIndex((k) => k.key === e[0]) : -1));
  // each kind's knobs: name, then texts (a list's every value, from its lowest; a float's at 51
  // knob positions), and whether it's a list
  const knobLines = [], textLines = [];
  const kindLines = kinds.map((k) => {
    const key = k.runsIn === "LaneOnly" ? "L1" : "1";
    const kindName = k.menuName ?? k.name.toLowerCase();
    const first = knobLines.length;
    for (const [id, label] of PorridgeParams.knobsOf(k)) {
      const d = defs.get(PorridgeParams.slotParamId(id, key));
      const texts = d.isInt
        ? Array.from({ length: d.max - d.min + 1 }, (_, i) => d.valueText(d.min + i))
        : Array.from({ length: 51 }, (_, i) => d.valueText(d.fromNorm(i / 50)));
      textLines.push(`    inline constexpr std::string_view texts${knobLines.length}[] = { ${texts.map(cs).join(", ")} };`);
      knobLines.push(`        { ${cs(kindName + " " + label)}, ${d.isInt}, ${cs(d.min)}, ${cs(d.max)}, ${texts.length}, texts${knobLines.length} },`);
    }
    return `        { ${first}, ${knobLines.length - first} },`;
  });
  const knobs = Array.from({ length: PorridgeParams.slotCount }, (_, g) =>
    Array.from({ length: PorridgeParams.knobCount(g) }, (_, i) => `        { ${cs(PorridgeParams.knobId(g, i + 1))}, ${g}, ${i} },`),
  ).flat();
  writeFileSync(
    join(project, "helpers", "clap", "PorridgeSlots.h"),
    `// Generated by tools/clap-patch.mjs from ui/PorridgeParams.res - do not edit.
// Included inside cmaj_CLAPPlugin.h's cmaj::plugin::clap::detail namespace, after PorridgeParamIds.h.

#pragma once

namespace porridge::slots
{
    struct Knob
    {
        std::string_view name;      // "delay wet": the kind's, with its label
        bool isList;
        double min, max;            // a list's lowest and highest value
        int numTexts;
        const std::string_view* texts;   // a list's values' names; a float's at 51 knob positions
    };

    struct Kind { int firstKnob, numKnobs; };

${textLines.join("\n")}

    inline const Knob knobs[] =
    {
${knobLines.join("\n")}
    };

    inline constexpr Kind kinds[] =
    {
${kindLines.join("\n")}
    };

    /// the kind each rack value holds (-1: none)
    inline constexpr int kindOfValue[] = { ${kindOf.join(", ")} };

    /// each slot's kind parameter and its name in the knobs' names
    inline constexpr std::string_view kindEndpoints[] = { ${Array.from({ length: PorridgeParams.slotCount }, (_, g) => cs(PorridgeParams.slotKindId(g))).join(", ")} };
    inline constexpr std::string_view titles[] = { ${Array.from({ length: PorridgeParams.slotCount }, (_, g) => cs(PorridgeParams.slotTitle(g))).join(", ")} };

    struct KnobEndpoint { std::string_view endpoint; int slot, knob; };

    inline constexpr KnobEndpoint knobEndpoints[] =
    {
${knobs.join("\n")}
    };

    /// The slot and knob of a knob's CLAP id, if it is one.
    inline const KnobEndpoint* knobOf (clap_id id)
    {
        static const auto byId = []
        {
            std::unordered_map<clap_id, const KnobEndpoint*> map;

            for (const auto& k : knobEndpoints)
                map.emplace (porridge::params::clapIdFor (k.endpoint), std::addressof (k));

            return map;
        }();

        const auto found = byId.find (id);
        return found != byId.end() ? found->second : nullptr;
    }

    /// The knob a slot's kind (its value) has there, if it has one.
    inline const Knob* kindKnob (const KnobEndpoint& k, float value)
    {
        const auto v = static_cast<int> (value);
        const auto kind = v >= 0 && v < static_cast<int> (std::size (kindOfValue)) ? kindOfValue[v] : -1;

        if (kind < 0 || k.knob >= kinds[kind].numKnobs)
            return nullptr;

        return std::addressof (knobs[kinds[kind].firstKnob + k.knob]);
    }

    /// A knob's info for what its slot holds (its kind parameter's value read by kindValue):
    /// named after the kind's parameter there, or hidden.
    template <typename KindValue>
    void describe (clap_param_info_t& info, KindValue&& kindValue)
    {
        if (const auto* k = knobOf (info.id))
        {
            const auto* knob = kindKnob (*k, kindValue (kindEndpoints[k->slot]));
            const auto name = std::string (titles[k->slot]) + " " + (knob ? std::string (knob->name) : "knob " + std::to_string (k->knob + 1));
            std::snprintf (info.name, sizeof (info.name), "%s", name.c_str());

            if (knob) info.flags &= ~static_cast<clap_param_info_flags> (CLAP_PARAM_IS_HIDDEN);
            else      info.flags |= CLAP_PARAM_IS_HIDDEN;
        }
    }

    /// A knob's value's text for what its slot holds: the kind's (false: not a knob, or one its
    /// slot's kind doesn't use).
    template <typename KindValue>
    bool text (clap_id id, double value, char* out, uint32_t capacity, KindValue&& kindValue)
    {
        const auto* k = knobOf (id);
        const auto* knob = k ? kindKnob (*k, kindValue (kindEndpoints[k->slot])) : nullptr;

        if (! knob || capacity == 0)
            return false;

        const auto v = std::clamp (value, 0.0, 1.0);
        const auto i = knob->isList ? static_cast<int> (std::floor (knob->min + v * (knob->max - knob->min) + 0.5) - knob->min)
                                    : static_cast<int> (std::floor (v * 50.0 + 0.5));
        const auto t = knob->texts[std::clamp (i, 0, knob->numTexts - 1)];
        std::snprintf (out, capacity, "%.*s", static_cast<int> (t.size()), t.data());
        return true;
    }
}
`,
  );
}

insertBefore(
  `#include "cmajor/helpers/cmaj_PluginHelpers.h"\n`,
  `${marker} the patch worker runs in QuickJS, rather than in a hidden web view that takes
// about a second to start (added by tools/clap-patch.mjs)
#ifndef CMAJ_USE_QUICKJS_WORKER
 #define CMAJ_USE_QUICKJS_WORKER 1
#endif

`,
);

insertAfter(
  `#include "choc/gui/choc_DesktopWindow.h"\n`,
  `#include "choc/text/choc_Files.h"\n#include "choc/text/choc_JSON.h"\n#include "choc/memory/choc_Base64.h"\n`,
);
insertAfter(`#include <algorithm>\n`, `#include <cmath>\n#include <cstdlib>\n#include <fstream>\n`);

// The CPU diagnostic (PORRIDGE_PERF, tools/clap/PorridgePerf.h); after the standard headers
insertAfter(
  `#include <vector>
`,
  `
${marker} an optional CPU diagnostic (added by tools/clap-patch.mjs)
#ifdef _WIN32
 #ifndef NOMINMAX
  #define NOMINMAX
 #endif
 #include <windows.h>
#endif
#include "PorridgePerf.h"
`,
);

//==============================================================================
insertAfter(
  `namespace detail
{
`,
  `
${marker} user settings shared by every instance, the host's parameter menu, and the bridge
// the view reaches them through (tools/clap/PorridgeBridge.h, added by tools/clap-patch.mjs).
#include "PorridgeBridge.h"

${marker} the parameters' CLAP ids (dsp/param-ids.txt), generated by tools/clap-patch.mjs
#include "PorridgeParamIds.h"

${marker} the slots' knobs' names and texts by kind, generated by tools/clap-patch.mjs
#include "PorridgeSlots.h"
`,
);

//==============================================================================
// Parameter ids: from here on, a parameter's "handle" in the wrapper's tables and events is its
// CLAP id (see PorridgeParamIds.h)
replace(
  `        // currently these are just laid out in the order they end up in the parameter list.
        // Endpoint handles are currenty used as IDs, which is brittle.
`,
  `        ${marker} the id is the parameter's in dsp/param-ids.txt, not its endpoint handle
`,
);

replace(
  `        const auto& properties = parameter->properties;
        const auto& endpointHandle = parameter->endpointHandle;

        if (! properties.automatable)
            continue;
`,
  `        const auto& properties = parameter->properties;

        ${marker} hosts know a parameter by its id in dsp/param-ids.txt, not by its endpoint
        // handle (which counts the endpoints before it). Everything below keys the parameter by
        // that id: the info, the tables "ByHandle", and the events the editor sends the host.
        const auto endpointHandle = static_cast<cmaj::EndpointHandle> (porridge::params::clapIdFor (properties.endpointID));

        if (! properties.automatable || endpointHandle == CLAP_INVALID_ID)
            continue;
`,
);

//==============================================================================
replace(
  `        ViewHolder (cmaj::Patch& patchToUse, std::optional<double> initialScaleFactorToUse)
            : webview (std::make_unique<cmaj::PatchWebView> (patchToUse, findDefaultViewForPatch (patchToUse)))
        {
            if (initialScaleFactorToUse)
                setScaleFactor (*initialScaleFactorToUse);
        }
`,
  `        ViewHolder (cmaj::Patch& patchToUse, std::optional<double> initialScaleFactorToUse, double zoomToUse)
            : webview (std::make_unique<cmaj::PatchWebView> (patchToUse, findDefaultViewForPatch (patchToUse))),
              designWidth (webview->width),
              designHeight (webview->height)
        {
            if (initialScaleFactorToUse)
                setScaleFactor (*initialScaleFactorToUse);

            webview->width  = sizeForZoom (zoomToUse).width;
            webview->height = sizeForZoom (zoomToUse).height;
        }
`,
);

insertBefore(
  `    private:
        void* nativeViewHandle() const`,
  `        ${marker} the view's size relative to the manifest's, which the panel keeps the aspect
        // ratio of
        Size designSize() const     { return { designWidth, designHeight }; }

        double zoom() const
        {
            return porridge::clampZoom (std::min (webview->width / double (designWidth),
                                                  webview->height / double (designHeight)));
        }

        /// The size of the view at a zoom, in host pixels.
        Size hostSizeForZoom (double z) const
        {
            auto s = sizeForZoom (z);
            return { scaled (s.width), scaled (s.height) };
        }

        /// The size nearest to one the host suggests that keeps the aspect ratio.
        Size adjust (Size suggested) const
        {
            auto unscaledExact = [this] (uint32_t x) { return inverseScaleFactor ? *inverseScaleFactor * x : double (x); };

            return hostSizeForZoom (std::min (unscaledExact (suggested.width) / designWidth,
                                              unscaledExact (suggested.height) / designHeight));
        }

        cmaj::PatchWebView& getPatchWebView()     { return *webview; }

        Size sizeForZoom (double z) const
        {
            z = porridge::clampZoom (z);
            return { toIntegerPixel (designWidth * z), toIntegerPixel (designHeight * z) };
        }

`,
);

insertAfter(`        std::unique_ptr<cmaj::PatchWebView> webview;\n`, `        uint32_t designWidth, designHeight;\n`);

insertAfter(
  `    std::optional<ViewHolder> editor;
`,
  `
    ${marker} the size of this instance's editor, kept while it is closed, and the bridge that
    // answers the view's settings and host requests
    std::optional<double> editorZoom;
    std::unique_ptr<porridge::RequestBridge> requestBridge;

    void handleViewRequest (std::string_view);
    void handleSettingsRequest (std::string_view);
    void sendSettingsToView();
    void handleLibraryRequest (std::string_view);

    ${marker} the host's menu for a parameter, which the view asks for and on_main_thread shows
    struct HostMenuRequest
    {
        clap_id param;
        int32_t x, y;
    };

    std::optional<HostMenuRequest> pendingHostMenu;

    // how many popup() calls haven't returned: hosts show the menu modally, so it is open
    // while this is above 0 (and may stay open after, if a host doesn't)
    int hostMenusRunning = 0;

    bool canShowHostMenu() const;
    void handleHostRequest (std::string_view);
    void sendHostInfoToView();
    void showPendingHostMenu();
`,
);

//==============================================================================
replace(
  `inline bool Plugin::Impl::clapGui_create (const char*, bool)
{
    editor = ViewHolder (patch, cachedViewScaleFactor);
    return true;
}

inline void Plugin::Impl::clapGui_destroy()
{
    editor = {};
}`,
  `inline bool Plugin::Impl::clapGui_create (const char*, bool)
{
    editor = ViewHolder (patch, cachedViewScaleFactor,
                         editorZoom.value_or (porridge::zoomSetting (porridge::loadSettings())));

    requestBridge = std::make_unique<porridge::RequestBridge> (patch, [this] (std::string_view key)
    {
        handleViewRequest (key);
    });

    return true;
}

inline void Plugin::Impl::clapGui_destroy()
{
    requestBridge.reset();
    pendingHostMenu = {};

    if (editor)
        editorZoom = editor->zoom();

    editor = {};
}`,
);

replace(
  `inline bool Plugin::Impl::clapGui_getResizeHints (clap_gui_resize_hints_t*)
{
    return {};
}

inline bool Plugin::Impl::clapGui_adjustSize (uint32_t*, uint32_t*)
{
    return {};
}`,
  `inline bool Plugin::Impl::clapGui_getResizeHints (clap_gui_resize_hints_t* hints)
{
    if (! (editor && editor->resizable()))
        return false;

    const auto design = editor->designSize();
    hints->can_resize_horizontally = true;
    hints->can_resize_vertically = true;
    hints->preserve_aspect_ratio = true;
    hints->aspect_ratio_width = design.width;
    hints->aspect_ratio_height = design.height;
    return true;
}

inline bool Plugin::Impl::clapGui_adjustSize (uint32_t* width, uint32_t* height)
{
    if (! (editor && editor->resizable()))
        return false;

    const auto size = editor->adjust ({ *width, *height });
    *width = size.width;
    *height = size.height;
    return true;
}`,
);

insertBefore(
  `inline void Plugin::Impl::resetIfRequestIsPending()
{`,
  `${marker} a stored-state request from the view (the whole key)
inline void Plugin::Impl::handleViewRequest (std::string_view key)
{
    if (choc::text::startsWith (key, porridge::requestPrefix))
        handleSettingsRequest (key.substr (porridge::requestPrefix.size()));
    else if (choc::text::startsWith (key, porridge::hostRequestPrefix))
        handleHostRequest (key.substr (porridge::hostRequestPrefix.size()));
    else if (choc::text::startsWith (key, porridge::library::requestPrefix))
        handleLibraryRequest (key.substr (porridge::library::requestPrefix.size()));
}

${marker} the bank library's requests (tools/clap/PorridgeLibrary.h); some parts aren't answered
inline void Plugin::Impl::handleLibraryRequest (std::string_view request)
{
    if (! editor)
        return;

    auto reply = porridge::bankLibrary().handle (request);

    if (! reply.isVoid())
        editor->getPatchWebView().sendMessage (
            choc::json::create ("type", "state_key_value",
                                "message", choc::json::create ("key", porridge::library::replyKey, "value", reply)));
}

${marker} ?get answers with the settings; ?zoom=<factor> asks the host to resize the window;
// ?save=<json> replaces the settings file. Every request is answered.
inline void Plugin::Impl::handleSettingsRequest (std::string_view request)
{
    if (! editor)
        return;

    if (choc::text::startsWith (request, "zoom="))
    {
        const auto zoom = porridge::clampZoom (std::strtod (std::string (request.substr (5)).c_str(), nullptr));
        const auto size = editor->hostSizeForZoom (zoom);
        const auto hostGui = getExtension<clap_host_gui_t> (host, CLAP_EXT_GUI);

        if (hostGui != nullptr && hostGui->request_resize != nullptr
             && hostGui->request_resize (std::addressof (host), size.width, size.height))
        {
            // some hosts resize the window without calling set_size
            editor->setSize (size);
            editorZoom = zoom;
        }
    }
    else if (choc::text::startsWith (request, "save="))
    {
        try
        {
            auto settings = choc::json::parse (request.substr (5));

            if (settings.isObject())
                porridge::saveSettings (settings);
        }
        catch (...) {}
    }

    sendSettingsToView();
}

inline void Plugin::Impl::sendSettingsToView()
{
    if (! editor)
        return;

    editor->getPatchWebView().sendMessage (
        choc::json::create ("type", "state_key_value",
                            "message", choc::json::create ("key", porridge::replyKey,
                                                           "value", choc::json::create ("settings", porridge::loadSettings(),
                                                                                        "zoom", editor->zoom()))));
}

${marker} whether the host can show its menu for the plugin, which can change once the view
// is in its window
inline bool Plugin::Impl::canShowHostMenu() const
{
    auto menu = porridge::hostContextMenu (host);
    return editor && menu != nullptr && menu->can_popup (std::addressof (host));
}

${marker} ?get answers with what the host offers; ?menu=<json> { id, x, y, scale } shows the
// host's menu for the parameter with that endpoint ID, at a point in the view in CSS pixels,
// scale being the view's device pixel ratio; ?dismiss closes it. The menu is left to
// on_main_thread rather than shown here, inside the web view's message handler. A dismiss
// usually comes while popup() is still running (the host's menu loop dispatches the web view's
// messages), which tells dismissHostMenu the menu is open.
inline void Plugin::Impl::handleHostRequest (std::string_view request)
{
    if (! editor)
        return;

    if (choc::text::startsWith (request, "menu="))
    {
        try
        {
            auto args = choc::json::parse (request.substr (5));
            const auto id = porridge::params::clapIdFor (args["id"].toString());

            if (id == CLAP_INVALID_ID || automatableParametersByHandle.count (id) == 0)
                return;

           #if CHOC_OSX
            const double scale = 1.0; // CLAP's coordinates are points on macOS, as are CSS pixels
           #else
            const double scale = args["scale"].getWithDefault<double> (1.0);
           #endif

            const auto toPixel = [scale] (const choc::value::ValueView& v)
            {
                const auto x = v.getWithDefault<double> (0.0) * scale;
                return static_cast<int32_t> (std::isfinite (x) ? std::round (x) : 0.0);
            };

            pendingHostMenu = HostMenuRequest { id, toPixel (args["x"]), toPixel (args["y"]) };
            host.request_callback (std::addressof (host));
        }
        catch (...) {}

        return;
    }

    if (request == "dismiss")
    {
        pendingHostMenu = {};
        porridge::dismissHostMenu (hostMenusRunning > 0);
        return;
    }

    sendHostInfoToView();
}

inline void Plugin::Impl::sendHostInfoToView()
{
    if (! editor)
        return;

    editor->getPatchWebView().sendMessage (
        choc::json::create ("type", "state_key_value",
                            "message", choc::json::create ("key", porridge::hostReplyKey,
                                                           "value", choc::json::create ("menu", canShowHostMenu()))));
}

inline void Plugin::Impl::showPendingHostMenu()
{
    auto request = std::exchange (pendingHostMenu, std::nullopt);

    if (! (request && canShowHostMenu()))
        return;

    const clap_context_menu_target_t target { CLAP_CONTEXT_MENU_TARGET_KIND_PARAM, request->param };
    ++hostMenusRunning;
    porridge::hostContextMenu (host)->popup (std::addressof (host), std::addressof (target), 0, request->x, request->y);
    --hostMenusRunning;
}

`,
);

insertAfter(
  `inline void Plugin::Impl::clapPlugin_onMainThread()
{
`,
  `    ${marker} the host's menu that the view asked for
    showPendingHostMenu();
`,
);

//==============================================================================
// A state that names parameters the patch no longer has keeps their values in the stored state
replace(
  `        const auto state = choc::json::parse ({ reinterpret_cast<const char*> (serialised.data()), serialised.size() });
`,
  `        auto state = choc::json::parse ({ reinterpret_cast<const char*> (serialised.data()), serialised.size() });

        ${marker} parameters that are stored state now (ui/StoredParams.res) keep their values
        if (porridge::params::keepRemovedParameters (state))
        {
            const auto text = choc::json::toString (state, false);
            serialised = Bytes (text.begin(), text.end());
        }
`,
);

//==============================================================================
// The slots' knobs: named and worded after what their slots hold, and rescanned when that changes
insertAfter(
  `    std::optional<double> editorZoom;
`,
  `
    ${marker} a slot's kind changed: the host rescans the knobs' names and texts (on the main thread)
    std::atomic<bool> slotKindsChanged { false };

    float slotKindValue (std::string_view endpoint) const
    {
        if (auto p = patch.findParameter (cmaj::EndpointID::create (endpoint)))
            return p->currentValue;

        return 0.0f;
    }
`,
);

replace(
  `    *out = automatableParameterInfo[index];
    return true;
}`,
  `    *out = automatableParameterInfo[index];

    ${marker} a slot's knob is named after what the slot holds (PorridgeSlots.h)
    porridge::slots::describe (*out, [this] (std::string_view e) { return slotKindValue (e); });
    return true;
}`,
);

replace(
  `inline bool Plugin::Impl::clapParameters_valueToText (clap_id id, double value, char* out, uint32_t capacity)
{
`,
  `inline bool Plugin::Impl::clapParameters_valueToText (clap_id id, double value, char* out, uint32_t capacity)
{
    ${marker} a slot's knob's text is its kind's (PorridgeSlots.h)
    if (porridge::slots::text (id, value, out, capacity, [this] (std::string_view e) { return slotKindValue (e); }))
        return true;

`,
);

insertBefore(
  `    // it isn't possible to distinguish an update from the audio thread vs the editor
`,
  `    ${marker} a slot that holds another kind: its knobs' names and texts change
    for (auto endpoint : porridge::slots::kindEndpoints)
    {
        if (auto p = patch.findParameter (cmaj::EndpointID::create (endpoint)))
        {
            p->valueChanged = [this] (auto)
            {
                if (! slotKindsChanged.exchange (true))
                    host.request_callback (std::addressof (host));
            };
        }
    }

`,
);

insertAfter(
  `    showPendingHostMenu();
`,
  `
    ${marker} the slots' knobs' names and texts, when a slot's kind changed
    if (slotKindsChanged.exchange (false))
        if (const auto* hostParameters = getExtension<clap_host_params_t> (host, CLAP_EXT_PARAMS))
            hostParameters->rescan (std::addressof (host), CLAP_PARAM_RESCAN_INFO | CLAP_PARAM_RESCAN_TEXT);
`,
);

//==============================================================================
replace(
  `    return static_cast<uint32_t> (patch.getFramesLatency());`,
  `    ${marker} the synth's MIDI latency, one ${blockSize}-sample block (see dsp/Synth.cmajor)
    return static_cast<uint32_t> (std::max (patch.getFramesLatency(), ${blockSize}.0));`,
);

//==============================================================================
insertAfter(
  `    bool loadPatch (const std::filesystem::path& pathToManifest, FrequencyAndBlockSize frequencyAndBlockSize)
    {
`,
  `        ${marker} a generated plugin's patch never changes, so once it's loaded, activating
        // only needs to rebuild it if the sample rate or block size changed, which
        // setPlaybackParams does (keeping the parameter values). Loading it again from scratch
        // built it three times: preload, setPlaybackParams' rebuild, then loadPatch.
        if (environment.engineType == Environment::EngineType::AOT && patch.isPlayable())
        {
            const auto channels = [] (const cmaj::EndpointDetailsList& endpoints)
            {
                uint32_t count = 0;

                for (const auto& endpoint : endpoints)
                    count += endpoint.getNumAudioChannels();

                return count;
            };

            patch.setPlaybackParams ({
                frequencyAndBlockSize.frequency,
                frequencyAndBlockSize.maxBlockSize,
                channels (patch.getInputEndpoints()),
                channels (patch.getOutputEndpoints()),
            });

            return patch.isPlayable();
        }

`,
);

// Porridge reads only the transport's tempo, so that is all it is sent, and only when it
// changes (a host sends the transport with every call, and with small buffers that is a thousand
// times a second; each event cost more than the synth's own work for a block). It is sent again
// when processing starts, in case the patch was built again.
insertAfter(`    double frequency = 0;
`, `    float lastSentTempo = -1.0f;   // Porridge: see clapPlugin_process's transport case
`);
replace(
  `            patch.sendTransportState (isRecording, isPlaying, isLooping, 0);

            if (event.flags & CLAP_TRANSPORT_HAS_TEMPO)
                patch.sendBPM (static_cast<float> (event.tempo), 0);

            if (event.flags & CLAP_TRANSPORT_HAS_TIME_SIGNATURE)
                patch.sendTimeSig (static_cast<int> (event.tsig_num), static_cast<int> (event.tsig_denom), 0);
`,
  `            (void) isRecording; (void) isPlaying; (void) isLooping;

            if ((event.flags & CLAP_TRANSPORT_HAS_TEMPO) && static_cast<float> (event.tempo) != lastSentTempo)
            {
                lastSentTempo = static_cast<float> (event.tempo);
                patch.sendBPM (lastSentTempo, 0);
            }

            return;   // the patch has no use for the time signature, the position or the transport state
`,
);
replace(
  `    blockRestartRequests = false;
    return patch.isPlayable();`,
  `    blockRestartRequests = false;
    lastSentTempo = -1.0f;
    return patch.isPlayable();`,
);

// With PORRIDGE_PERF set, the process calls are timed and logged (tools/clap/PorridgePerf.h)
replace(
  `        return unsafeCastToRef<Plugin> (plugin).impl->clapPlugin_process (process);
`,
  `        auto& impl = *unsafeCastToRef<Plugin> (plugin).impl;

        if (! ::porridge::perf::enabled())
            return impl.clapPlugin_process (process);

        return ::porridge::perf::timerFor (std::addressof (impl)).run (process, [&] { return impl.clapPlugin_process (process); });
`,
);

save();
