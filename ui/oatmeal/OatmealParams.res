// Oatmeal (Fuzzpilz, release 38-1) parameter table, value mapping and display text.
//
// Reverse-engineered from Oatmeal.dll: setParameter 0x10048260, getParameter 0x1004c890,
// status text 0x100405f0 (host display = text after the first ':' , max 23 chars, 0x1004f5b0),
// action-name lookup 0x100367bb.  See docs/internals/presets_params.md.
//
// Conventions:
//   v          normalized VST parameter value (float32 in the DLL)
//   x          internal value as stored in the program struct at chunk offset `offset`
//   prog       v38 program chunk (Uint8Array(10376)), see OatmealFormat

// DLL parameter names (effGetParamName; 124..128 are empty in the DLL) and skin action names (from the DLL's own
// action-name -> index table 0x100367bb, used by .oms skins as action=...)
let names = [
  ("1 Waveform", "O1_Waveform"),
  ("1 Amp", "O1_Amp"),
  ("1 Afterpitch", "O1_Afterpitch"),
  ("1 Pulsewidth", "O1_PWM_W"),
  ("1 PWM rate", "O1_PWM_R"),
  ("1 PWM depth", "O1_PWM_D"),
  ("2 Waveform", "O2_Waveform"),
  ("2 Amp", "O2_Amp"),
  ("2 Afterpitch", "O2_Afterpitch"),
  ("2 Pulsewidth", "O2_PWM_W"),
  ("2 PWM rate", "O2_PWM_R"),
  ("2 PWM depth", "O2_PWM_D"),
  ("Transpose", "Transpose"),
  ("Detune", "Detune"),
  ("Osc aftertouch", "OscAftertouch"),
  ("N amp", "N_Amp"),
  ("N aftertouch", "N_Aftertouch"),
  ("N resonance", "N_Resonance"),
  ("N transpose", "N_Transpose"),
  ("LFO 1 unit", "LFO_1_Unit"),
  ("LFO 1 shape", "LFO_1_Shape"),
  ("LFO 1 speed", "LFO_1_Speed"),
  ("LFO 1 quantize", "LFO_1_Quantize"),
  ("LFO 1 mode", "LFO_1_Sync"),
  ("LFO 1 cut 1", "LFO_1_Cutoff_1"),
  ("LFO 1 cut 2", "LFO_1_Cutoff_2"),
  ("LFO 1 res", "LFO_1_Resonance"),
  ("LFO 1 pitch", "LFO_1_Pitch"),
  ("LFO 1 pan", "LFO_1_Pan"),
  ("LFO 1 2", "LFO_1_2"),
  ("LFO 1 unit", "LFO_2_Unit"),
  ("LFO 2 shape", "LFO_2_Shape"),
  ("LFO 2 speed", "LFO_2_Speed"),
  ("LFO 2 quantize", "LFO_2_Quantize"),
  ("LFO 2 mode", "LFO_2_Sync"),
  ("LFO 2 cut 1", "LFO_2_Cutoff_1"),
  ("LFO 2 cut 2", "LFO_2_Cutoff_2"),
  ("LFO 2 res", "LFO_2_Resonance"),
  ("LFO 2 pitch", "LFO_2_Pitch"),
  ("LFO 2 pan", "LFO_2_Pan"),
  ("LFO 2 1", "LFO_2_1"),
  ("Filter", "Filter"),
  ("Filter 2", "Filter2"),
  ("Cutoff", "Cutoff"),
  ("Resonance", "Resonance"),
  ("F attack", "F_Attack"),
  ("F hold", "F_Hold"),
  ("F decay 1", "F_Decay1"),
  ("F breakpoint", "F_Breakpoint"),
  ("F decay 2", "F_Decay2"),
  ("F sustain", "F_Sustain"),
  ("F release", "F_Release"),
  ("F keytrack", "F_Track"),
  ("F double", "F_Double"),
  ("F mix", "F_Mix"),
  ("F split", "F_Split"),
  ("F envspeed", "F_Speed"),
  ("F envmod", "F_EnvMod"),
  ("F env velo sens", "F_VeloSens"),
  ("F aftertouch", "F_Aftertouch"),
  ("Attack", "Attack"),
  ("Hold", "Hold"),
  ("Decay 1", "Decay1"),
  ("Breakpoint", "Breakpoint"),
  ("Decay 2", "Decay2"),
  ("Sustain", "Sustain"),
  ("Release", "Release"),
  ("Chorus", "C_Mode"),
  ("Chorus", "C_Stereo"),
  ("C voices", "C_Voices"),
  ("C speed", "C_Rate"),
  ("C delay", "C_MinDelay"),
  ("C depth", "C_Depth"),
  ("C feedback", "C_Feedback"),
  ("C mix", "C_Mix"),
  ("Delay", "D_On"),
  ("D unit", "D_Unit"),
  ("D quantize", "D_Quantize"),
  ("D reverse", "D_ReverseL"),
  ("D reverse", "D_ReverseR"),
  ("D length L", "D_LengthL"),
  ("D length R", "D_LengthR"),
  ("D feedbk L", "D_FeedbackL"),
  ("D feedbk R", "D_FeedbackR"),
  ("D input pan", "D_InputPan"),
  ("D rotation", "D_Rotation"),
  ("D lowpass", "D_LP"),
  ("D highpass", "D_HP"),
  ("D dry out", "D_Dry"),
  ("D wet out", "D_Wet"),
  ("Reverb", "R_On"),
  ("R size", "R_Size"),
  ("R length", "R_Length"),
  ("R dullness", "R_Dullness"),
  ("R brightness", "R_Brightness"),
  ("R dry out", "R_Dry"),
  ("R wet out", "R_Wet"),
  ("R 1", "R_1"),
  ("R 2", "R_2"),
  ("R 3", "R_3"),
  ("R rotation", "R_Rotation"),
  ("R predelay", "R_Predelay"),
  ("R early mix", "R_EarlyMix"),
  ("Voice mode", "PolyMode"),
  ("Max polyphony", "Voices"),
  ("Glide", "Glide"),
  ("Glide mode", "GlideMode"),
  ("Output gain", "Gain"),
  ("Velocity sensitivity", "VeloSens"),
  ("Aftertouch mode", "AftertouchMode"),
  ("Frequency pan", "FreqPan"),
  ("Frequency env", "FreqEnv"),
  ("Random pan", "RandomPan"),
  ("Random amp", "RandomAmp"),
  ("Random freq", "RandomFreq"),
  ("Osc phase", "OscPhase"),
  ("Osc phase rand", "OscPhaseRand"),
  ("Osc retrigger", "OscRetrig"),
  ("PWM phase", "PWMPhase"),
  ("PWM phase rand", "PWMPhaseRand"),
  ("PWM retrigger", "PWMRetrig"),
  ("LFO phase", "LFOPhase"),
  ("LFO phase rand", "LFOPhaseRand"),
  ("LFO retrigger", "LFORetrig"),
  ("", "U_Voices"),
  ("", "U_Detune"),
  ("", "U_Spread"),
  ("", "U_PitchJitter"),
  ("", "U_PanJitter"),
  ("Arp mode", "Arp_Mode"),
  ("Arp unit", "Arp_Unit"),
  ("Arp quantize", "Arp_Quantize"),
  ("Arp step", "Arp_Step"),
  ("Arp step 1", "Arp_P0"),
  ("Arp step 2", "Arp_P1"),
  ("Arp step 3", "Arp_P2"),
  ("Arp step 4", "Arp_P3"),
  ("Arp step 5", "Arp_P4"),
  ("Arp step 6", "Arp_P5"),
  ("Arp step 7", "Arp_P6"),
  ("Arp step 8", "Arp_P7"),
  ("Arp step 9", "Arp_P8"),
  ("Arp step 10", "Arp_P9"),
  ("Arp step 11", "Arp_PA"),
  ("Arp step 12", "Arp_PB"),
  ("Arp step 13", "Arp_PC"),
  ("Arp step 14", "Arp_PD"),
  ("Arp step 15", "Arp_PE"),
  ("Arp step 16", "Arp_PF"),
  ("Arp pattern length", "Arp_End"),
  ("Arp note 1 on", "Arp_Add_1_On"),
  ("Arp note 2 on", "Arp_Add_2_On"),
  ("Arp note 3 on", "Arp_Add_3_On"),
  ("Arp note 4 on", "Arp_Add_4_On"),
  ("Arp note 5 on", "Arp_Add_5_On"),
  ("Arp note 6 on", "Arp_Add_6_On"),
  ("Arp note 7 on", "Arp_Add_7_On"),
  ("Arp note 1 shift", "Arp_Add_1_Shift"),
  ("Arp note 2 shift", "Arp_Add_2_Shift"),
  ("Arp note 3 shift", "Arp_Add_3_Shift"),
  ("Arp note 4 shift", "Arp_Add_4_Shift"),
  ("Arp note 5 shift", "Arp_Add_5_Shift"),
  ("Arp note 6 shift", "Arp_Add_6_Shift"),
  ("Arp note 7 shift", "Arp_Add_7_Shift"),
  ("P env on", "PEnv_On"),
  ("P start", "PEnv_Start"),
  ("P attack", "PEnv_Attack"),
  ("P peak", "PEnv_Peak"),
  ("P decay", "PEnv_Decay"),
  ("P sustain", "PEnv_Sustain"),
  ("P release", "PEnv_Release"),
  ("P env velo sens", "PEnv_VeloSens"),
  ("Dist type", "Sat_Type"),
  ("Dist mode", "Sat_Mode"),
  ("Dist limit", "Sat_Limit"),
  ("Dist pregain", "Sat_Pregain"),
  ("Dist postgain", "Sat_Postgain"),
  ("Dist oversample", "Sat_Oversample"),
  ("Tune main", "Tune_Main"),
  ("Octave", "Tune_Octave"),
  ("Cut reference", "Tune_CutReference"),
  ("Pan reference", "Tune_PanReference"),
  ("Tune C", "Tune_C"),
  ("Tune C#/Db", "Tune_Db"),
  ("Tune D", "Tune_D"),
  ("Tune D#/Eb", "Tune_Eb"),
  ("Tune E", "Tune_E"),
  ("Tune F", "Tune_F"),
  ("Tune F#/Gb", "Tune_Gb"),
  ("Tune G", "Tune_G"),
  ("Tune G#/Ab", "Tune_Ab"),
  ("Tune A", "Tune_A"),
  ("Tune A#/Bb", "Tune_Bb"),
  ("Tune B", "Tune_B"),
  ("Bend range", "BendRange"),
  ("Global transpose", "GlobalTranspose"),
  ("X", "X"),
  ("Y", "Y"),
  ("X depth 1", "XY_H_Depth_1"),
  ("X depth 2", "XY_H_Depth_2"),
  ("X depth 3", "XY_H_Depth_3"),
  ("X depth 4", "XY_H_Depth_4"),
  ("X target 1", "XY_H_Target_1"),
  ("X target 2", "XY_H_Target_2"),
  ("X target 3", "XY_H_Target_3"),
  ("X target 4", "XY_H_Target_4"),
  ("X CC", "XY_H_CC"),
  ("Y depth 1", "XY_V_Depth_1"),
  ("Y depth 2", "XY_V_Depth_2"),
  ("Y depth 3", "XY_V_Depth_3"),
  ("Y depth 4", "XY_V_Depth_4"),
  ("Y target 1", "XY_V_Target_1"),
  ("Y target 2", "XY_V_Target_2"),
  ("Y target 3", "XY_V_Target_3"),
  ("Y target 4", "XY_V_Target_4"),
  ("Y CC", "XY_V_CC"),
  ("XY var radius", "XY_Var_Radius"),
  ("XY var rate", "XY_Var_Rate"),
  ("EQ 1 freq", "EQ_1_Freq"),
  ("EQ 2 freq", "EQ_2_Freq"),
  ("EQ 3 freq", "EQ_3_Freq"),
  ("EQ 4 freq", "EQ_4_Freq"),
  ("EQ 5 freq", "EQ_5_Freq"),
  ("EQ 1 amp", "EQ_1_Amp"),
  ("EQ 2 amp", "EQ_2_Amp"),
  ("EQ 3 amp", "EQ_3_Amp"),
  ("EQ 4 amp", "EQ_4_Amp"),
  ("EQ 5 amp", "EQ_5_Amp"),
  ("EQ 1 slope", "EQ_1_Slope"),
  ("EQ 2 slope", "EQ_2_Slope"),
  ("EQ 3 slope", "EQ_3_Slope"),
  ("EQ 4 slope", "EQ_4_Slope"),
  ("EQ 5 slope", "EQ_5_Slope"),
  ("EQ 1 type", "EQ_1_Type"),
  ("EQ 2 type", "EQ_2_Type"),
  ("EQ 3 type", "EQ_3_Type"),
  ("EQ 4 type", "EQ_4_Type"),
  ("EQ 5 type", "EQ_5_Type"),
  ("M1 attack", "M1_Attack"),
  ("M1 hold", "M1_Hold"),
  ("M1 decay 1", "M1_Decay1"),
  ("M1 breakpoint", "M1_Breakpoint"),
  ("M1 decay 2", "M1_Decay2"),
  ("M1 sustain", "M1_Sustain"),
  ("M1 release", "M1_Release"),
  ("M1 velo sens", "M1_VeloSens"),
  ("M1 depth 1", "M1_Depth_1"),
  ("M1 depth 2", "M1_Depth_2"),
  ("M1 depth 3", "M1_Depth_3"),
  ("M1 depth 4", "M1_Depth_4"),
  ("M1 target 1", "M1_Target_1"),
  ("M1 target 2", "M1_Target_2"),
  ("M1 target 3", "M1_Target_3"),
  ("M1 target 4", "M1_Target_4"),
  ("M2 attack", "M2_Attack"),
  ("M2 hold", "M2_Hold"),
  ("M2 decay 1", "M2_Decay1"),
  ("M2 breakpoint", "M2_Breakpoint"),
  ("M2 decay 2", "M2_Decay2"),
  ("M2 sustain", "M2_Sustain"),
  ("M2 release", "M2_Release"),
  ("M2 velo sens", "M2_VeloSens"),
  ("M2 depth 1", "M2_Depth_1"),
  ("M2 depth 2", "M2_Depth_2"),
  ("M2 depth 3", "M2_Depth_3"),
  ("M2 depth 4", "M2_Depth_4"),
  ("M2 target 1", "M2_Target_1"),
  ("M2 target 2", "M2_Target_2"),
  ("M2 target 3", "M2_Target_3"),
  ("M2 target 4", "M2_Target_4"),
  ("MIDI channel 1", "MIDI_Channel_1"),
  ("MIDI channel 2", "MIDI_Channel_2"),
  ("MIDI channel 3", "MIDI_Channel_3"),
  ("MIDI channel 4", "MIDI_Channel_4"),
  ("MIDI channel 5", "MIDI_Channel_5"),
  ("MIDI channel 6", "MIDI_Channel_6"),
  ("MIDI channel 7", "MIDI_Channel_7"),
  ("MIDI channel 8", "MIDI_Channel_8"),
  ("MIDI channel 9", "MIDI_Channel_9"),
  ("MIDI channel 10", "MIDI_Channel_10"),
  ("MIDI channel 11", "MIDI_Channel_11"),
  ("MIDI channel 12", "MIDI_Channel_12"),
  ("MIDI channel 13", "MIDI_Channel_13"),
  ("MIDI channel 14", "MIDI_Channel_14"),
  ("MIDI channel 15", "MIDI_Channel_15"),
  ("MIDI channel 16", "MIDI_Channel_16"),
  ("Sustain pedal", "SustainPedal"),
  ("CC 1", "CC1"),
  ("CC 1 depth 1", "CC1_Depth_1"),
  ("CC 1 depth 2", "CC1_Depth_2"),
  ("CC 1 depth 3", "CC1_Depth_3"),
  ("CC 1 depth 4", "CC1_Depth_4"),
  ("CC 1 target 1", "CC1_Target_1"),
  ("CC 1 target 2", "CC1_Target_2"),
  ("CC 1 target 3", "CC1_Target_3"),
  ("CC 1 target 4", "CC1_Target_4"),
  ("CC 2", "CC2"),
  ("CC 2 depth 1", "CC2_Depth_1"),
  ("CC 2 depth 2", "CC2_Depth_2"),
  ("CC 2 depth 3", "CC2_Depth_3"),
  ("CC 2 depth 4", "CC2_Depth_4"),
  ("CC 2 target 1", "CC2_Target_1"),
  ("CC 2 target 2", "CC2_Target_2"),
  ("CC 2 target 3", "CC2_Target_3"),
  ("CC 2 target 4", "CC2_Target_4"),
  ("CC 3", "CC3"),
  ("CC 3 depth 1", "CC3_Depth_1"),
  ("CC 3 depth 2", "CC3_Depth_2"),
  ("CC 3 depth 3", "CC3_Depth_3"),
  ("CC 3 depth 4", "CC3_Depth_4"),
  ("CC 3 target 1", "CC3_Target_1"),
  ("CC 3 target 2", "CC3_Target_2"),
  ("CC 3 target 3", "CC3_Target_3"),
  ("CC 3 target 4", "CC3_Target_4"),
  ("CC 4", "CC4"),
  ("CC 4 depth 1", "CC4_Depth_1"),
  ("CC 4 depth 2", "CC4_Depth_2"),
  ("CC 4 depth 3", "CC4_Depth_3"),
  ("CC 4 depth 4", "CC4_Depth_4"),
  ("CC 4 target 1", "CC4_Target_1"),
  ("CC 4 target 2", "CC4_Target_2"),
  ("CC 4 target 3", "CC4_Target_3"),
  ("CC 4 target 4", "CC4_Target_4"),
  ("CC 5", "CC5"),
  ("CC 5 depth 1", "CC5_Depth_1"),
  ("CC 5 depth 2", "CC5_Depth_2"),
  ("CC 5 depth 3", "CC5_Depth_3"),
  ("CC 5 depth 4", "CC5_Depth_4"),
  ("CC 5 target 1", "CC5_Target_1"),
  ("CC 5 target 2", "CC5_Target_2"),
  ("CC 5 target 3", "CC5_Target_3"),
  ("CC 5 target 4", "CC5_Target_4"),
  ("CC 6", "CC6"),
  ("CC 6 depth 1", "CC6_Depth_1"),
  ("CC 6 depth 2", "CC6_Depth_2"),
  ("CC 6 depth 3", "CC6_Depth_3"),
  ("CC 6 depth 4", "CC6_Depth_4"),
  ("CC 6 target 1", "CC6_Target_1"),
  ("CC 6 target 2", "CC6_Target_2"),
  ("CC 6 target 3", "CC6_Target_3"),
  ("CC 6 target 4", "CC6_Target_4"),
  ("Osc mix", "OscMix"),
]

