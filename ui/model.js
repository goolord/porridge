// Parameter model: the single source of truth for the view. Values are internal
// (preset-struct) values; the patch's endpoints use the same units.

export class ParamModel
{
    constructor (patchConnection, defs)
    {
        this.pc = patchConnection;
        this.defs = new Map (defs.map (d => [d.id, d]));
        this.values = new Map (defs.map (d => [d.id, d.init]));
        this.listeners = new Map();
        this.anyListeners = [];
        this.suppressSend = false;

        this.onParam = ev =>
        {
            const d = this.defs.get (ev.endpointID);
            if (! d) return;
            const x = d.isInt ? Math.round (ev.value) : ev.value;
            if (this.values.get (d.id) === x) return;
            this.values.set (d.id, x);
            this.notify (d.id);
        };

        if (this.pc)
        {
            this.pc.addAllParameterListener (this.onParam);
            for (const d of defs)
                this.pc.requestParameterValue (d.id);
        }
    }

    dispose()
    {
        this.pc?.removeAllParameterListener?.(this.onParam);
    }

    def (id)     { return this.defs.get (id); }
    get (id)     { return this.values.get (id); }

    listen (id, fn)
    {
        if (! this.listeners.has (id)) this.listeners.set (id, []);
        this.listeners.get (id).push (fn);
    }

    listenAny (fn) { this.anyListeners.push (fn); }

    notify (id)
    {
        for (const fn of this.listeners.get (id) ?? []) fn();
        for (const fn of this.anyListeners) fn (id);
    }

    set (id, x)
    {
        const d = this.defs.get (id);
        if (! d) return;
        x = d.clamp (x);
        if (this.values.get (id) === x) return;
        this.values.set (id, x);
        this.pc?.sendEventOrValue (id, x);
        this.notify (id);
    }

    begin (id) { this.pc?.sendParameterGestureStart?.(id); }
    end (id)   { this.pc?.sendParameterGestureEnd?.(id); }

    gestureSet (id, x)
    {
        this.begin (id);
        this.set (id, x);
        this.end (id);
    }

    // Push a whole set of values (e.g. a loaded program). Every endpoint is sent, even
    // if unchanged, so the patch is guaranteed to match.
    setAll (valuesById)
    {
        for (const [id, x0] of valuesById)
        {
            const d = this.defs.get (id);
            if (! d) continue;
            const x = d.clamp (x0);
            this.values.set (id, x);
            this.pc?.sendEventOrValue (id, x, -1, 1000);
        }
        for (const id of valuesById.keys()) this.notify (id);
    }
}
