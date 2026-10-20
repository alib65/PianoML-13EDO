(
~pianoML13LoadMIDI = { |path|
	var midiClass = \SimpleMIDIFile.asClass;
	var midi, noteEvents, onsets, intervals, rhythms, notes;
	if(midiClass.isNil) {
		Error("SimpleMIDIFile is missing. Install the wslib Quark and recompile the class library.").throw;
	};
	midi = midiClass.read(path);
	if(midi.isNil or: { midi.midiEvents.isEmpty }) {
		Error("The selected MIDI file contains no readable events.").throw;
	};
	midi.timeMode = \ticks;
	noteEvents = midi.midiEvents.select { |event|
		(event[2] == \noteOn) and: { event[5] > 0 }
	}.sort { |left, right| left[1] <= right[1] };
	if(noteEvents.isEmpty) {
		Error("The selected MIDI file has no note-on events.").throw;
	};
	notes = noteEvents.collect { |event|
		(
			step: ~pianoML13Edo[\stepsFromMidi].value(~pianoML13Edo, event[4]),
			velocity: event[5].clip(1, 127),
			time: event[1]
		)
	};
	onsets = notes.collect(_[\time]);
	intervals = notes.collect { |note, index|
		if(index == 0) { 0 } { note[\step] - notes[index - 1][\step] }
	}.select { |interval| interval.abs <= 12 and: { interval != 0 } };
	rhythms = onsets.collect { |time, index|
		if(index < (onsets.size - 1)) {
			((onsets[index + 1] - time) / midi.division).round(0.25).clip(0.25, 2.0)
		} { 1.0 }
	}.select { |duration| duration > 0 };
	~pianoML13[\source] = (
		path: path,
		name: PathName(path).fileName,
		notes: notes,
		// Top-voice phrases: the opening primes the learned model.
		phrases: ~pianoML13MelodyFromMIDI.value(path),
		division: midi.division,
		intervals: if(intervals.notEmpty) { intervals } { [-5, -3, -2, -1, 1, 2, 3, 5] },
		rhythms: if(rhythms.notEmpty) { rhythms } { [0.25, 0.5, 0.75, 1.0] }
	);
	~pianoML13[\source]
};
)