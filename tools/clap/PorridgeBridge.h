// Porridge's additions to Cmajor's CLAP wrapper: user settings shared by every instance, the
// host's parameter menu, the bank library (PorridgeLibrary.h), and the bridge the view reaches
// them through. tools/clap-patch.mjs copies this and PorridgeLibrary.h next to
// helpers/clap/cmaj_CLAPPlugin.h and includes it inside that file's cmaj::plugin::clap::detail
// namespace, after the headers it needs (choc's files, JSON and base64, <cmath>, <cstdlib>,
// <fstream>), so it has no includes of its own but that one.

#pragma once

#include "PorridgeLibrary.h"

namespace porridge
{
    inline const std::string requestPrefix = "porridge:settings?";
    inline const std::string replyKey = "porridge:settings";
    inline const std::string hostRequestPrefix = "porridge:host?";
    inline const std::string hostReplyKey = "porridge:host";

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

    /// The bank library, beside the settings file.
    inline library::Library bankLibrary()
    {
        auto file = settingsFile();
        return { file.empty() ? std::filesystem::path() : file.parent_path() / "banks" };
    }

    inline double zoomSetting (const choc::value::ValueView& settings)
    {
        return clampZoom (settings.isObject() ? settings["zoom"].getWithDefault<double> (1.0) : 1.0);
    }

    /// The host's context menu extension, if it can show its menu for the plugin.
    inline const clap_host_context_menu_t* hostContextMenu (const clap_host_t& host)
    {
        for (auto id : { CLAP_EXT_CONTEXT_MENU, CLAP_EXT_CONTEXT_MENU_COMPAT })
        {
            auto menu = static_cast<const clap_host_context_menu_t*> (host.get_extension (std::addressof (host), id));

            if (menu != nullptr && menu->can_popup != nullptr && menu->popup != nullptr)
                return menu;
        }

        return nullptr;
    }

    /// Closes the menu the host is showing for the plugin, after a press or Escape in the view.
    /// On Windows the menu never hears those: the web view's window belongs to its browser
    /// process, whose thread gets the view's input, while a host's menu watches the input of
    /// the host's thread. This runs on that thread (the web view calls back on the thread that
    /// made it, the host's main thread, the one that calls on_main_thread and so popup()), and
    /// often while popup() is still running: hosts show the menu modally, and their menu loop
    /// dispatches the web view's messages to us.
    ///
    ///  - A Win32 menu (TrackPopupMenu) ends with EndMenu.
    ///  - A menu that holds the mouse capture closes when it loses it (WM_CANCELMODE).
    ///  - FL Studio's menus (TQuickPopupMenu in FLEngine_x64.dll) are windows of its own with a
    ///    PeekMessage loop inside popup() that takes the mouse and key messages of FL's thread
    ///    (Escape closes a level), closes when FL is deactivated (a WM_ACTIVATEAPP hook), and
    ///    closes entirely on a WM_CLOSE, WM_QUIT or non-client press message for any window,
    ///    or for none. They hold no capture (unless something had it when they opened), so
    ///    while popup() is running and no Win32 menu is, a WM_CLOSE is posted to the thread.
    ///    With no window it closes nothing else: a loop that doesn't look for it dispatches it
    ///    to nowhere.
    inline void dismissHostMenu (bool popupRunning)
    {
       #if CHOC_WINDOWS
        GUITHREADINFO info {};
        info.cbSize = sizeof (info);

        if (! GetGUIThreadInfo (GetCurrentThreadId(), &info))
            info = {};

        if ((info.flags & (GUI_INMENUMODE | GUI_POPUPMENUMODE | GUI_SYSTEMMENUMODE)) != 0)
        {
            EndMenu();
            return;
        }

        if (auto capture = info.hwndCapture)
        {
            DWORD process = 0;
            GetWindowThreadProcessId (capture, &process);

            // losing the capture closes it (DefWindowProc releases it)
            if (process == GetCurrentProcessId())
                SendMessageW (capture, WM_CANCELMODE, 0, 0);
        }

        if (popupRunning)
            PostThreadMessageW (GetCurrentThreadId(), WM_CLOSE, 0, 0);
       #else
        (void) popupRunning;
       #endif
    }

    /// Listens to what the patch sends its views, and passes on the settings, host and library
    /// requests (the whole key).
    struct RequestBridge  : public cmaj::PatchView
    {
        RequestBridge (cmaj::Patch& p, std::function<void(std::string_view)> handleToUse)
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

            if (choc::text::startsWith (key, requestPrefix) || choc::text::startsWith (key, hostRequestPrefix)
                 || choc::text::startsWith (key, library::requestPrefix))
                handle (key);
        }

        std::function<void(std::string_view)> handle;
    };
}
