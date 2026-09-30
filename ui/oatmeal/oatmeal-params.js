// oatmeal-params.js -- Oatmeal (Fuzzpilz, release 38-1) parameter table, value mapping and display text.
//
// Plain ES module, no dependencies (browser + Node >= 18).
// Reverse-engineered from Oatmeal.dll: setParameter 0x10048260, getParameter 0x1004c890,
// status text 0x100405f0 (host display = text after the first ':' , max 23 chars, 0x1004f5b0),
// action-name lookup 0x100367bb.  See docs/internals/presets_params.md.
//
// Conventions:
//   v / V      normalized VST parameter value (float32 in the DLL)
//   x          internal value as stored in the program struct at chunk offset `offset`
//   prog       v38 program chunk (Uint8Array(10376)), see oatmeal-format.js

// DLL parameter names (effGetParamName; 124..128 are empty in the DLL) and skin action names (from the DLL's own
// action-name -> index table 0x100367bb, used by .oms skins as action=...)
const NAMES = [
  ["1 Waveform", "O1_Waveform"],
  ["1 Amp", "O1_Amp"],
  ["1 Afterpitch", "O1_Afterpitch"],
  ["1 Pulsewidth", "O1_PWM_W"],
  ["1 PWM rate", "O1_PWM_R"],
  ["1 PWM depth", "O1_PWM_D"],
  ["2 Waveform", "O2_Waveform"],
  ["2 Amp", "O2_Amp"],
  ["2 Afterpitch", "O2_Afterpitch"],
  ["2 Pulsewidth", "O2_PWM_W"],
  ["2 PWM rate", "O2_PWM_R"],
  ["2 PWM depth", "O2_PWM_D"],
  ["Transpose", "Transpose"],
  ["Detune", "Detune"],
  ["Osc aftertouch", "OscAftertouch"],
  ["N amp", "N_Amp"],
  ["N aftertouch", "N_Aftertouch"],
  ["N resonance", "N_Resonance"],
  ["N transpose", "N_Transpose"],
  ["LFO 1 unit", "LFO_1_Unit"],
  ["LFO 1 shape", "LFO_1_Shape"],
  ["LFO 1 speed", "LFO_1_Speed"],
  ["LFO 1 quantize", "LFO_1_Quantize"],
  ["LFO 1 mode", "LFO_1_Sync"],
  ["LFO 1 cut 1", "LFO_1_Cutoff_1"],
  ["LFO 1 cut 2", "LFO_1_Cutoff_2"],
  ["LFO 1 res", "LFO_1_Resonance"],
  ["LFO 1 pitch", "LFO_1_Pitch"],
  ["LFO 1 pan", "LFO_1_Pan"],
  ["LFO 1 2", "LFO_1_2"],
  ["LFO 1 unit", "LFO_2_Unit"],
  ["LFO 2 shape", "LFO_2_Shape"],
  ["LFO 2 speed", "LFO_2_Speed"],
  ["LFO 2 quantize", "LFO_2_Quantize"],
  ["LFO 2 mode", "LFO_2_Sync"],
  ["LFO 2 cut 1", "LFO_2_Cutoff_1"],
  ["LFO 2 cut 2", "LFO_2_Cutoff_2"],
  ["LFO 2 res", "LFO_2_Resonance"],
  ["LFO 2 pitch", "LFO_2_Pitch"],
  ["LFO 2 pan", "LFO_2_Pan"],
  ["LFO 2 1", "LFO_2_1"],
  ["Filter", "Filter"],
  ["Filter 2", "Filter2"],
  ["Cutoff", "Cutoff"],
  ["Resonance", "Resonance"],
  ["F attack", "F_Attack"],
  ["F hold", "F_Hold"],
  ["F decay 1", "F_Decay1"],
  ["F breakpoint", "F_Breakpoint"],
  ["F decay 2", "F_Decay2"],
  ["F sustain", "F_Sustain"],
  ["F release", "F_Release"],
  ["F keytrack", "F_Track"],
  ["F double", "F_Double"],
  ["F mix", "F_Mix"],
  ["F split", "F_Split"],
  ["F envspeed", "F_Speed"],
  ["F envmod", "F_EnvMod"],
  ["F env velo sens", "F_VeloSens"],
  ["F aftertouch", "F_Aftertouch"],
  ["Attack", "Attack"],
  ["Hold", "Hold"],
  ["Decay 1", "Decay1"],
  ["Breakpoint", "Breakpoint"],
  ["Decay 2", "Decay2"],
  ["Sustain", "Sustain"],
  ["Release", "Release"],
  ["Chorus", "C_Mode"],
  ["Chorus", "C_Stereo"],
  ["C voices", "C_Voices"],
  ["C speed", "C_Rate"],
  ["C delay", "C_MinDelay"],
  ["C depth", "C_Depth"],
  ["C feedback", "C_Feedback"],
  ["C mix", "C_Mix"],
  ["Delay", "D_On"],
  ["D unit", "D_Unit"],
  ["D quantize", "D_Quantize"],
  ["D reverse", "D_ReverseL"],
  ["D reverse", "D_ReverseR"],
  ["D length L", "D_LengthL"],
  ["D length R", "D_LengthR"],
  ["D feedbk L", "D_FeedbackL"],
  ["D feedbk R", "D_FeedbackR"],
  ["D input pan", "D_InputPan"],
  ["D rotation", "D_Rotation"],
  ["D lowpass", "D_LP"],
  ["D highpass", "D_HP"],
  ["D dry out", "D_Dry"],
  ["D wet out", "D_Wet"],
  ["Reverb", "R_On"],
  ["R size", "R_Size"],
  ["R length", "R_Length"],
  ["R dullness", "R_Dullness"],
  ["R brightness", "R_Brightness"],
  ["R dry out", "R_Dry"],
  ["R wet out", "R_Wet"],
  ["R 1", "R_1"],
  ["R 2", "R_2"],
  ["R 3", "R_3"],
  ["R rotation", "R_Rotation"],
  ["R predelay", "R_Predelay"],
  ["R early mix", "R_EarlyMix"],
  ["Voice mode", "PolyMode"],
  ["Max polyphony", "Voices"],
  ["Glide", "Glide"],
  ["Glide mode", "GlideMode"],
  ["Output gain", "Gain"],
  ["Velocity sensitivity", "VeloSens"],
  ["Aftertouch mode", "AftertouchMode"],
  ["Frequency pan", "FreqPan"],
  ["Frequency env", "FreqEnv"],
  ["Random pan", "RandomPan"],
  ["Random amp", "RandomAmp"],
  ["Random freq", "RandomFreq"],
  ["Osc phase", "OscPhase"],
  ["Osc phase rand", "OscPhaseRand"],
  ["Osc retrigger", "OscRetrig"],
  ["PWM phase", "PWMPhase"],
  ["PWM phase rand", "PWMPhaseRand"],
  ["PWM retrigger", "PWMRetrig"],
  ["LFO phase", "LFOPhase"],
  ["LFO phase rand", "LFOPhaseRand"],
  ["LFO retrigger", "LFORetrig"],
  ["", "U_Voices"],
  ["", "U_Detune"],
  ["", "U_Spread"],
  ["", "U_PitchJitter"],
  ["", "U_PanJitter"],
  ["Arp mode", "Arp_Mode"],
  ["Arp unit", "Arp_Unit"],
  ["Arp quantize", "Arp_Quantize"],
  ["Arp step", "Arp_Step"],
  ["Arp step 1", "Arp_P0"],
  ["Arp step 2", "Arp_P1"],
  ["Arp step 3", "Arp_P2"],
  ["Arp step 4", "Arp_P3"],
  ["Arp step 5", "Arp_P4"],
  ["Arp step 6", "Arp_P5"],
  ["Arp step 7", "Arp_P6"],
  ["Arp step 8", "Arp_P7"],
  ["Arp step 9", "Arp_P8"],
  ["Arp step 10", "Arp_P9"],
  ["Arp step 11", "Arp_PA"],
  ["Arp step 12", "Arp_PB"],
  ["Arp step 13", "Arp_PC"],
  ["Arp step 14", "Arp_PD"],
  ["Arp step 15", "Arp_PE"],
  ["Arp step 16", "Arp_PF"],
  ["Arp pattern length", "Arp_End"],
  ["Arp note 1 on", "Arp_Add_1_On"],
  ["Arp note 2 on", "Arp_Add_2_On"],
  ["Arp note 3 on", "Arp_Add_3_On"],
  ["Arp note 4 on", "Arp_Add_4_On"],
  ["Arp note 5 on", "Arp_Add_5_On"],
  ["Arp note 6 on", "Arp_Add_6_On"],
  ["Arp note 7 on", "Arp_Add_7_On"],
  ["Arp note 1 shift", "Arp_Add_1_Shift"],
  ["Arp note 2 shift", "Arp_Add_2_Shift"],
  ["Arp note 3 shift", "Arp_Add_3_Shift"],
  ["Arp note 4 shift", "Arp_Add_4_Shift"],
  ["Arp note 5 shift", "Arp_Add_5_Shift"],
  ["Arp note 6 shift", "Arp_Add_6_Shift"],
  ["Arp note 7 shift", "Arp_Add_7_Shift"],
  ["P env on", "PEnv_On"],
  ["P start", "PEnv_Start"],
  ["P attack", "PEnv_Attack"],
  ["P peak", "PEnv_Peak"],
  ["P decay", "PEnv_Decay"],
  ["P sustain", "PEnv_Sustain"],
  ["P release", "PEnv_Release"],
  ["P env velo sens", "PEnv_VeloSens"],
  ["Dist type", "Sat_Type"],
  ["Dist mode", "Sat_Mode"],
  ["Dist limit", "Sat_Limit"],
  ["Dist pregain", "Sat_Pregain"],
  ["Dist postgain", "Sat_Postgain"],
  ["Dist oversample", "Sat_Oversample"],
  ["Tune main", "Tune_Main"],
  ["Octave", "Tune_Octave"],
  ["Cut reference", "Tune_CutReference"],
  ["Pan reference", "Tune_PanReference"],
  ["Tune C", "Tune_C"],
  ["Tune C#/Db", "Tune_Db"],
  ["Tune D", "Tune_D"],
  ["Tune D#/Eb", "Tune_Eb"],
  ["Tune E", "Tune_E"],
  ["Tune F", "Tune_F"],
  ["Tune F#/Gb", "Tune_Gb"],
  ["Tune G", "Tune_G"],
  ["Tune G#/Ab", "Tune_Ab"],
  ["Tune A", "Tune_A"],
  ["Tune A#/Bb", "Tune_Bb"],
  ["Tune B", "Tune_B"],
  ["Bend range", "BendRange"],
  ["Global transpose", "GlobalTranspose"],
  ["X", "X"],
  ["Y", "Y"],
  ["X depth 1", "XY_H_Depth_1"],
  ["X depth 2", "XY_H_Depth_2"],
  ["X depth 3", "XY_H_Depth_3"],
  ["X depth 4", "XY_H_Depth_4"],
  ["X target 1", "XY_H_Target_1"],
  ["X target 2", "XY_H_Target_2"],
  ["X target 3", "XY_H_Target_3"],
  ["X target 4", "XY_H_Target_4"],
  ["X CC", "XY_H_CC"],
  ["Y depth 1", "XY_V_Depth_1"],
  ["Y depth 2", "XY_V_Depth_2"],
  ["Y depth 3", "XY_V_Depth_3"],
  ["Y depth 4", "XY_V_Depth_4"],
  ["Y target 1", "XY_V_Target_1"],
  ["Y target 2", "XY_V_Target_2"],
  ["Y target 3", "XY_V_Target_3"],
  ["Y target 4", "XY_V_Target_4"],
  ["Y CC", "XY_V_CC"],
  ["XY var radius", "XY_Var_Radius"],
  ["XY var rate", "XY_Var_Rate"],
  ["EQ 1 freq", "EQ_1_Freq"],
  ["EQ 2 freq", "EQ_2_Freq"],
  ["EQ 3 freq", "EQ_3_Freq"],
  ["EQ 4 freq", "EQ_4_Freq"],
  ["EQ 5 freq", "EQ_5_Freq"],
  ["EQ 1 amp", "EQ_1_Amp"],
  ["EQ 2 amp", "EQ_2_Amp"],
  ["EQ 3 amp", "EQ_3_Amp"],
  ["EQ 4 amp", "EQ_4_Amp"],
  ["EQ 5 amp", "EQ_5_Amp"],
  ["EQ 1 slope", "EQ_1_Slope"],
  ["EQ 2 slope", "EQ_2_Slope"],
  ["EQ 3 slope", "EQ_3_Slope"],
  ["EQ 4 slope", "EQ_4_Slope"],
  ["EQ 5 slope", "EQ_5_Slope"],
  ["EQ 1 type", "EQ_1_Type"],
  ["EQ 2 type", "EQ_2_Type"],
  ["EQ 3 type", "EQ_3_Type"],
  ["EQ 4 type", "EQ_4_Type"],
  ["EQ 5 type", "EQ_5_Type"],
  ["M1 attack", "M1_Attack"],
  ["M1 hold", "M1_Hold"],
  ["M1 decay 1", "M1_Decay1"],
  ["M1 breakpoint", "M1_Breakpoint"],
  ["M1 decay 2", "M1_Decay2"],
  ["M1 sustain", "M1_Sustain"],
  ["M1 release", "M1_Release"],
  ["M1 velo sens", "M1_VeloSens"],
  ["M1 depth 1", "M1_Depth_1"],
  ["M1 depth 2", "M1_Depth_2"],
  ["M1 depth 3", "M1_Depth_3"],
  ["M1 depth 4", "M1_Depth_4"],
  ["M1 target 1", "M1_Target_1"],
  ["M1 target 2", "M1_Target_2"],
  ["M1 target 3", "M1_Target_3"],
  ["M1 target 4", "M1_Target_4"],
  ["M2 attack", "M2_Attack"],
  ["M2 hold", "M2_Hold"],
  ["M2 decay 1", "M2_Decay1"],
  ["M2 breakpoint", "M2_Breakpoint"],
  ["M2 decay 2", "M2_Decay2"],
  ["M2 sustain", "M2_Sustain"],
  ["M2 release", "M2_Release"],
  ["M2 velo sens", "M2_VeloSens"],
  ["M2 depth 1", "M2_Depth_1"],
  ["M2 depth 2", "M2_Depth_2"],
  ["M2 depth 3", "M2_Depth_3"],
  ["M2 depth 4", "M2_Depth_4"],
  ["M2 target 1", "M2_Target_1"],
  ["M2 target 2", "M2_Target_2"],
  ["M2 target 3", "M2_Target_3"],
  ["M2 target 4", "M2_Target_4"],
  ["MIDI channel 1", "MIDI_Channel_1"],
  ["MIDI channel 2", "MIDI_Channel_2"],
  ["MIDI channel 3", "MIDI_Channel_3"],
  ["MIDI channel 4", "MIDI_Channel_4"],
  ["MIDI channel 5", "MIDI_Channel_5"],
  ["MIDI channel 6", "MIDI_Channel_6"],
  ["MIDI channel 7", "MIDI_Channel_7"],
  ["MIDI channel 8", "MIDI_Channel_8"],
  ["MIDI channel 9", "MIDI_Channel_9"],
  ["MIDI channel 10", "MIDI_Channel_10"],
  ["MIDI channel 11", "MIDI_Channel_11"],
  ["MIDI channel 12", "MIDI_Channel_12"],
  ["MIDI channel 13", "MIDI_Channel_13"],
  ["MIDI channel 14", "MIDI_Channel_14"],
  ["MIDI channel 15", "MIDI_Channel_15"],
  ["MIDI channel 16", "MIDI_Channel_16"],
  ["Sustain pedal", "SustainPedal"],
  ["CC 1", "CC1"],
  ["CC 1 depth 1", "CC1_Depth_1"],
  ["CC 1 depth 2", "CC1_Depth_2"],
  ["CC 1 depth 3", "CC1_Depth_3"],
  ["CC 1 depth 4", "CC1_Depth_4"],
  ["CC 1 target 1", "CC1_Target_1"],
  ["CC 1 target 2", "CC1_Target_2"],
  ["CC 1 target 3", "CC1_Target_3"],
  ["CC 1 target 4", "CC1_Target_4"],
  ["CC 2", "CC2"],
  ["CC 2 depth 1", "CC2_Depth_1"],
  ["CC 2 depth 2", "CC2_Depth_2"],
  ["CC 2 depth 3", "CC2_Depth_3"],
  ["CC 2 depth 4", "CC2_Depth_4"],
  ["CC 2 target 1", "CC2_Target_1"],
  ["CC 2 target 2", "CC2_Target_2"],
  ["CC 2 target 3", "CC2_Target_3"],
  ["CC 2 target 4", "CC2_Target_4"],
  ["CC 3", "CC3"],
  ["CC 3 depth 1", "CC3_Depth_1"],
  ["CC 3 depth 2", "CC3_Depth_2"],
  ["CC 3 depth 3", "CC3_Depth_3"],
  ["CC 3 depth 4", "CC3_Depth_4"],
  ["CC 3 target 1", "CC3_Target_1"],
  ["CC 3 target 2", "CC3_Target_2"],
  ["CC 3 target 3", "CC3_Target_3"],
  ["CC 3 target 4", "CC3_Target_4"],
  ["CC 4", "CC4"],
  ["CC 4 depth 1", "CC4_Depth_1"],
  ["CC 4 depth 2", "CC4_Depth_2"],
  ["CC 4 depth 3", "CC4_Depth_3"],
  ["CC 4 depth 4", "CC4_Depth_4"],
  ["CC 4 target 1", "CC4_Target_1"],
  ["CC 4 target 2", "CC4_Target_2"],
  ["CC 4 target 3", "CC4_Target_3"],
  ["CC 4 target 4", "CC4_Target_4"],
  ["CC 5", "CC5"],
  ["CC 5 depth 1", "CC5_Depth_1"],
  ["CC 5 depth 2", "CC5_Depth_2"],
  ["CC 5 depth 3", "CC5_Depth_3"],
  ["CC 5 depth 4", "CC5_Depth_4"],
  ["CC 5 target 1", "CC5_Target_1"],
  ["CC 5 target 2", "CC5_Target_2"],
  ["CC 5 target 3", "CC5_Target_3"],
  ["CC 5 target 4", "CC5_Target_4"],
  ["CC 6", "CC6"],
  ["CC 6 depth 1", "CC6_Depth_1"],
  ["CC 6 depth 2", "CC6_Depth_2"],
  ["CC 6 depth 3", "CC6_Depth_3"],
  ["CC 6 depth 4", "CC6_Depth_4"],
  ["CC 6 target 1", "CC6_Target_1"],
  ["CC 6 target 2", "CC6_Target_2"],
  ["CC 6 target 3", "CC6_Target_3"],
  ["CC 6 target 4", "CC6_Target_4"],
  ["Osc mix", "OscMix"]
];