// switch value names, read off the DLL status texts (index = stored value)
let waveforms = ["Sine", "Saw", "Pulse", "Triangle", "User", "User PWM"]
let lfoUnits = [
  "ms",
  "10 ms",
  "sec",
  "4/5 16ths",
  "2/3 16ths",
  "16ths",
  "4/5 8ths",
  "2/3 8ths",
  "8ths",
  "4/5 quarter notes",
  "2/3 quarter notes",
  "quarter notes",
  "4/5 half notes",
  "2/3 half notes",
  "half notes",
  "4/5 whole notes",
  "2/3 whole notes",
  "whole notes",
]
let lfoShapes = ["Sine", "Saw", "Square", "Triangle", "Smooth random", "Stepping random", "User"]
let lfoQuantize = ["free speed", "quantize period"]
let lfoModes = ["per note", "global, reset on note", "global, free"]
let filterTypes = [
  "Off",
  "1P lowpass",
  "2P lowpass",
  "4P lowpass",
  "1P highpass",
  "2P highpass",
  "4P highpass",
  "2P wide bandpass",
  "2P narrow bandpass",
  "4P bandpass",
  "2P notch",
  "nonlinear 2P lowpass",
  "nonlinear 4P lowpass",
]
let filter2Types = [
  "same as filter 1",
  "1P lowpass",
  "2P lowpass",
  "4P lowpass",
  "1P highpass",
  "2P highpass",
  "4P highpass",
  "2P wide bandpass",
  "2P narrow bandpass",
  "4P bandpass",
  "2P notch",
  "nonlinear 2P lowpass",
  "nonlinear 4P lowpass",
]
let filterDouble = ["off", "parallel", "serial"]
let chorusModes = ["off", "sine", "ramp", "FM", "irregular"]
let chorusStereo = ["mono", "stereo 1", "stereo 2"]
let delayOn = ["off", "on"]
let delayUnits = [
  "ms",
  "10 ms",
  "sec",
  "4/5 16ths",
  "2/3 16ths",
  "16ths",
  "4/5 8ths",
  "2/3 8ths",
  "8ths",
  "4/5 quarter notes",
  "2/3 quarter notes",
  "quarter notes",
  "4/5 half notes",
  "2/3 half notes",
  "half notes",
]
let delayQuantize = ["free length", "quantize length"]
let delayReverse = ["normal", "reverse output", "reverse feedback"]
let reverbOn = ["off", "on"]
let voiceModes = ["Monophonic", "Polyphonic", "Monophonic, legato"]
let glideModes = [
  "Param",
  "P * octaves",
  "P / octaves",
  "P * (o + 1/o)",
  "P * (1 + o)",
  "P * (1 + 1/o)",
  "P * (1 + o + 1/o)",
]
let aftertouchModes = ["ignore all", "channel", "polyphonic"]
let offOn = ["off", "on"]
let arpModes = [
  "off",
  "pattern",
  "pattern (global subseq)",
  "chord pattern",
  "chord",
  "transposed chords",
]
let arpUnits = [
  "ms",
  "10 ms",
  "sec",
  "4/5 32nds",
  "2/3 32nds",
  "32nds",
  "4/5 16ths",
  "2/3 16ths",
  "16ths",
  "4/5 8ths",
  "2/3 8ths",
  "8ths",
  "4/5 quarter notes",
  "2/3 quarter notes",
  "quarter notes",
  "4/5 half notes",
  "2/3 half notes",
  "half notes",
]
let arpStepCommands = [
  "off",
  "up",
  "up, no wrap",
  "down",
  "down, no wrap",
  "up or down",
  "up or down, no wrap",
  "continue",
  "continue direction",
  "continue direction, bounce",
  "return",
  "return, up",
  "return, down",
  "top",
  "bottom",
  "random",
]
let distTypes = ["off", "hard clip", "soft clip", "sine", "asymmetric"]
let distModes = [
  "global",
  "per voice, after filter",
  "per voice, before filter",
  "double (before filter and global)",
]
let distOversample = ["off", "2x", "4x", "8x"]
let xyTargets = [
  "none",
  "cutoff 1",
  "cutoff 2",
  "resonance",
  "filter env mod",
  "pitch",
  "pan",
  "distortion",
  "LFO 1 speed",
  "LFO 2 speed",
  "LFO 1 depth",
  "LFO 2 depth",
  "1 pulsewidth",
  "1 PWM rate",
  "1 PWM depth",
  "2 pulsewidth",
  "2 PWM rate",
  "2 PWM depth",
  "1 amp",
  "2 amp",
  "noise amp",
  "1 pitch",
  "2 pitch",
  "noise pitch",
  "filter mix",
  "noise resonance",
  "ME 1 depth",
  "ME 2 depth",
  "amp envelope speed",
  "filter envelope speed",
  "mod envelope speed",
  "pitch envelope speed",
  "Unison detune",
  "Unison spread",
]
let eqTypes = ["off", "peak/notch", "low shelf", "high shelf"]
let modEnvTargets = [
  "none",
  "cutoff 1",
  "cutoff 2",
  "resonance",
  "1 amp",
  "2 amp",
  "noise amp",
  "1 pitch",
  "2 pitch",
  "noise pitch",
  "1 pulsewidth",
  "1 PWM rate",
  "1 PWM depth",
  "2 pulsewidth",
  "2 PWM rate",
  "2 PWM depth",
  "pan",
  "noise resonance",
  "LFO 1 speed",
  "LFO 2 speed",
  "LFO 1 depth",
  "LFO 2 depth",
  "filter mix",
  "cutoff 1 (unipolar)",
  "cutoff 2 (unipolar)",
  "1 pitch (unipolar)",
  "2 pitch (unipolar)",
  "noise pitch (unipolar)",
  "XY depth",
  "Unison detune",
  "Unison spread",
]
let midiChannel = ["ignore", "receive"]
let sustainPedal = ["ignore", "use"]
let ccTargets = [
  "none",
  "cutoff 1",
  "cutoff 2",
  "resonance",
  "filter env mod",
  "pitch",
  "pan",
  "distortion",
  "LFO 1 speed",
  "LFO 2 speed",
  "LFO 1 depth",
  "LFO 2 depth",
  "1 pulsewidth",
  "1 PWM rate",
  "1 PWM depth",
  "2 pulsewidth",
  "2 PWM rate",
  "2 PWM depth",
  "1 amp",
  "2 amp",
  "noise amp",
  "1 pitch",
  "2 pitch",
  "noise pitch",
  "filter mix",
  "noise resonance",
  "ME 1 depth",
  "ME 2 depth",
  "XY depth",
  "amp envelope speed",
  "filter envelope speed",
  "mod envelope speed",
  "pitch envelope speed",
  "Unison detune",
  "Unison spread",
]
let oscMix = ["normal", "hardsync", "FM (1 -> 2, 1 silent)"]

