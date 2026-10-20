(
// Generates a melody note by note from the trained model (neural net when
// ready, Markov model otherwise). The loaded MIDI file, if any, primes the
// model with its opening notes and supplies velocities. Each candidate's
// probability is reweighted towards the current chord's tones; the "Corpus
// influence" slider sets how much the model outweighs the harmony.
// The piece lasts ~pianoML13[\duration] seconds at the current tempo,
// rounded up to whole bars; the melody ends on a held tonic note in the last
// bar. onProgress (optional) receives the fraction done.
~pianoML13Generate = { |onDone, onError, onProgress|
	fork {
		var source = ~pianoML13[\source];
		var harmony = ~pianoML13[\harmony].select { |chord| chord.notEmpty };
		var styleAmount = ~pianoML13[\styleAmount].clip(0, 1);
		var temperature = (~pianoML13[\temperature] ? 1.0).clip(0.1, 3);
		var rhythmClasses = ~pianoML13Learn[\rhythmClasses];
		var useMLP = ~pianoML13Learn[\mlpReady];
		var melody = List.new, accompaniment = List.new, history = List.new;
		var beatsPerBar = ~pianoML13[\beatsPerBar] ? 4;
		var bars = ((~pianoML13[\duration] ? 60) * ~pianoML13[\tempo] / 60 / beatsPerBar).ceil.asInteger.max(2);
		var endOfMelody = (bars - 1) * beatsPerBar;
		var beat = 0.0, currentStep = 0, index = 0, finalChord, finalStep;
		var inBuf, outBuf, output;
		var velocities = if(source.notNil) { source[\notes].collect(_[\velocity]) } { [56, 64, 72, 80] };
		block { |break|
			if(harmony.isEmpty) { onError.value("The harmony progression is empty."); break.value };
			if(useMLP.not and: { ~pianoML13Learn[\markov].isNil }) {
				onError.value("Train the model first (Train on corpus button).");
				break.value;
			};
			// After a server reboot the net is gone; reload it from models/.
			if(useMLP.not and: { ~pianoML13CanLoadMLP.value }) { useMLP = ~pianoML13ReadMLP.value };
			thisThread.randSeed = ~pianoML13[\seed].asInteger;
			if(source.notNil and: { source[\phrases].notEmpty }) {
				var opening = source[\phrases].first;
				history.addAll(opening.drop(1).keep(~pianoML13Learn[\context]));
				currentStep = opening.first[\step].asInteger;
			};
			if(useMLP) {
				inBuf = Buffer.alloc(s, ~pianoML13Learn[\inputSize]);
				outBuf = Buffer.alloc(s, ~pianoML13Learn[\outputSize]);
				s.sync;
			};
			while { beat < endOfMelody } {
				var bar = (beat / beatsPerBar).floor.asInteger;
				var chord = harmony.wrapAt(bar);
				var chordTarget = chord.collect { |pitchClass|
					pitchClass + (13 * ((currentStep - pitchClass) / 13).round)
				}.minItem { |step| (step - currentStep).abs }.asInteger;
				var candidates, weights, choice, step, token;
				if(index == 0) {
					choice = [chordTarget - currentStep, rhythmClasses.indexOf(1.0)];
				} {
					if(useMLP) {
						inBuf.setn(0, ~pianoML13Features.value(history.asArray, (beat % beatsPerBar) / beatsPerBar, currentStep));
						output = ~pianoML13Await.value({ |reply| ~pianoML13Learn[\mlp].predictPoint(inBuf, outBuf, reply) }, 3);
						if(output != \timeout) {
							output = ~pianoML13Await.value({ |reply| outBuf.getn(0, ~pianoML13Learn[\outputSize], reply) }, 3);
						};
						if(output == \timeout) {
							"PianoML-13EDO: the neural net stopped answering; continuing with the Markov model.".warn;
							~pianoML13Learn[\mlpReady] = false;
							~pianoML13Learn[\mlp] = nil;
							useMLP = false;
						};
					};
					candidates = if(useMLP) {
						~pianoML13MLPCandidates.value(output)
					} {
						~pianoML13MarkovCandidates.value(history.asArray)
					};
					weights = candidates.collect { |candidate|
						var target = currentStep + candidate[0];
						var inChord = chord.includes((target % 13).asInteger);
						if(target.inclusivelyBetween(-36, 42).not) { 0 } {
							(candidate[2] ** (1 / temperature)) * if(inChord) { 1 + ((1 - styleAmount) * 8) } { 1 }
						}
					};
					choice = if(weights.sum > 0) {
						candidates.wchoose(weights.normalizeSum)
					} {
						[chordTarget - currentStep, rhythmClasses.indexOf(1.0)]
					};
				};
				step = currentStep + choice[0];
				token = (interval: choice[0].clip(~pianoML13Learn[\maxInterval].neg, ~pianoML13Learn[\maxInterval]), rhythm: choice[1], step: step);
				melody.add((
					step: step,
					beat: beat,
					dur: rhythmClasses[choice[1]],
					velocity: velocities.choose
				));
				history.add(token);
				currentStep = step;
				beat = beat + rhythmClasses[choice[1]];
				index = index + 1;
				if((index % 32) == 0) {
					onProgress.value(beat / endOfMelody);
					if(useMLP.not) { 0.001.wait };
				};
			};
			// Ending: the tonic chord tone nearest the last note, held to the
			// end of the final bar (at least two beats).
			finalChord = harmony.first;
			finalStep = ~pianoML13SnapToChord.value(currentStep, finalChord);
			bars = ((beat + 2) / beatsPerBar).ceil.asInteger.max(bars);
			melody.add((
				step: finalStep,
				beat: beat,
				dur: (bars * beatsPerBar) - beat,
				velocity: velocities.choose
			));
			inBuf !? _.free;
			outBuf !? _.free;
			accompaniment.addAll(~pianoML13Accompaniment.value(harmony, bars, beatsPerBar,
				~pianoML13[\leftHandForm] ? "Mixed", temperature));
			~pianoML13[\melody] = melody.asArray;
			~pianoML13[\accompaniment] = accompaniment.asArray;
			onDone.value(~pianoML13ModelName.value);
		};
	};
};
)
