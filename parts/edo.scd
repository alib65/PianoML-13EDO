(
~pianoML13Edo = (
	stepsPerOctave: 13,
	stepsFromMidi: { |self, midiNote|
		((midiNote - 69) * (13 / 12)).round.asInteger
	},
	frequency: { |self, step|
		440 * (2 ** (step / 13))
	},
	nearestMidi: { |self, step|
		(69 + (step * (12 / 13))).round.asInteger.clip(0, 127)
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