// switch value names, read off the DLL status texts (index = stored value)
export const WAVEFORMS = Object.freeze(["Sine", "Saw", "Pulse", "Triangle", "User", "User PWM"]);
export const LFO_UNITS = Object.freeze(["ms", "10 ms", "sec", "4/5 16ths", "2/3 16ths", "16ths", "4/5 8ths", "2/3 8ths", "8ths", "4/5 quarter notes", "2/3 quarter notes", "quarter notes", "4/5 half notes", "2/3 half notes", "half notes", "4/5 whole notes", "2/3 whole notes", "whole notes"]);
export const LFO_SHAPES = Object.freeze(["Sine", "Saw", "Square", "Triangle", "Smooth random", "Stepping random", "User"]);
export const LFO_QUANTIZE = Object.freeze(["free speed", "quantize period"]);
export const LFO_MODES = Object.freeze(["per note", "global, reset on note", "global, free"]);
export const FILTER_TYPES = Object.freeze(["Off", "1P lowpass", "2P lowpass", "4P lowpass", "1P highpass", "2P highpass", "4P highpass", "2P wide bandpass", "2P narrow bandpass", "4P bandpass", "2P notch", "nonlinear 2P lowpass", "nonlinear 4P lowpass"]);
export const FILTER2_TYPES = Object.freeze(["same as filter 1", "1P lowpass", "2P lowpass", "4P lowpass", "1P highpass", "2P highpass", "4P highpass", "2P wide bandpass", "2P narrow bandpass", "4P bandpass", "2P notch", "nonlinear 2P lowpass", "nonlinear 4P lowpass"]);
export const FILTER_DOUBLE = Object.freeze(["off", "parallel", "serial"]);
export const CHORUS_MODES = Object.freeze(["off", "sine", "ramp", "FM", "irregular"]);
export const CHORUS_STEREO = Object.freeze(["mono", "stereo 1", "stereo 2"]);
export const DELAY_ON = Object.freeze(["off", "on"]);
export const DELAY_UNITS = Object.freeze(["ms", "10 ms", "sec", "4/5 16ths", "2/3 16ths", "16ths", "4/5 8ths", "2/3 8ths", "8ths", "4/5 quarter notes", "2/3 quarter notes", "quarter notes", "4/5 half notes", "2/3 half notes", "half notes"]);
export const DELAY_QUANTIZE = Object.freeze(["free length", "quantize length"]);
export const DELAY_REVERSE = Object.freeze(["normal", "reverse output", "reverse feedback"]);
export const REVERB_ON = Object.freeze(["off", "on"]);
export const VOICE_MODES = Object.freeze(["Monophonic", "Polyphonic", "Monophonic, legato"]);
export const GLIDE_MODES = Object.freeze(["Param", "P * octaves", "P / octaves", "P * (o + 1/o)", "P * (1 + o)", "P * (1 + 1/o)", "P * (1 + o + 1/o)"]);
export const AFTERTOUCH_MODES = Object.freeze(["ignore all", "channel", "polyphonic"]);
export const OFF_ON = Object.freeze(["off", "on"]);
export const ARP_MODES = Object.freeze(["off", "pattern", "pattern (global subseq)", "chord pattern", "chord", "transposed chords"]);
export const ARP_UNITS = Object.freeze(["ms", "10 ms", "sec", "4/5 32nds", "2/3 32nds", "32nds", "4/5 16ths", "2/3 16ths", "16ths", "4/5 8ths", "2/3 8ths", "8ths", "4/5 quarter notes", "2/3 quarter notes", "quarter notes", "4/5 half notes", "2/3 half notes", "half notes"]);
export const ARP_STEP_COMMANDS = Object.freeze(["off", "up", "up, no wrap", "down", "down, no wrap", "up or down", "up or down, no wrap", "continue", "continue direction", "continue direction, bounce", "return", "return, up", "return, down", "top", "bottom", "random"]);
export const DIST_TYPES = Object.freeze(["off", "hard clip", "soft clip", "sine", "asymmetric"]);
export const DIST_MODES = Object.freeze(["global", "per voice, after filter", "per voice, before filter", "double (before filter and global)"]);
export const DIST_OVERSAMPLE = Object.freeze(["off", "2x", "4x", "8x"]);
export const XY_TARGETS = Object.freeze(["none", "cutoff 1", "cutoff 2", "resonance", "filter env mod", "pitch", "pan", "distortion", "LFO 1 speed", "LFO 2 speed", "LFO 1 depth", "LFO 2 depth", "1 pulsewidth", "1 PWM rate", "1 PWM depth", "2 pulsewidth", "2 PWM rate", "2 PWM depth", "1 amp", "2 amp", "noise amp", "1 pitch", "2 pitch", "noise pitch", "filter mix", "noise resonance", "ME 1 depth", "ME 2 depth", "amp envelope speed", "filter envelope speed", "mod envelope speed", "pitch envelope speed", "Unison detune", "Unison spread"]);
export const EQ_TYPES = Object.freeze(["off", "peak/notch", "low shelf", "high shelf"]);
export const MOD_ENV_TARGETS = Object.freeze(["none", "cutoff 1", "cutoff 2", "resonance", "1 amp", "2 amp", "noise amp", "1 pitch", "2 pitch", "noise pitch", "1 pulsewidth", "1 PWM rate", "1 PWM depth", "2 pulsewidth", "2 PWM rate", "2 PWM depth", "pan", "noise resonance", "LFO 1 speed", "LFO 2 speed", "LFO 1 depth", "LFO 2 depth", "filter mix", "cutoff 1 (unipolar)", "cutoff 2 (unipolar)", "1 pitch (unipolar)", "2 pitch (unipolar)", "noise pitch (unipolar)", "XY depth", "Unison detune", "Unison spread"]);
export const MIDI_CHANNEL = Object.freeze(["ignore", "receive"]);
export const SUSTAIN_PEDAL = Object.freeze(["ignore", "use"]);
export const CC_TARGETS = Object.freeze(["none", "cutoff 1", "cutoff 2", "resonance", "filter env mod", "pitch", "pan", "distortion", "LFO 1 speed", "LFO 2 speed", "LFO 1 depth", "LFO 2 depth", "1 pulsewidth", "1 PWM rate", "1 PWM depth", "2 pulsewidth", "2 PWM rate", "2 PWM depth", "1 amp", "2 amp", "noise amp", "1 pitch", "2 pitch", "noise pitch", "filter mix", "noise resonance", "ME 1 depth", "ME 2 depth", "XY depth", "amp envelope speed", "filter envelope speed", "mod envelope speed", "pitch envelope speed", "Unison detune", "Unison spread"]);
export const OSC_MIX = Object.freeze(["normal", "hardsync", "FM (1 -> 2, 1 silent)"]);

