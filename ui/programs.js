// The 64-program bank, as the view sees it. Programs are v38 Oatmeal chunks; the bank
// and the current program's shapes live in the patch's stored state so the host saves
// them with the session (parameters are saved by the host on their own).

import * as fmt from "./oatmeal/oatmeal-format.js";
import {
    PROGRAM_SIZE, NUM_PROGRAMS, programValues, writeValues, programShapes, readShape, writeShape,
    programName, setProgramName, sendShape, sendShapes, encodeBank, decodeBank, encodeShapes, decodeShapes,
} from "./bank.js";

export class ProgramStore
{
    constructor (pc, model, { onChange, onMessage })
    {
        this.pc = pc;
        this.model = model;
        this.onChange = onChange;
        this.message = onMessage;
        this.shapeListeners = [];
        this.current = 0;
        this.programs = Array.from ({ length: NUM_PROGRAMS }, (_, i) => fmt.makeDefaultProgram ("Init " + i));
        this.shapes = programShapes (this.programs[0]);
        this.pendingSend = new Map();

        this.stateListener = ev => this.onState (ev.key, ev.value);
        this.outListener = ev => this.onControllerSeen (ev);
    }

    start()
    {
        if (! this.pc) return;
        this.pc.addStoredStateValueListener (this.stateListener);
        this.pc.addEndpointListener?.("ccOut", this.outListener);
        this.pc.requestStoredStateValue ("bank");
        this.pc.requestStoredStateValue ("program");
        this.pc.requestStoredStateValue ("shapes");
    }

    dispose()
    {
        this.pc?.removeStoredStateValueListener?.(this.stateListener);
        this.pc?.removeEndpointListener?.("ccOut", this.outListener);
    }

    onState (key, value)
    {
        if (key === "bank" && typeof value === "string" && value.length > 1000)
        {
            this.programs = decodeBank (value);
            this.onChange();
        }
        else if (key === "program" && Number.isFinite (value))
        {
            this.current = Math.max (0, Math.min (NUM_PROGRAMS - 1, value | 0));
            this.onChange();
        }
        else if (key === "shapes")
        {
            const s = decodeShapes (value);
            if (s) { this.shapes = { ...this.shapes, ...s }; this.fireShapes(); }
        }
    }

    name (i) { return programName (this.programs[i] ?? new Uint8Array (PROGRAM_SIZE)); }

    shape (key) { return this.shapes[key]; }
    onShapes (fn) { this.shapeListeners.push (fn); }
    fireShapes() { for (const fn of this.shapeListeners) fn(); }

    // live edits are sent immediately (throttled to one event per animation frame);
    // committed edits are also written to the stored state
    setShape (key, data, commit)
    {
        this.shapes[key] = Float32Array.from (data);
        if (! this.pendingSend.has (key))
        {
            this.pendingSend.set (key, true);
            requestAnimationFrame (() =>
            {
                this.pendingSend.delete (key);
                if (this.pc) sendShape (this.pc, key, this.shapes[key]);
            });
        }
        if (commit)
        {
            this.pc?.sendStoredStateValue ("shapes", encodeShapes (this.shapes));
            this.fireShapes();
        }
    }

    // current program as a chunk, with the live parameter values and shapes folded in
    captureCurrent()
    {
        const bytes = Uint8Array.from (this.programs[this.current]);
        writeValues (bytes, this.model.values);
        for (const k of Object.keys (this.shapes)) writeShape (bytes, k, this.shapes[k]);
        return bytes;
    }

    storeBank()
    {
        this.pc?.sendStoredStateValue ("bank", encodeBank (this.programs));
    }

    apply (bytes)
    {
        this.model.setAll (programValues (bytes));
        this.shapes = programShapes (bytes);
        if (this.pc)
        {
            sendShapes (this.pc, this.shapes);
            this.pc.sendStoredStateValue ("shapes", encodeShapes (this.shapes));
        }
        this.fireShapes();
    }

    select (i)
    {
        i = ((i % NUM_PROGRAMS) + NUM_PROGRAMS) % NUM_PROGRAMS;
        this.programs[this.current] = this.captureCurrent();
        this.current = i;
        this.apply (this.programs[i]);
        this.pc?.sendStoredStateValue ("program", i);
        this.storeBank();
        this.onChange();
    }

    rename (i, name)
    {
        if (i === this.current) this.programs[i] = this.captureCurrent();
        setProgramName (this.programs[i], name.trim().slice (0, 23));
        this.storeBank();
        this.onChange();
    }

    initCurrent()
    {
        const p = fmt.makeDefaultProgram ("Init");
        this.programs[this.current] = p;
        this.apply (p);
        this.storeBank();
        this.onChange();
    }

    panic()
    {
        this.pc?.sendEventOrValue ("panic", 1);
    }

    loadFile (bytes, filename)
    {
        let result;
        try
        {
            result = fmt.parseFile (bytes, { filename });
        }
        catch (e)
        {
            this.message (`${filename} isn't an Oatmeal program or bank (${e.message})`);
            return;
        }

        const progs = (result.programs ?? []).map (p => p.bytes ?? p);
        if (progs.length === 0)
        {
            this.message (`${filename} has no programs in it`);
            return;
        }

        if (progs.length === 1 && result.kind !== "bank")
        {
            this.programs[this.current] = Uint8Array.from (progs[0]);
            this.apply (this.programs[this.current]);
            this.message (`Loaded "${programName (progs[0])}" into program ${this.current + 1}`);
        }
        else
        {
            for (let i = 0; i < NUM_PROGRAMS; ++i)
                this.programs[i] = Uint8Array.from (progs[i] ?? fmt.makeDefaultProgram ("Init " + i));
            this.current = 0;
            this.apply (this.programs[0]);
            this.pc?.sendStoredStateValue ("program", 0);
            this.message (`Loaded bank ${filename} (${progs.length} programs)`);
        }
        this.storeBank();
        this.onChange();
    }

    download (bytes, filename)
    {
        const blob = new Blob ([bytes], { type: "application/octet-stream" });
        const a = document.createElement ("a");
        a.href = URL.createObjectURL (blob);
        a.download = filename;
        document.body.appendChild (a);
        a.click();
        setTimeout (() => { URL.revokeObjectURL (a.href); a.remove(); }, 1000);
    }

    safeName (s) { return (s || "program").replace (/[^A-Za-z0-9 _.-]+/g, "").trim() || "program"; }

    downloadProgram()
    {
        const bytes = this.captureCurrent();
        this.programs[this.current] = bytes;
        this.download (fmt.writeProgramChunk (bytes), this.safeName (programName (bytes)) + ".omp");
    }

    downloadBank()
    {
        this.programs[this.current] = this.captureCurrent();
        this.download (fmt.writeBankChunk (this.programs), "porridge bank.omb");
    }

    learn (ccId)
    {
        this.learning = ccId;
        this.message ("Move a controller to assign it to " + ccId.replace ("CC", "slot "));
    }

    onControllerSeen (cc)
    {
        if (! this.learning) return;
        const n = typeof cc === "number" ? cc : cc?.controller;
        if (! Number.isFinite (n) || n < 1 || n > 127) return;
        this.model.gestureSet (this.learning, n);
        this.message (`Assigned controller ${n}`);
        this.learning = null;
    }
}
