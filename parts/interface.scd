(
~pianoML13OpenInterface = {
	var window, status, sourceField, tempoBox, styleSlider, harmonyField, seedBox, pedalToggle;
	var updateStatus, updateModelStatus, refreshButtons, loadSource, applyHarmony, generate;
	var generateButton, playButton, exportButton, audioButton, trainButton, modelStatus, temperatureBox;
	var minutesBox, secondsBox, setDuration, settingChanged;
	window = Window("PianoML-13EDO", Rect(120, 120, 600, 900)).front;
	window.background = Color.new255(241, 238, 228);
	window.view.decorator = FlowLayout(window.view.bounds, 18@18, 12@10);
	StaticText(window, 560@34).string_("PianoML-13EDO").font_(Font("Georgia", 22, bold: true)).stringColor_(Color.new255(36, 55, 55));
	StaticText(window, 560@22).string_("Machine-learned piano study in 13 equal divisions per octave").font_(Font("Georgia", 12)).stringColor_(Color.new255(88, 93, 83));
	StaticText(window, 560@22).string_("MIDI source").font_(Font("Helvetica", 12, bold: true));
	sourceField = TextField(window, 340@28).string_("Paste a .mid path or browse");
	Button(window, 96@28).states_([["Browse MIDI"]]).action_({
		Dialog.openPanel({ |paths|
			var path = if(paths.isKindOf(String)) { paths } { paths.first };
			if(path.notNil and: { path.notEmpty }) {
				sourceField.string = path;
				loadSource.value(path);
			};
			}, path: ~pianoML13[\corpusRoot]);
	});
	Button(window, 92@28).states_([["Load path"]]).action_({
		loadSource.value(sourceField.string.stripWhiteSpace);
	});
	StaticText(window, 560@22).string_("Tempo (BPM)").font_(Font("Helvetica", 12, bold: true));
	tempoBox = NumberBox(window, 100@28).value_(~pianoML13[\tempo]).clipLo_(30).clipHi_(220).decimals_(0).action_({ |box|
		~pianoML13[\tempo] = box.value.clip(30, 220);
		if(~pianoML13[\clock].notNil) { ~pianoML13[\clock].tempo = ~pianoML13[\tempo] / 60 };
	});
	pedalToggle = CheckBox(window, 190@24).string_("Auto sustain pedal").value_(if(~pianoML13[\usePedal]) { 1 } { 0 }).action_({ |control|
		~pianoML13[\usePedal] = control.value > 0;
	});
	StaticText(window, 560@22).string_("Form").font_(Font("Helvetica", 12, bold: true));
	StaticText(window, 62@26).string_("Duration").font_(Font("Helvetica", 12));
	minutesBox = NumberBox(window, 46@26).value_(((~pianoML13[\duration] ? 60) div: 60)).clipLo_(0).clipHi_(60).decimals_(0).action_({ setDuration.value });
	StaticText(window, 28@26).string_("min").font_(Font("Helvetica", 12));
	secondsBox = NumberBox(window, 46@26).value_(((~pianoML13[\duration] ? 60) % 60)).clipLo_(0).clipHi_(59).decimals_(0).action_({ setDuration.value });
	StaticText(window, 28@26).string_("sec").font_(Font("Helvetica", 12));
	StaticText(window, 46@26).string_("Meter").font_(Font("Helvetica", 12)).align_(\right);
	PopUpMenu(window, 70@26).items_(["4/4", "3/4"]).value_(if((~pianoML13[\beatsPerBar] ? 4) == 3) { 1 } { 0 }).action_({ |menu|
		~pianoML13[\beatsPerBar] = [4, 3][menu.value];
		settingChanged.value("Meter set to %.".format(menu.item));
	});
	StaticText(window, 62@26).string_("Left hand").font_(Font("Helvetica", 12));
	PopUpMenu(window, 200@26).items_(~pianoML13LeftHandForms).value_(~pianoML13LeftHandForms.detectIndex { |name| name == (~pianoML13[\leftHandForm] ? "Mixed") } ? 0).action_({ |menu|
		~pianoML13[\leftHandForm] = menu.item;
		settingChanged.value("Left hand: %.".format(menu.item));
	});
	StaticText(window, 560@18).string_("Mixed changes the left-hand form every 4 bars. Learned plays a left-hand line from a model trained on the corpus.").font_(Font("Helvetica", 10)).stringColor_(Color.new255(88, 93, 83));
	StaticText(window, 560@22).string_("Corpus influence").font_(Font("Helvetica", 12, bold: true));
	styleSlider = Slider(window, 450@22).value_(~pianoML13[\styleAmount]).action_({ |slider|
		~pianoML13[\styleAmount] = slider.value;
	});
	StaticText(window, 90@22).string_("Harmony").font_(Font("Helvetica", 12, bold: true));
	PopUpMenu(window, 450@26).items_(["13-EDO minor", "Wide / open", "Chromatic" ]).action_({ |menu|
		var presets = [
			"0,3,7; 5,8,12; 2,5,9; 7,10,1",
			"0,7,10; 3,8,12; 5,9,0; 2,7,11",
			"0,2,6,9; 1,5,8,12; 3,6,10; 4,7,11"
		];
		harmonyField.string = presets[menu.value];
	});
	harmonyField = TextField(window, 560@30).string_("0,3,7; 5,8,12; 2,5,9; 7,10,1");
	StaticText(window, 560@18).string_("Pitch classes 0-12, relative to A4. Separate chord tones with commas and chords with semicolons.").font_(Font("Helvetica", 10)).stringColor_(Color.new255(88, 93, 83));
	StaticText(window, 560@22).string_("Learned model").font_(Font("Helvetica", 12, bold: true));
	trainButton = Button(window, 160@30).states_([["Train on corpus"]]).action_({
		trainButton.enabled = false;
		~pianoML13Train.value(updateModelStatus, {
			{ trainButton.enabled = true }.defer;
			~pianoML13[\melody] = [];
			refreshButtons.value;
		});
	});
	StaticText(window, 110@30).string_("Temperature").font_(Font("Helvetica", 12)).align_(\right);
	temperatureBox = NumberBox(window, 70@28).value_(~pianoML13[\temperature] ? 1.0).clipLo_(0.1).clipHi_(3).decimals_(2).step_(0.05).scroll_step_(0.05).action_({ |box|
		~pianoML13[\temperature] = box.value;
	});
	modelStatus = StaticText(window, 560@44).string_("No model loaded.").font_(Font("Helvetica", 10)).stringColor_(Color.new255(88, 93, 83));
	StaticText(window, 560@18).string_("Trains a neural net (FluCoMa MLP) and a Markov fallback on a sample of the corpus. Temperature: lower = safer, higher = more surprising.").font_(Font("Helvetica", 10)).stringColor_(Color.new255(88, 93, 83));
	StaticText(window, 560@22).string_("Seed").font_(Font("Helvetica", 12, bold: true));
	seedBox = NumberBox(window, 100@28).value_(~pianoML13[\seed]).clipLo_(0).clipHi_(999999).decimals_(0).action_({ |box|
		~pianoML13[\seed] = box.value.asInteger;
	});
	Button(window, 122@34).states_([["Apply harmony"]]).action_({ applyHarmony.value });
	generateButton = Button(window, 122@34).states_([["Generate"]]).enabled_(false).action_({ generate.value });
	playButton = Button(window, 92@34).states_([["Play"]]).enabled_(false).action_({
		var start = {
			s.waitForBoot({
				~pianoML13Play.value({ updateStatus.value("Playing Salamander piano with sustain pedal") });
			});
		};
		if(~pianoML13[\melody].isEmpty) { generate.value(start) } { start.value };
	});
	Button(window, 92@34).states_([["Stop"]]).action_({
		~pianoML13Stop.value;
		updateStatus.value("Stopped");
	});
	exportButton = Button(window, 132@34).states_([["Export MIDI"]]).enabled_(false).action_({
		Dialog.savePanel({ |path|
			if(path.notNil and: { path.notEmpty }) {
				if(path.isKindOf(Array)) { path = path.first };
				if(path.endsWith(".mid").not) { path = path ++ ".mid" };
				~pianoML13ExportMIDI.value(path);
				updateStatus.value("Exported 12-EDO MIDI approximation");
			};
		});
	});
	audioButton = Button(window, 132@34).states_([["Export audio"]]).enabled_(false).action_({
		Dialog.savePanel({ |path|
			if(path.notNil and: { path.notEmpty }) {
				if(path.isKindOf(Array)) { path = path.first };
				if(path.endsWith(".wav").not) { path = path ++ ".wav" };
				audioButton.enabled = false;
				updateStatus.value("Rendering audio (offline, faster than real time)...");
				~pianoML13ExportAudio.value(path, { |seconds|
					{ audioButton.enabled = ~pianoML13[\melody].notEmpty }.defer;
					updateStatus.value("Exported %:% of 13-EDO audio to %".format(
						(seconds div: 60).asInteger, (seconds % 60).round.asInteger.asString.padLeft(2, "0"), PathName(path).fileName));
				}, { |message|
					{ audioButton.enabled = ~pianoML13[\melody].notEmpty }.defer;
					updateStatus.value(message);
				});
			};
		});
	});
	status = StaticText(window, 560@34).string_("Select a MIDI file to begin.").font_(Font("Helvetica", 11)).stringColor_(Color.new255(36, 55, 55));
	StaticText(window, 560@20).string_("Copyright © Ali Balighi 2026 (alibalighi.com)").font_(Font("Helvetica", 10)).stringColor_(Color.new255(88, 93, 83)).align_(\center);
	updateStatus = { |message| { status.string = message }.defer };
	// A changed setting makes the current phrase stale, so Play composes anew.
	settingChanged = { |message|
		~pianoML13[\melody] = [];
		~pianoML13[\accompaniment] = [];
		[exportButton, audioButton].do(_.enabled_(false));
		updateStatus.value(message + "Generate or Play to compose with it.");
	};
	setDuration = {
		~pianoML13[\duration] = ((minutesBox.value * 60) + secondsBox.value).max(10);
		settingChanged.value("Duration set to %:%.".format(
			(~pianoML13[\duration] div: 60).asInteger, (~pianoML13[\duration] % 60).asInteger.asString.padLeft(2, "0")));
	};
	updateModelStatus = { |message| { modelStatus.string = message }.defer };
	refreshButtons = {
		var ready = ~pianoML13Learn[\markov].notNil or: { ~pianoML13Learn[\mlpReady] };
		{
			generateButton.enabled = ready;
			playButton.enabled = ready;
		}.defer;
	};
	loadSource = { |path|
		var source;
		if(path.isEmpty) {
			updateStatus.value("Choose a MIDI file or paste its full path.");
		} {
			~pianoML13[\source] = nil;
			~pianoML13[\melody] = [];
			~pianoML13[\accompaniment] = [];
			[exportButton, audioButton].do(_.enabled_(false));
			try {
				source = ~pianoML13LoadMIDI.value(path);
				updateStatus.value("Loaded % notes from %. Its opening primes the model.".format(source[\notes].size, source[\name]));
				refreshButtons.value;
			} { |error|
				updateStatus.value("Could not load MIDI: %".format(error.errorString));
				error.reportError;
			};
		};
	};
	applyHarmony = {
		try {
			~pianoML13[\harmony] = ~pianoML13Edo[\parseHarmony].value(~pianoML13Edo, harmonyField.string);
			~pianoML13[\melody] = [];
			~pianoML13[\accompaniment] = [];
			[exportButton, audioButton].do(_.enabled_(false));
			updateStatus.value("Harmony updated: % chords. Generate a new phrase.".format(~pianoML13[\harmony].size));
		} { |error|
			updateStatus.value(error.errorString);
			error.reportError;
		};
	};
	// Generation is asynchronous (the neural net runs on the server), so
	// `then` runs once the phrase is ready.
	generate = { |then|
		updateStatus.value("Generating...");
		s.waitForBoot({
			~pianoML13Generate.value({ |modelName|
				var beats = ~pianoML13[\melody].collect { |event| event[\beat] + event[\dur] }.maxItem;
				var seconds = (beats * 60 / ~pianoML13[\tempo]).round.asInteger;
				{ [exportButton, audioButton].do(_.enabled_(true)) }.defer;
				updateStatus.value("Generated %:% (% bars, % melody notes) with the %".format(
					seconds div: 60, (seconds % 60).asString.padLeft(2, "0"),
					(beats / (~pianoML13[\beatsPerBar] ? 4)).round.asInteger, ~pianoML13[\melody].size, modelName));
				then.value;
			}, { |message|
				updateStatus.value("Generate failed: %".format(message));
			}, { |fraction|
				updateStatus.value("Generating... %\\%".format((fraction * 100).round.asInteger.min(99)));
			});
		});
	};
	~pianoML13[\window] = window;
	~pianoML13LoadModels.value({ |message| updateModelStatus.value(message); refreshButtons.value });
};

~pianoML13[\openInterface] = { ~pianoML13OpenInterface.value };
)