(
~pianoML13[\sampleBuffers] = IdentityDictionary.new;
// Only the C samples (C1..C8, MIDI 24..108) are used as roots, so no
// 12-EDO pitch from the sampler leaks into the 13-EDO tuning: every note
// is the nearest C, resampled by an exact frequency ratio.
~pianoML13SampleKeys = Array.series(8, 24, 12);
~pianoML13VelocityBounds = [26, 34, 36, 43, 46, 50, 56, 64, 72, 80, 88, 96, 104, 112, 120, 127];

~pianoML13SampleInfo = { |step, velocity|
	var frequency = ~pianoML13Edo[\frequency].value(~pianoML13Edo, step);
	var sampleRoot = ~pianoML13SampleKeys.minItem { |root| (frequency / root.midicps).log2.abs };
	var layer = (~pianoML13VelocityBounds.detectIndex { |upperBound| velocity <= upperBound } ? 15 + 1).clip(1, 16);
	var sampleName = "C" ++ ((sampleRoot div: 12) - 1).asString;
	(
		sampleRoot: sampleRoot,
		attackKey: ("attack-%-%".format(sampleRoot, layer)).asSymbol,
		attackPath: ~pianoML13[\sampleDir] +/+ (sampleName ++ "v" ++ layer.asString ++ ".wav"),
		// rel1.wav is A0 (MIDI 21), so the file index is MIDI note - 20.
		releaseKey: ("release-%".format(sampleRoot)).asSymbol,
		releasePath: ~pianoML13[\sampleDir] +/+ ("rel%.wav".format(sampleRoot - 20)),
		rate: frequency / sampleRoot.midicps
	)
};

~pianoML13LoadSamples = { |events, completion|
	var requests = IdentityDictionary.new;
	var pending;
	events.do { |event|
		var info = ~pianoML13SampleInfo.value(event[\step], event[\velocity]);
		if(~pianoML13[\sampleBuffers][info[\attackKey]].isNil) {
			requests[info[\attackKey]] = info[\attackPath];
		};
		if(~pianoML13[\sampleBuffers][info[\releaseKey]].isNil) {
			requests[info[\releaseKey]] = info[\releasePath];
		};
	};
	[\pedalDown1, \pedalDown2, \pedalUp1, \pedalUp2].do { |key|
		if(~pianoML13[\sampleBuffers][key].isNil) {
			requests[key] = ~pianoML13[\sampleDir] +/+ (key.asString.replace("pedalDown", "pedalD").replace("pedalUp", "pedalU") ++ ".wav");
		};
	};
	pending = requests.size;
	if(pending == 0) {
		completion.value;
	} {
		requests.keysValuesDo { |cacheKey, path|
			if(File.exists(path).not) {
				Error("Salamander sample not found: %".format(path)).throw;
			};
			Buffer.read(s, path, action: { |buffer|
				~pianoML13[\sampleBuffers][cacheKey] = buffer;
				pending = pending - 1;
				if(pending == 0) { completion.value };
			});
		};
	};
};

SynthDef(\pianoML13Salamander, { |out = 0, buf = 0, rate = 1, amp = 0.16, sustain = 0.5, release = 0.35, velocity = 80, pedalMix = 0.08|
	var source, envelope, signal;
	source = PlayBuf.ar(2, buf, BufRateScale.kr(buf) * rate, doneAction: 0);
	envelope = EnvGen.kr(Env([0, 1, 1, 0], [0.004, sustain.max(0.02), release.max(0.02)]), doneAction: 2);
	signal = FreeVerb2.ar(source[0], source[1], pedalMix.clip(0, 0.7), 0.82, 0.35);
	Out.ar(out, signal * envelope * amp * (velocity / 127).sqrt);
}).add;

// Hammer/damper release noise is unpitched (pitch_keytrack=0 in the SFZ),
// so it is never resampled; its level follows the SFZ (-37 dB below notes).
SynthDef(\pianoML13SalamanderRelease, { |out = 0, buf = 0, amp = 0.004|
	var signal = PlayBuf.ar(2, buf, BufRateScale.kr(buf), doneAction: 2);
	Out.ar(out, signal * amp);
}).add;

SynthDef(\pianoML13SalamanderPedal, { |out = 0, buf = 0, amp = 0.02|
	var signal = PlayBuf.ar(2, buf, BufRateScale.kr(buf), doneAction: 2);
	Out.ar(out, signal * amp);
}).add;

// Overlapping pedalled notes can sum above 0 dBFS and distort; a master
// limiter after the default group keeps the output clean.
SynthDef(\pianoML13Limiter, { |out = 0, gate = 1|
	var input = In.ar(out, 2);
	var fade = EnvGen.kr(Env.asr(0.01, 1, 0.5), gate, doneAction: 2);
	ReplaceOut.ar(out, XFade2.ar(input, Limiter.ar(input, 0.89, 0.01), fade * 2 - 1));
}).add;
)
