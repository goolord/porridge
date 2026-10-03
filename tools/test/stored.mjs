// The stored parameters (ui/StoredParams.res: the custom shapes' points) in the view's model,
// against a stand-in for the patch that keeps stored state as Cmajor's does (a value is echoed
// to the views when it changes):
//   - an edit sends its distortion's points in one shaperIn event and stores them under
//     "params", never as an endpoint; undo and redo too;
//   - the patch's echo of that changes nothing; a stored value from elsewhere (a host's state)
//     sets the model without sending anything back; none (a state without them) resets them;
//   - a program pushed whole sends every distortion's points at once;
//   - the stored value keeps only what differs from the defaults, and decodes back;
//   - a preset keeps them, and no stored parameter is an endpoint or a host parameter;
//   - and the wheels, the other way about: host parameters whose drags are gestures but no undo
//     steps, which a program pushed whole leaves where they are and the host's values move.
//
// run: node tools/test/stored.mjs (after npm run res and tools/gen.mjs)

import { readFileSync } from "node:fs";
import { join } from "node:path";
import * as ParamModel from "../../ui/ParamModel.res.mjs";
import * as ParamDefs from "../../ui/ParamDefs.res.mjs";
import * as StoredParams from "../../ui/StoredParams.res.mjs";
import * as Preset from "../../ui/Preset.res.mjs";
import * as PorridgeParams from "../../ui/PorridgeParams.res.mjs";
import { root, checker } from "./lib.mjs";

const { check, done } = checker ({ verbose: true });
const tick = () => new Promise (resolve => setTimeout (resolve, 0));

// the patch, as far as the view sees it
const patch =
{
    sent: [], state: new Map(), stateListeners: [],
    addAllParameterListener() {}, removeAllParameterListener() {},
    sendEventOrValue (id, value) { this.sent.push ([id, value]); },
    sendParameterGestureStart (id) { this.sent.push (["gesture", id]); },
    sendParameterGestureEnd (id) { this.sent.push (["gestureEnd", id]); },
    sendStoredStateValue (key, value)
    {
        this.sent.push (["state:" + key, value]);
        if (this.state.get (key) === value) return;
        this.state.set (key, value);
        this.stateListeners.forEach (f => f ({ key, value }));
    },
};

const model = ParamModel.make (patch, ParamDefs.makeDefs());
// (as ProgramStore passes them on)
patch.stateListeners.push (({ key, value }) => { if (key === "params") ParamModel.loadStored (model, value); });

const shaper = which => patch.sent.filter (([id]) => id === "shaperIn").map (([, v]) => v).filter (v => which === undefined || v.which === which);
const stored = () => JSON.parse (patch.state.get ("params") ?? "{}");
const indexOf = id => StoredParams.groups[StoredParams.groupOf (id)].indexOf (id);

// an edit
ParamModel.gestureSet (model, "Sat_Y2@1", 0.5);
await tick();
let events = shaper();
check (events.length === 1 && events[0].which === 1 && events[0].values[indexOf ("Sat_Y2@1")] === 0.5 && events[0].values.length === 49,
       `an edit sends its distortion's 49 points in one shaperIn event (${JSON.stringify (events.map (e => e.which))})`);
check (! patch.sent.some (([id]) => id === "Sat_Y2@1" || id === "gesture" || id === "gestureEnd"), "and nothing as an endpoint or a gesture");
check (JSON.stringify (stored()) === `{"Sat_Y2@1":0.5}`, `and stores only what differs from the defaults (${patch.state.get ("params")})`);
check (ParamModel.get (model, "Sat_Y2@1") === 0.5, "the echo leaves the edit");

// several points in one event: one shaperIn
patch.sent = [];
ParamModel.set (model, "Sat_X2", -0.2);
ParamModel.set (model, "Sat_Y2", 0.3);
ParamModel.set (model, "Sat_Points", 1);
await tick();
check (shaper().length === 1 && shaper (0).length === 1, `points set together go in one event (${shaper().length})`);

// undo and redo
patch.sent = [];
ParamModel.seal (model);
ParamModel.undo (model);
await tick();
check (ParamModel.get (model, "Sat_X2") === StoredParams.init ("Sat_X2") &&shaper (0).length === 1,
       `undo puts the points back and sends them (Sat_X2 ${ParamModel.get (model, "Sat_X2")})`);
check (stored().Sat_X2 === undefined && stored()["Sat_Y2@1"] === 0.5, `and stores them (${patch.state.get ("params")})`);
ParamModel.redo (model);
await tick();
check (ParamModel.get (model, "Sat_Y2") === 0.3 && stored().Sat_Y2 === 0.3, "redo does them again");