/** getParameter() values of the Init program (as printed by the DLL, 6 decimals). */
const DEFAULT_NORMALIZED = [0.0, 0.666667, 0.5, 0.5, 0.0, 0.5, 0.0, 0.0, 0.5, 0.5, 0.0, 0.5, 0.625, 0.5, 0.5, 0.0, 0.5, 0.0, 0.5, 0.058824, 0.0, 0.383007, 0.0, 1.0, 0.5, 0.5, 0.0, 0.0, 0.0, 0.0, 0.058824, 0.0, 0.396078, 0.0, 1.0, 0.5, 0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 0.0, 0.021909, 0.0, 0.03874, 1.0, 0.222542, 0.899657, 0.044733, 0.5, 0.0, 0.5, 0.291667, 0.375, 0.5, 0.5, 0.5, 0.021909, 0.0, 0.03874, 1.0, 0.222542, 0.899657, 0.044733, 0.0, 0.0, 0.2, 0.068929, 0.039039, 0.079079, 0.5, 0.8, 0.0, 0.357143, 0.0, 0.0, 0.0, 0.020202, 0.020202, 0.675, 0.675, 0.5, 0.5, 0.7, 0.0, 0.666667, 0.645131, 0.0, 0.43679, 0.191805, 0.8, 0.2, 0.666667, 0.51134, 0.385, 0.125, 0.635, 0.86, 0.5, 0.5, 0.5, 0.225806, 0.0, 0.166667, 0.444444, 0.825, 1.0, 0.5, 0.5, 0.0, 0.223607, 0.028868, 0.0, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.014434, 0.25, 0.0, 0.0, 0.0, 0.470588, 1.0, 0.25, 0.066667, 0.0, 0.0, 0.066667, 0.0, 0.0, 0.066667, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.466667, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.0, 0.375, 0.044498, 0.625, 0.067099, 0.5, 0.5, 0.5, 0.0, 0.0, 0.5, 0.5, 0.5, 0.0, 0.5, 0.25, 0.5, 0.3125, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.707107, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 0.5, 0.5, 0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.366644, 0.366644, 0.366644, 0.366644, 0.366644, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.021909, 0.0, 0.03874, 1.0, 0.222542, 0.899657, 0.044733, 0.5, 0.5, 0.5, 0.5, 0.5, 0.0, 0.0, 0.0, 0.0, 0.021909, 0.0, 0.03874, 1.0, 0.222542, 0.899657, 0.044733, 0.5, 0.5, 0.5, 0.5, 0.5, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.0, 0.5, 0.5, 0.5, 0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 0.5, 0.5, 0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 0.5, 0.5, 0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 0.5, 0.5, 0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 0.5, 0.5, 0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 0.5, 0.5, 0.5, 0.0, 0.0, 0.0, 0.0, 0.0];

// ---------------------------------------------------------------------------------------------------
// numeric helpers (x87 emulation)

const f32 = Math.fround;
/** MSVC _ftol: truncation toward zero (the DLL always adds 0.5 first => round-half-up for v >= 0). */
const ftol = (x) => Math.trunc(x);
/** int32 wrap like the x87 fistp/_ftol low dword. */
const i32 = (x) => { const t = Math.trunc(x); return Number.isFinite(t) ? (t >>> 0) | 0 : -2147483648; };
const log10 = Math.log10;
const pow = Math.pow;
// float32 constants exactly as stored in Oatmeal.dll's .rdata
function fromBits(u) { const d = new DataView(new ArrayBuffer(4)); d.setUint32(0, u, true); return d.getFloat32(0, true); }
const K = {
  PI: f32(Math.PI), C005: f32(0.05), C1_12: f32(1 / 12), C1_1200: f32(1 / 1200), C0998: f32(0.998),
  C0001: f32(0.001), C101: f32(1.01), C001: f32(0.01), A_MUL: f32(9999.8), A_ADD: f32(0.2), CSPD: f32(3.999),
  CDEL: f32(99.9), C01: f32(0.1), RLEN: f32(29.9), ARPS: f32(41.3333333), RLEN_INV: fromBits(0x3d08fd6f),
};

// ---------------------------------------------------------------------------------------------------
// C printf subset (MSVC semantics for %.Nf: round half away from zero; "-" kept for negative zero)
function fixed(x, n) {
  if (Number.isNaN(x)) return (n > 0 ? '-1.#IND' : '-1') ;            // MSVC prints e.g. -1.#IND00 (not reproduced exactly)
  if (!Number.isFinite(x)) return (x < 0 ? '-' : '') + '1.#INF';
  const neg = x < 0 || Object.is(x, -0);
  return (neg ? '-' : '') + Math.abs(x).toFixed(n);
}
/** sprintf for the formats Oatmeal uses: %.Nf %i %d %03i %s %% */
export function cfmt(fmt, ...args) {
  let k = 0;
  return fmt.replace(/%(0?)(\d*)(?:\.(\d+))?([fids%])/g, (m, zero, width, prec, conv) => {
    if (conv === '%') return '%';
    const a = args[k++];
    let s;
    if (conv === 'f') s = fixed(a, prec === undefined ? 6 : +prec);
    else if (conv === 'i' || conv === 'd') s = String(a | 0);
    else s = String(a);
    if (width) {
      const w = +width;
      if (zero && (conv === 'i' || conv === 'd')) { const neg = s[0] === '-'; let body = neg ? s.slice(1) : s; while (body.length + (neg ? 1 : 0) < w) body = '0' + body; s = (neg ? '-' : '') + body; }
      else while (s.length < w) s = ' ' + s;
    }
    return s;
  });
}

