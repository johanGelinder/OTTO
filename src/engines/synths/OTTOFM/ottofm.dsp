//An FM synth. Adapted for OTTO, by OTTO.

import("stdfaust.lib");

process = vgroup("voices", par(n, 6, vgroup("%n", voice(n)))) :> _ ;

voice(vnum) = control(out : *(adsre_OTTO(a,d,s,r,midigate)), adsre_OTTO(a,d,s,r,midigate)>0.001)
with {
  midigate	= button ("v:midi/trigger");
  midifreq	= hslider("v:midi/freq", 440, 20, 1000, 1);
  midigain	= hslider("v:midi/velocity", 1, 0, 1, 1/127);

  //Properties for all operators
  algN = hslider("/algN", 0, 0 ,11, 1) : int;
  fmAmount = hslider("/fmAmount", 1, 0 ,1, 0.01);



  //ADSR envelope----------------------------
  a = hslider("/v:envelope/Attack", 0.001, 0.001, 4, 0.001);
  d = hslider("/v:envelope/Decay", 0.0, 0.0, 4, 0.001);
  s = hslider("/v:envelope/Sustain", 1.0, 0.0, 1.0, 0.01);
  r = hslider("/v:envelope/Release", 0.0, 0.0, 4.0, 0.01);

  adsre_OTTO(attT60,decT60,susLvl,relT60,gate) = envel <: attach(hbargraph("/v:v%vnum/carrier",0,1))
  with {
    ugate = gate>0;
    samps = ugate : +~(*(ugate)); // ramp time in samples
    attSamps = int(attT60 * ma.SR);
    target = select2(ugate, 0.0,
                select2(samps<attSamps, (susLvl)*float(ugate), 1/0.63));
    t60 = select2(ugate, relT60, select2(samps<attSamps, decT60, attT60*6.91));
    pole = ba.tau2pole(t60/6.91);
    envel = target : si.smooth(pole) : min(1.0);
  };


  out = par(i, 11, control( DXOTTO_algo(vnum,i, a,d,s,r, fmAmount, midifreq, midigain, midigate) , algN==i)) :> *(adsre_OTTO(a,d,s,r,midigate));
};

//------------------------------`DXOTTO_modulator_op`---------------------------
// FM carrier operator for OTTO. Implements a phase-modulable sine wave oscillator connected
// to an ADSR envelope generator.
// ```
// DXOTTO_modulator_op(freq, fmAmount, phaseMod,outLev,att,dec,sus,rel,gain,gate) : _
// ```
// * `freq`: frequency of the oscillator
// * `phaseMod`: phase deviation (-1 - 1) (The 'input' of an operator. It is 0 for the top of a stack without self-modulation, and _ otherwise)
// * `outLev`: output level (0-1)
// * `att, rel` : AR parameters
// * `gate`: trigger signal
//-----------------------------------------------------------------
DXOTTO_modulator_op(vnum, j, basefreq,fmAmount,phaseMod,gate) =
adsr_OTTO(attack,dec,suspos,rel,gate)*outLev*sineWave
with{
  //Sine oscillator
  tablesize = 1 << 16;
  sineWave = rdtable(tablesize, os.sinwaveform(tablesize), ma.modulo(int(os.phasor(tablesize,freq) + phaseMod*tablesize),tablesize));
  freq =  hslider("/v:op%j/ratio",1,0.25,4,0.01)*basefreq + hslider("/v:op%j/detune",0,-1,1,0.01)*25;

  outLev = hslider("/v:op%j/outLev",1,0,1,0.01)*fmAmount;
  //Envelope
  attack = hslider("/v:op%j/mAtt", 0, 0, 1, 0.01)*3;
  decrel = hslider("/v:op%j/mDecrel", 0, 0, 1, 0.01)*3;
  suspos = hslider("/v:op%j/mSuspos", 0, 0, 1, 0.01);
  dec = decrel*(1 - suspos);
  rel = decrel*suspos;
  adsr_OTTO(a,d,s,r,t) = on*(ads) : ba.sAndH(on) : rel <: attach(hbargraph("/v:v%vnum/v:op%j/modulator",0,1))
  with{
        on = t>0;
        off = t==0;
        attTime = ma.SR*a;
        decTime = ma.SR*d;
        relTime = ma.SR*r : max(0.001);
        sustainGain = t*s;
        ads = ba.countup(attTime+decTime,off) : ba.bpf.start(0,0) :
                ba.bpf.point(attTime,1) : ba.bpf.end(attTime+decTime,sustainGain);
        rel = _,ba.countup(relTime,on) : ba.bpf.start(0) : ba.bpf.end(relTime,0);
  };

};