// a host's state
patch.sent = [];
patch.sendStoredStateValue ("params", JSON.stringify ({ "Sat_C4@2": -0.75, Sat_Points: 5 }));
await tick();
check (ParamModel.get (model, "Sat_C4@2") === -0.75 && ParamModel.get (model, "Sat_Points") === 5 && ParamModel.get (model, "Sat_Y2@1") === StoredParams.init ("Sat_Y2@1"),
       "a stored value from elsewhere sets every stored parameter");
check (shaper().length === 0 && patch.sent.filter (([k]) => k === "state:params").length === 1, "without sending anything back");
patch.state.delete ("params");
patch.stateListeners.forEach (f => f ({ key: "params", value: null }));
check (StoredParams.ids.every (id => ParamModel.get (model, id) === StoredParams.init (id)), "none at all: every point at its default");

// a whole program
patch.sent = [];
ParamModel.setAll (model, new Map ([...Preset.init ("program").values, ["Sat_X3@3", 0.125], ["Cutoff", 0.5]]));
check (shaper().length === StoredParams.groups.length && shaper (3)[0].values[indexOf ("Sat_X3@3")] === 0.125,
       `a program sends every distortion's points at once (${shaper().length} events)`);
check (patch.sent.some (([id]) => id === "Cutoff") && stored()["Sat_X3@3"] === 0.125, "and its endpoints, and stores them");

// the stored value
const values = StoredParams.decode (JSON.stringify ({ Sat_Y5: 0.5, nonsense: 3 }));
check (values.size === StoredParams.ids.length && values.get ("Sat_Y5") === 0.5 && values.get ("Sat_X1") === StoredParams.init ("Sat_X1"),
       "a stored value decodes to every stored parameter, defaults where it has none");
check (StoredParams.ids.length === 13 * 49, `${StoredParams.ids.length} stored parameters`);

// presets
const p = Preset.init ("shape");
const [preset] = Preset.decodeBank (Preset.encodeBank ([{ ...p, values: new Map ([...p.values, ["Sat_Y7@2", -0.5], ["FX_Rack_2", PorridgeParams.entryValue ("distortion", 2)]]) }])) ?? [];
check (preset?.values.get ("Sat_Y7@2") === -0.5, "a preset keeps them");

// no endpoints
const store = readFileSync (join (root, "dsp", "ParamStore.cmajor"), "utf8");
check (StoredParams.ids.every (id => ! new RegExp (`input event \\w+ ${id} `).test (store)), "none of them is an endpoint");

// The wheels, the other way about: host parameters (endpoints hosts list) that are playing, not
// the program: a drag is a gesture the host hears, but no undo step; a program pushed whole
// leaves them where they are; the host's values move them
{
    const wheels = [PorridgeParams.pitchWheelId, PorridgeParams.modWheelId];
    check (wheels.every (id => new RegExp (`input event float ${id} \\[\\[ name: "[^"]+", min`).test (store)),
           "the wheels are endpoints hosts list (automatable)");
    ParamModel.seal (model);
    ParamModel.clearHistory (model);
    patch.sent = [];
    ParamModel.beginGesture (model, PorridgeParams.pitchWheelId);
    ParamModel.set (model, PorridgeParams.pitchWheelId, 0.25);
    ParamModel.set (model, PorridgeParams.pitchWheelId, 0);
    ParamModel.endGesture (model, PorridgeParams.pitchWheelId);
    ParamModel.gestureSet (model, PorridgeParams.modWheelId, 0.5);
    await tick();
    const sent = patch.sent.map (([a, b]) => `${a} ${b}`).join (", ");
    check (sent === "gesture Wheel_Pitch, Wheel_Pitch 0.25, Wheel_Pitch 0, gestureEnd Wheel_Pitch, gesture Wheel_Mod, Wheel_Mod 0.5, gestureEnd Wheel_Mod",
           `a wheel's drag is a gesture with its values (${sent})`);
    check (ParamModel.undoLabel (model) === undefined, `and no undo step (${ParamModel.undoLabel (model)})`);
    patch.sent = [];
    ParamModel.setAll (model, Preset.init ("program").values);
    check (ParamModel.get (model, PorridgeParams.modWheelId) === 0.5 && ! patch.sent.some (([id]) => wheels.includes (id)),
           "a program pushed whole leaves the wheels as they are");
    model.onParam ({ endpointID: PorridgeParams.modWheelId, value: 0.75 });
    check (ParamModel.get (model, PorridgeParams.modWheelId) === 0.75 && ParamModel.undoLabel (model) === undefined,
           "the host's automation moves a wheel");
}

done ("stored parameters ok");
