(
// Left-hand accompaniment over the current chord.
//
// Forms:
//   * written figurations (broken chord, arpeggio, Alberti, waltz, block
//     chords, octave bass), one bar at a time;
//   * "Learned (corpus)": a Markov model of the corpus left hand (notes below
//     middle C), note by note. Each token is the leap of the lowest note, the
//     time to the next onset, and how many notes sound together. The corpus
//     holds recorded performances whose bar lines do not match the music, so
//     the model ignores bars; generated notes are snapped onto the current
//     13-EDO chord, and the first note of each bar takes the chord root;
//   * "Mixed": a new form every 4 bars, so long pieces keep changing.
// The last bar is always a held tonic chord.

~pianoML13LeftHandForms = ["Mixed", "Learned (corpus)", "Broken chord", "Arpeggio", "Alberti", "Waltz", "Block chords", "Octave bass"];

~pianoML13LeftHand = (model: nil);

// Chord root in the bass register (about D2 to A2).
~pianoML13BassStep = { |chord|
	(-35..-23).detect { |step| (step % 13) == chord.first }
};

// The first `count` chord tones at or above `bass`.
~pianoML13ChordTones = { |chord, bass, count = 8|
	var tones = List.new, step = bass.asInteger;
	while { tones.size < count } {
		if(chord.includes(step % 13)) { tones.add(step) };
		step = step + 1;
	};
	tones.asArray
};

~pianoML13SnapToChord = { |target, chord|
	// Integer steps: `includes` compares by identity, so 0.0 would not match 0.
	chord.collect { |pitchClass| pitchClass + (13 * ((target - pitchClass) / 13).round) }.minItem { |step| (step - target).abs }.asInteger
};

// One bar of a written form: an array of [onset, duration, step].
~pianoML13FormBar = { |form, chord, beatsPerBar|
	var bass = ~pianoML13BassStep.value(chord);
	var tones = ~pianoML13ChordTones.value(chord, bass);
	var eighths = (beatsPerBar * 2).asInteger;
	var half = if(beatsPerBar == 4) { 2 } { beatsPerBar };
	var notes = List.new;
	var chordAt = { |onset, duration| tones.copyRange(1, 3).do { |step| notes.add([onset, duration, step]) } };
	switch(form)
	{ "Broken chord" } {
		beatsPerBar.do { |beat| notes.add([beat, 0.95, tones[beat % 3]]) };
	}
	{ "Arpeggio" } {
		eighths.do { |index| notes.add([index * 0.5, 0.5, tones[[0, 1, 2, 3, 4, 3, 2, 1].wrapAt(index)]]) };
	}
	{ "Alberti" } {
		eighths.do { |index| notes.add([index * 0.5, 0.5, tones[[0, 2, 1, 2].wrapAt(index)]]) };
	}
	{ "Waltz" } {
		notes.add([0, 1, bass]);
		(1..(beatsPerBar - 1)).do { |beat| chordAt.value(beat, 0.8) };
	}
	{ "Block chords" } {
		(0, half..(beatsPerBar - 1)).do { |onset|
			notes.add([onset, half * 0.95, bass]);
			chordAt.value(onset, half * 0.95);
		};
	}
	{ "Octave bass" } {
		notes.add([0, half * 0.95, bass - 13]);
		notes.add([0, half * 0.95, bass]);
		if(beatsPerBar == 4) { chordAt.value(2, 1.9) } { [1, 2].do { |beat| chordAt.value(beat, 0.9) } };
	}
	{ "Final" } {
		notes.add([0, beatsPerBar, bass - 13]);
		notes.add([0, beatsPerBar, bass]);
		chordAt.value(0, beatsPerBar);
	};
	notes.asArray
};

~pianoML13LeftHandKey = { |token| "%,%,%".format(token[\interval], token[\rhythm], token[\voices]) };

// Left-hand token phrases of one MIDI file. Notes below middle C that start
// together (1/12-beat grid) form one onset; a gap over 4 beats or a leap over
// an octave starts a new phrase.
~pianoML13LeftHandFromMIDI = { |path|
	var midi = SimpleMIDIFile.read(path);
	var division, grid, onsets, ticks, phrases, phrase, previousLow;
	midi.timeMode = \ticks;
	division = midi.division.max(1);
	grid = (division / 12).max(1);
	onsets = Dictionary.new;
	midi.noteSustainEvents.do { |event|
		if((event[5] > 0) and: { event[3] != 9 } and: { event[4] < 60 }) {
			var tick = (event[1] / grid).round * grid;
			if(onsets[tick].isNil) { onsets[tick] = Set.new };
			onsets[tick].add(event[4]);
		};
	};
	ticks = onsets.keys.asArray.sort;
	phrases = List.new;
	phrase = List.new;
	ticks.do { |tick, index|
		var low = ~pianoML13Edo[\stepsFromMidi].value(~pianoML13Edo, onsets[tick].minItem);
		var gap = if(index < (ticks.size - 1)) { (ticks[index + 1] - tick) / division } { 1.0 };
		var interval = if(previousLow.isNil) { 0 } { low - previousLow };
		if(interval.abs > 13) {
			if(phrase.size >= 4) { phrases.add(phrase.asArray) };
			phrase = List.new;
			interval = 0;
		};
		phrase.add((interval: interval, rhythm: ~pianoML13RhythmIndex.value(gap.min(2.0)), voices: onsets[tick].size.clip(1, 4)));
		previousLow = low;
		if(gap > 4) {
			if(phrase.size >= 4) { phrases.add(phrase.asArray) };
			phrase = List.new;
			previousLow = nil;
		};
	};
	if(phrase.size >= 4) { phrases.add(phrase.asArray) };
	phrases.asArray
};

// Variable-order (0..2) counts of left-hand tokens; contexts seen fewer than
// 3 times are dropped. `counts` lets a MIDI file's phrases be merged into an
// already-trained model (e.g. a loaded primer file) instead of starting over.
~pianoML13TrainLeftHand = { |phrases, counts|
	counts = counts ?? { Dictionary.new };
	phrases.do { |phrase|
		var keys = phrase.drop(1).collect(~pianoML13LeftHandKey);
		keys.do { |key, index|
			3.do { |order|
				if(index >= order) {
					var context = keys.copyRange(index - order, index - 1).join(" ");
					var table = counts[context];
					if(table.isNil) { table = Dictionary.new; counts[context] = table };
					table[key] = (table[key] ? 0) + 1;
				};
			};
		};
	};
	counts.keys.asArray.do { |context|
		if(context.notEmpty and: { counts[context].values.sum < 3 }) { counts.removeAt(context) };
	};
	counts
};

// Samples the next left-hand token with Witten-Bell smoothing over orders
// 0..2, shaped by temperature. Returns [interval, rhythmIndex, voices].
~pianoML13NextLeftHandToken = { |history, temperature = 1|
	var counts = ~pianoML13LeftHand[\model];
	var keys = history.keep(-2);
	var unigram = counts[""];
	var unigramTotal = unigram.values.sum;
	var tokens = unigram.keys.asArray;
	var probs = tokens.collect { |key| unigram[key] / unigramTotal };
	[1, 2].do { |order|
		var table = if(keys.size >= order) { counts[keys.keep(order.neg).join(" ")] };
		if(table.notNil) {
			var total = table.values.sum;
			var lambda = total / (total + table.size);
			probs = tokens.collect { |key, index| (lambda * ((table[key] ? 0) / total)) + ((1 - lambda) * probs[index]) };
		};
	};
	tokens.wchoose((probs ** (1 / temperature)).normalizeSum).split($,).collect(_.asInteger)
};

// The learned left hand for the whole piece except the final bar.
~pianoML13LearnedLeftHand = { |harmony, bars, beatsPerBar, temperature = 1|
	var notes = List.new, history = List.new;
	var rhythmClasses = ~pianoML13Learn[\rhythmClasses];
	var beat = 0.0, low = ~pianoML13BassStep.value(harmony.first), lastBar = -1;
	var end = bars * beatsPerBar;
	while { beat < end } {
		var bar = (beat / beatsPerBar).floor.asInteger;
		var chord = harmony.wrapAt(bar);
		var token = ~pianoML13NextLeftHandToken.value(history.asArray, temperature);
		var duration = rhythmClasses[token[1]];
		low = if(bar != lastBar) {
			// New bar: the bass takes the chord root, in the octave nearest the line.
			~pianoML13SnapToChord.value(low + token[0], [chord.first])
		} {
			~pianoML13SnapToChord.value(low + token[0], chord)
		};
		// Keep the line between A0 and about A3.
		while { low < -50 } { low = low + 13 };
		while { low > -14 } { low = low - 13 };
		~pianoML13ChordTones.value(chord, low, token[2]).do { |step|
			notes.add([beat, duration.min(end - beat), step]);
		};
		history.add(~pianoML13LeftHandKey.value((interval: token[0], rhythm: token[1], voices: token[2])));
		lastBar = bar;
		beat = beat + duration;
	};
	notes.asArray
};

~pianoML13LeftHandReady = { ~pianoML13LeftHand[\model].notNil };

// The whole left hand: an array of (step, beat, dur, velocity) events.
~pianoML13Accompaniment = { |harmony, bars, beatsPerBar, form, temperature = 1|
	var events = List.new;
	var learned = if(~pianoML13LeftHandReady.value) {
		~pianoML13LearnedLeftHand.value(harmony, bars - 1, beatsPerBar, temperature)
	} { [] };
	var written = ~pianoML13LeftHandForms.drop(2);
	var mixedChoices = if(learned.notEmpty) { written ++ ["Learned (corpus)"] } { written };
	var mixedForm;
	bars.do { |bar|
		var last = bar == (bars - 1);
		var chord = if(last) { harmony.first } { harmony.wrapAt(bar) };
		var barStart = bar * beatsPerBar;
		var barForm = form, notes;
		if(form == "Mixed") {
			if((bar % 4) == 0) { mixedForm = mixedChoices.reject { |name| name == mixedForm }.choose };
			barForm = mixedForm;
		};
		if((barForm == "Learned (corpus)") and: { learned.isEmpty }) { barForm = "Broken chord" };
		if(last and: { bars > 1 }) { barForm = "Final" };
		notes = if(barForm == "Learned (corpus)") {
			learned.select { |note| (note[0] >= barStart) and: { note[0] < (barStart + beatsPerBar) } }
			.collect { |note| [note[0] - barStart, note[1].min(barStart + beatsPerBar - note[0]), note[2]] }
		} {
			~pianoML13FormBar.value(barForm, chord, beatsPerBar)
		};
		notes.do { |note|
			events.add((
				step: note[2].clip(-50, 8),
				beat: barStart + note[0],
				dur: note[1],
				velocity: (if(note[0] == 0) { 70 } { 54 }) + 4.rand2
			));
		};
	};
	events.asArray
};

~pianoML13SaveLeftHand = {
	File.mkdir(~pianoML13ModelDir.value);
	~pianoML13LeftHand[\model].writeArchive(~pianoML13ModelDir.value +/+ "lefthand.scdarchive");
};

~pianoML13LoadLeftHand = {
	var path = ~pianoML13ModelDir.value +/+ "lefthand.scdarchive";
	if(File.exists(path)) { ~pianoML13LeftHand[\model] = Object.readArchive(path) };
};
)