//------------------------------`DXOTTO_carrier_op`---------------------------
// FM carrier operator for OTTO. Implements a phase-modulable sine wave oscillator connected
// to an ADSR envelope generator.
// ```
// DXOTTO_carrier_op(freq, phaseMod,outLev,att,dec,sus,rel,gain,gate) : _
// ```
// * `freq`: frequency of the oscillator
// * `phaseMod`: phase deviation (-1 - 1) (The 'input' of an operator. It is 0 for the top of a stack without self-modulation, and _ otherwise)
// * `outLev`: output level (0-1)
// * `att, dec, sus, rel` : ADSR parameters
// * `gain`: Gain from MIDI velocity
// * `gate`: trigger signal
//-----------------------------------------------------------------
DXOTTO_carrier_op(vnum, j, basefreq,phaseMod,att,dec,sus,rel,gain,gate) = outLev*gain*sineWave
with{
  //Sine oscillator
  tablesize = 1 << 16;
  sineWave = rdtable(tablesize, os.sinwaveform(tablesize), ma.modulo(int(os.phasor(tablesize,freq) + phaseMod*tablesize),tablesize));
  freq =  hslider("/v:op%j/ratio",1,0.25,4,0.01)*basefreq + hslider("/v:op%j/detune",0,-1,1,0.01)*25;

  outLev = hslider("/v:op%j/outLev",1,0,1,0.01);

};

