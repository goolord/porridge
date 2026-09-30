// Main page. Block arrangement follows the original default skin's reading order:
// sound sources top-left, filter and envelopes next to them, modulation in the middle,
// global settings right, effects and performance controls along the bottom.

import { el, place, Block, Param, Choice, Toggle, Button } from "./controls.js";
import { EnvelopePlot, PitchEnvelopePlot, WavePlot, LfoPlot } from "./plots.js";
import { XYPad } from "./xypad.js";
import { ArpPattern } from "./arp.js";

export const CW = 74;      // grid column width
export const RH = 28;      // grid row height
const PX = 5, PT = 17, PB = 4, GAP = 6;

export function blockW (cols) { return cols * CW + 2 * PX; }
export function blockH (rows) { return PT + rows * RH + PB; }

// A block with a control grid. g.p(id, col, row) etc. place controls on the grid.
export class GridBlock extends Block
{
    constructor (ctx, parent, title, x, y, cols, rows, opts = {})
    {
        const cw = opts.cw ?? CW;
        const w = opts.w ?? cols * cw + 2 * PX, h = opts.h ?? blockH (rows);
        super (parent, title, x, y, w, h, opts);
        this.ctx = ctx;
        this.cols = cols;
        this.rows = rows;
        this.cw = cw;
        this.x = x; this.y = y;
        this.w = w;
        this.h = h;
    }

    cx (c) { return PX + c * this.cw - 1; }
    cy (r) { return PT + r * RH; }

    p (id, c, r, label, span = 1)  { return new Param  (this.ctx, this.el, id, this.cx (c), this.cy (r), span * this.cw - 2, label); }
    ch (id, c, r, label, span = 1, opts) { return new Choice (this.ctx, this.el, id, this.cx (c), this.cy (r), span * this.cw - 2, label, opts); }
    tg (id, c, r, label, dy = 5)   { return new Toggle (this.ctx, this.el, id, this.cx (c) + 3, this.cy (r) + dy, label); }
    btn (text, c, r, w, fn, status, dy = 3) { return new Button (this.ctx, this.el, text, this.cx (c) + 3, this.cy (r) + dy, w, fn, status); }
    box (c, r, cs, rs)            { return { x: this.cx (c) + 3, y: this.cy (r) + 2, w: cs * this.cw - 8, h: rs * RH - 4 }; }
    bottom (gap = GAP) { return this.y + this.h + gap; }
    right (gap = GAP)  { return this.x + this.w + gap; }

    // Extend the block down so that its bottom edge sits one gap above y.
    stretchTo (y)
    {
        this.h = Math.max (this.h, y - GAP - this.y);
        this.el.style.height = this.h + "px";
    }
}

