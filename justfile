# Builds the Porridge CLAP plugin on macOS, Linux and Windows.
#
#   just            build dist/Porridge.clap for this machine
#   just install    build, then copy it into the user's CLAP folder
#
# Build on each OS natively; there is no cross-compiling. Requirements:
#   all:      cmaj (Cmajor CLI), node and npm, git, cmake >= 3.16 and a C++17 compiler
#   Windows:  Visual Studio 2022 with the C++ workload (CMake's default generator)
#   macOS:    Xcode command line tools; the result is a universal arm64/x86_64 bundle
#   Linux:    pkg-config, gtk3 and webkit2gtk dev packages (see `just linux-deps`)
#
# Every recipe line is a plain command (file operations go through `cmake -E`),
# so the same recipes run under sh and PowerShell.

set windows-shell := ["powershell.exe", "-NoLogo", "-NoProfile", "-Command"]

cmaj         := env("CMAJ", "cmaj")
config       := env("CONFIG", "Release")
clap_version := env("CLAP_VERSION", "1.2.10")

root     := justfile_directory()
patch    := root / "Porridge.cmajorpatch"
build    := root / "build"
clap_dir := build / "deps" / ("clap-" + clap_version)
project  := build / "clap-project"
staging  := build / "clap-project-new"
cmake_dir := build / "cmake"
out_dir  := build / "out"
dist     := root / "dist"

plugin := "Porridge.clap"

# CLAP's per-user search path for each OS.
install_dir := if os() == "windows" {
    env("LOCALAPPDATA", "") / "Programs" / "Common" / "CLAP"
} else if os() == "macos" {
    home_directory() / "Library" / "Audio" / "Plug-Ins" / "CLAP"
} else {
    home_directory() / ".clap"
}

# macOS builds a .clap bundle (a folder); elsewhere it is a single shared library.
copy := if os() == "macos" { "copy_directory" } else { "copy" }

# Build the plugin into dist/
default: package

# Compile the ReScript interface and bundle it into bundle/
ui:
    npm install
    npm run build

# Regenerate dsp/ParamStore.cmajor and dsp/Slots.cmajor from the parameter table
gen: ui
    node "{{ root / "tools" / "gen.mjs" }}"

# Fetch the CLAP headers (once per CLAP_VERSION)
clap:
    {{ if path_exists(clap_dir / "include" / "clap" / "clap.h") == "true" { "cmake -E echo \"CLAP " + clap_version + " headers present\"" } else { "git clone --depth 1 --branch " + clap_version + " https://github.com/free-audio/clap \"" + clap_dir + "\"" } }}

# Generate the CLAP C++/CMake project from the patch and patch its wrapper (see tools/clap-patch.mjs),
# in a staging folder; only files that changed are copied into the project, so an unchanged
# entry.cpp keeps its timestamp and isn't recompiled
generate: gen clap
    cmake -E rm -rf "{{ staging }}"
    {{ cmaj }} generate --target=clap "--clapIncludePath={{ clap_dir / "include" }}" "--output={{ staging }}" "{{ patch }}"
    node "{{ root / "tools" / "clap-patch.mjs" }}" "{{ staging }}"
    node "{{ root / "tools" / "sync-dir.mjs" }}" "{{ staging }}" "{{ project }}"
    cmake -E rm -rf "{{ staging }}"

# Configure and compile the generated project
compile: generate
    cmake -S "{{ project }}" -B "{{ cmake_dir }}" --no-warn-unused-cli "-DCMAKE_BUILD_TYPE={{ config }}" "-DCLAP_INCLUDE_PATH={{ clap_dir / "include" }}" "-DCMAKE_LIBRARY_OUTPUT_DIRECTORY_{{ uppercase(config) }}={{ out_dir }}"
    cmake --build "{{ cmake_dir }}" --config {{ config }} --parallel

# Copy the built plugin to dist/
package: compile
    cmake -E rm -rf "{{ dist / plugin }}"
    cmake -E make_directory "{{ dist }}"
    cmake -E {{ copy }} "{{ out_dir / plugin }}" "{{ dist / plugin }}"
    cmake -E echo "built {{ dist / plugin }}"

# Build, then install into the user's CLAP folder
install: package
    cmake -E make_directory "{{ install_dir }}"
    cmake -E rm -rf "{{ install_dir / plugin }}"
    cmake -E {{ copy }} "{{ dist / plugin }}" "{{ install_dir / plugin }}"
    cmake -E echo "installed {{ install_dir / plugin }}"

# Remove the plugin from the user's CLAP folder
uninstall:
    cmake -E rm -rf "{{ install_dir / plugin }}"

# Install the Linux build dependencies (Debian/Ubuntu)
[linux]
linux-deps:
    sudo apt-get install -y build-essential cmake git pkg-config libgtk-3-dev libwebkit2gtk-4.1-dev

# Delete build/, dist/ and the compiled interface
clean:
    cmake -E rm -rf "{{ build }}" "{{ dist }}" "{{ root / "bundle" }}"
    npx rescript clean