// ---------------------------------------------------------------------------------------------------
// program access (little-endian)
const dv = (p) => new DataView(p.buffer, p.byteOffset, p.byteLength);
const rdF = (p, o) => dv(p).getFloat32(o, true);
const rdI = (p, o) => dv(p).getInt32(o, true);
const rdU = (p, o) => dv(p).getUint32(o, true);

/** Field offsets that some status texts read from the program. */
const OFF_OCTAVE = 9064, OFF_TUNE = 9060, OFF_CUTREF = 9072, OFF_FILTER = 8428, OFF_FDOUBLE = 8464;

// ---------------------------------------------------------------------------------------------------
// parameter specs
//  type: 'f32' float field, 'i32' int field, 'u32' (pulsewidth phase), 'lo16'/'hi16' (packed filter types)
//  set(v)   -> internal value, exactly as setParameter 0x10048260 computes it (v is taken as float32)
//  get(x)   -> DLL getParameter 0x1004c890 result (float32), including its quirks
//  inv(x)   -> mathematical inverse of set (the "proper" normalized value; clamped to [0,1] by toNormalized)
//  text(V, prog) -> DLL status-bar string (0x100405f0) for normalized V
//  labels   -> value names for switches (index = stored value, or stored-1 for the "+1" kinds)

const P = new Array(342);

function def(i, spec) { P[i] = Object.assign({ index: i, name: NAMES[i][0] || '', action: NAMES[i][1] }, spec); }

// generic builders ------------------------------------------------------------------------------------
/** bipolar linear: x = (2v-1)*s (+ add); DLL get = (x*f32(1/s) + 1)*0.5 (or (x+1)*0.5 when s==1) */
function bip(off, s, text, extra = {}) {
  const inv_s = f32(1 / s);
  return Object.assign({
    offset: off, type: 'f32', min: -s, max: s, unit: s === 1 ? 'bipolar -1..1' : '',
    set: (v) => f32((2 * v - 1) * s),
    get: (x) => f32(s === 1 ? (x + 1) * 0.5 : (x * inv_s + 1) * 0.5),
    inv: (x) => (x / s + 1) / 2,
    text,
  }, extra);
}
/** unipolar identity: x = v */
function uni(off, text, extra = {}) {
  return Object.assign({ offset: off, type: 'f32', min: 0, max: 1, unit: 'unipolar 0..1', set: (v) => f32(v), get: (x) => f32(x), inv: (x) => x, text }, extra);
}
/** square law: x = v*v*a + b ; DLL get = sqrt((x-b)*f32(1/a)) */
function sq(off, a, b, text, extra = {}) {
  const af = f32(a), bf = f32(b), ia = f32(1 / a);
  return Object.assign({
    offset: off, type: 'f32', min: bf, max: f32(af + bf),
    set: (v) => f32(v * v * af + bf),
    get: (x) => f32(Math.sqrt(bf === 0 ? x * ia : (x - bf) * ia)),
    inv: (x) => Math.sqrt(Math.max(0, (x - bf) / af)),
    text,
  }, extra);
}
/** amplitude in dB: v>0 ? 10^((90v-60)*0.05f) : 0 ; DLL get = x>0 ? (20*log10(x)+60)*f32(1/90) : 0 */
function amp(off, text, extra = {}) {
  const i90 = f32(1 / 90);
  return Object.assign({
    offset: off, type: 'f32', min: 0, max: f32(pow(10, 30 * K.C005)), unit: 'linear gain (-60..+30 dB, 0 = -inf)',
    set: (v) => (v > 0 ? f32(pow(10, (v * 90 - 60) * K.C005)) : 0),
    get: (x) => (x > 0 ? f32((log10(x) * 20 + 60) * i90) : 0),
    inv: (x) => (x > 0 ? (log10(x) / K.C005 + 60) / 90 : 0),
    text,
  }, extra);
}
/** envelope level (breakpoint/sustain): v != 0 ? 10^((v-1)*3) : 0 ; DLL get = x != 0 ? log10(x)*f32(1/3)+1 : 0 */
function lvl(off, text, extra = {}) {
  const i3 = f32(1 / 3);
  return Object.assign({
    offset: off, type: 'f32', min: 0, max: 1,
    set: (v) => (v !== 0 ? f32(pow(10, (v - 1) * 3)) : 0),
    // getParameter reads the LIVE program copy, in which the envelope coefficient update (0x100522a0) has
    // replaced breakpoint/sustain values > 0.998 by exactly 1.0 -> emulate that here
    get: (x) => { if (x > K.C0998) x = 1; return x !== 0 ? f32(log10(x) * i3 + 1) : 0; },
    inv: (x) => (x > 0 ? log10(x) / 3 + 1 : 0),
    text,
  }, extra);
}
/** switch: x = ftol(n*v + 0.5) + add ; DLL get = (x-add) * f32(1/n) (n==1: x) */
function sw(off, n, labels, text, extra = {}) {
  const add = extra.add || 0, inv_n = f32(1 / n);
  return Object.assign({
    offset: off, type: 'i32', min: add, max: n + add, states: n + 1, labels,
    set: (v) => i32(n * v + 0.5) + add,
    get: (x) => (n === 1 ? f32(x) : f32((x - add) * inv_n)),
    inv: (x) => (x - add) / n,
    text,
  }, extra);
}
/** status text of a plain enum: prefix + labels[ftol(n*V+0.5)] ('' when out of range, like the DLL) */
const enumText = (prefix, n, labels) => (V) => { const k = ftol(n * V + 0.5); return k >= 0 && k < labels.length && labels[k] !== undefined ? prefix + labels[k] : ''; };
const fmtText = (fmt, fn) => (V, prog) => cfmt(fmt, fn(V, prog));
const pct = (label) => fmtText(label + ': %.2f %%', (V) => V * 100);

// shared text functions ------------------------------------------------------------------------------
const ampText = (label) => (V) => (V > 0 ? cfmt(label + ': %.2f dB', V * 90 - 60) : label + ': -inf dB');
const dryWetText = (label) => (V) => (V !== 0 ? cfmt(label + ': %.2f dB', V * 90 - 60) : label + ': -inf dB');
const attackText = (V) => cfmt('Attack: %.2f ms', V * V * K.A_MUL + K.A_ADD);
const holdText = (V) => cfmt('Hold: %.2f ms', V * V * 10000);
const decay2Text = (V) => cfmt('Decay 2: %.2f ms', V * V * 19990 + 10);
const releaseText = (V) => cfmt('Release: %.2f ms', V * V * 19990 + 10);
const decay1Text = (bpOff) => (V, prog) => (rdF(prog, bpOff) > K.C0998 ? 'Decay 1: skip (breakpoint is 0 dB)' : cfmt('Decay 1: %.2f ms', V * V * 19990 + 10));
/** filter/mod env breakpoint and sustain (percent display) */
const lvlPctText = (label, skip) => (V) => {
  if (V === 0) return cfmt(label + ': %.2f %%', 0);
  const b = pow(10, (V - 1) * 3);
  return b > K.C0998 ? skip : cfmt(label + ': %.2f %%', b * 100);
};
/** amp env breakpoint / sustain (dB + percent display) */
const lvlDbText = (label, skip) => (V) => {
  if (V !== 0 && pow(10, (V - 1) * 3) > K.C0998) return skip;
  if (!(V > 0)) return label + ': -inf dB (0.00 %)';
  const t = f32(V - 1);
  return cfmt(label + ': %.2f dB (%.2f %%)', t * 60, pow(10, t * 3) * 100);
};
/** transposition with ratio (Transpose, N transpose, Arp note shift): t = f32(2V-1) */
const ratioText = (fmtMul, fmtDiv, st, octs, lead) => (V, prog) => {
  const t = f32(2 * V - 1), oct = rdF(prog, OFF_OCTAVE);
  const pre = lead ? [lead(V)] : [];
  return V < 0.5 ? cfmt(fmtDiv, ...pre, t * st, pow(oct, t * -octs)) : cfmt(fmtMul, ...pre, t * st, pow(oct, t * octs));
};
/** LFO speed / arp step with "units" (quantized display when the quantize field is on) */
const unitsText = (label, qOff, speed) => (V, prog) => {
  const s = speed(V);
  if (rdI(prog, qOff) !== 0) return 3 * s < 2 ? cfmt(label + ': 1/%i units', ftol(1 / s + 0.5)) : cfmt(label + ': %i units', ftol(s + 0.5));
  return s < 1 ? cfmt(label + ': 1/%.3f units', 1 / s) : cfmt(label + ': %.3f units', s);
};
const lfoSpeed = (V) => (3 * V < 1 ? 1 / (4 - V * 9) : (V * 1.5 - 0.5) * 255 + 1);
const arpStep = (V) => (V <= 0.25 ? 1 / ((1 - V * 4) * 7 + 1) : (V - 0.25) * K.ARPS + 1);
/** mod depth with unit chosen by the corresponding target (XY / M1,M2 / CC tables) */
function depthText(prefix, centsPrefix, tgtOff, unitOf, octScale) {
  return (V, prog) => {
    const t = rdI(prog, tgtOff), x = 2 * V - 1;
    switch (unitOf(t)) {
      case 'dB': return cfmt(prefix + '%.2f dB', x * 60);
      case 'st': return cfmt(prefix + '%.2f semitones', x * 24);
      case 'oct': return cfmt(prefix + '%.3f octaves', x * octScale);
      case 'cents': return cfmt(centsPrefix + '%.2f cents', x * Math.abs(x) * 1200);
      default: return cfmt(prefix + '%.2f %%', x * 100);
    }
  };
}
/** depth display unit per target (read off the DLL's byte tables 0x10046934 / 0x10046ab8 / 0x10046b64 / 0x10046c28) */
export const DEPTH_UNITS = Object.freeze({
  XY: Object.freeze({ 1: 'oct', 2: 'oct', 5: 'st', 18: 'dB', 19: 'dB', 20: 'dB', 21: 'st', 22: 'st', 23: 'st', 32: 'cents' }),
  ENV: Object.freeze({ 1: 'oct', 2: 'oct', 7: 'st', 8: 'st', 9: 'st', 23: 'oct', 24: 'oct', 25: 'st', 26: 'st', 27: 'st', 29: 'cents' }),
  CC: Object.freeze({ 1: 'oct', 2: 'oct', 21: 'st', 22: 'st', 23: 'st', 33: 'cents' }),
});
const unitXY = (t) => DEPTH_UNITS.XY[t] || '%', unitEnv = (t) => DEPTH_UNITS.ENV[t] || '%', unitCC = (t) => DEPTH_UNITS.CC[t] || '%';

