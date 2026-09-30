#!/bin/sh
# Builds the offline test host from the test graph.
set -e
cd "$(dirname "$0")"
node ../gen.mjs
cmaj generate --target=cpp --output=build/porridge_gen.h PorridgeTest.cmajorpatch
clang++ -std=c++17 -O2 host.cpp -o build/host.exe
echo "built tools/test/build/host.exe"