//------------------------------`DXOTTO_algo`---------------------------
// DXOTTO algorithms. Implements the FM algorithms. Each algorithm uses 4 operators
// ```
// DXOTTO_algo(algN,att,dec,sus,rel,outLevel,opFreq,opDetune,feedback,freq,gain,gate) : _
// ```
// * `algN`: algorithm number (0-11, should be an int...)
// * `att, dec, sus, rel` : Carrier ADSR parameters (default)
// * `freq`: fundamental frequency
// * `gain`: general gain
// * `gate`: trigger signal
//-----------------------------------------------------------------
// Alg 0
DXOTTO_algo(vnum, 0, att, dec, sus, rel, fmAmount,freq, gain, gate) =
op4 : op3 : op2 : op1 : _
with{
  op4 = DXOTTO_modulator_op(vnum, 3, freq, fmAmount, 0,gate);
  op3 = DXOTTO_modulator_op(vnum, 2, freq, fmAmount, _,gate);
  op2 = DXOTTO_modulator_op(vnum, 1, freq, fmAmount, _,gate);
  op1 = ( + : DXOTTO_carrier_op(vnum, 0, freq, _,att,dec,sus,rel,gain,gate))~*(feedback1);
  feedback1 = hslider("/v:op0/feedback", 0, -0.5, 0.5, 0.01) : si.smoo;
};
// Alg 1
DXOTTO_algo(vnum, 1, att, dec, sus, rel, fmAmount, freq, gain, gate) =
(op4 , op3) :> op2 :op1 : _
with{
  op4 = DXOTTO_modulator_op(vnum, 3, freq, fmAmount, 0,gate);
  op3 = DXOTTO_modulator_op(vnum, 2, freq, fmAmount, 0,gate);
  op2 = DXOTTO_modulator_op(vnum, 1, freq, fmAmount, _,gate);
  op1 = ( + : DXOTTO_carrier_op(vnum, 0, freq, _,att,dec,sus,rel,gain,gate))~*(feedback1);
  feedback1 = hslider("/v:op0/feedback", 0, -0.5, 0.5, 0.01) : si.smoo;
};
// Alg 2
DXOTTO_algo(vnum, 2, att, dec, sus, rel, fmAmount, freq, gain, gate) =
op3 : (op2, op4) :> op1 : _
with{
  op4 = DXOTTO_modulator_op(vnum, 3, freq, fmAmount, 0,gate);
  op3 = DXOTTO_modulator_op(vnum, 2, freq, fmAmount, 0,gate);
  op2 = DXOTTO_modulator_op(vnum, 1, freq, fmAmount, _,gate);
  op1 = ( + : DXOTTO_carrier_op(vnum, 0, freq, _,att,dec,sus,rel,gain,gate))~*(feedback1);
  feedback1 = hslider("/v:op0/feedback", 0, -0.5, 0.5, 0.01) : si.smoo;
};
// Alg 3
DXOTTO_algo(vnum, 3, att, dec, sus, rel, fmAmount, freq, gain, gate) =
op4 <: (op2, op3) :> op1 : _
with{
  op4 = DXOTTO_modulator_op(vnum, 3, freq, fmAmount, 0,gate);
  op3 = DXOTTO_modulator_op(vnum, 2, freq, fmAmount, _,gate);
  op2 = DXOTTO_modulator_op(vnum, 1, freq, fmAmount, _,gate);
  op1 = ( + : DXOTTO_carrier_op(vnum, 0, freq, _,att,dec,sus,rel,gain,gate))~*(feedback1);
  feedback1 = hslider("/v:op0/feedback", 0, -0.5, 0.5, 0.01) : si.smoo;
};
// Alg 4
DXOTTO_algo(vnum, 4, att, dec, sus, rel, fmAmount, freq, gain, gate) =
op4 : op3 <: (op1, op2) :> _
with{
  op4 = DXOTTO_modulator_op(vnum, 3, freq, fmAmount, 0,gate);
  op3 = DXOTTO_modulator_op(vnum, 2, freq, fmAmount, _,gate);
  op2 = ( + : DXOTTO_carrier_op(vnum, 1, freq, _,att,dec,sus,rel,gain,gate))~*(feedback2);
  op1 = ( + : DXOTTO_carrier_op(vnum, 0, freq, _,att,dec,sus,rel,gain,gate))~*(feedback1);
  feedback1 = hslider("/v:op0/feedback", 0, -0.5, 0.5, 0.01) : si.smoo;
  feedback2 = hslider("/v:op1/feedback", 0, -0.5, 0.5, 0.01) : si.smoo;
};
// Alg 5
DXOTTO_algo(vnum, 5, att, dec, sus, rel, fmAmount, freq, gain, gate) =
op4 : op3 : (op1, op2) :> _
with{
  op4 = DXOTTO_modulator_op(vnum, 3, freq, fmAmount, 0,gate);
  op3 = DXOTTO_modulator_op(vnum, 2, freq, fmAmount, _,gate);
  op2 = ( + : DXOTTO_carrier_op(vnum, 1, freq, _,att,dec,sus,rel,gain,gate))~*(feedback2);
  op1 = DXOTTO_carrier_op(vnum, 0, freq, _,att,dec,sus,rel,gain,gate)~*(feedback1);
  feedback1 = hslider("/v:op0/feedback", 0, -0.5, 0.5, 0.01) : si.smoo;
  feedback2 = hslider("/v:op1/feedback", 0, -0.5, 0.5, 0.01) : si.smoo;
};
// Alg 6
DXOTTO_algo(vnum, 6, att, dec, sus, rel, fmAmount, freq, gain, gate) =
(op4, op3, op2) :> op1 : _
with{
  op4 = DXOTTO_modulator_op(vnum, 3, freq, fmAmount, 0,gate);
  op3 = DXOTTO_modulator_op(vnum, 2, freq, fmAmount, 0,gate);
  op2 = DXOTTO_modulator_op(vnum, 1, freq, fmAmount, 0,gate);
  op1 = ( + : DXOTTO_carrier_op(vnum, 0, freq, _,att,dec,sus,rel,gain,gate))~*(feedback1);
  feedback1 = hslider("/v:op0/feedback", 0, -0.5, 0.5, 0.01) : si.smoo;
};
// Alg 7
DXOTTO_algo(vnum, 7, att, dec, sus, rel, fmAmount, freq, gain, gate) =
(op2 : op1),(op4 : op3) :> _
with{
  op4 = DXOTTO_modulator_op(vnum, 3, freq, fmAmount, 0,gate);
  op3 = ( + : DXOTTO_carrier_op(vnum, 2, freq, _,att,dec,sus,rel,gain,gate))~*(feedback3);
  op2 = DXOTTO_modulator_op(vnum, 1, freq, fmAmount, 0,gate);
  op1 = ( + : DXOTTO_carrier_op(vnum, 0, freq, _,att,dec,sus,rel,gain,gate))~*(feedback1);
  feedback1 = hslider("/v:op0/feedback", 0, -0.5, 0.5, 0.01) : si.smoo;
  feedback3 = hslider("/v:op2/feedback", 0, -0.5, 0.5, 0.01) : si.smoo;
};
// Alg 8
DXOTTO_algo(vnum, 8, att, dec, sus, rel, fmAmount, freq, gain, gate) =
op4 <: (op1, op2, op3) :> _
with{
  op4 = DXOTTO_modulator_op(vnum, 3, freq, fmAmount, 0,gate);
  op3 = ( + : DXOTTO_carrier_op(vnum, 2, freq, _,att,dec,sus,rel,gain,gate))~*(feedback3);
  op2 = ( + : DXOTTO_carrier_op(vnum, 1, freq, _,att,dec,sus,rel,gain,gate))~*(feedback2);
  op1 = ( + : DXOTTO_carrier_op(vnum, 0, freq, _,att,dec,sus,rel,gain,gate))~*(feedback1);
  feedback1 = hslider("/v:op0/feedback", 0, -0.5, 0.5, 0.01) : si.smoo;
  feedback2 = hslider("/v:op1/feedback", 0, -0.5, 0.5, 0.01) : si.smoo;
  feedback3 = hslider("/v:op2/feedback", 0, -0.5, 0.5, 0.01) : si.smoo;
};
// Alg 9
DXOTTO_algo(vnum, 9, att, dec, sus, rel, fmAmount, freq, gain, gate) =
op1 : (op4, op2, op3) :> _
with{
  op4 = DXOTTO_carrier_op(vnum, 3, freq, _,att,dec,sus,rel,gain,gate)~*(feedback4);
  op3 = DXOTTO_carrier_op(vnum, 2, freq, _,att,dec,sus,rel,gain,gate)~*(feedback3);
  op2 = ( + : DXOTTO_carrier_op(vnum, 1, freq, _,att,dec,sus,rel,gain,gate))~*(feedback2);
  op1 = DXOTTO_modulator_op(vnum, 0, freq, fmAmount, 0,gate);
  feedback2 = hslider("/v:op1/feedback", 0, -0.5, 0.5, 0.01) : si.smoo;
  feedback3 = hslider("/v:op2/feedback", 0, -0.5, 0.5, 0.01) : si.smoo;
  feedback4 = hslider("/v:op3/feedback", 0, -0.5, 0.5, 0.01) : si.smoo;
};
// Alg 10
DXOTTO_algo(vnum, 10, att, dec, sus, rel, fmAmount, freq, gain, gate) =
(op1, op2, op3, op4) :> _
with{
  op4 = DXOTTO_carrier_op(vnum, 3, freq, _,att,dec,sus,rel,gain,gate)~*(feedback4);
  op3 = DXOTTO_carrier_op(vnum, 2, freq, _,att,dec,sus,rel,gain,gate)~*(feedback3);
  op2 = DXOTTO_carrier_op(vnum, 1, freq, _,att,dec,sus,rel,gain,gate)~*(feedback2);
  op1 = DXOTTO_carrier_op(vnum, 0, freq, _,att,dec,sus,rel,gain,gate)~*(feedback1);
  feedback1 = hslider("/v:op0/feedback", 0, -0.5, 0.5, 0.01) : si.smoo;
  feedback2 = hslider("/v:op1/feedback", 0, -0.5, 0.5, 0.01) : si.smoo;
  feedback3 = hslider("/v:op2/feedback", 0, -0.5, 0.5, 0.01) : si.smoo;
  feedback4 = hslider("/v:op3/feedback", 0, -0.5, 0.5, 0.01) : si.smoo;
};