// ---------------------------------------------------------------------------------------------------
// the 342 parameters

for (const [o, n] of [[0, 1], [6, 2]]) {
  const b = n === 1 ? 0 : 1;                                       // osc 2 fields are 4 bytes after osc 1
  def(o + 0, sw(8468 + 4 * b, 5, WAVEFORMS, enumText(`${n} Waveform: `, 5, WAVEFORMS)));
  def(o + 1, amp(8508 + 4 * b, ampText(`${n} Amp`)));
  def(o + 2, bip(8476 + 4 * b, 48, fmtText(`Aftertouch -> ${n} pitch: %.2f semitones`, (V) => (2 * V - 1) * 48), { unit: 'semitones' }));
  def(o + 3, {
    offset: 8484 + 4 * b, type: 'u32', min: 0, max: 4294967295,
    set: (v) => (Math.trunc(pow(2, 32) * v + 0.5) >>> 0),              // uint32 phase; v=1 wraps to 0 (DLL quirk)
    get: (x) => f32((x >>> 0) * pow(2, -32)),
    inv: (x) => (x >>> 0) / 4294967296,
    text: fmtText(`${n} Pulsewidth: %.2f %%`, (V) => V * 100), unit: '% (uint32 fraction of 2^32)',
  });
  def(o + 4, {
    offset: 8500 + 4 * b, type: 'f32', min: 0, max: 8, unit: 'Hz',
    set: (v) => f32(v * 8), get: (x) => f32(x * 0.0625),               // QUIRK: getParameter returns x/16 = v/2
    inv: (x) => x / 8,
    text: fmtText(`${n} PWM rate: %.3f Hz`, (V) => V * 16),
  });
  def(o + 5, bip(8492 + 4 * b, 1, fmtText(`${n} PWM depth: %.2f %%`, (V) => (2 * V - 1) * 100)));
}
def(12, bip(8516, 4, ratioText('Transpose: %.2f st (*%.4f)', 'Transpose: %.2f st (/%.4f)', 48, 4), { unit: 'octaves (display: semitones = 12*x)' }));
def(13, bip(8520, 50, fmtText('Detune: %.3f Hz', (V) => (2 * V - 1) * 50), { unit: 'Hz' }));
def(14, bip(8524, 60, fmtText('Aftertouch -> osc: %.2f dB', (V) => (2 * V - 1) * 60), { unit: 'dB' }));
def(15, amp(8528, ampText('N Amp')));
def(16, bip(8532, 60, fmtText('Aftertouch -> noise: %.2f dB', (V) => (2 * V - 1) * 60), { unit: 'dB' }));
def(17, uni(8540, (V) => (V > 0 || Number.isNaN(V) ? cfmt('Noise resonance: %.2f %%', V * 100) : 'Noise resonance: no filtering')));
def(18, bip(8536, 48, ratioText('Noise transpose: %.2f st (*%.4f)', 'Noise transpose: %.2f st (/%.4f)', 48, 4), { unit: 'semitones' }));

for (const [base, n, offs] of [[19, 1, { unit: 8544, shape: 8548, speed: 8556, quant: 9520, mode: 8552, c1: 8560, c2: 8564, res: 8568, pitch: 8572, pan: 9224, other: 8576 }],
                               [30, 2, { unit: 8580, shape: 8584, speed: 8592, quant: 9524, mode: 8588, c1: 8596, c2: 8600, res: 8604, pitch: 8608, pan: 9228, other: 8612 }]]) {
  const L = `L${n}`;
  def(base + 0, sw(offs.unit, 17, LFO_UNITS, enumText(`LFO ${n} unit: `, 17, LFO_UNITS)));
  def(base + 1, sw(offs.shape, 6, LFO_SHAPES, enumText(`${L} shape: `, 6, LFO_SHAPES)));
  def(base + 2, {
    offset: offs.speed, type: 'f32', min: 0.25, max: 256, unit: 'units (periods per unit, see LFO unit)',
    set: (v) => f32(3 * v < 1 ? 1 / (4 - v * 9) : (v * 1.5 - 0.5) * 255 + 1),
    get: (x) => f32(x <= 1 ? (4 - 1 / x) * f32(1 / 9) : ((x - 1) * f32(1 / 255) + 0.5) * f32(2 / 3)),
    inv: (x) => (x <= 1 ? (4 - 1 / x) / 9 : ((x - 1) / 255 + 0.5) / 1.5),
    text: unitsText(`${L} speed`, offs.quant, lfoSpeed),
  });
  def(base + 3, sw(offs.quant, 1, LFO_QUANTIZE, enumText(`${L}: `, 1, LFO_QUANTIZE)));
  def(base + 4, sw(offs.mode, 2, LFO_MODES, enumText(`${L} mode: `, 2, LFO_MODES)));
  def(base + 5, bip(offs.c1, 1, fmtText(`${L} -> cutoff 1: %.4f octaves`, (V) => (2 * V - 1) * 4), { unit: 'x4 octaves' }));
  def(base + 6, bip(offs.c2, 1, fmtText(`${L} -> cutoff 2: %.4f octaves`, (V) => (2 * V - 1) * 4), { unit: 'x4 octaves' }));
  def(base + 7, uni(offs.res, pct(`${L} -> resonance`)));
  def(base + 8, uni(offs.pitch, fmtText(`${L} -> pitch: %.3f st`, (V) => V * V * V * V * 24), { unit: 'st = 24*x^4' }));
  def(base + 9, uni(offs.pan, pct(`${L} -> pan`)));
  def(base + 10, uni(offs.other, pct(n === 1 ? 'L1 -> L2 speed' : 'L2 -> L1 speed')));
}

def(41, Object.assign(sw(OFF_FILTER, 15, FILTER_TYPES, enumText('Filter: ', 15, FILTER_TYPES)), { type: 'lo16', states: 13, max: 12 }));
def(42, Object.assign(sw(OFF_FILTER, 15, FILTER2_TYPES, (V, prog) => {
  if ((rdU(prog, OFF_FILTER) & 0xffff) === 0 || rdI(prog, OFF_FDOUBLE) === 0) return 'Filter 2: off (filter 1 and doubling needs to be on)';
  return enumText('Filter 2: ', 15, FILTER2_TYPES)(V);
}), { type: 'hi16', states: 13, max: 12 }));
def(43, {
  offset: 8432, type: 'f32', min: 0, max: 1, unit: 'normalized (Hz = v^3*10980+20)',
  set: (v) => f32(v), get: (x) => f32(x), inv: (x) => x,
  text: (V, prog) => {
    const hz = f32(V * V * V * 10980 + 20);
    const ref = pow(rdF(prog, OFF_OCTAVE), rdF(prog, OFF_CUTREF) * K.C1_12) * rdF(prog, OFF_TUNE);
    return hz < ref ? cfmt('Cutoff: %.2f Hz (/%.4f)', hz, ref / hz) : cfmt('Cutoff: %.2f Hz (*%.4f)', hz, hz / ref);
  },
});
def(44, uni(8436, pct('Resonance')));

// envelopes: filter (45..51), amp (60..66), mod 1 (238..244), mod 2 (254..260)
const ENVS = [
  { a: 45, off: 8300, kind: 'pct', bpParam: 48 },
  { a: 60, off: 8232, kind: 'db', bpParam: 63 },
  { a: 238, off: 9312, kind: 'pct', bpParam: 241 },
  { a: 254, off: 9408, kind: 'pct', bpParam: 257 },
];
for (const e of ENVS) {
  const o = e.off;
  def(e.a + 0, sq(o + 4, 9999.8, 0.2, attackText, { unit: 'ms' }));
  def(e.a + 1, sq(o + 8, 10000, 0, holdText, { unit: 'ms' }));
  def(e.a + 2, sq(o + 12, 19990, 10, decay1Text(o + 44), { unit: 'ms' }));
  def(e.a + 3, lvl(o + 44, e.kind === 'db' ? lvlDbText('Breakpoint', 'Breakpoint: skip decay 1') : lvlPctText('Breakpoint', 'Breakpoint: skip decay 1')));
  def(e.a + 4, sq(o + 16, 19990, 10, decay2Text, { unit: 'ms' }));
  def(e.a + 5, lvl(o + 52, e.kind === 'db' ? lvlDbText('Sustain', 'Sustain: 0.00 dB (100.00 %)') : lvlPctText('Sustain', 'Sustain: 100.00 %')));
  def(e.a + 6, sq(o + 20, 19990, 10, releaseText, { unit: 'ms', offset2: o + 24, note: 'also writes offset+4 = release*0.5' }));
}
def(52, {
  offset: 8444, type: 'f32', min: -2, max: 2, unit: 'keytrack factor (snapped to -1/0/1 within 0.001)',
  set: (v) => f32(keytrack(v)), get: (x) => f32((x * 0.5 + 1) * 0.5), inv: (x) => (x + 2) / 4,
  text: (V) => cfmt('Keytrack: %.4f', keytrack(V)),
});
function keytrack(v) {
  let x = v * 4 - 2;
  if (Math.abs(1 - x) < K.C0001) x = 1;
  if (Math.abs(1 + x) < K.C0001) x = -1;
  if (Math.abs(x) < K.C0001) x = 0;
  return x;
}
def(53, sw(8464, 2, FILTER_DOUBLE, enumText('Double filter: ', 2, FILTER_DOUBLE)));
def(54, uni(8456, pct('Filter mix')));
def(55, uni(8448, fmtText('Split: %.2f st', (V) => V * 24), { unit: 'x24 semitones' }));
def(56, {
  offset: 8452, type: 'f32', min: 0.2, max: 5, unit: 'filter-2 env time factor',
  set: (v) => f32(v > 0.5 ? 1 / ((v - 0.5) * 8 + 1) : (0.5 - v) * 8 + 1),
  // QUIRK: for x < 1 (v > 0.5) the DLL returns v-1 (negative) instead of v
  get: (x) => f32(x < 1 ? (1 / x - 1) * 0.125 - 0.5 : 0.5 - (x - 1) * 0.125),
  inv: (x) => (x < 1 ? (1 / x - 1) / 8 + 0.5 : 0.5 - (x - 1) / 8),
  text: (V) => (V < 0.5 ? cfmt('Env ratio: /%.3f', (0.5 - V) * 8 + 1) : cfmt('Env ratio: *%.3f', (V - 0.5) * 8 + 1)),
});
def(57, bip(8440, 1, fmtText('Env Mod: %.3f octaves', (V) => (2 * V - 1) * 8), { unit: 'x8 octaves' }));
const veloText = fmtText('Env velocity sensitivity: %.2f %%', (V) => (2 * V - 1) * 100);
def(58, bip(9512, 1, veloText));
def(59, bip(8460, 48, fmtText('Aftertouch -> cutoff: %.2f semitones', (V) => (2 * V - 1) * 48), { unit: 'semitones' }));

