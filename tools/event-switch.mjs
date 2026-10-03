// Cmajor's C++ generator dispatches addEvent (every parameter change and MIDI message that
// reaches the patch) through one `if (endpointHandle == n)` per input endpoint, in endpoint
// order. midiIn is declared after the ~1,600 parameters, so each MIDI message ran ~1,600
// compares first: ~1.7 µs a message, +1.85 % of a core in a dense MPE stream. Declaring midiIn
// first would shift every parameter's handle, and the handles are the plugin's CLAP parameter
// IDs, which hosts store in projects. So this turns the chain into a switch, which compilers
// make a jump table: every event finds its handler in a few instructions, and no handle changes.
//
// The test host (tools/test/build.sh) and the CLAP wrapper (tools/clap-patch.mjs, entry.cpp)
// both run it on the generated class:
//
//   node tools/event-switch.mjs <generated header>

import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const signature = "void addEvent (EndpointHandle endpointHandle, uint32_t typeIndex, const unsigned char* eventData)";

// The generated source (with "\n" line ends) with addEvent's chain as a switch, its comment
// starting with `marker`. Throws if addEvent isn't laid out as the generator writes it.
export const switchAddEvent = (source, marker = "// Porridge:") => {
  const fail = (what) => {
    throw new Error(`event-switch: ${what}; Cmajor's generated addEvent has changed, so update tools/event-switch.mjs`);
  };
  const at = source.indexOf(signature);
  if (at < 0 || source.indexOf(signature, at + 1) >= 0) fail("no single addEvent");

  const lineStart = source.lastIndexOf("\n", at) + 1;
  const indent = source.slice(lineStart, at);
  const open = `\n${indent}{\n`;
  const close = `\n${indent}}\n`;
  if (!source.startsWith(open, at + signature.length)) fail("no body");
  const bodyStart = at + signature.length + open.length;
  const bodyEnd = source.indexOf(close, bodyStart);
  if (bodyEnd < 0) fail("no end");

  const inner = indent + "    ";
  const lines = source.slice(bodyStart, bodyEnd).split("\n");
  if (!/^\s*\(void\) endpointHandle; \(void\) typeIndex; \(void\) eventData;$/.test(lines[0])) fail("no (void) line");

  let cases = 0;
  const body = lines.slice(lines[1] === "" ? 2 : 1).map((line) => {
    const m = /^(\s*)if \(endpointHandle == (\d+)\)$/.exec(line);
    if (m) {
      if (m[1] !== inner) fail(`a case at another depth: ${line.trim()}`);
      ++cases;
      return `${inner}    case ${m[2]}:`;
    }
    return line.length > 0 ? "    " + line : line;
  });
  if (cases === 0) fail("no cases");

  const patched = [
    lines[0],
    "",
    `${inner}${marker} a switch instead of the generator's if chain, which compilers make a jump`,
    `${inner}// table, so a MIDI message no longer tries every parameter's handle first (added by`,
    `${inner}// tools/event-switch.mjs)`,
    `${inner}switch (endpointHandle)`,
    `${inner}{`,
    ...body,
    `${inner}    default:`,
    `${inner}        break;`,
    `${inner}}`,
  ].join("\n");

  return source.slice(0, bodyStart) + patched + source.slice(bodyEnd);
};

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const file = process.argv[2];
  if (!file) throw new Error("usage: node tools/event-switch.mjs <generated header>");
  const source = readFileSync(file, "utf8").replace(/\r\n/g, "\n");
  writeFileSync(file, switchAddEvent(source));
}