// ---------------------------------------------------------------------------------------------------
// numeric helpers (x87 emulation)

let f32 = Math.fround
// MSVC _ftol: truncation toward zero (the DLL always adds 0.5 first => round-half-up for v >= 0).
let ftol = Math.trunc
// int32 wrap like the x87 fistp/_ftol low dword.
let i32 = x => {
  let t = Math.trunc(x)
  Float.isFinite(t) ? t->Float.toInt->Int.toFloat : -2147483648.
}
let pow = (x, y) => Math.pow(x, ~exp=y)
let log10 = Math.log10

// float32 constants exactly as stored in Oatmeal.dll's .rdata
module K = {
  let pi = f32(Math.Constants.pi)
  let c005 = f32(0.05)
  let c1_12 = f32(1. / 12.)
  let c1_1200 = f32(1. / 1200.)
  let c0998 = f32(0.998)
  let c0001 = f32(0.001)
  let c101 = f32(1.01)
  let c001 = f32(0.01)
  let attackMul = f32(9999.8)
  let attackAdd = f32(0.2)
  let chorusSpeed = f32(3.999)
  let chorusDelay = f32(99.9)
  let c01 = f32(0.1)
  let reverbLength = f32(29.9)
  let arpStep = f32(41.3333333)
  let reverbLengthInv = ByteView.float32OfBits(0x3d08fd6f)
}

// ---------------------------------------------------------------------------------------------------
// C printf subset (MSVC semantics for %.Nf: round half away from zero; "-" kept for negative zero)

let isNegative = x => x < 0. || (x == 0. && 1. / x < 0.)

// %.Nf
let fixed = (x, n) =>
  if Float.isNaN(x) {
    n > 0 ? "-1.#IND" : "-1" // MSVC prints e.g. -1.#IND00 (not reproduced exactly)
  } else if !Float.isFinite(x) {
    (x < 0. ? "-" : "") ++ "1.#INF"
  } else {
    (isNegative(x) ? "-" : "") ++ Math.abs(x)->Float.toFixed(~digits=n)
  }

// %i
let int = x => x->Float.toInt->Int.toString

// %03i
let int03 = x => {
  let s = int(x)
  String.startsWith(s, "-")
    ? "-" ++ s->String.slice(~start=1)->String.padStart(2, "0")
    : s->String.padStart(3, "0")
}

// ---------------------------------------------------------------------------------------------------
// parameter specs

type storage =
  | @as("f32") F32
  | @as("i32") I32
  // pulsewidth phase
  | @as("u32") U32
  // packed filter types
  | @as("lo16") Lo16
  | @as("hi16") Hi16

type t = {
  index: int,
  name: string,
  action: string,
  offset: int,
  // envelope releases also write release * 0.5 here
  offset2: option<int>,
  @as("type") storage: storage,
  min: float,
  max: float,
  unit: string,
  states: option<int>,
  add: int,
  // value names for switches (index = stored value - add)
  labels: option<array<string>>,
  // normalized -> internal value, exactly as setParameter 0x10048260 computes it (v is taken as float32)
  set: float => float,
  // DLL getParameter 0x1004c890 result (float32), including its quirks
  get: float => float,
  // mathematical inverse of set (the "proper" normalized value; clamped to [0,1] by toNormalized)
  inv: float => float,
  // DLL status-bar string (0x100405f0) for normalized v, in the context of a program
  text: (float, Uint8Array.t) => string,
}

let blank = {
  index: 0,
  name: "",
  action: "",
  offset: 0,
  offset2: None,
  storage: F32,
  min: 0.,
  max: 1.,
  unit: "",
  states: None,
  add: 0,
  labels: None,
  set: v => v,
  get: x => x,
  inv: x => x,
  text: (_, _) => "",
}

// Field offsets that some status texts read from the program.
let offOctave = 9064
let offTune = 9060
let offCutRef = 9072
let offFilter = 8428
let offFDouble = 8464

// generic builders ------------------------------------------------------------------------------------

// bipolar linear: x = (2v-1)*s ; DLL get = (x*f32(1/s) + 1)*0.5 (or (x+1)*0.5 when s==1)
let bip = (offset, s, text, ~unit=?) => {
  let invS = f32(1. / s)
  {
    ...blank,
    offset,
    min: -s,
    max: s,
    unit: unit->Option.getOr(s == 1. ? "bipolar -1..1" : ""),
    set: v => f32((2. * v - 1.) * s),
    get: x => f32(s == 1. ? (x + 1.) * 0.5 : (x * invS + 1.) * 0.5),
    inv: x => (x / s + 1.) / 2.,
    text,
  }
}

