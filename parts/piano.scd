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

~pianoML13ExportMIDI = { |path|
	var midiClass = \SimpleMIDIFile.asClass;
	var midi, tempo = ~pianoML13[\tempo];
	var secondsPerBeat = 60 / tempo;
	var pedalSchedule;
	if(midiClass.isNil) { Error("Install wslib before exporting MIDI.").throw };
	if(~pianoML13[\melody].isEmpty) { Error("Generate a phrase before exporting.").throw };
	midi = midiClass.new(path);
	midi.init1(4, tempo, "%/4".format(~pianoML13[\beatsPerBar] ? 4));
	midi.timeMode = \seconds;
	~pianoML13[\accompaniment].do { |event|
		midi.addNote(
			~pianoML13Edo[\nearestMidi].value(~pianoML13Edo, event[\step]),
			event[\velocity], event[\beat] * secondsPerBeat,
			event[\dur] * secondsPerBeat, 127, track: 1
		);
	};
	~pianoML13[\melody].do { |event|
		midi.addNote(
			~pianoML13Edo[\nearestMidi].value(~pianoML13Edo, event[\step]),
			event[\velocity], event[\beat] * secondsPerBeat,
			event[\dur] * secondsPerBeat, 127, track: 2
		);
	};
	if(~pianoML13[\usePedal]) {
		pedalSchedule = ~pianoML13PedalSchedule.value(~pianoML13[\melody] ++ ~pianoML13[\accompaniment]);
		pedalSchedule.do { |event|
			midi.addCC(
				64, if(event[\down]) { 127 } { 0 },
				event[\beat] * secondsPerBeat,
				track: 3
			);
		};
	};
	midi.write;
	("Exported 12-tone MIDI approximation to %".format(path)).postln;
};
)