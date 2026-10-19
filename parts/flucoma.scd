(
~pianoML13FluCoMaAnalyze = { |source|
	var dataSetClass = \FluidDataSet.asClass;
	var phrases, featureRows;
	if(dataSetClass.isNil) {
		"FluCoMa not installed: symbolic generation remains available; install FluCoMa to build phrase feature data.".warn;
		nil
	} {
		phrases = source[\notes].clump(16).select { |phrase| phrase.size >= 4 };
		featureRows = phrases.collect { |phrase|
			var pitches = phrase.collect(_[\step]);
			var gaps = phrase.collect { |note, noteIndex|
				if(noteIndex < (phrase.size - 1)) {
					(phrase[noteIndex + 1][\time] - note[\time]).max(0)
				} { 0 }
			}.select(_ > 0);
			var intervals = pitches.differentiate.drop(1);
			[
				pitches.mean / 48,
				(pitches.maxItem - pitches.minItem) / 48,
				if(intervals.notEmpty) { intervals.abs.mean / 13 } { 0 },
				if(gaps.notEmpty) { (gaps.mean / source[\division]).clip(0, 4) / 4 } { 0 },
				phrase.collect(_[\velocity]).mean / 127
			]
		};
		// FluidDataSet.addPoint runs on the server and needs a Buffer, not a
		// language-side array, so each feature row is written to a buffer first.
		if(featureRows.isEmpty) {
			"FluCoMa: MIDI file too short to build phrase features.".warn;
		} { fork {
			var dataSet = dataSetClass.new(s);
			var pointBuffer = Buffer.alloc(s, featureRows.first.size);
			s.sync;
			featureRows.do { |features, index|
				pointBuffer.setn(0, features);
				s.sync;
				dataSet.addPoint("phrase-%".format(index), pointBuffer);
				s.sync;
			};
			pointBuffer.free;
			~pianoML13[\flucomaDataSet] = dataSet;
			("FluCoMa feature dataset built from % phrases.".format(featureRows.size)).postln;
		} };
		nil
	}
};
)
