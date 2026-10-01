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
//    the plugin's state. See ui/Settings.res.
//  - The latency is the synth's 64 samples (dsp/Synth.cmajor applies MIDI a block late, on
//    its own sample). Cmajor's C++ generator reports 0 whatever the patch declares.
//
//   node tools/clap-patch.mjs [path to the generated project]

import { readFileSync, writeFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const project = process.argv[2] ?? join(root, "build", "clap-project");
const file = join(project, "helpers", "clap", "cmaj_CLAPPlugin.h");
const marker = "// Porridge:";

let source = readFileSync(file, "utf8").replace(/\r\n/g, "\n");

if (source.includes(marker)) {
  console.log(`${file} is already patched`);
  process.exit(0);
}

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

// Replaces everything from `start` up to and including `end`.
const replaceRange = (start, end, replacement) => {
  const a = source.indexOf(start);
  if (a < 0 || source.indexOf(start, a + 1) >= 0) fail(JSON.stringify(start.slice(0, 80)));
  const b = source.indexOf(end, a);
  if (b < 0) fail(JSON.stringify(end.slice(0, 80)));
  source = source.slice(0, a) + replacement + source.slice(b + end.length);
};

//==============================================================================
replace(
  `#include "choc/gui/choc_DesktopWindow.h"\n`,
  `#include "choc/gui/choc_DesktopWindow.h"
#include "choc/text/choc_Files.h"
#include "choc/text/choc_JSON.h"
`,
);

replace(
  `#include <algorithm>\n`,
  `#include <algorithm>
#include <cmath>
#include <cstdlib>
`,
);

//==============================================================================
replace(
  `namespace detail
{
`,
  `namespace detail
{

${marker} user settings shared by every instance, and the bridge the view reaches them
// through (added by tools/clap-patch.mjs).
namespace porridge
{
    inline const std::string requestPrefix = "porridge:settings?";
    inline const std::string replyKey = "porridge:settings";

    constexpr double minZoom = 0.5, maxZoom = 3.0;

    inline double clampZoom (double z)
    {
        return std::isfinite (z) ? std::clamp (z, minZoom, maxZoom) : 1.0;
    }

    inline std::filesystem::path settingsFile()
    {
       #if CHOC_WINDOWS
        wchar_t* appData = nullptr;
        size_t length = 0;

        if (_wdupenv_s (&appData, &length, L"APPDATA") == 0 && appData != nullptr)
        {
            std::filesystem::path folder (appData);
            free (appData);
            return folder / "Porridge" / "settings.json";
        }
       #elif CHOC_OSX
        if (auto home = std::getenv ("HOME"))
            return std::filesystem::path (home) / "Library" / "Application Support" / "Porridge" / "settings.json";
       #else
        if (auto config = std::getenv ("XDG_CONFIG_HOME"); config != nullptr && *config != 0)
            return std::filesystem::path (config) / "porridge" / "settings.json";

        if (auto home = std::getenv ("HOME"))
            return std::filesystem::path (home) / ".config" / "porridge" / "settings.json";
       #endif

        return {};
    }

    inline choc::value::Value loadSettings()
    {
        try
        {
            auto file = settingsFile();

            if (! file.empty() && std::filesystem::exists (file))
            {
                auto settings = choc::json::parse (choc::file::loadFileAsString (file));

                if (settings.isObject())
                    return settings;
            }
        }
        catch (...) {}

        return choc::value::createObject ({});
    }

    inline void saveSettings (const choc::value::ValueView& settings)
    {
        try
        {
            auto file = settingsFile();

            if (! file.empty())
            {
                std::filesystem::create_directories (file.parent_path());
                choc::file::replaceFileWithContent (file, choc::json::toString (settings, true));
            }
        }
        catch (...) {}
    }

    inline double zoomSetting (const choc::value::ValueView& settings)
    {
        return clampZoom (settings.isObject() ? settings["zoom"].getWithDefault<double> (1.0) : 1.0);
    }

    /// Listens to what the patch sends its views, and passes on the settings requests.
    struct SettingsBridge  : public cmaj::PatchView
    {
        SettingsBridge (cmaj::Patch& p, std::function<void(std::string_view)> handleToUse)
            : cmaj::PatchView (p), handle (std::move (handleToUse))
        {}

        void sendMessage (const choc::value::ValueView& msg) override
        {
            if (! msg.isObject() || msg["type"].toString() != "state_key_value")
                return;

            auto message = msg["message"];

            if (! message.isObject())
                return;

            auto key = message["key"].toString();

            if (choc::text::startsWith (key, requestPrefix))
                handle (std::string_view (key).substr (requestPrefix.size()));
        }

        std::function<void(std::string_view)> handle;
    };
}
`,
);

//==============================================================================
replaceRange(
  `    struct ViewHolder
    {`,
  `    std::optional<ViewHolder> editor;
`,
  `    struct ViewHolder
    {
        ViewHolder (cmaj::Patch& patchToUse, std::optional<double> initialScaleFactorToUse, double zoomToUse)
            : webview (std::make_unique<cmaj::PatchWebView> (patchToUse, findDefaultViewForPatch (patchToUse))),
              designWidth (webview->width),
              designHeight (webview->height)
        {
            if (initialScaleFactorToUse)
                setScaleFactor (*initialScaleFactorToUse);

            webview->width  = sizeForZoom (zoomToUse).width;
            webview->height = sizeForZoom (zoomToUse).height;
        }

        struct Size
        {
            uint32_t width;
            uint32_t height;
        };

        bool setScaleFactor (double factor)
        {
            scaleFactor = factor;
            inverseScaleFactor = 1.0 / factor;

            return true;
        }

        Size size() const
        {
            return { scaled (webview->width),
                     scaled (webview->height) };
        }

        bool setSize (const Size& sizeToUse)
        {
            webview->width  = unscaled (sizeToUse.width);
            webview->height = unscaled (sizeToUse.height);

            return updateNativeViewSize();
        }

        bool resizable() const
        {
            return webview->resizable;
        }

        bool setParent (void* parent)
        {
            if (! cmaj::plugin::addChildView (parent, nativeViewHandle()))
                return false;

            return updateNativeViewSize();
        }

        ${marker} the view's size relative to the manifest's, which the panel keeps the aspect
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

    private:
        void* nativeViewHandle() const                  { return webview->getWebView().getViewHandle(); }
        uint32_t scaled (uint32_t x) const              { return scaleFactor ? toIntegerPixel (*scaleFactor * x) : x; }
        uint32_t unscaled (uint32_t x) const            { return scaleFactor ? toIntegerPixel (*inverseScaleFactor * x) : x; }
        static uint32_t toIntegerPixel (double x)       { return static_cast<uint32_t> (0.5 + x); }

        Size sizeForZoom (double z) const
        {
            z = porridge::clampZoom (z);
            return { toIntegerPixel (designWidth * z), toIntegerPixel (designHeight * z) };
        }

        bool updateNativeViewSize()
        {
            const auto [width, height] = size();

            return cmaj::plugin::setViewSize (nativeViewHandle(), width, height);
        }

        std::unique_ptr<cmaj::PatchWebView> webview;
        uint32_t designWidth, designHeight;
        std::optional<double> scaleFactor;
        std::optional<double> inverseScaleFactor;
    };

    std::optional<double> cachedViewScaleFactor; // workaround Bitwig only passing the scale factor the first time the view is shown
    std::optional<ViewHolder> editor;

    ${marker} the size of this instance's editor, kept while it is closed, and the bridge that
    // answers the view's settings requests
    std::optional<double> editorZoom;
    std::unique_ptr<porridge::SettingsBridge> settingsBridge;

    void handleSettingsRequest (std::string_view);
    void sendSettingsToView();
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

    settingsBridge = std::make_unique<porridge::SettingsBridge> (patch, [this] (std::string_view request)
    {
        handleSettingsRequest (request);
    });

    return true;
}

inline void Plugin::Impl::clapGui_destroy()
{
    settingsBridge.reset();

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

replace(
  `inline void Plugin::Impl::resetIfRequestIsPending()
{`,
  `${marker} ?get answers with the settings; ?zoom=<factor> asks the host to resize the window;
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

inline void Plugin::Impl::resetIfRequestIsPending()
{`,
);

//==============================================================================
replace(
  `    return static_cast<uint32_t> (patch.getFramesLatency());`,
  `    ${marker} the synth's MIDI latency, one 64-sample block (see dsp/Synth.cmajor)
    return static_cast<uint32_t> (std::max (patch.getFramesLatency(), 64.0));`,
);

writeFileSync(file, source);
console.log(`patched ${file}`);
