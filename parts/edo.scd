(
// 13-EDO spelled with 13 distinct letter names per octave: the usual 12-EDO
// chromatic scale has no sharp between E and F (or B and C), since those are
// already a semitone apart. 13-EDO needs one extra degree, so that gap is
// filled with E#, a 13th name that is NOT the same pitch as F.
~pianoML13NoteNames = ["A", "A#", "B", "C", "C#", "D", "D#", "E", "E#", "F", "F#", "G", "G#"];

// A triad is "balanced" in 13-EDO when each of its three cyclic gaps (between
// consecutive tones, wrapping the last back to the first across the octave)
// is 3, 4, 5 or 6 steps -- close enough to be a chord, wide enough that no
// two tones crowd each other. The three gaps always sum to 13 (the octave),
// so this is every (a, b, c) in that range adding up to 13.
~pianoML13ValidTriadGaps = {
	var gaps = List.new;
	(3..6).do { |a| (3..6).do { |b| (3..6).do { |c|
		if((a + b + c) == 13) { gaps.add([a, b, c]) };
	} } };
	gaps.asArray
}.value;

~pianoML13Edo = (
	stepsPerOctave: 13,
	// Letter name + octave number for a step, e.g. step 8 -> "E#4". Octave 4
	// starts at step 0 (A4, 440 Hz), matching the project's pitch-class anchor.
	nameFor: { |self, step|
		var pitchClass = step.mod(13);
		var octave = 4 + ((step - pitchClass) div: 13);
		~pianoML13NoteNames[pitchClass] ++ octave.asString
	},
	// 12-EDO -> 13-EDO is not exact: one semitone per octave (offset 6 from
	// A4, i.e. step 6/7's boundary) lands exactly halfway between two
	// 13-EDO steps. Rounding that the same way every time means step 6 is
	// never produced from a 12-EDO corpus, so it is instead resolved by
	// chance: 30% step 6, 70% split between its neighbors 5 and 7.
	stepsFromMidi: { |self, midiNote|
		var n = midiNote - 69;
		var exact = n * (13 / 12);
		if(n.mod(12) == 6) {
			var lower = exact.floor.asInteger;
			[lower - 1, lower, lower + 1].wchoose([0.35, 0.3, 0.35])
		} {
			exact.round.asInteger
		}
	},
	frequency: { |self, step|
		440 * (2 ** (step / 13))
	},
	nearestMidi: { |self, step|
		(69 + (step * (12 / 13))).round.asInteger.clip(0, 127)
	},
	// A random balanced triad (see ~pianoML13ValidTriadGaps), as sorted pitch
	// classes 0-12.
	randomTriad: { |self|
		var gaps = ~pianoML13ValidTriadGaps.choose;
		var root = 13.rand;
		[root, (root + gaps[0]) % 13, (root + gaps[0] + gaps[1]) % 13].sort
	},
	// A random harmony progression of `chordCount` balanced triads, in the
	// same "p,p,p; p,p,p; ..." text the harmony field expects.
	randomHarmony: { |self, chordCount = 4|
		chordCount.collect { self[\randomTriad].value(self).join(",") }.join("; ")
	},
	// A random chord of up to `size` pitch classes (3-6 notes), sorted.
	// Stacks (size - 1) random intervals of 3, 4, 5 or 6 steps onto a random
	// root, wrapping each sum back into 0-12 (e.g. 14 steps -> 14 % 13 = 1)
	// since 13-EDO only has 13 pitch classes. Large sizes can wrap onto a
	// pitch already in the chord, which just yields fewer than `size` tones.
	randomChord: { |self, size = 3|
		var pitch = 13.rand;
		var notes = Set[pitch];
		(size - 1).do {
			pitch = (pitch + [3, 4, 5, 6].choose) % 13;
			notes.add(pitch);
		};
		notes.asArray.sort
	},
	// A random harmony progression of at least `chordCount` chords, each
	// a random size from 3 to 6 notes, in the same "p,p,p; ..." text the
	// harmony field expects.
	randomMixedHarmony: { |self, chordCount = 5|
		chordCount.collect { self[\randomChord].value(self, [3, 4, 5, 6].choose).join(",") }.join("; ")
	},
	parseHarmony: { |self, text|
		var chords = text.split($;).collect { |chordText|
			chordText.stripWhiteSpace.split($,).collect { |pitchText|
				pitchText.stripWhiteSpace.asInteger
			}.select { |pitchClass| pitchClass.notNil and: { pitchClass.inclusivelyBetween(0, 12) } }
		}.select { |chord| chord.notEmpty };
		if(chords.isEmpty) { Error("Enter chord pitch classes from 0 to 12, separated by commas and semicolons.").throw };
		chords
	}
);
)