// unipolar identity: x = v
let uni = (offset, text, ~unit="unipolar 0..1") => {
  ...blank,
  offset,
  unit,
  set: f32,
  get: f32,
  text,
}

// square law: x = v*v*a + b ; DLL get = sqrt((x-b)*f32(1/a))
let sq = (offset, a, b, text, ~unit="") => {
  let a = f32(a)
  let b = f32(b)
  let invA = f32(1. / a)
  {
    ...blank,
    offset,
    min: b,
    max: f32(a + b),
    unit,
    set: v => f32(v * v * a + b),
    get: x => f32(Math.sqrt(b == 0. ? x * invA : (x - b) * invA)),
    inv: x => Math.sqrt(Math.max(0., (x - b) / a)),
    text,
  }
}

// amplitude in dB: v>0 ? 10^((90v-60)*0.05f) : 0 ; DLL get = x>0 ? (20*log10(x)+60)*f32(1/90) : 0
let amp = (offset, text) => {
  let inv90 = f32(1. / 90.)
  {
    ...blank,
    offset,
    min: 0.,
    max: f32(pow(10., 30. * K.c005)),
    unit: "linear gain (-60..+30 dB, 0 = -inf)",
    set: v => v > 0. ? f32(pow(10., (v * 90. - 60.) * K.c005)) : 0.,
    get: x => x > 0. ? f32((log10(x) * 20. + 60.) * inv90) : 0.,
    inv: x => x > 0. ? (log10(x) / K.c005 + 60.) / 90. : 0.,
    text,
  }
}

// envelope level (breakpoint/sustain): v != 0 ? 10^((v-1)*3) : 0 ; DLL get = x != 0 ? log10(x)*f32(1/3)+1 : 0
let lvl = (offset, text) => {
  let inv3 = f32(1. / 3.)
  {
    ...blank,
    offset,
    set: v => v != 0. ? f32(pow(10., (v - 1.) * 3.)) : 0.,
    // getParameter reads the LIVE program copy, in which the envelope coefficient update (0x100522a0) has
    // replaced breakpoint/sustain values > 0.998 by exactly 1.0 -> emulate that here
    get: x => {
      let x = x > K.c0998 ? 1. : x
      x != 0. ? f32(log10(x) * inv3 + 1.) : 0.
    },
    inv: x => x > 0. ? log10(x) / 3. + 1. : 0.,
    text,
  }
}

// switch: x = ftol(n*v + 0.5) + add ; DLL get = (x-add) * f32(1/n) (n==1: x)
let sw = (offset, n, labels, text, ~add=0, ~unit="") => {
  let nf = Int.toFloat(n)
  let addf = Int.toFloat(add)
  let invN = f32(1. / nf)
  {
    ...blank,
    offset,
    storage: I32,
    min: addf,
    max: nf + addf,
    states: Some(n + 1),
    labels,
    add,
    unit,
    set: v => i32(nf * v + 0.5) + addf,
    get: x => n == 1 ? f32(x) : f32((x - addf) * invN),
    inv: x => (x - addf) / nf,
    text,
  }
}

// text functions ------------------------------------------------------------------------------------

let at = (labels, k) => k >= 0. ? labels[Float.toInt(k)] : None

// status text of a plain enum: prefix + labels[ftol(n*v+0.5)] ('' when out of range, like the DLL)
let enumText = (prefix, n, labels) =>
  (v: float, _) =>
    switch labels->at(ftol(Int.toFloat(n) * v + 0.5)) {
    | Some(label) => prefix ++ label
    | None => ""
    }

let pct = label => (v: float, _) => `${label}: ${fixed(v * 100., 2)} %`
let ampText = label =>
  (v: float, _) => v > 0. ? `${label}: ${fixed(v * 90. - 60., 2)} dB` : `${label}: -inf dB`
let dryWetText = label =>
  (v: float, _) => v != 0. ? `${label}: ${fixed(v * 90. - 60., 2)} dB` : `${label}: -inf dB`
let attackText = (v: float, _) => `Attack: ${fixed(v * v * K.attackMul + K.attackAdd, 2)} ms`
let holdText = (v: float, _) => `Hold: ${fixed(v * v * 10000., 2)} ms`
let decay2Text = (v: float, _) => `Decay 2: ${fixed(v * v * 19990. + 10., 2)} ms`
let releaseText = (v: float, _) => `Release: ${fixed(v * v * 19990. + 10., 2)} ms`
let decay1Text = bpOffset =>
  (v: float, prog) =>
    prog->ByteView.getF32(bpOffset) > K.c0998
      ? "Decay 1: skip (breakpoint is 0 dB)"
      : `Decay 1: ${fixed(v * v * 19990. + 10., 2)} ms`

// filter/mod env breakpoint and sustain (percent display)
let levelPercentText = (label, skip) =>
  (v: float, _) =>
    if v == 0. {
      `${label}: ${fixed(0., 2)} %`
    } else {
      let b = pow(10., (v - 1.) * 3.)
      b > K.c0998 ? skip : `${label}: ${fixed(b * 100., 2)} %`
    }

// amp env breakpoint / sustain (dB + percent display)
let levelDbText = (label, skip) =>
  (v: float, _) =>
    if v != 0. && pow(10., (v - 1.) * 3.) > K.c0998 {
      skip
    } else if v <= 0. || Float.isNaN(v) {
      `${label}: -inf dB (0.00 %)`
    } else {
      let t = f32(v - 1.)
      `${label}: ${fixed(t * 60., 2)} dB (${fixed(pow(10., t * 3.) * 100., 2)} %)`
    }

// transposition with ratio (Transpose, N transpose, Arp note shift): t = f32(2v-1)
let ratioText = (label, digits, st: float, octs: float) =>
  (v: float, prog) => {
    let t = f32(2. * v - 1.)
    let oct = prog->ByteView.getF32(offOctave)
    v < 0.5
      ? `${label}: ${fixed(t * st, digits)} st (/${fixed(pow(oct, t * -octs), 4)})`
      : `${label}: ${fixed(t * st, digits)} st (*${fixed(pow(oct, t * octs), 4)})`
  }

// LFO speed / arp step with "units" (quantized display when the quantize field is on)
let unitsText = (label, quantizeOffset, speed) =>
  (v: float, prog) => {
    let s = speed(v)
    if prog->ByteView.getI32(quantizeOffset) != 0 {
      3. * s < 2.
        ? `${label}: 1/${int(ftol(1. / s + 0.5))} units`
        : `${label}: ${int(ftol(s + 0.5))} units`
    } else if s < 1. {
      `${label}: 1/${fixed(1. / s, 3)} units`
    } else {
      `${label}: ${fixed(s, 3)} units`
    }
  }
let lfoSpeed = (v: float) => 3. * v < 1. ? 1. / (4. - v * 9.) : (v * 1.5 - 0.5) * 255. + 1.
let arpStep = (v: float) => v <= 0.25 ? 1. / ((1. - v * 4.) * 7. + 1.) : (v - 0.25) * K.arpStep + 1.

// depth display unit per target (read off the DLL's byte tables 0x10046934 / 0x10046ab8 / 0x10046b64 / 0x10046c28)
type depthUnit = Db | Semitones | Octaves | Cents | Percent

let xyDepthUnit = target =>
  switch target {
  | 1 | 2 => Octaves
  | 5 | 21 | 22 | 23 => Semitones
  | 18 | 19 | 20 => Db
  | 32 => Cents
  | _ => Percent
  }

let envDepthUnit = target =>
  switch target {
  | 1 | 2 | 23 | 24 => Octaves
  | 7 | 8 | 9 | 25 | 26 | 27 => Semitones
  | 29 => Cents
  | _ => Percent
  }

let ccDepthUnit = target =>
  switch target {
  | 1 | 2 => Octaves
  | 21 | 22 | 23 => Semitones
  | 33 => Cents
  | _ => Percent
  }

// mod depth with unit chosen by the corresponding target (XY / M1,M2 / CC tables)
let depthText = (prefix, centsPrefix, targetOffset, unitOf, octScale) =>
  (v: float, prog) => {
    let x = 2. * v - 1.
    switch unitOf(prog->ByteView.getI32(targetOffset)) {
    | Db => `${prefix}${fixed(x * 60., 2)} dB`
    | Semitones => `${prefix}${fixed(x * 24., 2)} semitones`
    | Octaves => `${prefix}${fixed(x * octScale, 3)} octaves`
    | Cents => `${centsPrefix}${fixed(x * Math.abs(x) * 1200., 2)} cents`
    | Percent => `${prefix}${fixed(x * 100., 2)} %`
    }
  }

let onOffText = label => (v: float, _) => label ++ (ftol(v + 0.5) != 0. ? "on" : "off")

let keytrack = (v: float) => {
  let x = v * 4. - 2.
  if Math.abs(1. - x) < K.c0001 {
    1.
  } else if Math.abs(1. + x) < K.c0001 {
    -1.
  } else if Math.abs(x) < K.c0001 {
    0.
  } else {
    x
  }
}

let octaveOf = (v: float) => {
  let o = v * 4. + 1.
  let o = o < K.c101 ? K.c101 : o
  Math.abs(2. - o) < K.c001 ? 2. : o
}

let eqSlope = (v: float) =>
  if v > 0.5 {
    (v - 0.5) * 30. + 1.
  } else if v < 0.5 {
    1. / ((0.5 - v) * 30. + 1.)
  } else {
    1.
  }

// ---------------------------------------------------------------------------------------------------
// the 342 parameters

let paramCount = 342

let table: array<option<t>> = Array.make(~length=paramCount, None)

let def = (i, spec) => {
  let (name, action) = names->Array.getUnsafe(i)
  table->Array.setUnsafe(i, Some({...spec, index: i, name, action}))
}