def(67, sw(8616, 4, CHORUS_MODES, enumText('Chorus mode: ', 4, CHORUS_MODES)));
def(68, sw(8620, 2, CHORUS_STEREO, enumText('Chorus mode: ', 2, CHORUS_STEREO)));
def(69, sw(8624, 15, null, (V) => cfmt('Chorus: %i voices', ftol(15 * V + 0.5) + 1), { add: 1, unit: 'voices' }));
def(70, sq(8628, 3.999, 0.001, (V) => cfmt('Chorus speed: %.4f Hz', V * V * K.CSPD + K.C0001), { unit: 'Hz' }));
for (const [i, off, lab] of [[71, 8632, 'Chorus min delay'], [72, 8636, 'Chorus depth']]) {
  def(i, {
    offset: off, type: 'f32', min: K.C01, max: f32(K.CDEL + K.C01), unit: 'ms',
    set: (v) => f32(v * K.CDEL + K.C01), get: (x) => f32((x - K.C01) * f32(1 / 99.9)), inv: (x) => (x - K.C01) / K.CDEL,
    text: (V) => cfmt(lab + ': %.2f ms', V * K.CDEL + K.C01),
  });
}
def(73, bip(8644, 1, fmtText('Chorus feedback: %.2f %%', (V) => V * 200 - 100)));
def(74, uni(8640, fmtText('Chorus mix: %.2f %% wet', (V) => V * 100)));
def(75, sw(8648, 1, DELAY_ON, enumText('Delay: ', 1, DELAY_ON)));
def(76, sw(8652, 14, DELAY_UNITS, enumText('Delay unit: ', 14, DELAY_UNITS)));
def(77, sw(8656, 1, DELAY_QUANTIZE, enumText('Delay: ', 1, DELAY_QUANTIZE)));
def(78, sw(8660, 2, DELAY_REVERSE, enumText('Delay, left: ', 2, DELAY_REVERSE)));
def(79, sw(8664, 2, DELAY_REVERSE, enumText('Delay, right: ', 2, DELAY_REVERSE)));
for (const [i, off, lab] of [[80, 8676, 'Left length'], [81, 8684, 'Right length']]) {
  def(i, {
    offset: off, type: 'f32', min: 1, max: 100, unit: 'delay units',
    set: (v) => f32(v * 99 + 1), get: (x) => f32((x - 1) * f32(1 / 99)), inv: (x) => (x - 1) / 99,
    text: (V, prog) => { const L = V * 99 + 1; return rdI(prog, 8656) !== 0 ? cfmt(lab + ': %i units', ftol(L + 0.5)) : cfmt(lab + ': %.3f units', L); },
  });
}
for (const [i, off, lab] of [[82, 8680, 'Left feedback'], [83, 8688, 'Right feedback']]) {
  def(i, {
    offset: off, type: 'f32', min: -2, max: 2, unit: 'linear feedback gain',
    set: (v) => f32(v * 4 - 2), get: (x) => f32((x + 2) * 0.25), inv: (x) => (x + 2) / 4,
    text: (V) => {
      const x = V * 4 - 2;
      const small = V < 0.5 ? !(x <= -K.C0001) : x < K.C0001;
      return small ? cfmt(lab + ': %.1f %% (-60.00+ dB)', x * 100) : cfmt(lab + ': %.1f %% (%.2f dB)', x * 100, log10(Math.abs(x)) * 20);
    },
  });
}
def(84, uni(8668, (V) => cfmt('Input pan: %.1f %% %s', Math.abs(V * 200 - 100), V > 0.5 ? 'right' : 'left')));
const rotText = (lab) => fmtText(lab + ': %.3f Pi', (V) => 2 * V - 1);
const rot = (off, lab) => ({
  offset: off, type: 'f32', min: -K.PI, max: K.PI, unit: 'radians',
  set: (v) => f32((2 * v - 1) * K.PI), get: (x) => f32((x / K.PI + 1) * 0.5), inv: (x) => (x / K.PI + 1) / 2, text: rotText(lab),
});
def(85, rot(8672, 'Rotation'));
def(86, uni(8692, fmtText('Lowpass: %.1f %%', (V) => V * 100)));
def(87, uni(8696, fmtText('Highpass: %.1f %%', (V) => V * 100)));
def(88, amp(8700, dryWetText('Dry')));
def(89, amp(8704, dryWetText('Wet')));
def(90, sw(8708, 1, REVERB_ON, enumText('Reverb: ', 1, REVERB_ON)));
def(91, {
  offset: 8712, type: 'f32', min: 10, max: 250, unit: 'size',
  set: (v) => f32(v * v * v * 240 + 10), get: (x) => f32(pow((x - 10) * (1 / 240), 1 / 3)), inv: (x) => Math.cbrt((x - 10) / 240),
  text: (V) => cfmt('Size: %.1f', V * V * V * 240 + 10),
});
def(92, {
  offset: 8716, type: 'f32', min: K.C01, max: 120, unit: 'sec (120 = infinite)',
  set: (v) => (v === 1 ? 120 : f32(v * v * K.RLEN + K.C01)),
  get: (x) => (x < 30 ? f32(Math.sqrt((x - K.C01) * K.RLEN_INV)) : 1),   // DLL constant is f32(1/29.9)+1ulp
  inv: (x) => (x >= 30 ? 1 : Math.sqrt(Math.max(0, (x - K.C01) / K.RLEN))),
  text: (V) => (V < 1 || Number.isNaN(V) ? cfmt('Length: %.2f sec', V * V * K.RLEN + K.C01) : 'Length: ETERNITY.'),
});
def(93, uni(8720, fmtText('Dullness: %.1f %%', (V) => V * 100)));
def(94, uni(8724, fmtText('Brightness: %.1f %%', (V) => V * 100)));
def(95, amp(8728, dryWetText('Dry')));
def(96, amp(8732, dryWetText('Wet')));
def(97, rot(8736, '1'));
def(98, rot(8740, '2'));
def(99, rot(8744, '3'));
def(100, rot(8748, 'Rotation'));
def(101, bip(8752, 500, fmtText('Predelay: %.1f ms', (V) => (2 * V - 1) * 500), { unit: 'ms' }));
def(102, uni(8756, fmtText('Early reflections mix: %.1f %%', (V) => V * 100)));
def(103, sw(8760, 2, VOICE_MODES, enumText('', 2, VOICE_MODES)));
def(104, sw(8764, 31, null, (V) => cfmt('Voices: %i', ftol(31 * V + 0.5) + 1), { add: 1, unit: 'voices' }));
def(105, sq(8768, 500, 0, (V) => cfmt('Glide: %.2f ms', V * V * 500), { unit: 'ms' }));
def(106, sw(8772, 6, GLIDE_MODES, enumText('Glide mode: ', 6, GLIDE_MODES)));
def(107, amp(8776, ampText('Gain')));
def(108, bip(8780, 1, fmtText('Velocity: %.1f %%', (V) => V * 200 - 100)));
def(109, sw(8784, 2, AFTERTOUCH_MODES, enumText('Aftertouch mode: ', 2, AFTERTOUCH_MODES)));
def(110, bip(8788, 1, fmtText('Frequency pan: %.2f %%/octave', (V) => (2 * V - 1) * 100)));
def(111, bip(8792, 1, fmtText('Frequency env scale: %.2f %%/octave', (V) => (2 * V - 1) * 200)));
def(112, uni(8796, pct('Random pan')));
def(113, sq(8800, 20, 0, (V) => cfmt('Random amp: %.2f dB', V * V * 20), { unit: 'dB' }));
def(114, sq(8804, 1200, 0, (V) => cfmt('Random frequency: %.2f cents', V * V * 1200), { unit: 'cents' }));
const onOffText = (label) => (V) => label + (ftol(V + 0.5) !== 0 ? 'on' : 'off');
def(115, uni(8808, pct('Osc phase')));
def(116, uni(8812, pct('Osc phase random')));
def(117, sw(8816, 1, OFF_ON, onOffText('Osc retrigger: ')));
def(118, uni(8820, pct('PWM phase')));
def(119, uni(8824, pct('PWM phase random')));
def(120, sw(8828, 1, OFF_ON, onOffText('PWM retrigger: ')));
def(121, uni(8832, pct('LFO phase')));
def(122, uni(8836, pct('LFO phase random')));
def(123, sw(8840, 1, OFF_ON, onOffText('LFO retrigger: ')));
def(124, sw(10328, 15, null, (V) => cfmt('U voices: %i', ftol(15 * V + 0.5) + 1), { add: 1, unit: 'voices' }));
def(125, sq(10332, 4800, 0, (V) => cfmt('U detune: %.2f cents', V * V * 4800), { unit: 'cents' }));
def(126, uni(10336, pct('U stereo spread')));
def(127, uni(10340, pct('U pitch jitter')));
def(128, uni(10344, pct('U pan jitter')));
def(129, sw(8844, 5, ARP_MODES, enumText('Arp mode: ', 5, ARP_MODES)));
def(130, sw(8848, 17, ARP_UNITS, enumText('Arp unit: ', 17, ARP_UNITS)));
def(131, sw(8852, 1, OFF_ON, enumText('Quantize: ', 1, OFF_ON)));
def(132, {
  offset: 8856, type: 'f32', min: 0.125, max: 32, unit: 'arp units per step',
  set: (v) => f32(v <= 0.25 ? 1 / ((1 - v * 4) * 7 + 1) : (v - 0.25) * K.ARPS + 1),
  get: (x) => (x < 1 ? (x <= 0 ? 0 : f32((1 - (1 / x - 1) * f32(1 / 7)) * 0.25)) : f32((x - 1) * f32(0.75 / 31) + 0.25)),
  inv: (x) => (x < 1 ? (x <= 0 ? 0 : (1 - (1 / x - 1) / 7) * 0.25) : (x - 1) / K.ARPS + 0.25),
  text: unitsText('Arp step', 8852, arpStep),
});
for (let k = 1; k <= 16; k++) {
  const i = 132 + k;
  def(i, sw(4 * i + 8328, 15, ARP_STEP_COMMANDS, enumText(`Arp step ${k}: `, 15, ARP_STEP_COMMANDS)));
}
def(149, sw(8924, 15, null, (V) => { const n = ftol(15 * V + 0.5); return n === 0 ? 'Arp pattern length: 1 step' : cfmt('Arp pattern length: %i steps', n + 1); }, { unit: 'steps-1' }));
for (let k = 1; k <= 7; k++) {
  def(149 + k, sw(4 * (149 + k) + 8328, 1, OFF_ON, (V) => cfmt('Arp note %i: %s', k, V > 0.5 ? 'on' : 'off')));
  def(156 + k, bip(4 * (156 + k) + 8328, 36, ratioText('Arp note %i: %.3f st (*%.4f)', 'Arp note %i: %.3f st (/%.4f)', 36, 3, () => k), { unit: 'semitones' }));
}
def(164, sw(8984, 1, OFF_ON, (V) => (V > 0.5 ? 'Pitch envelope: on' : 'Pitch envelope: off')));
def(165, bip(8988, 48, (V) => (V !== 0 ? cfmt('Start: %.2f st', (2 * V - 1) * 48) : 'Start: -inf st'), { unit: 'semitones (<= -48: no start offset)' }));
def(166, sq(8996, 9999.8, 0.2, attackText, { unit: 'ms' }));
def(167, bip(9004, 48, fmtText('Peak: %.2f st', (V) => (2 * V - 1) * 48), { unit: 'semitones' }));
def(168, sq(9012, 19990, 10, (V) => cfmt('Decay: %.2f ms', V * V * 19990 + 10), { unit: 'ms' }));
def(169, bip(9020, 48, fmtText('Sustain: %.2f st', (V) => (2 * V - 1) * 48), { unit: 'semitones' }));
def(170, bip(9028, 48, fmtText('Release: %.2f st/sec', (V) => (2 * V - 1) * 48), { unit: 'semitones/sec' }));
def(171, bip(9516, 1, veloText));
def(172, sw(9036, 4, DIST_TYPES, enumText('Distortion: ', 4, DIST_TYPES)));
def(173, sw(9040, 3, DIST_MODES, enumText('Distortion: ', 3, DIST_MODES)));
def(174, bip(9044, 30, fmtText('Distortion limit: %.2f dB', (V) => (2 * V - 1) * 30), { unit: 'dB' }));
def(175, bip(9048, 60, fmtText('Distortion pregain: %.2f dB', (V) => (2 * V - 1) * 60), { unit: 'dB' }));
def(176, bip(9052, 60, fmtText('Distortion postgain: %.2f dB', (V) => (2 * V - 1) * 60), { unit: 'dB' }));
def(177, sw(9056, 3, DIST_OVERSAMPLE, enumText('Distortion oversample: ', 3, DIST_OVERSAMPLE)));
def(178, {
  offset: 9060, type: 'f32', min: 360, max: 520, unit: 'Hz',
  set: (v) => f32((2 * v - 1) * 80 + 440), get: (x) => f32(((x - 440) * f32(1 / 80) + 1) * 0.5), inv: (x) => ((x - 440) / 80 + 1) / 2,
  text: fmtText('Tune: %.2f Hz', (V) => (2 * V - 1) * 80 + 440),
});
function octaveOf(v) {
  let o = v * 4 + 1;
  if (o < K.C101) o = K.C101;
  if (Math.abs(2 - o) < K.C001) o = 2;
  return o;
}
def(179, {
  offset: 9064, type: 'f32', min: K.C101, max: 5, unit: 'frequency ratio of an "octave" (2 = normal)',
  set: (v) => f32(octaveOf(v)), get: (x) => f32((x - 1) * 0.25), inv: (x) => (x - 1) / 4,
  text: (V) => {
    const o = octaveOf(V), semis = 12 * Math.LN2 / Math.log(o);
    return semis > 96 || Number.isNaN(semis) ? cfmt('Octave: %.6f (x2 > 96.0000 semitones)', o) : cfmt('Octave: %.6f (x2 = %.4f semitones)', o, semis);
  },
});
const refText = (label) => (V, prog) => { const t = f32(2 * V - 1); return cfmt(label + ': %.2f st (%.2f Hz)', t * 24, pow(rdF(prog, OFF_OCTAVE), t * 2) * rdF(prog, OFF_TUNE)); };
def(180, bip(9072, 24, refText('Cutoff reference frequency'), { unit: 'semitones' }));
def(181, bip(9076, 24, refText('Pan center frequency'), { unit: 'semitones' }));
const NOTES = ['C', 'C#/Db', 'D', 'D#/Eb', 'E', 'F', 'F#/Gb', 'G', 'G#/Ab', 'A', 'A#/Bb', 'B'];
for (let k = 0; k < 12; k++) {
  const i = 182 + k;
  def(i, bip(4 * i + 8352, 200, (V, prog) => {
    const c = f32((2 * V - 1) * 200);
    return cfmt(`Tune ${NOTES[k]}: %.2f cents (*%.4f)`, c, pow(rdF(prog, OFF_OCTAVE), (k ? c + 100 * k : c) * K.C1_1200));
  }, { unit: 'cents' }));
}
def(194, sq(9128, 24, 0, (V) => cfmt('Pitch bend range: %.2f st', V * V * 24), { unit: 'semitones' }));
def(195, {
  offset: 9132, type: 'f32', min: -4, max: 4, unit: 'octaves (quantized to semitones)',
  set: (v) => f32(Math.floor((2 * v - 1) * 48 + 0.5) * K.C1_12), get: (x) => f32((x * 0.25 + 1) * 0.5), inv: (x) => (x / 4 + 1) / 2,
  text: (V) => cfmt('Global transpose: %.0f st', Math.floor((2 * V - 1) * 48 + 0.5)),
});
def(196, bip(9136, 1, fmtText('X: %.4f', (V) => 2 * V - 1)));
def(197, bip(9140, 1, fmtText('Y: %.4f', (V) => 2 * V - 1)));
for (const [base, L, tgt0, cc] of [[198, 'X', 9160, 9176], [207, 'Y', 9196, 9212]]) {
  for (let k = 1; k <= 4; k++) {
    def(base + k - 1, bip(4 * (base + k - 1) + 8352, 1, depthText(`${L} mod depth ${k}: `, `${L} mod depth ${k}: `, tgt0 + 4 * (k - 1), unitXY, 4)));
    def(base + 3 + k, sw(4 * (base + 3 + k) + 8352, 33, XY_TARGETS, (V) => {
      const t = ftol(33 * V + 0.5);
      if (t < 0 || t > 33) return '';
      return cfmt(`${L === 'Y' && t === 26 ? 'y' : L} mod target %i: ${XY_TARGETS[t]}`, k);   // DLL typo "y mod target"
    }));
  }
  def(base + 8, sw(cc, 127, null, (V) => (V > 0 ? cfmt(`${L} CC: %03i`, ftol(127 * V + 0.5)) : `${L} CC: ---`), { unit: 'MIDI CC number (0 = none)' }));
}
def(216, uni(9216, fmtText('XY random radius: %.4f', (V) => V)));
def(217, {
  offset: 9220, type: 'f32', min: 0, max: 16, unit: 'Hz',
  set: (v) => f32(v * 16), get: (x) => f32(x * 0.0625), inv: (x) => x / 16, text: fmtText('XY random rate: %.4f Hz', (V) => V * 16),
});
for (let k = 1; k <= 5; k++) {
  def(217 + k, {
    offset: 4 * (217 + k) + 8360, type: 'f32', min: 15, max: 20000, unit: 'Hz',
    set: (v) => f32(v * v * v * 19985 + 15), get: (x) => f32(pow((x - 15) * (1 / 19985), 1 / 3)), inv: (x) => Math.cbrt((x - 15) / 19985),
    text: (V) => cfmt('EQ %i frequency: %.2f Hz', k, V * V * V * 19985 + 15),
  });
  def(222 + k, bip(4 * (222 + k) + 8360, 60, (V) => cfmt('EQ %i amp: %.2f dB', k, (2 * V - 1) * 60), { unit: 'dB' }));
  def(227 + k, {
    offset: 4 * (227 + k) + 8360, type: 'f32', min: 1 / 16, max: 16, unit: 'slope factor',
    set: (v) => f32(eqSlope(v)),
    get: (x) => f32(x > 1 ? (x - 1) * f32(1 / 30) + 0.5 : x < 1 ? 0.5 - (1 / x - 1) * f32(1 / 30) : 0.5),
    inv: (x) => (x > 1 ? (x - 1) / 30 + 0.5 : x < 1 ? 0.5 - (1 / x - 1) / 30 : 0.5),
    text: (V) => cfmt('EQ %i slope: %.3f', k, eqSlope(V)),
  });
  def(232 + k, sw(4 * (232 + k) + 8360, 3, EQ_TYPES, (V) => { const t = ftol(3 * V + 0.5); return t >= 0 && t <= 3 ? cfmt(`EQ %i type: ${EQ_TYPES[t]}`, k) : ''; }));
}
function eqSlope(v) { return v > 0.5 ? (v - 0.5) * 30 + 1 : v < 0.5 ? 1 / ((0.5 - v) * 30 + 1) : 1; }
def(245, bip(9504, 1, veloText));
def(261, bip(9508, 1, veloText));
for (const [base, M, dOff] of [[246, 'M1', 9376], [262, 'M2', 9472]]) {
  for (let k = 1; k <= 4; k++) {
    def(base + k - 1, bip(dOff + 4 * (k - 1), 1, depthText(`${M} mod depth ${k}: `, `${M} mod depth ${k}: `, dOff + 16 + 4 * (k - 1), unitEnv, 2)));
    def(base + 3 + k, sw(dOff + 16 + 4 * (k - 1), 30, MOD_ENV_TARGETS, (V) => { const t = ftol(30 * V + 0.5); return t >= 0 && t <= 30 ? cfmt(`${M} mod target %i: ${MOD_ENV_TARGETS[t]}`, k) : ''; }));
  }
}
for (let ch = 1; ch <= 16; ch++) def(269 + ch, sw(9524 + 4 * ch, 1, MIDI_CHANNEL, (V) => cfmt('MIDI channel %i: %s', ch, ftol(V + 0.5) !== 0 ? 'receive' : 'ignore')));
def(286, sw(9592, 1, SUSTAIN_PEDAL, (V) => cfmt('Sustain pedal: %s', ftol(V + 0.5) !== 0 ? 'use' : 'ignore')));
for (let c = 1; c <= 6; c++) {
  const base = 287 + 9 * (c - 1), off = 10108 + 36 * (c - 1);
  def(base, sw(off, 127, null, (V) => { const n = ftol(127 * V + 0.5); return n > 0 ? cfmt('CC %i: %i', c, n) : cfmt('CC %i: ---', c); }, { unit: 'MIDI CC number (0 = none)' }));
  for (let k = 1; k <= 4; k++) {
    def(base + k, bip(off + 4 * k, 1, depthText(`CC ${c} depth ${k}: `, `CC ${c} mod depth ${k}: `, off + 16 + 4 * k, unitCC, 4)));
    def(base + 4 + k, sw(off + 16 + 4 * k, 34, CC_TARGETS, (V) => {
      const t = ftol(34 * V + 0.5);
      if (t < 0 || t > 34) return cfmt('CC %i target %i: ??? mystery value! Something is broken.', c, k);
      return cfmt(t >= 33 ? `CC %i mod target %i: ${CC_TARGETS[t]}` : `CC %i target %i: ${CC_TARGETS[t]}`, c, k);
    }));
  }
}
def(341, sw(10324, 2, OSC_MIX, (V) => { const t = ftol(2 * V + 0.5); return 'Osc mix: ' + OSC_MIX[t === 1 || t === 2 ? t : 0]; }));

