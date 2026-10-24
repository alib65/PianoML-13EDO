(
var projectRoot = PathName(thisProcess.nowExecutingPath).pathOnly;
// The corpus is the deduped, flat "midi" folder that lives directly inside
// this SuperCollider folder (see supercollider/dedupe_chopin_midis.py).

~pianoML13 = (
	projectRoot: projectRoot,
	corpusRoot: (projectRoot +/+ "midi").standardizePath,
	tempo: 72,
	harmony: [[0, 3, 7], [5, 8, 12], [2, 5, 9], [7, 10, 1]],
	styleAmount: 0.65,
	temperature: 1.0,
	duration: 60,
	beatsPerBar: 4,
	leftHandForm: "Mixed",
	usePedal: true,
	seed: 0,
	sampleDir: (projectRoot +/+ "SalamanderGrandPianoV3_44.1khz16bit/44.1khz16bit").standardizePath,
	source: nil,
	melody: [],
	accompaniment: [],
	clock: nil,
	player: nil,
	window: nil
);

(projectRoot +/+ "parts/edo.scd").load;
(projectRoot +/+ "parts/salamander.scd").load;
(projectRoot +/+ "parts/learning.scd").load;
(projectRoot +/+ "parts/lefthand.scd").load;
(projectRoot +/+ "parts/corpus.scd").load;
(projectRoot +/+ "parts/composer.scd").load;
(projectRoot +/+ "parts/piano.scd").load;
(projectRoot +/+ "parts/interface.scd").load;

~pianoML13[\openInterface].value;
)