[(0, 1), (6, 2)]->Array.forEach(((o, n)) => {
  let b = 4 * (n - 1) // osc 2 fields are 4 bytes after osc 1
  let osc = Int.toString(n)
  def(o + 0, sw(8468 + b, 5, Some(waveforms), enumText(`${osc} Waveform: `, 5, waveforms)))
  def(o + 1, amp(8508 + b, ampText(`${osc} Amp`)))
  def(
    o + 2,
    bip(
      8476 + b,
      48.,
      (v: float, _) => `Aftertouch -> ${osc} pitch: ${fixed((2. * v - 1.) * 48., 2)} semitones`,
      ~unit="semitones",
    ),
  )
  def(
    o + 3,
    {
      ...blank,
      offset: 8484 + b,
      storage: U32,
      max: 4294967295.,
      unit: "% (uint32 fraction of 2^32)",
      set: v => ByteView.toUint32(pow(2., 32.) * v + 0.5), // uint32 phase; v=1 wraps to 0 (DLL quirk)
      get: x => f32(ByteView.toUint32(x) * pow(2., -32.)),
      inv: x => ByteView.toUint32(x) / 4294967296.,
      text: (v: float, _) => `${osc} Pulsewidth: ${fixed(v * 100., 2)} %`,
    },
  )
  def(
    o + 4,
    {
      ...blank,
      offset: 8500 + b,
      max: 8.,
      unit: "Hz",
      set: v => f32(v * 8.),
      get: x => f32(x * 0.0625), // QUIRK: getParameter returns x/16 = v/2
      inv: x => x / 8.,
      text: (v: float, _) => `${osc} PWM rate: ${fixed(v * 16., 3)} Hz`,
    },
  )
  def(
    o + 5,
    bip(8492 + b, 1., (v: float, _) => `${osc} PWM depth: ${fixed((2. * v - 1.) * 100., 2)} %`),
  )
})
def(
  12,
  bip(8516, 4., ratioText("Transpose", 2, 48., 4.), ~unit="octaves (display: semitones = 12*x)"),
)
def(13, bip(8520, 50., (v: float, _) => `Detune: ${fixed((2. * v - 1.) * 50., 3)} Hz`, ~unit="Hz"))
def(
  14,
  bip(
    8524,
    60.,
    (v: float, _) => `Aftertouch -> osc: ${fixed((2. * v - 1.) * 60., 2)} dB`,
    ~unit="dB",
  ),
)
def(15, amp(8528, ampText("N Amp")))
def(
  16,
  bip(
    8532,
    60.,
    (v: float, _) => `Aftertouch -> noise: ${fixed((2. * v - 1.) * 60., 2)} dB`,
    ~unit="dB",
  ),
)
def(
  17,
  uni(8540, (v: float, _) =>
    v > 0. || Float.isNaN(v)
      ? `Noise resonance: ${fixed(v * 100., 2)} %`
      : "Noise resonance: no filtering"
  ),
)
def(18, bip(8536, 48., ratioText("Noise transpose", 2, 48., 4.), ~unit="semitones"))

type lfoOffsets = {
  unit: int,
  shape: int,
  speed: int,
  quantize: int,
  mode: int,
  cut1: int,
  cut2: int,
  res: int,
  pitch: int,
  pan: int,
  other: int,
}

[
  (
    19,
    1,
    {
      unit: 8544,
      shape: 8548,
      speed: 8556,
      quantize: 9520,
      mode: 8552,
      cut1: 8560,
      cut2: 8564,
      res: 8568,
      pitch: 8572,
      pan: 9224,
      other: 8576,
    },
  ),
  (
    30,
    2,
    {
      unit: 8580,
      shape: 8584,
      speed: 8592,
      quantize: 9524,
      mode: 8588,
      cut1: 8596,
      cut2: 8600,
      res: 8604,
      pitch: 8608,
      pan: 9228,
      other: 8612,
    },
  ),
]->Array.forEach(((base, n, o)) => {
  let l = `L${Int.toString(n)}`
  def(
    base + 0,
    sw(o.unit, 17, Some(lfoUnits), enumText(`LFO ${Int.toString(n)} unit: `, 17, lfoUnits)),
  )
  def(base + 1, sw(o.shape, 6, Some(lfoShapes), enumText(`${l} shape: `, 6, lfoShapes)))
  def(
    base + 2,
    {
      ...blank,
      offset: o.speed,
      min: 0.25,
      max: 256.,
      unit: "units (periods per unit, see LFO unit)",
      set: v => f32(lfoSpeed(v)),
      get: x =>
        f32(
          x <= 1. ? (4. - 1. / x) * f32(1. / 9.) : ((x - 1.) * f32(1. / 255.) + 0.5) * f32(2. / 3.),
        ),
      inv: x => x <= 1. ? (4. - 1. / x) / 9. : ((x - 1.) / 255. + 0.5) / 1.5,
      text: unitsText(`${l} speed`, o.quantize, lfoSpeed),
    },
  )
  def(base + 3, sw(o.quantize, 1, Some(lfoQuantize), enumText(`${l}: `, 1, lfoQuantize)))
  def(base + 4, sw(o.mode, 2, Some(lfoModes), enumText(`${l} mode: `, 2, lfoModes)))
  def(
    base + 5,
    bip(
      o.cut1,
      1.,
      (v: float, _) => `${l} -> cutoff 1: ${fixed((2. * v - 1.) * 4., 4)} octaves`,
      ~unit="x4 octaves",
    ),
  )
  def(
    base + 6,
    bip(
      o.cut2,
      1.,
      (v: float, _) => `${l} -> cutoff 2: ${fixed((2. * v - 1.) * 4., 4)} octaves`,
      ~unit="x4 octaves",
    ),
  )
  def(base + 7, uni(o.res, pct(`${l} -> resonance`)))
  def(
    base + 8,
    uni(
      o.pitch,
      (v: float, _) => `${l} -> pitch: ${fixed(v * v * v * v * 24., 3)} st`,
      ~unit="st = 24*x^4",
    ),
  )
  def(base + 9, uni(o.pan, pct(`${l} -> pan`)))
  def(base + 10, uni(o.other, pct(n == 1 ? "L1 -> L2 speed" : "L2 -> L1 speed")))
})

def(
  41,
  {
    ...sw(offFilter, 15, Some(filterTypes), enumText("Filter: ", 15, filterTypes)),
    storage: Lo16,
    states: Some(13),
    max: 12.,
  },
)
def(
  42,
  {
    ...sw(offFilter, 15, Some(filter2Types), (v: float, prog) =>
      if (
        (prog->ByteView.getI32(offFilter) &&& 0xffff) == 0 || prog->ByteView.getI32(offFDouble) == 0
      ) {
        "Filter 2: off (filter 1 and doubling needs to be on)"
      } else {
        enumText("Filter 2: ", 15, filter2Types)(v, prog)
      }
    ),
    storage: Hi16,
    states: Some(13),
    max: 12.,
  },
)
def(
  43,
  {
    ...blank,
    offset: 8432,
    unit: "normalized (Hz = v^3*10980+20)",
    set: f32,
    get: f32,
    text: (v: float, prog) => {
      let hz = f32(v * v * v * 10980. + 20.)
      let octave = prog->ByteView.getF32(offOctave)
      let ref =
        pow(octave, prog->ByteView.getF32(offCutRef) * K.c1_12) * prog->ByteView.getF32(offTune)
      hz < ref
        ? `Cutoff: ${fixed(hz, 2)} Hz (/${fixed(ref / hz, 4)})`
        : `Cutoff: ${fixed(hz, 2)} Hz (*${fixed(hz / ref, 4)})`
    },
  },
)
def(44, uni(8436, pct("Resonance")))

// envelopes: filter (45..51), amp (60..66), mod 1 (238..244), mod 2 (254..260)
type levelDisplay = LevelPercent | LevelDb
type envelope = {first: int, offset: int, display: levelDisplay}

let envelopes = [
  {first: 45, offset: 8300, display: LevelPercent},
  {first: 60, offset: 8232, display: LevelDb},
  {first: 238, offset: 9312, display: LevelPercent},
  {first: 254, offset: 9408, display: LevelPercent},
]

envelopes->Array.forEach(({first, offset: o, display}) => {
  let levelText = (label, skipDb, skipPercent) =>
    switch display {
    | LevelDb => levelDbText(label, skipDb)
    | LevelPercent => levelPercentText(label, skipPercent)
    }
  def(first + 0, sq(o + 4, 9999.8, 0.2, attackText, ~unit="ms"))
  def(first + 1, sq(o + 8, 10000., 0., holdText, ~unit="ms"))
  def(first + 2, sq(o + 12, 19990., 10., decay1Text(o + 44), ~unit="ms"))
  def(
    first + 3,
    lvl(o + 44, levelText("Breakpoint", "Breakpoint: skip decay 1", "Breakpoint: skip decay 1")),
  )
  def(first + 4, sq(o + 16, 19990., 10., decay2Text, ~unit="ms"))
  def(
    first + 5,
    lvl(o + 52, levelText("Sustain", "Sustain: 0.00 dB (100.00 %)", "Sustain: 100.00 %")),
  )
  def(first + 6, {...sq(o + 20, 19990., 10., releaseText, ~unit="ms"), offset2: Some(o + 24)})
})
def(
  52,
  {
    ...blank,
    offset: 8444,
    min: -2.,
    max: 2.,
    unit: "keytrack factor (snapped to -1/0/1 within 0.001)",
    set: v => f32(keytrack(v)),
    get: x => f32((x * 0.5 + 1.) * 0.5),
    inv: x => (x + 2.) / 4.,
    text: (v: float, _) => `Keytrack: ${fixed(keytrack(v), 4)}`,
  },
)
def(53, sw(8464, 2, Some(filterDouble), enumText("Double filter: ", 2, filterDouble)))
def(54, uni(8456, pct("Filter mix")))
def(55, uni(8448, (v: float, _) => `Split: ${fixed(v * 24., 2)} st`, ~unit="x24 semitones"))
def(
  56,
  {
    ...blank,
    offset: 8452,
    min: 0.2,
    max: 5.,
    unit: "filter-2 env time factor",
    set: v => f32(v > 0.5 ? 1. / ((v - 0.5) * 8. + 1.) : (0.5 - v) * 8. + 1.),
    // QUIRK: for x < 1 (v > 0.5) the DLL returns v-1 (negative) instead of v
    get: x => f32(x < 1. ? (1. / x - 1.) * 0.125 - 0.5 : 0.5 - (x - 1.) * 0.125),
    inv: x => x < 1. ? (1. / x - 1.) / 8. + 0.5 : 0.5 - (x - 1.) / 8.,
    text: (v: float, _) =>
      v < 0.5
        ? `Env ratio: /${fixed((0.5 - v) * 8. + 1., 3)}`
        : `Env ratio: *${fixed((v - 0.5) * 8. + 1., 3)}`,
  },
)
def(
  57,
  bip(
    8440,
    1.,
    (v: float, _) => `Env Mod: ${fixed((2. * v - 1.) * 8., 3)} octaves`,
    ~unit="x8 octaves",
  ),
)
let veloText = (v: float, _) => `Env velocity sensitivity: ${fixed((2. * v - 1.) * 100., 2)} %`
def(58, bip(9512, 1., veloText))
def(
  59,
  bip(
    8460,
    48.,
    (v: float, _) => `Aftertouch -> cutoff: ${fixed((2. * v - 1.) * 48., 2)} semitones`,
    ~unit="semitones",
  ),
)

