(
var include_relative = { |relative_path|
	var path = (PathName(thisProcess.nowExecutingPath).pathOnly +/+ relative_path).standardizePath;
	if (File.exists(path)) {
		var result = this.executeFile(path);
		if (result.isNil) { Error("error importing %".format(path)).throw; } { result };
	} {
		Error("include_relative: file % does not exist".format(path.quote)).throw;
	};
};

var lib_root_relative = "lib";
var norns_engine_tester = include_relative.value(lib_root_relative +/+ "norns_engine_tester.scd");
var start_script = norns_engine_tester['start_script'];
var script_name = PathName(thisProcess.nowExecutingPath).fileNameWithoutExtension;

var r_engine_root_relative = ".." +/+ ".." +/+ "r";

start_script.value(script_name) {

// scriptname: moln
// v1.3.0 @jah
var formatters = include_relative.value(lib_root_relative +/+ "formatters.scd");

var common = include_relative.value("lib/common.scd");
var common_init_script_state = common[\init_script_state];
var common_cleanup = common[\cleanup];
var common_redraw = common[\redraw];
var common_enc = common[\enc];
var common_key = common[\key];
var common_mouse = common[\mouse];
var common_add_params = common[\add_params];
var common_render_arc = common[\render_arc];
var common_get_param_id_for_current_page = common[\get_param_id_for_current_page];
var common_load_settings_and_params = common[\load_settings_and_params];
var common_calculate_ui_page_label_widths = common[\calculate_ui_page_label_widths];
var common_update_page_transition = common[\update_page_transition];

var rrrr = include_relative.value(r_engine_root_relative +/+ "lib" +/+ "r.scd");
var rrrr_lib = rrrr[\lib];
var r_specs = rrrr_lib[\specs];
var r_util = rrrr_lib[\util];
var r_engine = rrrr_lib[\engine];

var custom_formatters = include_relative.value(lib_root_relative +/+ "formatters.scd"); // TODO

var voice = include_relative.value(lib_root_relative +/+ "voice.scd");
var voice_new = voice[\voice_new];

var polyphony = 5;
var note_downs = ();
var note_slots = ();

var ui_dirty = false;

var ui_refresh_rate = 35;

var settings_file = "moln.data";

var script_state;

var pages = [
	[ (id: "filter_frequency"), (id: "filter_resonance") ],
	[ (id: "osc_a_range"), (id: "osc_b_range") ],
	[ (id: "osc_a_pulsewidth"), (id: "osc_b_pulsewidth") ],
	[ (id: "osc_detune"), (id: "lfo_frequency") ],
	[ (id: "lfo_to_osc_pwm"), (id: "env_to_filter_fm") ],
	[ (id: "env_attack"), (id: "env_decay") ],
	[ (id: "env_sustain"), (id: "env_release") ],
];

var arc_device;

var midi_device;

var show_event_indicator = false;

var event_flash_frames = 5;
var event_flash_frame_counter = nil;

var flash_event = {
	event_flash_frame_counter = event_flash_frames;
	ui_dirty = true;
};
  
var update_event_indicator = {
	if (event_flash_frame_counter.notNil) {
		event_flash_frame_counter = event_flash_frame_counter - 1;
		case
		{ event_flash_frame_counter == 0 } {
			event_flash_frame_counter = nil;
			show_event_indicator = false;
			ui_dirty = true;
		}
		{ show_event_indicator.not } {
			show_event_indicator = true;
			ui_dirty = true;
		};
	};
};

var refresh_ui = {
	if (script_state[\target_page].notNil) {
		common_update_page_transition.value(script_state);
		ui_dirty = true;
	};

	update_event_indicator.value();

	if (ui_dirty) {
		common_render_arc.value(~params, script_state, pages, arc_device);
		arc_device.refresh_();

		~redraw.value();

		ui_dirty = false;
	};
};

var init_ui_refresh_metro = {
	var ui_refresh_metro = ~metro.init_();
	ui_refresh_metro.event = refresh_ui;
	ui_refresh_metro.time = 1/ui_refresh_rate;
	ui_refresh_metro.start_();
};

var init_ui = {
	arc_device = ~arc.connect_();

	arc_device[\delta] = { |n, delta| // not .delta notation to suppress self argument?
		var d;
		var id;
		var val;

		flash_event.value();

		if (script_state[\fine]) {
			d = delta/5;
		} {
			d = delta;
		};
		id = common_get_param_id_for_current_page.value(pages, script_state, n-1); // TODO: zero-based
		val = ~params.get_raw_(id);
		~params.set_raw_(id, val+(d/500));
		ui_dirty = true;
	};

	midi_device = ~midi.connect_();

	midi_device[\event] = { |data|
		flash_event.value();
		if (engine_ready) {
			var msg = ~midi.to_msg_(data);
			case
			{msg['type'] == 'note_off'} {
				note_off.value(msg.note);
			}
			{msg['type'] == 'note_on'} {
				note_on.value(msg.note, msg.vel / 127);

			}
			{msg['type'] == 'cc'} {
				var num = msg['num'];
				var val = msg['val'];
				var rel_cc_delta = if (val > 64, val-128, val);
				[num, val].debug;
				case
				{num == 1} {
					// ~params.delta_( "lfo_frequency", rel_cc_delta);
					common_enc.value(~params, pages, script_state, 2, rel_cc_delta);
				}
				{num == 2} {
					//~params.delta_( "lfo_to_osc_pwm", rel_cc_delta);
					//~params.delta_( "osc_detune", rel_cc_delta);
					common_enc.value(~params, pages, script_state, 3, rel_cc_delta);
				}
				{num == 3} {
					// ~params.delta_( "filter_frequency", rel_cc_delta);
				}
				{num == 4} {
					//~params.delta_( "env_release", rel_cc_delta);
					common_enc.value(~params, pages, script_state, 1, rel_cc_delta);
				}
				{num == 11} {
					case
					{val == 127} {
						common_key.value(pages, ui_refresh_rate, script_state, 2, 1);
					}
					{val == 0} {
						common_key.value(pages, ui_refresh_rate, script_state, 2, 0);
					};
				}
				{num == 12} {
					case
					{val == 127} {
						common_key.value(pages, ui_refresh_rate, script_state, 3, 1);
					}
					{val == 0} {
						common_key.value(pages, ui_refresh_rate, script_state, 3, 0);
					};
				}
				{num == 14} {
					case
					{val == 127} {
						common_key.value(pages, ui_refresh_rate, script_state, 1, 1);
					}
					{val == 0} {
						common_key.value(pages, ui_refresh_rate, script_state, 1, 0);
					};
				}
				;
				ui_dirty = true;
			};
		}
	};

	init_ui_refresh_metro.value();
};

var engine_ready = false;

var start_after_1_second_delay; // TODO: global in lua
var init_engine_init_delay_metro; // TODO: global in lua

var init_r_modules = {
	create_modules.value();
	set_static_module_params.value();
	connect_modules.value();
	create_macros.value();
};

var create_modules = {
	r_engine.poly_new_("FreqGate", "FreqGate", polyphony);
	r_engine.poly_new_("LFO", "SineLFO", polyphony);
	r_engine.poly_new_("Env", "ADSREnv", polyphony);
	r_engine.poly_new_("OscA", "PulseOsc", polyphony);
	r_engine.poly_new_("OscB", "PulseOsc", polyphony);
	r_engine.poly_new_("Filter", "LPFilter", polyphony);
	r_engine.poly_new_("Amp", "Amp", polyphony);

	~engine.new_("Amplifier", "SGain");
	~engine.new_("SoundOut", "SoundOut");
};

var set_static_module_params = {
	r_engine.poly_set_("OscA.FM", 1, polyphony);
	r_engine.poly_set_("OscB.FM", 1, polyphony);
	r_engine.poly_set_("Filter.AudioLevel", 1, polyphony);
};

var connect_modules = {
	r_engine.poly_connect_("FreqGate/Frequency", "OscA*FM", polyphony);
	r_engine.poly_connect_("FreqGate/Frequency", "OscB*FM", polyphony);
	r_engine.poly_connect_("FreqGate/Gate", "Env*Gate", polyphony);
	r_engine.poly_connect_("LFO/Out", "OscA*PWM", polyphony);
	r_engine.poly_connect_("LFO/Out", "OscB*PWM", polyphony);
	r_engine.poly_connect_("Env/Out", "Amp*Lin", polyphony);
	r_engine.poly_connect_("Env/Out", "Filter*FM", polyphony);
	r_engine.poly_connect_("OscA/Out", "Filter*In", polyphony);
	r_engine.poly_connect_("OscB/Out", "Filter*In", polyphony);
	r_engine.poly_connect_("Filter/Out", "Amp*In", polyphony);
	
	polyphony.do { |i|
		var voicenum = i + 1;
		~engine.connect_("Amp"++voicenum++"/Out", "Amplifier*Left");
		~engine.connect_("Amp"++voicenum++"/Out", "Amplifier*Right");
	};
	~engine.connect_("Amplifier/Left", "SoundOut*Left");
	~engine.connect_("Amplifier/Right", "SoundOut*Right");
};

var create_macros = {
	~engine.newmacro_("osc_a_range", r_util.poly_expand_("OscA.Range", polyphony));
	~engine.newmacro_("osc_a_pulsewidth", r_util.poly_expand_("OscA.PulseWidth", polyphony));
	~engine.newmacro_("osc_b_range", r_util.poly_expand_("OscB.Range", polyphony));
	~engine.newmacro_("osc_b_pulsewidth", r_util.poly_expand_("OscB.PulseWidth", polyphony));
	~engine.newmacro_("osc_a_detune", r_util.poly_expand_("OscA.Tune", polyphony));
	~engine.newmacro_("osc_b_detune", r_util.poly_expand_("OscB.Tune", polyphony));
	~engine.newmacro_("lfo_frequency", r_util.poly_expand_("LFO.Frequency", polyphony));
	~engine.newmacro_("osc_a_pwm", r_util.poly_expand_("OscA.PWM", polyphony));
	~engine.newmacro_("osc_b_pwm", r_util.poly_expand_("OscB.PWM", polyphony));
	~engine.newmacro_("filter_frequency", r_util.poly_expand_("Filter.Frequency", polyphony));
	~engine.newmacro_("filter_resonance", r_util.poly_expand_("Filter.Resonance", polyphony));
	~engine.newmacro_("env_to_filter_fm", r_util.poly_expand_("Filter.FM", polyphony));
	~engine.newmacro_("env_attack", r_util.poly_expand_("Env.Attack", polyphony));
	~engine.newmacro_("env_decay", r_util.poly_expand_("Env.Decay", polyphony));
	~engine.newmacro_("env_sustain", r_util.poly_expand_("Env.Sustain", polyphony));
	~engine.newmacro_("env_release", r_util.poly_expand_("Env.Release", polyphony));
};

var get_filter_frequency_param_spec = {
	var spec = r_specs[\LPFilter][\Frequency].copy();
	spec.maxval = 8000;
	spec.minval = 10;
	spec.default = 500;

	IdentityDictionary[
		\id -> "filter_frequency",
		\type -> "control",
		\name -> "Filter Frequency",
		\narrow_name -> "FREQ",
		\controlspec -> spec,
		\narrow_formatter -> formatters[\adaptive_freq],
		\action -> { |value|
			~engine.macroset_("filter_frequency", value);
		}
	];
};

var get_filter_resonance_param_spec = {
	var spec = r_specs[\LPFilter][\Resonance].copy();
	spec.default = 0.2;

	IdentityDictionary[
		\id -> "filter_resonance",
		\type -> "control",
		\name -> "Filter Resonance",
		\narrow_name -> "RES",
		\controlspec -> spec,
		\formatter -> formatters[\percentage],
		\action -> { |value|
			~engine.macroset_("filter_resonance", value);
		}
	];
};

var get_osc_a_range_param_spec = {
	IdentityDictionary[
		\id -> "osc_a_range",
		\type -> "control",
		\name -> "Osc A Range",
		\narrow_name -> "A.RNG",
		\controlspec -> r_specs[\PulseOsc][\Range],
		\formatter -> formatters[\round].value(1),
		\narrow_formatter -> formatters[\range],
		\action -> { |value|
			~engine.macroset_("osc_a_range", value);
		}
	];
};

var get_osc_b_range_param_spec = {
	IdentityDictionary[
		\id -> "osc_b_range",
		\type -> "control",
		\name -> "Osc B Range",
		\narrow_name -> "B.RNG",
		\controlspec -> r_specs[\PulseOsc][\Range],
		\formatter -> formatters[\round].value(1),
		\narrow_formatter -> formatters[\range],
		\action -> { |value|
			~engine.macroset_("osc_b_range", value);
		}
	];
};

var get_osc_a_pulsewidth_param_spec = {
	var spec = r_specs[\PulseOsc][\PulseWidth].copy();
	spec.default = 0.88;

	IdentityDictionary[
		\id -> "osc_a_pulsewidth",
		\type -> "control",
		\name -> "Osc A Pulse Width",
		\narrow_name -> "A.PW",
		\controlspec -> spec,
		\formatter -> formatters[\percentage],
		\action -> { |value|
			~engine.macroset_("osc_a_pulsewidth", value);
		}
	];
};

var get_osc_b_pulsewidth_param_spec = {
	var spec = r_specs[\PulseOsc][\PulseWidth].copy();
	spec.default = 0.88;

	IdentityDictionary[
		\id -> "osc_b_pulsewidth",
		\type -> "control",
		\name -> "Osc B Pulse Width",
		\narrow_name -> "B.PW",
		\controlspec -> spec,
		\formatter -> formatters[\percentage],
		\action -> { |value|
			~engine.macroset_("osc_b_pulsewidth", value);
		}
	];
};

var get_osc_detune_param_spec = {
	var spec = \unipolar.asSpec.copy();
	spec.default = 0.36;

	IdentityDictionary[
		\id -> "osc_detune",
		\type -> "control",
		\name -> "Detune",
		\narrow_name -> "DETUN",
		\controlspec -> spec,
		\formatter -> formatters[\percentage],
		\action -> { |value|
			~engine.macroset_("osc_a_detune", -1 * value * 20);
			~engine.macroset_("osc_b_detune", value * 20);
		}
	];
};

var get_lfo_frequency_param_spec = {
	var spec = r_specs[\MultiLFO][\Frequency].copy();
	spec.default = 0.125;

	IdentityDictionary[
		\id -> "lfo_frequency",
		\type -> "control",
		\name -> "PWM Rate",
		\narrow_name -> "LFO",
		\controlspec -> spec,
		\formatter -> formatters[\round].value(0.001),
		\narrow_formatter -> formatters[\adaptive_freq],
		\action -> { |value|
			~engine.macroset_("lfo_frequency", value);
		}
	];
};

var get_lfo_to_osc_pwm_param_spec = {
	var spec = \unipolar.asSpec.copy();
	spec.default = 0.46;

	IdentityDictionary[
		\id -> "lfo_to_osc_pwm",
		\type -> "control",
		\name -> "PWM Depth",
		\narrow_name -> "PWM",
		\controlspec -> spec,
		\formatter -> formatters[\percentage],
		\action -> { |value|
			~engine.macroset_("osc_a_pwm", value*0.76);
			~engine.macroset_("osc_b_pwm", value*0.56);
		}
	];
};

var get_env_to_filter_fm_param_spec = {
	var spec = r_specs[\LPFilter][\FM].copy();
	spec.default = 0.35;

	IdentityDictionary[
		\id -> "env_to_filter_fm",
		\type -> "control",
		\name -> "Env > Filter Frequency",
		\narrow_name -> "E>FIL",
		\controlspec -> spec,
		\formatter -> formatters[\percentage],
		\action -> { |value|
			~engine.macroset_("env_to_filter_fm", value);
		}
	];
};

var get_env_attack_param_spec = {
	var spec = r_specs[\ADSREnv][\Attack].copy();
	spec.default = 1;

	IdentityDictionary[
		\id -> "env_attack",
		\type -> "control",
		\name -> "Env Attack",
		\narrow_name -> "E.ATK",
		\controlspec -> spec,
		\narrow_formatter -> formatters[\adaptive_time],
		\action -> { |value|
			~engine.macroset_("env_attack", value);
		}
	];
};

var get_env_decay_param_spec = {
	var spec = r_specs[\ADSREnv][\Decay].copy();
	spec.default = 200;

	IdentityDictionary[
		\id -> "env_decay",
		\type -> "control",
		\name -> "Env Decay",
		\narrow_name -> "E.DEC",
		\controlspec -> spec,
		\narrow_formatter -> formatters[\adaptive_time],
		\action -> { |value|
			~engine.macroset_("env_decay", value);
		}
	];
};

var get_env_sustain_param_spec = {
	var spec = r_specs[\ADSREnv][\Sustain].copy();
	spec.default = 0.5;

	IdentityDictionary[
		\id -> "env_sustain",
		\type -> "control",
		\name -> "Env Sustain",
		\narrow_name -> "E.SUS",
		\controlspec -> spec,
		\formatter -> formatters[\percentage],
		\action -> { |value|
			~engine.macroset_("env_sustain", value);
		}
	];
};

var get_env_release_param_spec = {
	var spec = r_specs[\ADSREnv][\Release].copy();
	spec.default = 500;

	IdentityDictionary[
		\id -> "env_release",
		\type -> "control",
		\name -> "Env Release",
		\narrow_name -> "E.REL",
		\controlspec -> spec,
		\narrow_formatter -> formatters[\adaptive_time],
		\action -> { |value|
			~engine.macroset_("env_release", value);
		}
	];
};

var get_main_level_param_spec = {
	var spec = r_specs['MGain']['Gain'].copy;
	spec.default = -10;

	IdentityDictionary[
		\id -> "main_level",
		\type -> "control",
		\name -> "Amplifier.Gain",
		\controlspec -> spec,
		\formatter -> formatters.round_(0.1),
		\action -> { |value|
			~engine.set_("Amplifier.Gain", value);
		}
	];
};

var get_param_specs = {
	[
		get_filter_frequency_param_spec.value(),
		get_filter_resonance_param_spec.value(),
		get_osc_a_range_param_spec.value(),
		get_osc_b_range_param_spec.value(),
		get_osc_a_pulsewidth_param_spec.value(),
		get_osc_b_pulsewidth_param_spec.value(),
		get_osc_detune_param_spec.value(),
		get_lfo_frequency_param_spec.value(),
		get_lfo_to_osc_pwm_param_spec.value(),
		get_env_to_filter_fm_param_spec.value(),
		get_env_attack_param_spec.value(),
		get_env_decay_param_spec.value(),
		get_env_sustain_param_spec.value(),
		get_env_release_param_spec.value(),
		get_main_level_param_spec.value()
	];
};

var note_on = { |note, velocity|
	if (note_slots[note].isNil) {
		var slot = ~voice_allocator.get__();
		var voicenum = slot[\id__]; // TODO: + 1
		trig_voice.value(voicenum, note);
		slot[\on_release__] = {
			release_voice.value(voicenum);
			note_slots[note] = nil;
		};
		note_slots[note] = slot;
		note_downs[voicenum] = note;
	};
};

var trig_voice = { |voicenum, note|
	~engine.bulkset_("FreqGate"++voicenum++".Gate 1 FreqGate"++voicenum++".Frequency "++note.midicps);
};

var release_voice = { |voicenum|
	~engine.bulkset_("FreqGate"++voicenum++".Gate 0");
};

var note_off = { |note|
	var slot = note_slots[note];
	if (slot.notNil) {
		~voice_allocator.release__(slot);
		note_downs[slot[\id]] = nil;
	};
};

~engine.name = 'R';

~init = {
	var param_specs;

	~voice_allocator = voice_new.value(polyphony);
	init_r_modules.value();

	param_specs = get_param_specs.value();

	common_add_params.value(~params, param_specs, { ui_dirty = true });

	script_state = common_init_script_state.value();

	common_calculate_ui_page_label_widths.value(~params, ~screen, pages);

	common_load_settings_and_params.value(~params, settings_file);

	init_ui.value();

	start_after_1_second_delay.value();
};

start_after_1_second_delay = {
	init_engine_init_delay_metro.value();
};

init_engine_init_delay_metro = {
	var engine_init_delay_metro = ~metro.init_();
	engine_init_delay_metro[\event] = {
		engine_ready = true;

		ui_dirty = true;

		engine_init_delay_metro.stop_();
	};
	engine_init_delay_metro.time = 1;
	engine_init_delay_metro.start_();
};

~cleanup = {
	common_cleanup.value(~params, settings_file);
};

~redraw = {
	common_redraw.value(~params, ~screen, pages, script_state, show_event_indicator);
};

~enc = { |n, delta|
	common_enc.value(~params, pages, script_state, n, delta);
	ui_dirty = true;
};

~key = { |n, z|
	if (n == 1) {
		if (z == 1) {
			[60, 63, 67] do: { |note|
				note_on.value(note, 1);
			};
		} {
			[60, 63, 67] do: { |note|
				note_off.value(note);
			};
		}
	} {
		common_key.value(pages, ui_refresh_rate, script_state, n, z);
	};
	ui_dirty = true;
};

~mouse = { |... args|
	common_mouse.value(*([~params, ~screen, pages, ui_refresh_rate, script_state]++args));
	ui_dirty = true;
};

};
)
