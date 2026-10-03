#!/bin/sh
# Builds the offline test host from the test graph.
set -e
cd "$(dirname "$0")"
node ../gen.mjs
cmaj generate --target=cpp --output=build/porridge_gen.h PorridgeTest.cmajorpatch
# addEvent as a switch, as in the plugin (tools/event-switch.mjs)
node ../event-switch.mjs build/porridge_gen.h
clang++ -std=c++17 -O2 -ftemplate-depth=4096 host.cpp -o build/host.exe
echo "built tools/test/build/host.exe"
# the plugin's bank library, with the choc headers `just generate` fetches
if [ -d ../../build/clap-project/include/choc ]; then
    clang++ -std=c++17 -I../../build/clap-project/include/choc banklibrary.cpp -o build/banklibrary.exe
    ./build/banklibrary.exe
fi