def(67, sw(8616, 4, Some(chorusModes), enumText("Chorus mode: ", 4, chorusModes)))
def(68, sw(8620, 2, Some(chorusStereo), enumText("Chorus mode: ", 2, chorusStereo)))
def(
  69,
  sw(
    8624,
    15,
    None,
    (v: float, _) => `Chorus: ${int(ftol(15. * v + 0.5) + 1.)} voices`,
    ~add=1,
    ~unit="voices",
  ),
)
def(
  70,
  sq(
    8628,
    3.999,
    0.001,
    (v: float, _) => `Chorus speed: ${fixed(v * v * K.chorusSpeed + K.c0001, 4)} Hz`,
    ~unit="Hz",
  ),
)
[(71, 8632, "Chorus min delay"), (72, 8636, "Chorus depth")]->Array.forEach(((i, offset, label)) =>
  def(
    i,
    {
      ...blank,
      offset,
      min: K.c01,
      max: f32(K.chorusDelay + K.c01),
      unit: "ms",
      set: v => f32(v * K.chorusDelay + K.c01),
      get: x => f32((x - K.c01) * f32(1. / 99.9)),
      inv: x => (x - K.c01) / K.chorusDelay,
      text: (v: float, _) => `${label}: ${fixed(v * K.chorusDelay + K.c01, 2)} ms`,
    },
  )
)
def(73, bip(8644, 1., (v: float, _) => `Chorus feedback: ${fixed(v * 200. - 100., 2)} %`))
def(74, uni(8640, (v: float, _) => `Chorus mix: ${fixed(v * 100., 2)} % wet`))
def(75, sw(8648, 1, Some(delayOn), enumText("Delay: ", 1, delayOn)))
def(76, sw(8652, 14, Some(delayUnits), enumText("Delay unit: ", 14, delayUnits)))
def(77, sw(8656, 1, Some(delayQuantize), enumText("Delay: ", 1, delayQuantize)))
def(78, sw(8660, 2, Some(delayReverse), enumText("Delay, left: ", 2, delayReverse)))
def(79, sw(8664, 2, Some(delayReverse), enumText("Delay, right: ", 2, delayReverse)))
[(80, 8676, "Left length"), (81, 8684, "Right length")]->Array.forEach(((i, offset, label)) =>
  def(
    i,
    {
      ...blank,
      offset,
      min: 1.,
      max: 100.,
      unit: "delay units",
      set: v => f32(v * 99. + 1.),
      get: x => f32((x - 1.) * f32(1. / 99.)),
      inv: x => (x - 1.) / 99.,
      text: (v: float, prog) => {
        let length = v * 99. + 1.
        prog->ByteView.getI32(8656) != 0
          ? `${label}: ${int(ftol(length + 0.5))} units`
          : `${label}: ${fixed(length, 3)} units`
      },
    },
  )
)
[(82, 8680, "Left feedback"), (83, 8688, "Right feedback")]->Array.forEach(((i, offset, label)) =>
  def(
    i,
    {
      ...blank,
      offset,
      min: -2.,
      max: 2.,
      unit: "linear feedback gain",
      set: v => f32(v * 4. - 2.),
      get: x => f32((x + 2.) * 0.25),
      inv: x => (x + 2.) / 4.,
      text: (v: float, _) => {
        let x = v * 4. - 2.
        let small = v < 0.5 ? !(x <= -K.c0001) : x < K.c0001
        small
          ? `${label}: ${fixed(x * 100., 1)} % (-60.00+ dB)`
          : `${label}: ${fixed(x * 100., 1)} % (${fixed(log10(Math.abs(x)) * 20., 2)} dB)`
      },
    },
  )
)
def(
  84,
  uni(8668, (v: float, _) =>
    `Input pan: ${fixed(Math.abs(v * 200. - 100.), 1)} % ${v > 0.5 ? "right" : "left"}`
  ),
)
let rot = (offset, label) => {
  ...blank,
  offset,
  min: -K.pi,
  max: K.pi,
  unit: "radians",
  set: v => f32((2. * v - 1.) * K.pi),
  get: x => f32((x / K.pi + 1.) * 0.5),
  inv: x => (x / K.pi + 1.) / 2.,
  text: (v: float, _) => `${label}: ${fixed(2. * v - 1., 3)} Pi`,
}
def(85, rot(8672, "Rotation"))
def(86, uni(8692, (v: float, _) => `Lowpass: ${fixed(v * 100., 1)} %`))
def(87, uni(8696, (v: float, _) => `Highpass: ${fixed(v * 100., 1)} %`))
def(88, amp(8700, dryWetText("Dry")))
def(89, amp(8704, dryWetText("Wet")))
def(90, sw(8708, 1, Some(reverbOn), enumText("Reverb: ", 1, reverbOn)))
def(
  91,
  {
    ...blank,
    offset: 8712,
    min: 10.,
    max: 250.,
    unit: "size",
    set: v => f32(v * v * v * 240. + 10.),
    get: x => f32(pow((x - 10.) * (1. / 240.), 1. / 3.)),
    inv: x => Math.cbrt((x - 10.) / 240.),
    text: (v: float, _) => `Size: ${fixed(v * v * v * 240. + 10., 1)}`,
  },
)
def(
  92,
  {
    ...blank,
    offset: 8716,
    min: K.c01,
    max: 120.,
    unit: "sec (120 = infinite)",
    set: v => v == 1. ? 120. : f32(v * v * K.reverbLength + K.c01),
    // DLL constant is f32(1/29.9)+1ulp
    get: x => x < 30. ? f32(Math.sqrt((x - K.c01) * K.reverbLengthInv)) : 1.,
    inv: x => x >= 30. ? 1. : Math.sqrt(Math.max(0., (x - K.c01) / K.reverbLength)),
    text: (v: float, _) =>
      v < 1. || Float.isNaN(v)
        ? `Length: ${fixed(v * v * K.reverbLength + K.c01, 2)} sec`
        : "Length: ETERNITY.",
  },
)
def(93, uni(8720, (v: float, _) => `Dullness: ${fixed(v * 100., 1)} %`))
def(94, uni(8724, (v: float, _) => `Brightness: ${fixed(v * 100., 1)} %`))
def(95, amp(8728, dryWetText("Dry")))
def(96, amp(8732, dryWetText("Wet")))
def(97, rot(8736, "1"))
def(98, rot(8740, "2"))
def(99, rot(8744, "3"))
def(100, rot(8748, "Rotation"))
def(
  101,
  bip(8752, 500., (v: float, _) => `Predelay: ${fixed((2. * v - 1.) * 500., 1)} ms`, ~unit="ms"),
)
def(102, uni(8756, (v: float, _) => `Early reflections mix: ${fixed(v * 100., 1)} %`))
def(103, sw(8760, 2, Some(voiceModes), enumText("", 2, voiceModes)))
def(
  104,
  sw(
    8764,
    31,
    None,
    (v: float, _) => `Voices: ${int(ftol(31. * v + 0.5) + 1.)}`,
    ~add=1,
    ~unit="voices",
  ),
)
def(105, sq(8768, 500., 0., (v: float, _) => `Glide: ${fixed(v * v * 500., 2)} ms`, ~unit="ms"))
def(106, sw(8772, 6, Some(glideModes), enumText("Glide mode: ", 6, glideModes)))
def(107, amp(8776, ampText("Gain")))
def(108, bip(8780, 1., (v: float, _) => `Velocity: ${fixed(v * 200. - 100., 1)} %`))
def(109, sw(8784, 2, Some(aftertouchModes), enumText("Aftertouch mode: ", 2, aftertouchModes)))
def(
  110,
  bip(8788, 1., (v: float, _) => `Frequency pan: ${fixed((2. * v - 1.) * 100., 2)} %/octave`),
)
def(
  111,
  bip(8792, 1., (v: float, _) => `Frequency env scale: ${fixed((2. * v - 1.) * 200., 2)} %/octave`),
)
def(112, uni(8796, pct("Random pan")))
def(113, sq(8800, 20., 0., (v: float, _) => `Random amp: ${fixed(v * v * 20., 2)} dB`, ~unit="dB"))
def(
  114,
  sq(
    8804,
    1200.,
    0.,
    (v: float, _) => `Random frequency: ${fixed(v * v * 1200., 2)} cents`,
    ~unit="cents",
  ),
)
def(115, uni(8808, pct("Osc phase")))
def(116, uni(8812, pct("Osc phase random")))
def(117, sw(8816, 1, Some(offOn), onOffText("Osc retrigger: ")))
def(118, uni(8820, pct("PWM phase")))
def(119, uni(8824, pct("PWM phase random")))
def(120, sw(8828, 1, Some(offOn), onOffText("PWM retrigger: ")))
def(121, uni(8832, pct("LFO phase")))
def(122, uni(8836, pct("LFO phase random")))
def(123, sw(8840, 1, Some(offOn), onOffText("LFO retrigger: ")))
def(
  124,
  sw(
    10328,
    15,
    None,
    (v: float, _) => `U voices: ${int(ftol(15. * v + 0.5) + 1.)}`,
    ~add=1,
    ~unit="voices",
  ),
)
def(
  125,
  sq(
    10332,
    4800.,
    0.,
    (v: float, _) => `U detune: ${fixed(v * v * 4800., 2)} cents`,
    ~unit="cents",
  ),
)
def(126, uni(10336, pct("U stereo spread")))
def(127, uni(10340, pct("U pitch jitter")))
def(128, uni(10344, pct("U pan jitter")))
def(129, sw(8844, 5, Some(arpModes), enumText("Arp mode: ", 5, arpModes)))
def(130, sw(8848, 17, Some(arpUnits), enumText("Arp unit: ", 17, arpUnits)))
def(131, sw(8852, 1, Some(offOn), enumText("Quantize: ", 1, offOn)))
def(
  132,
  {
    ...blank,
    offset: 8856,
    min: 0.125,
    max: 32.,
    unit: "arp units per step",
    set: v => f32(arpStep(v)),
    get: x =>
      if x < 1. {
        x <= 0. ? 0. : f32((1. - (1. / x - 1.) * f32(1. / 7.)) * 0.25)
      } else {
        f32((x - 1.) * f32(0.75 / 31.) + 0.25)
      },
    inv: x =>
      if x < 1. {
        x <= 0. ? 0. : (1. - (1. / x - 1.) / 7.) * 0.25
      } else {
        (x - 1.) / K.arpStep + 0.25
      },
    text: unitsText("Arp step", 8852, arpStep),
  },
)
for k in 1 to 16 {
  let i = 132 + k
  def(
    i,
    sw(
      4 * i + 8328,
      15,
      Some(arpStepCommands),
      enumText(`Arp step ${Int.toString(k)}: `, 15, arpStepCommands),
    ),
  )
}
def(
  149,
  sw(
    8924,
    15,
    None,
    (v: float, _) => {
      let n = ftol(15. * v + 0.5)
      n == 0. ? "Arp pattern length: 1 step" : `Arp pattern length: ${int(n + 1.)} steps`
    },
    ~unit="steps-1",
  ),
)
for k in 1 to 7 {
  let note = Int.toString(k)
  def(
    149 + k,
    sw(4 * (149 + k) + 8328, 1, Some(offOn), (v: float, _) =>
      `Arp note ${note}: ${v > 0.5 ? "on" : "off"}`
    ),
  )
  def(
    156 + k,
    bip(4 * (156 + k) + 8328, 36., ratioText(`Arp note ${note}`, 3, 36., 3.), ~unit="semitones"),
  )
}
def(
  164,
  sw(8984, 1, Some(offOn), (v: float, _) => v > 0.5 ? "Pitch envelope: on" : "Pitch envelope: off"),
)
def(
  165,
  bip(
    8988,
    48.,
    (v: float, _) => v != 0. ? `Start: ${fixed((2. * v - 1.) * 48., 2)} st` : "Start: -inf st",
    ~unit="semitones (<= -48: no start offset)",
  ),
)
def(166, sq(8996, 9999.8, 0.2, attackText, ~unit="ms"))
def(
  167,
  bip(9004, 48., (v: float, _) => `Peak: ${fixed((2. * v - 1.) * 48., 2)} st`, ~unit="semitones"),
)
def(
  168,
  sq(9012, 19990., 10., (v: float, _) => `Decay: ${fixed(v * v * 19990. + 10., 2)} ms`, ~unit="ms"),
)
def(
  169,
  bip(
    9020,
    48.,
    (v: float, _) => `Sustain: ${fixed((2. * v - 1.) * 48., 2)} st`,
    ~unit="semitones",
  ),
)
def(
  170,
  bip(
    9028,
    48.,
    (v: float, _) => `Release: ${fixed((2. * v - 1.) * 48., 2)} st/sec`,
    ~unit="semitones/sec",
  ),
)
def(171, bip(9516, 1., veloText))
def(172, sw(9036, 4, Some(distTypes), enumText("Distortion: ", 4, distTypes)))
def(173, sw(9040, 3, Some(distModes), enumText("Distortion: ", 3, distModes)))
def(
  174,
  bip(
    9044,
    30.,
    (v: float, _) => `Distortion limit: ${fixed((2. * v - 1.) * 30., 2)} dB`,
    ~unit="dB",
  ),
)
def(
  175,
  bip(
    9048,
    60.,
    (v: float, _) => `Distortion pregain: ${fixed((2. * v - 1.) * 60., 2)} dB`,
    ~unit="dB",
  ),
)
def(
  176,
  bip(
    9052,
    60.,
    (v: float, _) => `Distortion postgain: ${fixed((2. * v - 1.) * 60., 2)} dB`,
    ~unit="dB",
  ),
)
def(177, sw(9056, 3, Some(distOversample), enumText("Distortion oversample: ", 3, distOversample)))
def(
  178,
  {
    ...blank,
    offset: 9060,
    min: 360.,
    max: 520.,
    unit: "Hz",
    set: v => f32((2. * v - 1.) * 80. + 440.),
    get: x => f32(((x - 440.) * f32(1. / 80.) + 1.) * 0.5),
    inv: x => ((x - 440.) / 80. + 1.) / 2.,
    text: (v: float, _) => `Tune: ${fixed((2. * v - 1.) * 80. + 440., 2)} Hz`,
  },
)
def(
  179,
  {
    ...blank,
    offset: 9064,
    min: K.c101,
    max: 5.,
    unit: `frequency ratio of an "octave" (2 = normal)`,
    set: v => f32(octaveOf(v)),
    get: x => f32((x - 1.) * 0.25),
    inv: x => (x - 1.) / 4.,
    text: (v: float, _) => {
      let o = octaveOf(v)
      let semis = 12. * Math.Constants.ln2 / Math.log(o)
      semis > 96. || Float.isNaN(semis)
        ? `Octave: ${fixed(o, 6)} (x2 > 96.0000 semitones)`
        : `Octave: ${fixed(o, 6)} (x2 = ${fixed(semis, 4)} semitones)`
    },
  },
)
let refText = label =>
  (v: float, prog) => {
    let t = f32(2. * v - 1.)
    let hz = pow(prog->ByteView.getF32(offOctave), t * 2.) * prog->ByteView.getF32(offTune)
    `${label}: ${fixed(t * 24., 2)} st (${fixed(hz, 2)} Hz)`
  }