export function buildMainPage (ctx, page)
{
    const G = (title, x, y, cols, rows, opts) => new GridBlock (ctx, page, title, x, y, cols, rows, opts);
    const X0 = 6, Y0 = 6;

    //==============================================================================
    // column 1: oscillators, noise, unison
    const osc = G ("oscs", X0, Y0, 3, 8);
    osc.ch ("O1_Waveform", 0, 0, "1 waveform");
    osc.p ("O1_Amp", 0, 1, "amp");
    osc.p ("O1_Afterpitch", 0, 2, "touch > pitch");
    osc.p ("O1_PWM_W", 1, 0, "pulsewidth");
    osc.p ("O1_PWM_R", 1, 1, "pwm rate");
    osc.p ("O1_PWM_D", 1, 2, "pwm depth");
    new WavePlot (ctx, osc.el, 0, osc.box (2, 0, 1, 2));
    osc.btn ("edit", 2, 2, 52, () => ctx.view.openShape ("wave1"), "Draw oscillator 1's user waveform");
    el ("div", "sep", osc.el).style.cssText = `left:${PX}px;right:${PX}px;top:${osc.cy (3) - 1}px`;
    osc.ch ("O2_Waveform", 0, 3, "2 waveform");
    osc.p ("O2_Amp", 0, 4, "amp");
    osc.p ("O2_Afterpitch", 0, 5, "touch > pitch");
    osc.p ("O2_PWM_W", 1, 3, "pulsewidth");
    osc.p ("O2_PWM_R", 1, 4, "pwm rate");
    osc.p ("O2_PWM_D", 1, 5, "pwm depth");
    new WavePlot (ctx, osc.el, 1, osc.box (2, 3, 1, 2));
    osc.btn ("edit", 2, 5, 52, () => ctx.view.openShape ("wave2"), "Draw oscillator 2's user waveform");
    osc.p ("Transpose", 0, 6, "2 transpose");
    osc.p ("Detune", 1, 6, "2 detune");
    osc.p ("OscAftertouch", 2, 6, "touch > amp");
    osc.ch ("OscMix", 0, 7, "mix", 2);

    const noise = G ("noise", X0, osc.bottom(), 3, 2);
    noise.p ("N_Amp", 0, 0, "amp");
    noise.p ("N_Aftertouch", 1, 0, "touch > amp");
    noise.p ("N_Resonance", 0, 1, "resonance");
    noise.p ("N_Transpose", 1, 1, "transpose");

    const uni = G ("unison", X0, noise.bottom(), 3, 2);
    uni.p ("U_Voices", 0, 0, "voices");
    uni.p ("U_Detune", 1, 0, "detune");
    uni.p ("U_Spread", 2, 0, "spread");
    uni.p ("U_PitchJitter", 0, 1, "pitch jitter");
    uni.p ("U_PanJitter", 1, 1, "pan jitter");

    //==============================================================================
    // column 2: filter, amp envelope, distortion
    const X1 = osc.right();
    const flt = G ("filter", X1, Y0, 4, 7);
    flt.ch ("Filter", 0, 0, "type", 2);
    flt.ch ("Filter2", 2, 0, "filter 2", 2);
    flt.p ("Cutoff", 0, 1, "cutoff");
    flt.p ("F_Track", 1, 1, "track");
    flt.p ("Resonance", 2, 1, "reso");
    flt.p ("F_Aftertouch", 3, 1, "touch");
    flt.ch ("F_Double", 0, 2, "double");
    flt.p ("F_Split", 1, 2, "split");
    flt.p ("F_Mix", 2, 2, "mix");
    flt.p ("F_Speed", 3, 2, "speed ratio");
    flt.p ("F_EnvMod", 0, 3, "env mod");
    flt.p ("F_VeloSens", 1, 3, "velocity");
    new EnvelopePlot (ctx, flt.el, "F_", flt.box (2, 3, 2, 1));
    envRows (flt, "F_", 4);

    const amp = G ("envelope", X1, flt.bottom(), 4, 3);
    envRows (amp, "", 0);
    new EnvelopePlot (ctx, amp.el, "", amp.box (0, 2, 4, 1));

    const dist = G ("distortion", X1, amp.bottom(), 4, 2);
    dist.ch ("Sat_Type", 0, 0, "type");
    dist.ch ("Sat_Mode", 1, 0, "mode", 2);
    dist.ch ("Sat_Oversample", 3, 0, "oversample");
    dist.p ("Sat_Pregain", 0, 1, "pregain");
    dist.p ("Sat_Limit", 1, 1, "limit");
    dist.p ("Sat_Postgain", 2, 1, "postgain");

    //==============================================================================
    // column 3: mod envelopes, pitch envelope
    const X2 = flt.right();
    const m1 = modEnv (ctx, page, G, "mod env 1", "M1_", X2, Y0);
    const m2 = modEnv (ctx, page, G, "mod env 2", "M2_", X2, m1.bottom());

    const pe = G ("pitch env", X2, m2.bottom(), 4, 4);
    pe.p ("PEnv_Start", 0, 0, "start");
    pe.p ("PEnv_Attack", 1, 0, "attack");
    pe.p ("PEnv_Peak", 2, 0, "peak");
    pe.p ("PEnv_Decay", 3, 0, "decay");
    pe.p ("PEnv_Sustain", 0, 1, "sustain");
    pe.p ("PEnv_Release", 1, 1, "release");
    pe.p ("PEnv_VeloSens", 2, 1, "velocity");
    pe.tg ("PEnv_On", 3, 1, "on");

    //==============================================================================
    // column 4: LFOs, phase
    const X3 = m1.right();
    const l1 = lfo (ctx, G, 1, X3, Y0);
    const l2 = lfo (ctx, G, 2, X3, l1.bottom());

    const ph = G ("phase", X3, l2.bottom(), 3, 3);
    ph.p ("OscPhase", 0, 0, "osc");
    ph.p ("OscPhaseRand", 1, 0, "osc rand");
    ph.tg ("OscRetrig", 2, 0, "retrigger");
    ph.p ("PWMPhase", 0, 1, "pwm");
    ph.p ("PWMPhaseRand", 1, 1, "pwm rand");
    ph.tg ("PWMRetrig", 2, 1, "retrigger");
    ph.p ("LFOPhase", 0, 2, "lfo");
    ph.p ("LFOPhaseRand", 1, 2, "lfo rand");
    ph.tg ("LFORetrig", 2, 2, "retrigger");

    //==============================================================================
    // column 5: voice ("hodgepodge"), tuning
    const X4 = l1.right();
    const hp = G ("hodgepodge", X4, Y0, 3, 5);
    hp.p ("Gain", 0, 0, "output gain");
    hp.p ("VeloSens", 1, 0, "velocity");
    hp.ch ("AftertouchMode", 2, 0, "touch");
    hp.ch ("PolyMode", 0, 1, "voice mode", 2);
    hp.p ("Voices", 2, 1, "polyphony");
    hp.p ("Glide", 0, 2, "glide");
    hp.ch ("GlideMode", 1, 2, "glide mode", 2);
    hp.p ("BendRange", 0, 3, "bend range");
    hp.p ("GlobalTranspose", 1, 3, "transpose");
    hp.p ("RandomFreq", 2, 3, "random freq");
    hp.p ("RandomPan", 0, 4, "random pan");
    hp.p ("RandomAmp", 1, 4, "random amp");
    hp.p ("FreqPan", 2, 4, "freq > pan");

    const tn = G ("tuning", X4, hp.bottom(), 3, 6);
    tn.p ("Tune_Main", 0, 0, "tune");
    tn.p ("Tune_Octave", 1, 0, "octave");
    tn.p ("FreqEnv", 2, 0, "freq > env");
    tn.p ("Tune_CutReference", 0, 1, "cut ref");
    tn.p ("Tune_PanReference", 1, 1, "pan ref");
    const notes = [["Tune_C", "c"], ["Tune_Db", "c#"], ["Tune_D", "d"], ["Tune_Eb", "d#"], ["Tune_E", "e"], ["Tune_F", "f"],
                   ["Tune_Gb", "f#"], ["Tune_G", "g"], ["Tune_Ab", "g#"], ["Tune_A", "a"], ["Tune_Bb", "a#"], ["Tune_B", "b"]];
    notes.forEach (([id, label], i) => tn.p (id, i % 3, 2 + Math.floor (i / 3), label));

    //==============================================================================
    // bottom band: XY, arpeggiator, effects
    const YB = Math.max (uni.bottom(), dist.bottom(), pe.bottom(), ph.bottom(), tn.bottom());
    for (const b of [uni, dist, pe, ph, tn]) b.stretchTo (YB);
    new PitchEnvelopePlot (ctx, pe.el, { ...pe.box (0, 2, 4, 2), h: pe.h - pe.cy (2) - PB - 6 });

    const xy = G ("xy", X0, YB, 6, 5);
    new XYPad (ctx, xy.el, { x: PX + 2, y: PT + 2, w: 2 * CW - 6, h: 4 * RH - 6 });
    for (let k = 0; k < 4; ++k)
    {
        xy.ch (`XY_H_Target_${k + 1}`, 2, k, "x target " + (k + 1));
        xy.p  (`XY_H_Depth_${k + 1}`, 3, k, "depth");
        xy.ch (`XY_V_Target_${k + 1}`, 4, k, "y target " + (k + 1));
        xy.p  (`XY_V_Depth_${k + 1}`, 5, k, "depth");
    }
    xy.p ("XY_Var_Radius", 0, 4, "rand radius");
    xy.p ("XY_Var_Rate", 1, 4, "rand rate");
    xy.p ("XY_X", 2, 4, "x");
    xy.p ("XY_H_CC", 3, 4, "x cc");
    xy.p ("XY_Y", 4, 4, "y");
    xy.p ("XY_V_CC", 5, 4, "y cc");

    const arp = G ("arp", xy.right(), YB, 6, 5);
    new ArpPattern (ctx, arp.el, { x: PX + 2, y: PT + 2, w: 6 * CW - 6, h: 2 * RH - 4 });
    arp.ch ("Arp_Mode", 0, 2, "mode", 2);
    arp.ch ("Arp_Unit", 2, 2, "unit", 2);
    arp.p ("Arp_Step", 4, 2, "step");
    arp.tg ("Arp_Quantize", 5, 2, "quantize");
    for (let k = 0; k < 7; ++k)
    {
        const x = arp.cx (0) + (k % 4) * 111, y = arp.cy (3 + Math.floor (k / 4));
        new Toggle (ctx, arp.el, `Arp_Add_${k + 1}_On`, x + 3, y + 5, String (k + 1));
        new Param (ctx, arp.el, `Arp_Add_${k + 1}_Shift`, x + 26, y, 80, "shift");
    }

    const ch = G ("chorus", arp.right(), YB, 2, 5);
    ch.ch ("C_Mode", 0, 0, "mode");
    ch.ch ("C_Stereo", 1, 0, "stereo");
    ch.p ("C_Rate", 0, 1, "rate");
    ch.p ("C_Voices", 1, 1, "voices");
    ch.p ("C_MinDelay", 0, 2, "delay");
    ch.p ("C_Depth", 1, 2, "range");
    ch.p ("C_Feedback", 0, 3, "feedback");
    ch.p ("C_Mix", 1, 3, "mix");

    const dl = G ("delay", ch.right(), YB, 3, 5);
    dl.tg ("D_On", 0, 0, "on");
    dl.ch ("D_Unit", 1, 0, "unit");
    dl.tg ("D_Quantize", 2, 0, "quantize");
    dl.p ("D_LengthL", 0, 1, "length l");
    dl.p ("D_FeedbackL", 1, 1, "feedback l");
    dl.ch ("D_ReverseL", 2, 1, "reverse l");
    dl.p ("D_LengthR", 0, 2, "length r");
    dl.p ("D_FeedbackR", 1, 2, "feedback r");
    dl.ch ("D_ReverseR", 2, 2, "reverse r");
    dl.p ("D_InputPan", 0, 3, "input pan");
    dl.p ("D_Rotation", 1, 3, "rotation");
    dl.p ("D_LP", 2, 3, "lowpass");
    dl.p ("D_Dry", 0, 4, "dry");
    dl.p ("D_Wet", 1, 4, "wet");
    dl.p ("D_HP", 2, 4, "highpass");

    const YC = xy.bottom();
    const eq = G ("eq", X0, YC, 10, 2);
    for (let b = 0; b < 5; ++b)
    {
        eq.ch (`EQ_${b + 1}_Type`, 2 * b, 0, "band " + (b + 1));
        eq.p (`EQ_${b + 1}_Freq`, 2 * b + 1, 0, "freq");
        eq.p (`EQ_${b + 1}_Amp`, 2 * b, 1, "amp");
        eq.p (`EQ_${b + 1}_Slope`, 2 * b + 1, 1, "slope");
    }

    const rv = G ("reverb", eq.right(), YC, 7, 2, { w: dl.x + dl.w - eq.right() });
    rv.tg ("R_On", 0, 0, "on");
    rv.p ("R_Size", 1, 0, "room size");
    rv.p ("R_Length", 2, 0, "length");
    rv.p ("R_Predelay", 3, 0, "predelay");
    rv.p ("R_EarlyMix", 4, 0, "early");
    rv.p ("R_Dry", 5, 0, "dry");
    rv.p ("R_Wet", 6, 0, "wet");
    rv.p ("R_Dullness", 0, 1, "dull");
    rv.p ("R_Brightness", 1, 1, "bright");
    rv.p ("R_1", 2, 1, "angle 1");
    rv.p ("R_2", 3, 1, "angle 2");
    rv.p ("R_3", 4, 1, "angle 3");
    rv.p ("R_Rotation", 5, 1, "rotate");

    return page;
}

