(
// Pedal goes down on every downbeat and up just before the next bar.
~pianoML13PedalSchedule = { |events|
	var beatsPerBar = ~pianoML13[\beatsPerBar] ? 4;
	var endBeat = events.collect { |event| event[\beat] + event[\dur] }.maxItem;
	var bars = (endBeat / beatsPerBar).ceil.asInteger.max(1);
	var schedule = List.new;
	bars.do { |bar|
		schedule.add((beat: bar * beatsPerBar, down: true));
		schedule.add((beat: (bar * beatsPerBar) + beatsPerBar - 0.35, down: false));
	};
	schedule.asArray
};

~pianoML13GateForPedal = { |event|
	var beatsPerBar = ~pianoML13[\beatsPerBar] ? 4;
	var result = event.copy;
	var beatsToPedalUp = (beatsPerBar - 0.35) - (event[\beat] % beatsPerBar);
	var gateDuration = event[\dur];
	if(~pianoML13[\usePedal] and: { beatsToPedalUp > 0 }) {
		gateDuration = gateDuration.max(beatsToPedalUp);
	};
	result[\gateDur] = gateDuration;
	result
};

// Plays events scheduled at absolute beats, so chords and overlapping notes
// work. A leading rest waits until the first event.
~pianoML13NotePattern = { |events, amp|
	var sorted = events.copy.sort { |left, right| left[\beat] <= right[\beat] };
	var infos = sorted.collect { |event| ~pianoML13SampleInfo.value(event[\step], event[\velocity]) };
	var deltas = sorted.collect { |event, index|
		if(index < (sorted.size - 1)) { sorted[index + 1][\beat] - event[\beat] } { 0.1 }
	};
	Pbind(
		\type, Pseq([\rest] ++ Array.fill(sorted.size, \note), 1),
		\instrument, \pianoML13Salamander,
		\buf, Pseq([0] ++ infos.collect { |info| ~pianoML13[\sampleBuffers][info[\attackKey]].bufnum }, 1),
		\rate, Pseq([1] ++ infos.collect(_[\rate]), 1),
		\dur, Pseq([sorted.first[\beat]] ++ deltas, 1),
		// The synth's sustain is in seconds; gate lengths are in beats.
		\sustain, Pseq([0.1] ++ sorted.collect(_[\gateDur]), 1) / Pfunc { thisThread.clock.tempo },
		\velocity, Pseq([0] ++ sorted.collect(_[\velocity]), 1),
		\pedalMix, Pseq([0] ++ sorted.collect { |event| if(event[\gateDur] > event[\dur]) { 0.36 } { 0.08 } }, 1),
		\amp, amp
	)
};

~pianoML13Play = { |onStarted|
	var melody = ~pianoML13[\melody];
	var accompaniment = ~pianoML13[\accompaniment];
	var sourceEvents, melodyEvents, accompanimentEvents, pedalSchedule;
	if(melody.isEmpty or: { accompaniment.isEmpty }) {
		Error("Generate a phrase before pressing Play.").throw;
	};
	~pianoML13Stop.value;
	sourceEvents = melody ++ accompaniment;
	melodyEvents = melody.collect(~pianoML13GateForPedal);
	accompanimentEvents = accompaniment.collect(~pianoML13GateForPedal);
	pedalSchedule = if(~pianoML13[\usePedal]) { ~pianoML13PedalSchedule.value(sourceEvents) } { [] };
	~pianoML13[\pedalSchedule] = pedalSchedule;
	~pianoML13LoadSamples.value(sourceEvents, {
		var clock, patterns = List.new, releaseEvents, releaseDurs, pedalDurs;
		clock = TempoClock(~pianoML13[\tempo] / 60);
		~pianoML13[\clock] = clock;
		patterns.add(~pianoML13NotePattern.value(melodyEvents, 0.19));
		patterns.add(~pianoML13NotePattern.value(accompanimentEvents, 0.15));
		releaseEvents = (melodyEvents ++ accompanimentEvents).collect { |event|
			var info = ~pianoML13SampleInfo.value(event[\step], event[\velocity]);
			(beat: event[\beat] + event[\gateDur], buffer: ~pianoML13[\sampleBuffers][info[\releaseKey]])
		}.sort { |left, right| left[\beat] <= right[\beat] };
		if(releaseEvents.notEmpty) {
			releaseDurs = [releaseEvents.first[\beat]] ++ Array.fill(releaseEvents.size - 1, { |index|
				(releaseEvents[index + 1][\beat] - releaseEvents[index][\beat]).max(0.001)
			}) ++ [0.1];
			patterns.add(Pbind(
				\type, Pseq([\rest] ++ Array.fill(releaseEvents.size, \note), 1),
				\instrument, \pianoML13SalamanderRelease,
				\buf, Pseq([0] ++ releaseEvents.collect { |event| event[\buffer].bufnum }, 1),
				\dur, Pseq(releaseDurs, 1),
				\amp, Pseq([0] ++ Array.fill(releaseEvents.size, 0.004), 1)
			));
		};
		if(pedalSchedule.notEmpty) {
			pedalDurs = Array.fill(pedalSchedule.size, { |index|
				if(index < (pedalSchedule.size - 1)) {
					(pedalSchedule[index + 1][\beat] - pedalSchedule[index][\beat]).max(0.001)
				} { 0.1 }
			});
			patterns.add(Pbind(
				\instrument, \pianoML13SalamanderPedal,
				\buf, Pseq(pedalSchedule.collect { |event, index|
					var key = if(event[\down]) {
						[\pedalDown1, \pedalDown2][(index div: 2) % 2]
					} {
						[\pedalUp1, \pedalUp2][(index div: 2) % 2]
					};
					~pianoML13[\sampleBuffers][key].bufnum
				}, 1),
				\dur, Pseq(pedalDurs, 1),
				\amp, 0.02
			));
		};
		~pianoML13[\limiter] = Synth(\pianoML13Limiter, target: s.defaultGroup, addAction: \addAfter);
		~pianoML13[\player] = Ppar(patterns.asArray, 1).play(clock);
		if(onStarted.notNil) { onStarted.value };
	});
};

~pianoML13Stop = {
	if(~pianoML13[\player].notNil) {
		~pianoML13[\player].stop;
		~pianoML13[\player] = nil;
	};
	if(~pianoML13[\clock].notNil) {
		~pianoML13[\clock].stop;
		~pianoML13[\clock] = nil;
	};
	if(~pianoML13[\limiter].notNil) {
		~pianoML13[\limiter].release;
		~pianoML13[\limiter] = nil;
	};
};

// Renders the current piece to an audio file offline (NRT): a separate
// scsynth process plays the same notes, release and pedal noises through
// the limiter, faster than real time. onDone receives the duration in
// seconds, onError a message.
~pianoML13ExportAudio = { |path, onDone, onError|
	var melody = ~pianoML13[\melody], accompaniment = ~pianoML13[\accompaniment];
	var secondsPerBeat = 60 / ~pianoML13[\tempo];
	var buffers = IdentityDictionary.new, paths = List.new, score = List.new;
	var bufferFor, noteEvents, pedalSchedule, endSeconds, oscPath, options;
	if(melody.isEmpty) {
		onError.value("Generate a phrase before exporting audio.");
	} {
		bufferFor = { |key, file|
			buffers[key] ?? {
				buffers[key] = paths.size;
				paths.add(file);
				buffers[key]
			}
		};
		noteEvents = (melody.collect { |event| [event, 0.19] } ++ accompaniment.collect { |event| [event, 0.15] })
			.collect { |pair| [~pianoML13GateForPedal.value(pair[0]), pair[1]] };
		noteEvents.do { |pair|
			var event = pair[0];
			var info = ~pianoML13SampleInfo.value(event[\step], event[\velocity]);
			score.add([event[\beat] * secondsPerBeat, [\s_new, \pianoML13Salamander, -1, 0, 0,
				\buf, bufferFor.value(info[\attackKey], info[\attackPath]),
				\rate, info[\rate],
				\sustain, event[\gateDur] * secondsPerBeat,
				\velocity, event[\velocity],
				\pedalMix, if(event[\gateDur] > event[\dur]) { 0.36 } { 0.08 },
				\amp, pair[1]]]);
			score.add([(event[\beat] + event[\gateDur]) * secondsPerBeat, [\s_new, \pianoML13SalamanderRelease, -1, 0, 0,
				\buf, bufferFor.value(info[\releaseKey], info[\releasePath]),
				\amp, 0.004]]);
		};
		pedalSchedule = if(~pianoML13[\usePedal]) { ~pianoML13PedalSchedule.value(melody ++ accompaniment) } { [] };
		pedalSchedule.do { |event, index|
			var name = if(event[\down]) { "pedalD%.wav" } { "pedalU%.wav" }.format(((index div: 2) % 2) + 1);
			score.add([event[\beat] * secondsPerBeat, [\s_new, \pianoML13SalamanderPedal, -1, 0, 0,
				\buf, bufferFor.value(name.asSymbol, ~pianoML13[\sampleDir] +/+ name),
				\amp, 0.02]]);
		};
		endSeconds = ((melody ++ accompaniment).collect { |event| event[\beat] + event[\dur] }.maxItem * secondsPerBeat) + 4;
		// Setup runs as one bundle at time 0 (definitions, then samples, then
		// the limiter at the tail); the music starts 0.1 s later.
		score = score.collect { |entry| [entry[0] + 0.1, entry[1]] };
		score.addFirst([0] ++
			[\pianoML13Salamander, \pianoML13SalamanderRelease, \pianoML13SalamanderPedal, \pianoML13Limiter].collect { |name|
				[\d_recv, SynthDescLib.global[name].def.asBytes]
			} ++
			paths.collect { |file, bufnum| [\b_allocRead, bufnum, file, 0, 0] } ++
			[[\s_new, \pianoML13Limiter, 1000, 1, 0]]);
		score.add([endSeconds + 0.1, [\c_set, 0, 0]]);
		oscPath = PathName.tmp +/+ "pianoML13-%.osc".format(UniqueID.next);
		options = ServerOptions.new
			.numOutputBusChannels_(2)
			.numInputBusChannels_(0)
			.numBuffers_((paths.size + 64).nextPowerOfTwo)
			.memSize_(65536)
			.sampleRate_(48000);
		Score(score.asArray).sort.recordNRT(oscPath, path, nil, 48000, "WAV", "int24", options, action: {
			File.delete(oscPath);
			if(File.exists(path)) { onDone.value(endSeconds) } { onError.value("Audio render failed; see the post window.") };
		});
	};
};

// Writes a MIDI 2.0 Clip File (SMF2CLIP; MMA/AMEI document M2-116-U), hand-rolled
// as sequences of Universal MIDI Packet words -- no SC quark implements MIDI 2.0
// yet. Each note carries its exact 13-EDO pitch as a Note On/Off Per-Note Pitch
// 7.9 attribute (7 semitone bits + 9 fractional bits), so unlike the old 12-tone
// SMF export, pitch is exact rather than rounded to the nearest semitone.
// Byte layout cross-checked against atsushieno/ktmidi's Midi2ReaderWriter.kt and
// UmpFactory.kt (reference MIDI 2.0 implementation), since the MMA PDF spec has
// no machine-readable text extract.
~pianoML13ExportMIDI = { |path|
	var ticksPerQuarter = 480;
	var melody = ~pianoML13[\melody], accompaniment = ~pianoML13[\accompaniment];
	var pedalSchedule, file;

	var ticksFor = { |beat| (beat * ticksPerQuarter).round.asInteger };

	// Absolute MIDI note number (fractional) for a 13-EDO step; step 0 = A4 = MIDI 69.
	// Only pitch7_9For below uses this -- it is the exact pitch a receiver must
	// use for correct playback.
	var midiFloatFor = { |step| 69 + (step * 12 / 13) };

	// The Note On/Off "note" field is the scale degree itself, 0-12, the same
	// numbering the harmony field already uses (e.g. "0,3,7"). Earlier this
	// rounded to the nearest 12-tone MIDI note instead, which put two
	// different 13-EDO steps on the same number; round-tripping cleanly
	// through a plain 12-tone MIDI device is not a goal, so that rounding is
	// gone and every scale just uses 0-12.
	var noteNumberFor = { |step| step.mod(13) };

	// Pitch 7.9: 7-bit semitone + 9-bit fraction (1/512 semitone resolution),
	// clipped just under 128 so the fraction can never carry into a 17th bit.
	var pitch7_9For = { |step|
		var pitch = midiFloatFor.value(step).clip(0, 127.998046875);
		var semitone = pitch.asInteger;
		var microtone = pitch - semitone;
		(semitone << 9) + (microtone * 512).round.asInteger
	};

	// MIDI 2.0 Channel Voice word 1 (group 0), per UMP 4.2.
	var channelVoiceWord1 = { |statusByte, channel, byte3, byte4|
		0x40000000 + ((statusByte + channel) << 16) + (byte3 << 8) + byte4
	};

	var noteWords = { |isOn, note, attributeType, velocity16, attributeData16|
		[
			channelVoiceWord1.value(if(isOn) { 0x90 } { 0x80 }, 0, (note bitAnd: 0x7F), (attributeType bitAnd: 0xFF)),
			((velocity16 bitAnd: 0xFFFF) << 16) + (attributeData16 bitAnd: 0xFFFF)
		]
	};

	var ccWords = { |index8, data32|
		[channelVoiceWord1.value(0xB0, 0, (index8 bitAnd: 0x7F), 0), data32]
	};

	// Flex Data (type 0xD), format 0 (complete in one packet, <=12 text bytes),
	// addressed by channel 0, status bank 1 (Metadata Text), status 0
	// (Unknown/custom -- there is no standard "note spelling" status). Carries
	// the 13-EDO letter name (e.g. "E#4") alongside each Note On, since the
	// name itself (unlike pitch) has nowhere else to go in a MIDI file.
	var noteNameWords = { |name|
		var bytes = name.collect(_.ascii).keep(12);
		var wordFor = { |offset|
			((bytes[offset] ?? 0) << 24) + ((bytes[offset + 1] ?? 0) << 16)
			+ ((bytes[offset + 2] ?? 0) << 8) + (bytes[offset + 3] ?? 0)
		};
		[0xD0000100, wordFor.value(0), wordFor.value(4), wordFor.value(8)]
	};

	// Delta Clockstamp is a 20-bit field; chain DCS(0xFFFFF) words for longer gaps.
	var deltaClockstampWords = { |deltaTicks|
		var remaining = deltaTicks, words = List.new;
		while { remaining > 0xFFFFF } {
			words.add(0x00400000 + 0xFFFFF);
			remaining = remaining - 0xFFFFF;
		};
		words.add(0x00400000 + remaining);
		words.asArray
	};

	var writeTrack = { |events|
		var sorted = events.sort { |a, b| a[\tick] < b[\tick] };
		var lastTick = 0;
		file.putString("SMF2CLIP");
		file.putInt32(0x00400000); // DCS(0)
		file.putInt32(0x00300000 + ticksPerQuarter); // DCTPQ
		file.putInt32(0x00400000); // DCS(0)
		file.putInt32(0xF0200000); file.putInt32(0); file.putInt32(0); file.putInt32(0); // Start of Clip
		sorted.do { |event|
			deltaClockstampWords.value(event[\tick] - lastTick).do { |w| file.putInt32(w) };
			lastTick = event[\tick];
			event[\words].do { |w| file.putInt32(w) };
		};
		file.putInt32(0x00400000); // DCS(0)
		file.putInt32(0xF0210000); file.putInt32(0); file.putInt32(0); file.putInt32(0); // End of Clip
	};

	var noteEvents = { |events|
		events.collect { |event|
			var note = noteNumberFor.value(event[\step]);
			var attributeData = pitch7_9For.value(event[\step]);
			var velocity16 = (event[\velocity] bitAnd: 0x7F) << 9;
			var onTick = ticksFor.value(event[\beat]);
			[
				(tick: onTick, words: noteWords.value(true, note, 3, velocity16, attributeData)),
				(tick: onTick, words: noteNameWords.value(~pianoML13Edo[\nameFor].value(~pianoML13Edo, event[\step]))),
				(tick: ticksFor.value(event[\beat] + event[\dur]), words: noteWords.value(false, note, 0, 0, 0))
			]
		}.flatten(1)
	};

	if(melody.isEmpty) { Error("Generate a phrase before exporting.").throw };

	pedalSchedule = if(~pianoML13[\usePedal]) {
		~pianoML13PedalSchedule.value(melody ++ accompaniment)
	} { [] };

	file = File(path, "wb");
	file.putString("AAAAAAAA");
	file.putString("EEEEEEEE");
	file.putInt32(ticksPerQuarter);
	file.putInt32(3); // accompaniment, melody, pedal tracks

	writeTrack.value(noteEvents.value(accompaniment));
	writeTrack.value(noteEvents.value(melody));
	writeTrack.value(pedalSchedule.collect { |event|
		(tick: ticksFor.value(event[\beat]), words: ccWords.value(64, if(event[\down]) { 127 << 25 } { 0 }))
	});

	file.close;
	("Exported MIDI 2.0 Clip File (exact 13-EDO pitch) to %".format(path)).postln;
};
)