// defaults (Init program) -----------------------------------------------------------------------------
for (let i = 0; i < 342; i++) {
  if (!P[i]) throw new Error('param ' + i + ' undefined');
  P[i].defaultNormalized = DEFAULT_NORMALIZED[i];
}

// ---------------------------------------------------------------------------------------------------
// public API

export const PARAM_COUNT = 342;
/** The parameter table (frozen spec objects; functions inside). */
export const PARAMS = Object.freeze(P.map((p) => Object.freeze(p)));

/** normalized (0..1) -> internal value exactly like setParameter (v is rounded to float32 first).
 *  Returns a Number: float32 value for 'f32', int for 'i32'/'lo16'/'hi16', uint32 for 'u32'.
 *  No clamping (the DLL does not clamp either). */
export function toInternal(i, v) { return P[i].set(f32(v)); }

/** internal -> normalized, mathematical inverse of toInternal (not the DLL's getParameter), clamped to [0,1]. */
export function toNormalized(i, x) {
  const v = P[i].inv(x);
  return Number.isNaN(v) ? 0 : Math.min(1, Math.max(0, v));
}

/** Like toNormalized, but returns the float32 v (searching a few hundred ulps around the inverse) for which
 *  toInternal(i, v) reproduces x bit-exactly when such a v exists (lossless VST parameter round trips). */