def(180, bip(9072, 24., refText("Cutoff reference frequency"), ~unit="semitones"))
def(181, bip(9076, 24., refText("Pan center frequency"), ~unit="semitones"))
[
  "C",
  "C#/Db",
  "D",
  "D#/Eb",
  "E",
  "F",
  "F#/Gb",
  "G",
  "G#/Ab",
  "A",
  "A#/Bb",
  "B",
]->Array.forEachWithIndex((note, k) => {
  let i = 182 + k
  def(
    i,
    bip(
      4 * i + 8352,
      200.,
      (v: float, prog) => {
        let c = f32((2. * v - 1.) * 200.)
        let cents = k == 0 ? c : c + 100. * Int.toFloat(k)
        let ratio = pow(prog->ByteView.getF32(offOctave), cents * K.c1_1200)
        `Tune ${note}: ${fixed(c, 2)} cents (*${fixed(ratio, 4)})`
      },
      ~unit="cents",
    ),
  )
})
def(
  194,
  sq(
    9128,
    24.,
    0.,
    (v: float, _) => `Pitch bend range: ${fixed(v * v * 24., 2)} st`,
    ~unit="semitones",
  ),
)
def(
  195,
  {
    ...blank,
    offset: 9132,
    min: -4.,
    max: 4.,
    unit: "octaves (quantized to semitones)",
    set: v => f32(Math.floor((2. * v - 1.) * 48. + 0.5) * K.c1_12),
    get: x => f32((x * 0.25 + 1.) * 0.5),
    inv: x => (x / 4. + 1.) / 2.,
    text: (v: float, _) =>
      `Global transpose: ${fixed(Math.floor((2. * v - 1.) * 48. + 0.5), 0)} st`,
  },
)
def(196, bip(9136, 1., (v: float, _) => `X: ${fixed(2. * v - 1., 4)}`))
def(197, bip(9140, 1., (v: float, _) => `Y: ${fixed(2. * v - 1., 4)}`))
[(198, "X", 9160, 9176), (207, "Y", 9196, 9212)]->Array.forEach(((
  base,
  axis,
  target0,
  ccOffset,
)) => {
  for k in 1 to 4 {
    let slot = Int.toString(k)
    let prefix = `${axis} mod depth ${slot}: `
    def(
      base + k - 1,
      bip(
        4 * (base + k - 1) + 8352,
        1.,
        depthText(prefix, prefix, target0 + 4 * (k - 1), xyDepthUnit, 4.),
      ),
    )
    def(
      base + 3 + k,
      sw(4 * (base + 3 + k) + 8352, 33, Some(xyTargets), (v: float, _) => {
        let t = ftol(33. * v + 0.5)
        switch xyTargets->at(t) {
        | Some(target) =>
          let axis = axis == "Y" && t == 26. ? "y" : axis // DLL typo "y mod target"
          `${axis} mod target ${slot}: ${target}`
        | None => ""
        }
      }),
    )
  }
  def(
    base + 8,
    sw(
      ccOffset,
      127,
      None,
      (v: float, _) => v > 0. ? `${axis} CC: ${int03(ftol(127. * v + 0.5))}` : `${axis} CC: ---`,
      ~unit="MIDI CC number (0 = none)",
    ),
  )
})
def(216, uni(9216, (v: float, _) => `XY random radius: ${fixed(v, 4)}`))
def(
  217,
  {
    ...blank,
    offset: 9220,
    max: 16.,
    unit: "Hz",
    set: v => f32(v * 16.),
    get: x => f32(x * 0.0625),
    inv: x => x / 16.,
    text: (v: float, _) => `XY random rate: ${fixed(v * 16., 4)} Hz`,
  },
)
for k in 1 to 5 {
  let band = Int.toString(k)
  def(
    217 + k,
    {
      ...blank,
      offset: 4 * (217 + k) + 8360,
      min: 15.,
      max: 20000.,
      unit: "Hz",
      set: v => f32(v * v * v * 19985. + 15.),
      get: x => f32(pow((x - 15.) * (1. / 19985.), 1. / 3.)),
      inv: x => Math.cbrt((x - 15.) / 19985.),
      text: (v: float, _) => `EQ ${band} frequency: ${fixed(v * v * v * 19985. + 15., 2)} Hz`,
    },
  )
  def(
    222 + k,
    bip(
      4 * (222 + k) + 8360,
      60.,
      (v: float, _) => `EQ ${band} amp: ${fixed((2. * v - 1.) * 60., 2)} dB`,
      ~unit="dB",
    ),
  )
  def(
    227 + k,
    {
      ...blank,
      offset: 4 * (227 + k) + 8360,
      min: 1. / 16.,
      max: 16.,
      unit: "slope factor",
      set: v => f32(eqSlope(v)),
      get: x =>
        f32(
          x > 1.
            ? (x - 1.) * f32(1. / 30.) + 0.5
            : x < 1.
            ? 0.5 - (1. / x - 1.) * f32(1. / 30.)
            : 0.5,
        ),
      inv: x => x > 1. ? (x - 1.) / 30. + 0.5 : x < 1. ? 0.5 - (1. / x - 1.) / 30. : 0.5,
      text: (v: float, _) => `EQ ${band} slope: ${fixed(eqSlope(v), 3)}`,
    },
  )
  def(
    232 + k,
    sw(4 * (232 + k) + 8360, 3, Some(eqTypes), (v: float, _) =>
      switch eqTypes->at(ftol(3. * v + 0.5)) {
      | Some(t) => `EQ ${band} type: ${t}`
      | None => ""
      }
    ),
  )
}
def(245, bip(9504, 1., veloText))
def(261, bip(9508, 1., veloText))
[(246, "M1", 9376), (262, "M2", 9472)]->Array.forEach(((base, env, depthOffset)) =>
  for k in 1 to 4 {
    let slot = Int.toString(k)
    let prefix = `${env} mod depth ${slot}: `
    let targetOffset = depthOffset + 16 + 4 * (k - 1)
    def(
      base + k - 1,
      bip(depthOffset + 4 * (k - 1), 1., depthText(prefix, prefix, targetOffset, envDepthUnit, 2.)),
    )
    def(
      base + 3 + k,
      sw(targetOffset, 30, Some(modEnvTargets), (v: float, _) =>
        switch modEnvTargets->at(ftol(30. * v + 0.5)) {
        | Some(t) => `${env} mod target ${slot}: ${t}`
        | None => ""
        }
      ),
    )
  }
)
for ch in 1 to 16 {
  def(
    269 + ch,
    sw(9524 + 4 * ch, 1, Some(midiChannel), (v: float, _) =>
      `MIDI channel ${Int.toString(ch)}: ${ftol(v + 0.5) != 0. ? "receive" : "ignore"}`
    ),
  )
}
def(
  286,
  sw(9592, 1, Some(sustainPedal), (v: float, _) =>
    `Sustain pedal: ${ftol(v + 0.5) != 0. ? "use" : "ignore"}`
  ),
)
for c in 1 to 6 {
  let base = 287 + 9 * (c - 1)
  let offset = 10108 + 36 * (c - 1)
  let cc = Int.toString(c)
  def(
    base,
    sw(
      offset,
      127,
      None,
      (v: float, _) => {
        let n = ftol(127. * v + 0.5)
        n > 0. ? `CC ${cc}: ${int(n)}` : `CC ${cc}: ---`
      },
      ~unit="MIDI CC number (0 = none)",
    ),
  )
  for k in 1 to 4 {
    let slot = Int.toString(k)
    let depth = depthText(
      `CC ${cc} depth ${slot}: `,
      `CC ${cc} mod depth ${slot}: `,
      offset + 16 + 4 * k,
      ccDepthUnit,
      4.,
    )
    def(base + k, bip(offset + 4 * k, 1., depth))
    def(
      base + 4 + k,
      sw(offset + 16 + 4 * k, 34, Some(ccTargets), (v: float, _) => {
        let t = ftol(34. * v + 0.5)
        switch ccTargets->at(t) {
        | Some(target) if t >= 33. => `CC ${cc} mod target ${slot}: ${target}`
        | Some(target) => `CC ${cc} target ${slot}: ${target}`
        | None => `CC ${cc} target ${slot}: ??? mystery value! Something is broken.`
        }
      }),
    )
  }
}
def(
  341,
  sw(10324, 2, Some(oscMix), (v: float, _) => {
    let t = ftol(2. * v + 0.5)
    "Osc mix: " ++ oscMix->Array.getUnsafe(t == 1. || t == 2. ? Float.toInt(t) : 0)
  }),
)