function envRows (g, prefix, row)
{
    g.p (prefix + "Attack", 0, row, "attack");
    g.p (prefix + "Hold", 1, row, "hold");
    g.p (prefix + "Decay1", 2, row, "decay 1");
    g.p (prefix + "Breakpoint", 3, row, "breakpoint");
    g.p (prefix + "Decay2", 0, row + 1, "decay 2");
    g.p (prefix + "Sustain", 1, row + 1, "sustain");
    g.p (prefix + "Release", 2, row + 1, "release");
}

function modEnv (ctx, page, G, title, pre, x, y)
{
    const g = G (title, x, y, 4, 4);
    envRows (g, pre, 0);
    g.p (pre + "VeloSens", 3, 1, "velocity");
    for (let k = 0; k < 4; ++k)
    {
        const c = (k % 2) * 2, r = 2 + Math.floor (k / 2);
        g.ch (`${pre}Target_${k + 1}`, c, r, "target " + (k + 1));
        g.p (`${pre}Depth_${k + 1}`, c + 1, r, "depth");
    }
    return g;
}

function lfo (ctx, G, n, x, y)
{
    const pre = `LFO_${n}_`;
    const g = G ("lfo " + n, x, y, 3, 5);
    g.ch (pre + "Shape", 0, 0, "shape");
    g.ch (pre + "Sync", 1, 0, "mode", 2);
    g.ch (pre + "Unit", 0, 1, "unit");
    g.p (pre + "Speed", 1, 1, "rate");
    g.tg (pre + "Quantize", 2, 1, "quantize");
    g.p (pre + "Cutoff_1", 0, 2, "cut 1");
    g.p (pre + "Cutoff_2", 1, 2, "cut 2");
    g.p (pre + "Resonance", 2, 2, "res");
    g.p (pre + "Pitch", 0, 3, "pitch");
    g.p (pre + "Pan", 1, 3, "pan");
    g.p (n === 1 ? "LFO_1_2" : "LFO_2_1", 2, 3, n === 1 ? "rate 2" : "rate 1");
    new LfoPlot (ctx, g.el, n - 1, g.box (0, 4, 2, 1));
    g.btn ("edit", 2, 4, 52, () => ctx.view.openShape ("lfo" + n), `Draw LFO ${n}'s user shape`);
    return g;
}
