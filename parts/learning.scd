(
// Learned melody model, trained on the MIDI corpus.
//
// Every melody note is a token (interval in 13-EDO steps, rhythm class).
// Two models are trained on the same token sequences:
//   * a FluCoMa MLP (FluidMLPRegressor) that reads the last `context` tokens
//     plus metric position and register, and outputs a probability for every
//     interval and every rhythm class;
//   * a variable-order Markov model (orders 0..markovOrder) in sclang, used
//     while the MLP is missing, untrained or FluCoMa is not installed.
// Both are saved to models/ and reloaded on the next start.

~pianoML13Learn = (
	context: 4,
	maxInterval: 13,
	rhythmClasses: [0.25, 1/3, 0.5, 2/3, 0.75, 1.0, 1.5, 2.0],
	markovOrder: 3,
	trainFiles: 1000,
	maxPoints: 20000,
	trainRounds: 10,
	epochsPerRound: 25,
	markov: nil,
	mlp: nil,
	mlpReady: false,
	training: false,
	info: "No model trained yet."
);
~pianoML13Learn[\intervalCount] = (~pianoML13Learn[\maxInterval] * 2) + 1;
~pianoML13Learn[\rhythmCount] = ~pianoML13Learn[\rhythmClasses].size;
~pianoML13Learn[\inputSize] = (~pianoML13Learn[\context] * 2) + 3;
~pianoML13Learn[\outputSize] = ~pianoML13Learn[\intervalCount] + ~pianoML13Learn[\rhythmCount];

~pianoML13ModelDir = { (~pianoML13[\projectRoot] +/+ "models").standardizePath };

~pianoML13RhythmIndex = { |beats|
	var classes = ~pianoML13Learn[\rhythmClasses];
	classes.indexOf(classes.minItem { |value| (beats.max(0.05) / value).log2.abs })
};

// Extracts the top voice of a MIDI file as phrases of tokens (skyline).
// Notes starting together (1/12-beat grid) form a chord whose highest note is
// the melody candidate. A candidate lower than a melody note that is still
// sounding is an inner or bass voice and is skipped, and so is one more than
// an octave below the last melody note within 2 beats of its end. A gap
// longer than 4 beats or a leap wider than an octave starts a new phrase.
~pianoML13MelodyFromMIDI = { |path|
	var midi = SimpleMIDIFile.read(path);
	var division, grid, onsets, ticks, melody, phrases, phrase, heldPitch = -1, heldUntil = -1;
	var signature, beatsPerBar;
	midi.timeMode = \ticks;
	division = midi.division.max(1);
	signature = midi.timeSignatureAsArray;
	beatsPerBar = (signature[0] * 4 / signature[1]).max(1);
	grid = (division / 12).max(1);
	onsets = Dictionary.new;
	midi.noteSustainEvents.do { |event|
		if((event[5] > 0) and: { event[3] != 9 }) {
			var tick = (event[1] / grid).round * grid;
			var current = onsets[tick];
			if(current.isNil or: { event[4] > current[0] }) { onsets[tick] = [event[4], event[5], tick + event[6]] };
		};
	};
	ticks = onsets.keys.asArray.sort;
	melody = List.new;
	ticks.do { |tick|
		var note = onsets[tick];
		if((note[0] >= heldPitch) or: {
			(tick >= heldUntil) and: { (note[0] >= (heldPitch - 12)) or: { tick >= (heldUntil + (2 * division)) } }
		}) {
			melody.add([tick] ++ note);
			heldPitch = note[0];
			heldUntil = note[2];
		};
	};
	phrases = List.new;
	phrase = List.new;
	melody.do { |note, index|
		var tick = note[0];
		var step = ~pianoML13Edo[\stepsFromMidi].value(~pianoML13Edo, note[1]);
		var gap = if(index < (melody.size - 1)) { (melody[index + 1][0] - tick) / division } { 1.0 };
		var interval = if(phrase.isEmpty) { 0 } { step - phrase.last[\step] };
		if(interval.abs > ~pianoML13Learn[\maxInterval]) {
			if(phrase.size >= 4) { phrases.add(phrase.asArray) };
			phrase = List.new;
			interval = 0;
		};
		phrase.add((
			step: step,
			interval: interval.clip(~pianoML13Learn[\maxInterval].neg, ~pianoML13Learn[\maxInterval]),
			rhythm: ~pianoML13RhythmIndex.value(gap.min(2.0)),
			phase: ((tick / division) % beatsPerBar) / beatsPerBar,
			velocity: note[2]
		));
		if(gap > 4) {
			if(phrase.size >= 4) { phrases.add(phrase.asArray) };
			phrase = List.new;
		};
	};
	if(phrase.size >= 4) { phrases.add(phrase.asArray) };
	phrases.asArray
};

~pianoML13TokenKey = { |token| "%,%".format(token[\interval], token[\rhythm]) };

// Network input for predicting the token after `history` (oldest first).
// `phase` is the position in the bar, from 0 (downbeat) to 1.
~pianoML13Features = { |history, phase, step|
	var context = ~pianoML13Learn[\context];
	var recent = history.keep(context.neg).reverse;
	var features = Array.fill(context, { |index|
		var token = recent[index];
		if(token.isNil) { [0, -1] } {
			[token[\interval] / ~pianoML13Learn[\maxInterval], (token[\rhythm] / (~pianoML13Learn[\rhythmCount] - 1)) * 2 - 1]
		}
	}).flatten;
	features ++ [sin(2pi * phase), cos(2pi * phase), (step / 40).clip(-1.5, 1.5)]
};

~pianoML13Target = { |token|
	Array.fill(~pianoML13Learn[\intervalCount], { |index| if(index == (token[\interval] + ~pianoML13Learn[\maxInterval])) { 1 } { 0 } })
	++ Array.fill(~pianoML13Learn[\rhythmCount], { |index| if(index == token[\rhythm]) { 1 } { 0 } })
};

~pianoML13TrainMarkov = { |phrases|
	var order = ~pianoML13Learn[\markovOrder];
	var counts = Dictionary.new;
	phrases.do { |phrase|
		// The first token of a phrase has no real interval, so it is skipped.
		var keys = phrase.drop(1).collect(~pianoML13TokenKey);
		keys.do { |key, index|
			(order + 1).do { |n|
				if(index >= n) {
					var context = keys.copyRange(index - n, index - 1).join(" ");
					var table = counts[context];
					if(table.isNil) { table = Dictionary.new; counts[context] = table };
					table[key] = (table[key] ? 0) + 1;
				};
			};
		};
	};
	// Contexts seen fewer than 3 times are never used for sampling (see
	// ~pianoML13MarkovCandidates), so they are dropped to keep the model small.
	counts.keys.asArray.do { |context|
		if(context.notEmpty and: { counts[context].values.sum < 3 }) { counts.removeAt(context) };
	};
	counts
};

// Joint candidates [interval, rhythmIndex, probability] from the Markov
// model with Witten-Bell smoothing: each context order is interpolated with
// the next shorter one, weighted by how much evidence the context has, so
// unseen continuations keep some probability.
~pianoML13MarkovCandidates = { |history|
	var counts = ~pianoML13Learn[\markov];
	var keys = history.collect(~pianoML13TokenKey);
	var unigram = counts[""];
	var unigramTotal = unigram.values.sum;
	var tokens = unigram.keys.asArray;
	var probs = tokens.collect { |key| unigram[key] / unigramTotal };
	(1..~pianoML13Learn[\markovOrder]).do { |n|
		var table = if(keys.size >= n) { counts[keys.keep(n.neg).join(" ")] };
		if(table.notNil) {
			var total = table.values.sum;
			var lambda = total / (total + table.size);
			probs = tokens.collect { |key, index|
				(lambda * ((table[key] ? 0) / total)) + ((1 - lambda) * probs[index])
			};
		};
	};
	tokens.collect { |key, index|
		var parts = key.split($,).collect(_.asInteger);
		[parts[0], parts[1], probs[index]]
	}
};

~pianoML13MLPCandidates = { |output|
	var intervalCount = ~pianoML13Learn[\intervalCount];
	var intervalProbs = output.keep(intervalCount).max(0.0001).normalizeSum;
	var rhythmProbs = output.drop(intervalCount).max(0.0001).normalizeSum;
	var candidates = List.new;
	intervalProbs.do { |intervalProb, intervalIndex|
		rhythmProbs.do { |rhythmProb, rhythmIndex|
			candidates.add([intervalIndex - ~pianoML13Learn[\maxInterval], rhythmIndex, intervalProb * rhythmProb]);
		};
	};
	candidates.asArray
};

~pianoML13ModelName = {
	case
	{ ~pianoML13Learn[\mlpReady] } { "neural net (FluCoMa MLP)" }
	{ ~pianoML13Learn[\markov].notNil } { "Markov model" }
	{ "none" }
};

~pianoML13SaveMarkov = {
	var dir = ~pianoML13ModelDir.value;
	File.mkdir(dir);
	~pianoML13Learn[\markov].writeArchive(dir +/+ "markov.scdarchive");
	File.use(dir +/+ "model-info.txt", "w", { |file| file.write(~pianoML13Learn[\info]) });
};

// Runs an asynchronous server request inside a Routine and waits for its
// reply, at most `timeout` seconds. `start` receives the reply callback.
// Returns the reply, or \timeout if the server never answered.
~pianoML13Await = { |start, timeout = 10|
	var condition = CondVar.new, done = false, result;
	start.value({ |value| result = value; done = true; condition.signalOne });
	condition.waitFor(timeout, { done });
	if(done) { result } { \timeout }
};

~pianoML13MLPPath = { ~pianoML13ModelDir.value +/+ "mlp.json" };

~pianoML13CanLoadMLP = {
	\FluidMLPRegressor.asClass.notNil and: { File.exists(~pianoML13MLPPath.value) }
};

// Creates the MLP on the running server and reads the saved weights into it.
// Call from a Routine. Returns true when the net is ready.
~pianoML13ReadMLP = {
	var mlp = ~pianoML13NewMLP.value;
	s.sync;
	if(~pianoML13Await.value({ |reply| mlp.read(~pianoML13MLPPath.value, reply) }) == \timeout) {
		"PianoML-13EDO: the neural net did not load; using the Markov model.".warn;
		false
	} {
		~pianoML13Learn[\mlp] = mlp;
		~pianoML13Learn[\mlpReady] = true;
		true
	}
};

// The MLP lives inside the server, so a server quit or reboot destroys it.
// Mark it unavailable then; the next Generate reloads it from models/.
if(~pianoML13ServerQuitHook.notNil) { ServerQuit.remove(~pianoML13ServerQuitHook) };
~pianoML13ServerQuitHook = {
	~pianoML13Learn[\mlpReady] = false;
	~pianoML13Learn[\mlp] = nil;
};
ServerQuit.add(~pianoML13ServerQuitHook);

// Loads saved models. The Markov model loads at once; the MLP needs the
// server, so it is read after boot.
~pianoML13LoadModels = { |onStatus|
	var dir = ~pianoML13ModelDir.value;
	var markovPath = dir +/+ "markov.scdarchive";
	var infoPath = dir +/+ "model-info.txt";
	if(File.exists(markovPath)) {
		~pianoML13Learn[\markov] = Object.readArchive(markovPath);
		~pianoML13LoadLeftHand.value;
		if(File.exists(infoPath)) { ~pianoML13Learn[\info] = File.readAllString(infoPath) };
	};
	if(~pianoML13CanLoadMLP.value) {
		s.waitForBoot({
			if(~pianoML13ReadMLP.value) {
				onStatus.value("Model loaded: %. %".format(~pianoML13ModelName.value, ~pianoML13Learn[\info]));
			};
		});
	};
	onStatus.value("Model: %. %".format(~pianoML13ModelName.value, ~pianoML13Learn[\info]));
};

~pianoML13NewMLP = {
	\FluidMLPRegressor.asClass.new(s,
		hiddenLayers: [64, 48],
		activation: 2,
		outputActivation: 1,
		maxIter: ~pianoML13Learn[\epochsPerRound],
		learnRate: 0.02,
		momentum: 0.9,
		batchSize: 64,
		validation: 0.1
	)
};

// Samples up to `count` paths, round-robin across each file's containing
// folder (one piece/movement in the corpus layout). The corpus holds many
// differently-performed renderings per piece but far fewer distinct pieces
// (e.g. one Chopin étude might have 1000+ renderings while another piece has
// only 2), so a flat random sample is mostly repeats of whichever pieces
// were recorded most; round-robin instead gives every piece a turn before
// any piece gets a second file, and only the still-nonempty, most-recorded
// pieces fill in the remainder once the smaller ones run out.
~pianoML13SampleFilesPerPiece = { |paths, count|
	var byPiece = Dictionary.new;
	var groups, pointers, picked = List.new, active = true;
	paths.do { |path|
		var key = PathName(path).pathOnly;
		var list = byPiece[key];
		if(list.isNil) { list = List.new; byPiece[key] = list };
		list.add(path);
	};
	groups = byPiece.values.collect({ |list| list.scramble.asArray }).asArray.scramble;
	pointers = Array.fill(groups.size, 0);
	while { (picked.size < count) and: { active } } {
		active = false;
		groups.do { |group, index|
			if((picked.size < count) and: { pointers[index] < group.size }) {
				picked.add(group[pointers[index]]);
				pointers[index] = pointers[index] + 1;
				active = true;
			};
		};
	};
	picked.asArray
};

// Trains both models from a seeded random sample of the corpus. Runs as a
// Routine; onStatus receives progress messages, onDone runs at the end.
~pianoML13Train = { |onStatus, onDone|
	if(~pianoML13Learn[\training]) {
		onStatus.value("Training is already running.");
	} {
		~pianoML13Learn[\training] = true;
		fork {
			var root = ~pianoML13[\corpusRoot];
			var files, phrases = List.new, leftHand = List.new, failed = 0, points, inputs, targets;
			var startTime = Main.elapsedTime;
			var useMLP = \FluidMLPRegressor.asClass.notNil;
			files = ("find % -iname '*.mid'".format(root.shellQuote)).unixCmdGetStdOutLines;
			thisThread.randSeed = ~pianoML13[\seed].asInteger;
			files = ~pianoML13SampleFilesPerPiece.value(files, ~pianoML13Learn[\trainFiles]);
			onStatus.value("Reading % of the corpus MIDI files...".format(files.size));
			files.do { |path, index|
				try {
					phrases.addAll(~pianoML13MelodyFromMIDI.value(path));
					leftHand.addAll(~pianoML13LeftHandFromMIDI.value(path));
				} { failed = failed + 1 };
				if(index % 50 == 49) {
					onStatus.value("Reading MIDI files: % / %".format(index + 1, files.size));
					0.01.wait;
				};
			};
			if(phrases.isEmpty) {
				onStatus.value("Training failed: no melody phrases found in the corpus.");
				~pianoML13Learn[\training] = false;
				onDone.value;
			} {
				onStatus.value("Training Markov model on % phrases...".format(phrases.size));
				0.01.wait;
				~pianoML13Learn[\markov] = ~pianoML13TrainMarkov.value(phrases);
				if(leftHand.notEmpty) {
					~pianoML13LeftHand[\model] = ~pianoML13TrainLeftHand.value(leftHand);
					~pianoML13SaveLeftHand.value;
				};
				~pianoML13Learn[\info] = "Trained on % files: % melody phrases (% notes), % left-hand phrases (% onsets).".format(
					files.size - failed, phrases.size, phrases.collect(_.size).sum,
					leftHand.size, leftHand.collect(_.size).sum);
				~pianoML13SaveMarkov.value;
				if(useMLP.not) {
					onStatus.value("FluCoMa not installed: using the Markov model. %".format(~pianoML13Learn[\info]));
				} {
					var source, target, mlp, condition = Condition.new, loss;
					points = List.new;
					phrases.do { |phrase|
						phrase.do { |token, index|
							if(index > 0) {
								var previous = phrase[index - 1];
								points.add([
									~pianoML13Features.value(phrase.keep(index), token[\phase], previous[\step]),
									~pianoML13Target.value(token)
								]);
							};
						};
					};
					points = points.asArray.scramble.keep(~pianoML13Learn[\maxPoints]);
					onStatus.value("Uploading % training examples to the server...".format(points.size));
					s.bootSync;
					source = \FluidDataSet.asClass.new(s);
					target = \FluidDataSet.asClass.new(s);
					inputs = Dictionary.new;
					targets = Dictionary.new;
					points.do { |point, index|
						inputs["p%".format(index)] = point[0];
						targets["p%".format(index)] = point[1];
					};
					s.sync;
					source.load(Dictionary["cols" -> ~pianoML13Learn[\inputSize], "data" -> inputs], { condition.unhang });
					condition.hang;
					target.load(Dictionary["cols" -> ~pianoML13Learn[\outputSize], "data" -> targets], { condition.unhang });
					condition.hang;
					~pianoML13Learn[\mlpReady] = false;
					mlp = ~pianoML13NewMLP.value;
					s.sync;
					~pianoML13Learn[\trainRounds].do { |round|
						onStatus.value("Training neural net: round % / %%".format(round + 1, ~pianoML13Learn[\trainRounds],
							if(loss.notNil) { ", loss %".format(loss.round(0.0001)) } { "" }));
						mlp.fit(source, target, { |value| loss = value.asArray.first; condition.unhang });
						condition.hang;
					};
					File.mkdir(~pianoML13ModelDir.value);
					mlp.write(~pianoML13ModelDir.value +/+ "mlp.json", { condition.unhang });
					condition.hang;
					source.free;
					target.free;
					~pianoML13Learn[\mlp] = mlp;
					~pianoML13Learn[\mlpReady] = true;
					~pianoML13Learn[\info] = ~pianoML13Learn[\info] ++ " Neural net loss %.".format(loss.round(0.0001));
					~pianoML13SaveMarkov.value;
				};
				~pianoML13Learn[\training] = false;
				onStatus.value("Model ready (% s): %. %".format(
					(Main.elapsedTime - startTime).round(1), ~pianoML13ModelName.value, ~pianoML13Learn[\info]));
				onDone.value;
			};
		};
	};
};
)