// ---------------------------------------------------------------------------------------------------
// public API

// The parameter table.
let params = table->Array.mapWithIndex((spec, i) =>
  switch spec {
  | Some(p) => p
  | None => JsError.panic(`param ${Int.toString(i)} undefined`)
  }
)

let param = i => params->Array.getUnsafe(i)

// normalized (0..1) -> internal value exactly like setParameter (v is rounded to float32 first).
// float32 value for F32, int for I32/Lo16/Hi16, uint32 for U32. No clamping (the DLL does not clamp either).
let toInternal = (i, v) => param(i).set(f32(v))

// internal -> normalized, mathematical inverse of toInternal (not the DLL's getParameter), clamped to [0,1].
let toNormalized = (i, x) => {
  let v = param(i).inv(x)
  Float.isNaN(v) ? 0. : Math.min(1., Math.max(0., v))
}

// internal -> what Oatmeal.dll's getParameter returns (float32, with its quirks: PWM rate = v/2, F envspeed > 0.5 -> v-1).
let dllGetParameter = (i, x) => param(i).get(x)

// Read a parameter's internal value from a v38 program.
let readInternal = (prog, i) => {
  let p = param(i)
  switch p.storage {
  | F32 => prog->ByteView.getF32(p.offset)
  | U32 => prog->ByteView.getU32(p.offset)
  | Lo16 => (prog->ByteView.getI32(p.offset) &&& 0xffff)->Int.toFloat
  | Hi16 => (prog->ByteView.getI32(p.offset) >> 16)->Int.toFloat // DLL reads it as signed word
  | I32 => prog->ByteView.getI32(p.offset)->Int.toFloat
  }
}

// Write an internal value (also the second release field for envelope releases).
let writeInternal = (prog, i, x) => {
  let p = param(i)
  switch p.storage {
  | F32 =>
    prog->ByteView.setF32(p.offset, x)
    p.offset2->Option.forEach(o => prog->ByteView.setF32(o, f32(f32(x) * 0.5)))
  | U32 => prog->ByteView.setU32(p.offset, x)
  | Lo16 =>
    let packed = prog->ByteView.getI32(p.offset)
    prog->ByteView.setI32(p.offset, packed &&& ~~~0xffff ||| Float.toInt(x) &&& 0xffff)
  | Hi16 =>
    let packed = prog->ByteView.getI32(p.offset)
    prog->ByteView.setI32(p.offset, packed &&& 0xffff ||| (Float.toInt(x) &&& 0xffff) << 16)
  | I32 => prog->ByteView.setI32(p.offset, Float.toInt(x))
  }
}

// setParameter(i, v) applied to a program: exactly the bytes the DLL writes into the program.
let setParamNormalized = (prog, i, v) => writeInternal(prog, i, toInternal(i, v))

// Context used when no program is passed: only the fields status texts read, set to their Init values.
let initContext = Lazy.make(() => {
  let prog = Uint8Array.fromLength(10376)
  prog->ByteView.setF32(offOctave, 2.)
  prog->ByteView.setF32(offTune, 440.)
  prog->ByteView.setF32(offCutRef, 0.)
  envelopes->Array.forEach(e => {
    prog->ByteView.setF32(e.offset + 44, 1.)
    prog->ByteView.setF32(e.offset + 52, 0.5)
  })
  prog->ByteView.setI32(8852, 1) // Arp quantize on (Init)
  prog
})

// Full status-bar text (Oatmeal.dll 0x100405f0) for normalized value v, in the context of program prog
// (needed for: Octave/Tune/Cut reference ratios, decay-1 "skip", depth units, speed/length quantize, filter 2 off).
let statusText = (i, v, ~prog=?) =>
  if i < 0 || i >= paramCount {
    ""
  } else {
    param(i).text(f32(v), prog->Option.getOr(Lazy.get(initContext)))
  }

// The normalized value the status-text function expects for internal value x.  This is the DLL getParameter
// value (the status texts are written against it: e.g. PWM rate text = 16*v Hz with v = x/16), except for
// F envspeed (56), whose getParameter is broken for x < 1 (returns v-1) -> the proper inverse is used there.
let textNormalized = (i, x) => i == 56 ? toNormalized(i, x) : dllGetParameter(i, x)

let valuePart = s =>
  switch String.indexOfOpt(s, ":") {
  | Some(c) => s->String.slice(~start=c + 1)
  | None => ""
  }

// Value part of the display for internal value x ("1392.50 Hz (*3.1648)", "-inf dB", "skip decay 1", "ETERNITY.").
// prog supplies the context fields (Octave, Tune, targets, quantize switches...; default = Init values).
// ~dll: reproduce the VST host display exactly, bugs included (v = DLL getParameter for every param).
// ~v: use this normalized value directly (e.g. the value a GUI knob holds).
let displayText = (i, x, ~prog=?, ~dll=false, ~v=?) => {
  let v = switch v {
  | Some(v) => v
  | None => dll ? dllGetParameter(i, x) : textNormalized(i, x)
  }
  let value = statusText(i, v, ~prog?)->valuePart
  String.startsWith(value, " ") ? value->String.slice(~start=1) : value
}