export function toNormalizedF32(i, x) {
  const v0 = f32(toNormalized(i, x));
  const same = (a) => a === x || (Number.isNaN(a) && Number.isNaN(x));
  if (same(toInternal(i, v0))) return v0;
  const d = new DataView(new ArrayBuffer(4));
  d.setFloat32(0, v0, true);
  const b0 = d.getUint32(0, true);
  for (let k = 1; k <= 512; k++) {
    for (const b of [b0 + k, b0 - k]) {
      if (b < 0 || b > 0x3f800000) continue;                      // stay within [0, 1]
      d.setUint32(0, b, true);
      const v = d.getFloat32(0, true);
      if (same(toInternal(i, v))) return v;
    }
  }
  return v0;
}

/** internal -> what Oatmeal.dll's getParameter returns (float32, with its quirks: PWM rate = v/2, F envspeed > 0.5 -> v-1). */
export function dllGetParameter(i, x) { return P[i].get(x); }

/** Read a parameter's internal value from a v38 program (Uint8Array 10376). */
export function readInternal(prog, i) {
  const p = P[i], d = dv(prog);
  switch (p.type) {
    case 'f32': return d.getFloat32(p.offset, true);
    case 'u32': return d.getUint32(p.offset, true);
    case 'lo16': return d.getInt32(p.offset, true) & 0xffff;
    case 'hi16': return d.getInt32(p.offset, true) >> 16;         // DLL reads it as signed word
    default: return d.getInt32(p.offset, true);
  }
}
/** Write an internal value (also the second release field for envelope releases). */
export function writeInternal(prog, i, x) {
  const p = P[i], d = dv(prog);
  switch (p.type) {
    case 'f32': d.setFloat32(p.offset, x, true); if (p.offset2) d.setFloat32(p.offset2, f32(f32(x) * 0.5), true); break;
    case 'u32': d.setUint32(p.offset, x >>> 0, true); break;
    case 'lo16': d.setInt32(p.offset, (d.getInt32(p.offset, true) & ~0xffff) | (x & 0xffff), true); break;
    case 'hi16': d.setInt32(p.offset, (d.getInt32(p.offset, true) & 0xffff) | ((x & 0xffff) << 16), true); break;
    default: d.setInt32(p.offset, x | 0, true);
  }
}
/** setParameter(i, v) applied to a program: exactly the bytes the DLL writes into the program. */
export function setParamNormalized(prog, i, v) { writeInternal(prog, i, toInternal(i, v)); }
/** getParameter as the DLL computes it from a program. */
export function getParamDll(prog, i) { return dllGetParameter(i, readInternal(prog, i)); }

let _initProg = null;
/** Context used when no program is passed: only the fields status texts read, set to their Init values. */
function ctx(prog) {
  if (prog) return prog;
  if (!_initProg) {
    _initProg = new Uint8Array(10376);
    const d = dv(_initProg);
    d.setFloat32(OFF_OCTAVE, 2, true); d.setFloat32(OFF_TUNE, 440, true); d.setFloat32(OFF_CUTREF, 0, true);
    for (const e of ENVS) { d.setFloat32(e.off + 44, 1, true); d.setFloat32(e.off + 52, 0.5, true); }
    d.setInt32(8852, 1, true);                                     // Arp quantize on (Init)
  }
  return _initProg;
}

/** Full status-bar text (Oatmeal.dll 0x100405f0) for normalized value V, in the context of program prog
 *  (needed for: Octave/Tune/Cut reference ratios, decay-1 "skip", depth units, speed/length quantize, filter 2 off). */
export function statusText(i, V, prog) {
  if (i < 0 || i >= 342) return '';
  return P[i].text(f32(V), ctx(prog));
}

/** The normalized value the status-text function expects for internal value x.  This is the DLL getParameter
 *  value (the status texts are written against it: e.g. PWM rate text = 16*V Hz with V = x/16), except for
 *  F envspeed (56), whose getParameter is broken for x < 1 (returns v-1) -> the proper inverse is used there. */
export function textNormalized(i, x) { return i === 56 ? toNormalized(i, x) : dllGetParameter(i, x); }

/** Value part of the display for internal value x ("1392.50 Hz (*3.1648)", "-inf dB", "skip decay 1", "ETERNITY.").
 *  prog supplies the context fields (Octave, Tune, targets, quantize switches...; default = Init values).
 *  opts.dll: reproduce the VST host display exactly, bugs included (V = DLL getParameter for every param).
 *  opts.v: use this normalized value directly (e.g. the value a GUI knob holds). */
export function displayText(i, x, prog, opts = {}) {
  const V = opts.v !== undefined ? opts.v : opts.dll ? dllGetParameter(i, x) : textNormalized(i, x);
  const s = statusText(i, V, prog);
  const c = s.indexOf(':');
  return c < 0 ? '' : s.slice(c + 1).replace(/^ /, '');
}

/** Exactly what the VST host sees from effGetParamDisplay: " " + value part (from the DLL getParameter value), max 23 chars. */
export function hostDisplay(prog, i) {
  const s = statusText(i, getParamDll(prog, i), prog);
  const c = s.indexOf(':');
  return (c < 0 ? '' : s.slice(c + 1)).slice(0, 23);
}

/** Switch value names for parameter i (null for continuous params). */
export function valueNames(i) { return P[i].labels ? P[i].labels.slice() : null; }

/** Plain-data description of every parameter (for docs / GUIs).  Pass the Init program (oatmeal-format.js
 *  makeDefaultProgram()) to also get defaultInternal / defaultText. */
export function describeParams(initProg) {
  return P.map((p) => {
    const r = {
      index: p.index, name: p.name, action: p.action, offset: p.offset, offset2: p.offset2 || null, type: p.type,
      min: p.min, max: p.max, unit: p.unit || (p.labels ? 'enum' : ''), states: p.states || null, add: p.add || 0,
      labels: p.labels ? p.labels.slice() : null, defaultNormalized: p.defaultNormalized,
    };
    if (initProg) { r.defaultInternal = readInternal(initProg, p.index); r.defaultText = statusText(p.index, getParamDll(initProg, p.index), initProg); }
    return r;
  });
}
