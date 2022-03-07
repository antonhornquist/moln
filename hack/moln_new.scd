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

var r_engine_root_relative = ".." +/+ ".." +/+ "r";

var norns_engine_tester = include_relative.value(r_engine_root_relative +/+ "hack" +/+ "lib" +/+ "norns_engine_tester.scd");
var start_script = norns_engine_tester['start_script'];
var script_name = PathName(thisProcess.nowExecutingPath).fileNameWithoutExtension;

start_script.value(script_name) {

// scriptname: moln
// v1.3.0 @jah
var rrrr = include_relative.value(r_engine_root_relative +/+ "lib" +/+ "r.scd");
var rrrr_lib = rrrr[\lib];
var r_specs = rrrr_lib[\specs];
var r_util = rrrr_lib[\util];
var r_engine = rrrr_lib[\engine];

var formatters = include_relative.value("lib" +/+ "formatters.scd");
var custom_formatters = include_relative.value("lib" +/+ "formatters.scd");

var event_flash_duration = 0.15;
var event_indicator_frame_counter = nil;

var page_transition_duration = 0.2;
var current_page = 0; // TODO: zero based
var target_page;
var page_trans_delta_per_frame;
var page_trans_frames;
var pages = [
	[ "filter_frequency", "filter_resonance" ],
	[ "osc_a_range", "osc_b_range" ],
	[ "osc_a_pulsewidth", "osc_b_pulsewidth" ],
	[ "osc_detune", "lfo_frequency" ],
	[ "lfo_to_osc_pwm", "env_to_filter_fm" ],
	[ "env_attack", "env_decay" ],
	[ "env_sustain", "env_release" ],
];
var param_name_widths = (); // TODO: rather, label width

var midi_device;

var arc_device;

var arc_led_x_spec = ControlSpec(1, 64, 'linear', 1, 0, "");
var arc_led_l_spec = ControlSpec(0, 15, 'linear', 1, 0, "");

// TODO: naming below
var num_arc_ring_leds = asInteger(arc_led_x_spec.maxval*0.71); // TODO: ought to be odd for best visualization

var ui_refresh_rate = 35;
var visual_trail_duration = 0.05;
var ui_dirty = false;

var visual_values_dict;
var polls;

var settings_file = "skev.data";

var hi_level = 15;
var lo_level = 5; // TODO: 4 in lua
var mid_level = round((hi_level+lo_level)/2); // TODO

var screen_width = 128;

var enc1_label = "LEVEL";
var enc1_label_top = 1;
var enc1_label_left = 1;
var enc1_label_right;
var enc1_label_bottom = 12;

var enc1_value_top = enc1_label_top + 1;
var enc1_value_left;
var enc1_value_bottom = enc1_label_bottom;

var event_indicator_top = enc1_label_top + 4;
var event_indicator_left = 122;
var event_indicator_width = 5;
var event_indicator_height = 5;

var enc2_label_top = 17;
var enc2_label_left = 10;
var enc2_label_bottom = enc2_label_top + 12;

var enc2_value_top = enc2_label_bottom;
var enc2_value_left = enc2_label_left;
var enc2_value_bottom = enc2_value_top + 12;

var enc2_widget_top = enc2_value_bottom + 2;
var enc2_widget_left = enc2_label_left + 1;
var enc2_widget_bottom = enc2_widget_top + 2;

var enc3_label_top = enc2_label_top;
var enc3_label_left = enc2_label_left + 65;
var enc3_label_bottom = enc2_label_top + 12;

var enc3_value_top = enc3_label_bottom;
var enc3_value_left = enc3_label_left;
var enc3_value_bottom = enc3_value_top + 12;

var enc3_widget_top = enc3_value_bottom + 2;
var enc3_widget_left = enc3_label_left + 1;
var enc3_widget_bottom = enc3_widget_top + 2;

var page_indicator_top = enc3_label_bottom + 16 + 3;
var page_indicator_left = 1;
var page_indicator_width = screen_width;
var page_indicator_height = 2;

var key2_label = "PREV";
var key2_top = 51;
var key2_left = 1;
var key2_right;
var key2_bottom = key2_top + 12;

var key3_label = "NEXT";
var key3_top = 51;
var key3_left = key2_left + 65;
var key3_right;
var key3_bottom = key2_bottom;

var fine = false;
var prev_key_held = false;
var next_key_held = false;

var focus;
var active;

var engine_ready = false;

// section: event flash logic

var
flash_event =
{
	event_indicator_frame_counter = floor(event_flash_duration * ui_refresh_rate);
};
  
var
event_indicator_should_be_shown =
{
	event_indicator_frame_counter != nil
};

var
update_event_indicator =
{
	if (event_indicator_frame_counter.notNil) {
		event_indicator_frame_counter = event_indicator_frame_counter - 1;
		case
		{ event_indicator_frame_counter <= 0 } {
			event_indicator_frame_counter = nil;
		};
		ui_dirty = true;
	};
};

// section: ui paging logic

var
transition_to_page =
{ |page|
	target_page = page;
	page_trans_frames = floor(ui_refresh_rate*page_transition_duration);
	page_trans_delta_per_frame = (target_page - current_page) / page_trans_frames;
};

var
is_transitioning = // TODO: better naming
{
	target_page != nil
};

var
page_delta =
{ |delta|
	var page;

	if (is_transitioning.value()) {
		page = target_page;
	} {
		page = get_active_page.value();
	};

	page = page + delta;
	if (page < 0) { // TODO: zero based indexing
		page = pages.size-1;
	};
	if (page > (pages.size-1)) { // TODO: zero based indexing
		page = 0;
	};

	transition_to_page.value(page);

	transition_to_page.value(page); // TODO
};

var
transition_to_prev_page =
{
	page_delta.value(-1);
};

var
transition_to_next_page =
{
	page_delta.value(1);
};

var
update_page_transition =
{
	var new_current_page;
	new_current_page = current_page + page_trans_delta_per_frame;
	page_trans_frames = page_trans_frames - 1;
	if (page_trans_frames == 0) {
		new_current_page = target_page;
		target_page = nil;
	};
	current_page = new_current_page;
};

var
get_active_page =
{
	round(current_page); // TODO zero-based - make one based
};

var
get_id_for_displayed_param = { |n|
	var page = get_active_page.value(); // TODO: zero-based
	pages[page][n-1]; // TODO: zero based
};

var
get_page_transition_offset_in_pixels =
{
	var left = floor(current_page); // TODO: zero based
	var offset = current_page - left; // TODO: zero based
	round(offset*screen_width);
};

var
get_params_to_draw =
{
	var params_to_draw = [];
	var pixel_offset = get_page_transition_offset_in_pixels.value();

	if (is_transitioning.value()) {
		var pixel_offset_2 = (screen_width-pixel_offset);
		params_to_draw = params_to_draw.add(
			(
				page_index: floor(current_page), // TODO: zero based
				param_index: 1,
				label_left: enc2_label_left-pixel_offset,
				label_bottom: enc2_label_bottom,
				value_left: enc2_value_left-pixel_offset,
				value_bottom: enc2_value_bottom,
				widget_left: enc2_widget_left-pixel_offset,
				widget_top: enc2_widget_top,
				indicate_focussed_widget: ((focus == 'enc2_widget') && (active == nil)), // TODO: refactor to focus of widget based on param_id instead
				indicate_focussed_value: (focus == 'enc2_value') // TODO: refactor to focus of value based on param_id instead
			)
		);
		params_to_draw = params_to_draw.add(
			(
				page_index: floor(current_page), // TODO: zero based
				param_index: 2,
				label_left: enc3_label_left-pixel_offset,
				label_bottom: enc3_label_bottom,
				value_left: enc3_value_left-pixel_offset,
				value_bottom: enc3_value_bottom,
				widget_left: enc3_widget_left-pixel_offset,
				widget_top: enc3_widget_top,
				indicate_focussed_widget: ((focus == 'enc3_widget') && (active == nil)),
				indicate_focussed_value: (focus == 'enc3_value')
			)
		);
		params_to_draw = params_to_draw.add(
			(
				page_index: ceil(current_page), // TODO: zero based
				param_index: 1,
				label_left: enc2_label_left+pixel_offset_2,
				label_bottom: enc2_label_bottom,
				value_left: enc2_value_left+pixel_offset_2,
				value_bottom: enc2_value_bottom,
				widget_left: enc2_widget_left+pixel_offset_2,
				widget_top: enc2_widget_top,
				indicate_focussed_widget: ((focus == 'enc2_widget') && (active == nil)),
				indicate_focussed_value: (focus == 'enc2_value')
			)
		);
		params_to_draw = params_to_draw.add(
			(
				page_index: ceil(current_page), // TODO: zero based
				param_index: 2,
				label_left: enc3_label_left+pixel_offset_2,
				label_bottom: enc3_label_bottom,
				value_left: enc3_value_left+pixel_offset_2,
				value_bottom: enc3_value_bottom,
				widget_left: enc3_widget_left+pixel_offset_2,
				widget_top: enc3_widget_top,
				indicate_focussed_widget: ((focus == 'enc3_widget') && (active == nil)),
				indicate_focussed_value: (focus == 'enc3_value')
			)
		);
	} {
		params_to_draw = params_to_draw.add(
			(
				page_index: get_active_page.value(), // TODO: zero based
				param_index: 1,
				label_left: enc2_label_left-pixel_offset,
				label_bottom: enc2_label_bottom,
				value_left: enc2_value_left-pixel_offset,
				value_bottom: enc2_value_bottom,
				widget_left: enc2_widget_left-pixel_offset,
				widget_top: enc2_widget_top,
				indicate_focussed_widget: ((focus == 'enc2_widget') && (active == nil)),
				indicate_focussed_value: (focus == 'enc2_value')
			)
		);

		params_to_draw = params_to_draw.add(
			(
				page_index: get_active_page.value(), // TODO: zero based
				param_index: 2,
				label_left: enc3_label_left-pixel_offset,
				label_bottom: enc3_label_bottom,
				value_left: enc3_value_left-pixel_offset,
				value_bottom: enc3_value_bottom,
				widget_left: enc3_widget_left-pixel_offset,
				widget_top: enc3_widget_top,
				indicate_focussed_widget: ((focus == 'enc3_widget') && (active == nil)),
				indicate_focussed_value: (focus == 'enc3_value')
			)
		);
	};
};

// section: param led array visualization

var
value_to_pixel =
{ |value, num_pixels|
	round((num_pixels-1) * value.clip(0, 1));
};

var
pixel_to_value =
{ |pixel, num_pixels|
	pixel.clip(0, num_pixels-1) / (num_pixels-1);
};

var
map_param_state_to_led_array = // TODO: naming
{ |num_pixels, value, value_level, visual_values, max_visual_level|
	var value_pixel = value_to_pixel.value(value, num_pixels);

	var min_max_visuals;
	var num_visual_values;

	if (visual_values.notNil) {
		num_visual_values = visual_values.size;

		case
		{ num_visual_values > 1 } {
			var prev_visual_value = visual_values[0]; // TODO: zero based indexing

			min_max_visuals = nil ! (num_visual_values - 1);

			(num_visual_values-1).do { |visual_value_idx| // TODO: zero based indexing
				var idx = visual_value_idx + 1;
				var visual_value = visual_values[idx];

				var min_visual_value = min(prev_visual_value, visual_value);
				var max_visual_value = max(prev_visual_value, visual_value);

				min_max_visuals[visual_value_idx] = [
					value_to_pixel.value(min_visual_value, num_pixels),
					value_to_pixel.value(max_visual_value, num_pixels)
				];

				prev_visual_value = visual_value;
			};
		}
		{ num_visual_values == 1 } {
			min_max_visuals = [
				[
					value_to_pixel.value(visual_values[0], num_pixels),
					value_to_pixel.value(visual_values[0], num_pixels)
				]
			];
		};
	};

	num_pixels.collect { |index| // TODO: store references instead of levels?
		case
		{ index == value_pixel } {
			value_level
		}
		{ visual_values.notNil } {
			var level;
			min_max_visuals.do { |min_max_pixels, min_max_visuals_index|
				var min_value = min_max_pixels[0];
				var max_value = min_max_pixels[1];
				if ((min_value <= index).and(index <= max_value)) {
					if (num_visual_values == 1) {
						level = max_visual_level;
					} {
						level = round(max_visual_level/(num_visual_values-1)*(min_max_visuals_index+1));
					};
				};
			};
			level;
		};
	};
};

// section: arc device logic

var
init_arc =
{
	arc_device = ~arc.connect_();
	arc_device[\delta] = { |n, delta| // not .delta notation to suppress self argument?
		var d;
		var param_id;
		var val;

		flash_event.value();

		if (fine) {
			d = delta/5;
		} {
			d = delta;
		};

		param_id = get_id_for_displayed_param.value(n);

		if (param_id != nil) {
			val = ~params.get_raw_(param_id);
			~params.set_raw_(param_id, val+(d/500));
			ui_dirty = true;
		};
	};
};

var
draw_ring = { |ring, value, visual_values|
	var led_levels = map_param_state_to_led_array.value(num_arc_ring_leds, value, arc_led_l_spec.maxval, visual_values, round(arc_led_l_spec.maxval/4));
	var led_x_offset = arc_led_x_spec.maxval - ((num_arc_ring_leds-1)/2);
	(1..led_levels.size).do { |index|
		var led_x_pos = ((led_x_offset + index) mod: arc_led_x_spec.maxval) + 1; // TODO: one based ?
		var led_level = led_levels[index-1];
		arc_device.led_(ring, led_x_pos, led_level);
	};
};

var
draw_arc =
{ |value1, visual_values1, value2, visual_values2|
	var ring_base_led_level = round(arc_led_l_spec.maxval/3); // TODO: move, no need to recalculate all the time
	arc_device.all_(ring_base_led_level);
	draw_ring.value(1, value1, visual_values1);
	draw_ring.value(2, value2, visual_values2);
};

var
refresh_arc =
{
	var param1_id = get_id_for_displayed_param.value(1);
	var param2_id = get_id_for_displayed_param.value(2);

	var visual_values1;
	var visual_values2;

	var param1_raw_value;
	var param2_raw_value;

	if (param1_id != nil) {
		param1_raw_value = ~params.get_raw_(param1_id);
	} {
		param1_raw_value = 0; // TODO: should not show any value - blank ring
	};

	if (param2_id != nil) {
		param2_raw_value = ~params.get_raw_(param2_id);
	} {
		param2_raw_value = 0; // TODO: should not show any value - blank ring
	};

	// if (~params.get_("visual_feedback") == 1) { TODO: no polls
		if (param1_id != nil) {
			var visual_values_param1 = visual_values_dict[param1_id];
			if (visual_values_param1.notNil) {
				visual_values1 = visual_values_param1[\content];
			};
		};
		if (param1_id != nil) {
			var visual_values_param2 = visual_values_dict[param2_id];
			if (visual_values_param2.notNil) {
				visual_values2 = visual_values_param2[\content];
			};
		};
	// }; TODO: no polls

	draw_arc.value(
		param1_raw_value,
		visual_values1,
		param2_raw_value,
		visual_values2
	);

	arc_device.refresh_();
};

// section: midi device logic

var
init_midi =
{
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
/*
	TODO
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
*/
		}
	};
};

// section: ui bounds calculation

var
calculate_page_param_name_widths =
{
	pages.do { |page|
		page.do { |param_id|
			if (param_id != nil) {
				var param_name = ~params.get_name_(param_id);
				param_name_widths[param_id] = 40; // TODO round(~screen.text_extents_(param_name)).asInteger;
			};
		};
	};
};

var
calculate_enc1_bounds =
{
	enc1_label_right = enc1_label_left + round(~screen.text_extents_(enc1_label) - 2).asInteger;
	enc1_value_left = enc1_label_right + 5;
};

var
calculate_key2_bounds =
{
	key2_right = key2_left + round(~screen.text_extents_(key2_label)).asInteger;
};

var
calculate_key3_bounds =
{
	key3_right = key3_left + round(~screen.text_extents_(key3_label)).asInteger;
};

var
calculate_ui_bounds =
{
	~screen.font_size_(16);
	calculate_page_param_name_widths.value();
	calculate_enc1_bounds.value();
	calculate_key2_bounds.value();
	calculate_key3_bounds.value();
};

// section: ui refresh logic

var
refresh_ui =
{
	if (is_transitioning.value()) {
		update_page_transition.value();
		ui_dirty = true;
	};

	update_event_indicator.value();

	if (ui_dirty) {
		~redraw.value();
		refresh_arc.value();
		ui_dirty = false;
	};
};

var
init_ui_refresh_metro =
{
	var ui_refresh_metro = ~metro.init_();
	ui_refresh_metro.event = refresh_ui;
	ui_refresh_metro.time = 1/ui_refresh_rate;
	ui_refresh_metro.start_();
};

// section: ui initialization

var
init_ui =
{
	init_arc.value();
	init_midi.value();
	calculate_ui_bounds.value();
	init_ui_refresh_metro.value();
};

// section: engine initialization delay

var
start_after_1_second_delay = // TODO: global in lua
{
	init_engine_init_delay_metro.value();
};

var
init_engine_init_delay_metro = // TODO: global in lua
{
	var engine_init_delay_metro = ~metro.init_();
	engine_init_delay_metro[\event] = {
		engine_ready = true;

		ui_dirty = true;

		engine_init_delay_metro.stop_();
	};
	engine_init_delay_metro.time = 1;
	engine_init_delay_metro.start_();
};


var
init_r_modules =
{
	create_modules.value();
	set_static_module_params.value();
	connect_modules.value();
	create_macros.value();
};

var
create_modules =
{
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

var
set_static_module_params =
{
	r_engine.poly_set_("OscA.FM", 1, polyphony);
	r_engine.poly_set_("OscB.FM", 1, polyphony);
	r_engine.poly_set_("Filter.AudioLevel", 1, polyphony);
};

var
connect_modules =
{
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

var
create_macros =
{
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

// section: params

var
get_filter_frequency_param_spec =
{
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

var
get_filter_resonance_param_spec =
{
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

var
get_osc_a_range_param_spec =
{
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

var
get_osc_b_range_param_spec =
{
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

var
get_osc_a_pulsewidth_param_spec =
{
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

var
get_osc_b_pulsewidth_param_spec =
{
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

var
get_osc_detune_param_spec =
{
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

var
get_lfo_frequency_param_spec =
{
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

var
get_lfo_to_osc_pwm_param_spec =
{
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

var
get_env_to_filter_fm_param_spec =
{
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

var
get_env_attack_param_spec =
{
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

var
get_env_decay_param_spec =
{
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

var
get_env_sustain_param_spec =
{
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

var
get_env_release_param_spec =
{
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

var
get_main_level_param_spec =
{
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

var
get_param_specs =
{
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

var
add_params =
{ |param_specs|
	param_specs.do { |param_spec|
		~params.add_((
			type: param_spec[\type],
			id: param_spec[\id],
			name: param_spec[\narrow_name] ? param_spec[\name],
			controlspec: param_spec[\controlspec],
			formatter: param_spec[\narrow_formatter] ? param_spec[\formatter],
			action: { |value|
				param_spec[\action].value(value);
				ui_dirty = true;
			}
		));
	};
/*
	TODO: no polls
	~params.add_((
		type: "option",
		id: "visual_feedback",
		name: "Visual Feedback",
		options: ["enabled", "disabled"],
		action: { |value|
			if (value == 1) {
				start_polls.value();
			} {
				stop_polls.value();
			};
			ui_dirty = true;
		}
	));
*/
};

// section: polls

// TODO: no polls here

// section: settings

var
load_settings =
{
	var filename = ~norns.state.data ++ settings_file;
	var page;
	if (File.exists(filename.standardizePath)) {
		File.use(filename.standardizePath, "r") { |file|
			page = file.getLine().asInteger;
		};
	};
	// TODO: zero based
	if (page.notNil) {
		if (page < pages.size) {
			current_page = page;
		} {
			current_page = 0;
		};
	} {
		current_page = 0;
	};
};

var
save_settings =
{
	var filename = ~norns.state.data ++ settings_file;
	File.use(filename.standardizePath, "w+") { |file|
		file.write(get_active_page.value().asString ++ "\n"); // TODO: zero based
	};
};

// section: screen draw primitives

var
draw_text =
{ |left, bottom, level, text|
	~screen.move_(left, bottom);
	~screen.level_(level);
	~screen.text_(text);
};

var
fill_rect =
{ |left, top, width, height, level|
	~screen.level_(level);
	~screen.rect_(left, top, width, height);
	~screen.fill_();
};

// section: enc1 screen draw

var
get_enc1_value =
{
	round(~params.get_raw_("main_level")*100).asInteger; // TODO: use formatter instead of raw?
};

var
draw_enc1_param =
{ |value_level|
	draw_text.value(enc1_label_left, enc1_label_bottom, lo_level, enc1_label);
	draw_text.value(enc1_value_left, enc1_value_bottom, value_level, get_enc1_value.value().asString);
};

// section: event indicator screen draw

var
draw_event_indicator =
{
	fill_rect.value(event_indicator_left, event_indicator_top, event_indicator_width, event_indicator_height, lo_level);
};

// section: enc2 and enc3 screen draw

var
draw_param_widget =
{ |left, top, width, raw_value, visual_values, widget_value_in_focus|
	var num_pixels = width-1;
	var widget_value_in_focus_level = 2;
	var led_array = map_param_state_to_led_array.value(num_pixels, raw_value, hi_level, visual_values, round(hi_level/4)); // TODO: establish screen_level_spec, and use instead of hi_level

	if (widget_value_in_focus.notNil) {
		var widget_pixel_in_focus;
		widget_pixel_in_focus = value_to_pixel.value(widget_value_in_focus, num_pixels);
		if (widget_pixel_in_focus != value_to_pixel.value(raw_value, num_pixels)) {
			led_array[widget_pixel_in_focus] = widget_value_in_focus_level;
		};
	};

	width.do { |index|
		var x_pos = left + index;
		var widget_background_level = 1;
		var level = (led_array[index] ? widget_background_level) max: (led_array[index-1] ? widget_background_level);
		fill_rect.value(x_pos, top, 1, 2, level);
	};
};

// section: page indicator screen draw

var
draw_page_indicator =
{ |page, level| // TODO: page is zero based
	var div = page_indicator_width/pages.size;
	var width = round(div);
	fill_rect.value(round(page*div), page_indicator_top, width, page_indicator_height, level);
};

// section: key1 and key2 screen draw

var
draw_key_widget =
{ |x_pos, y_pos, text, key_held, focussed|
	var level;
	if (key_held and: fine.not) {
		level = hi_level;
	} {
		if (focussed) {
			level = mid_level;
		} {
			level = lo_level;
		};
	};
	draw_text.value(x_pos, y_pos, level, text);
};

var
draw_key2_widget =
{
	draw_key_widget.value(key2_left, key2_bottom, key2_label, prev_key_held, focus == 'key2');
};

var
draw_in_between_key2_key3_widget =
{
	~screen.move_(key2_left+42, key2_bottom);
	~screen.level_(hi_level);
	~screen.text_("FN");
};

var
draw_key3_widget =
{
	draw_key_widget.value(key3_left, key3_bottom, key3_label, next_key_held, focus == 'key3');
};

// section: mouse related things
// TODO: what to do with focus without mouse?

var param_in_focus;
var page_in_focus;
var param_widget_value_in_focus;
var mouse_move_pos; // TODO: variables
var mouse_down_pos; // TODO: variables

var
get_enc1_value_width =
{
	~screen.font_size_(16);
	round(~screen.text_extents_(round(~params.get_raw_("main_level")*100).asInteger.asString)).asInteger; // TODO: use formatter instead of raw?
};

var
within_enc1_value_bounds =
{ |pos|
	var bounds = Rect(enc1_value_left, enc1_value_top, get_enc1_value_width.value(), enc1_value_bottom - enc1_value_top);
	bounds.contains(pos);
};

var
get_enc2_value_width =
{
	var param_id = get_id_for_displayed_param.value(1);
	if (param_id != nil) {
		var value = ~params.string_(param_id);
		var value_extents = ~screen.text_extents_(value.asString);
		round(value_extents).asInteger; // TODO: probably round in text_extents_ ??
	} {
		0
	};
};

var
get_enc2_label_width =
{
	var param_id = get_id_for_displayed_param.value(1);
	if (param_id != nil) {
		param_name_widths[param_id];
	} {
		0 // TODO: even needed?
	};
};

var
get_enc2_widget_width =
{
	get_enc2_label_width.value() - 2;
};

var
within_enc2_value_bounds =
{ |current_page, pos|
	var bounds = Rect(enc2_value_left-get_page_transition_offset_in_pixels.value(), enc2_value_top, get_enc2_value_width.value(), enc2_value_bottom - enc2_value_top);
	bounds.contains(pos);
};

var
within_enc2_widget_bounds =
{ |current_page, pos|
	var bounds = Rect(enc2_widget_left-get_page_transition_offset_in_pixels.value(), enc2_widget_top, get_enc2_widget_width.value(), enc2_widget_bottom - enc2_widget_top);
	bounds.contains(pos);
};

var
get_enc3_value_width =
{
	var param_id = get_id_for_displayed_param.value(2);
	if (param_id != nil) {
		var value = ~params.string_(param_id);
		var value_extents = ~screen.text_extents_(value.asString);
		round(value_extents).asInteger; // TODO: probably round in text_extents_ ??
	} {
		0
	};
};

var
get_enc3_label_width =
{
	var param_id = get_id_for_displayed_param.value(2);
	if (param_id != nil) {
		param_name_widths[param_id];
	} {
		0
	};
};

var
get_enc3_widget_width =
{
	get_enc3_label_width.value() - 2;
};

var
within_enc3_value_bounds =
{ |current_page, pos|
	var bounds = Rect(enc3_value_left-get_page_transition_offset_in_pixels.value(), enc3_value_top, get_enc3_value_width.value(), enc3_value_bottom - enc3_value_top);
	bounds.contains(pos);
};

var
within_enc3_widget_bounds =
{ |current_page, pos|
	var bounds = Rect(enc3_widget_left-get_page_transition_offset_in_pixels.value(), enc3_widget_top, get_enc3_widget_width.value(), enc3_widget_bottom - enc3_widget_top);
	bounds.contains(pos);
};

var
within_page_indicator_bounds =
{ |pos|
	var bounds = Rect(page_indicator_left, page_indicator_top, page_indicator_width, page_indicator_height);
	bounds.contains(pos);
};

var
get_key2_label_width =
{
	~screen.text_extents_(key2_label);
};

var
within_key2_bounds =
{ |pos|
	var bounds = Rect(key2_left, key2_bottom-12, get_key2_label_width.value(), 10);
	bounds.contains(pos);
};

var
get_key3_label_width =
{
	~screen.text_extents_(key3_label);
};

var
within_key3_bounds =
{ |pos|
	var bounds = Rect(key3_left, key3_top, get_key3_label_width.value(), 10);
	bounds.contains(pos);
};

var
update_focus =
{ |pos|
	case
	{ within_enc1_value_bounds.value(pos) } {
		focus = 'enc1_value';
		param_in_focus = 'main_level';
	}
	{ within_enc2_value_bounds.value(current_page, pos) } {
		focus = 'enc2_value';
		param_in_focus = get_id_for_displayed_param.value(1);
	}
	{ within_enc2_widget_bounds.value(current_page, pos) } {
		focus = 'enc2_widget';
		param_widget_value_in_focus = pixel_to_value.value(pos.x - enc2_widget_left - 1, get_enc2_widget_width.value() - 1);
		param_in_focus = get_id_for_displayed_param.value(1);
	}
	{ within_enc3_value_bounds.value(current_page, pos) } {
		focus = 'enc3_value';
		param_in_focus = get_id_for_displayed_param.value(2);
	}
	{ within_enc3_widget_bounds.value(current_page, pos) } {
		focus = 'enc3_widget';
		param_widget_value_in_focus = pixel_to_value.value(pos.x - enc3_widget_left - 1, get_enc3_widget_width.value() - 1);
		param_in_focus = get_id_for_displayed_param.value(2);
	}
	{ within_page_indicator_bounds.value(pos) } {
		var div = page_indicator_width/pages.size;
		focus = 'page_indicator';
		page_in_focus = floor((pos.x - page_indicator_left) / div); // TODO: zero based
	}
	{ within_key2_bounds.value(pos) } {
		focus = 'key2';
	}
	{ within_key3_bounds.value(pos) } {
		focus = 'key3';
	}
	{ true } {
		focus = nil;
	};
};

var
mouse_over =
{ |x_pos, y_pos|
	var mouse_over_pos = x_pos@y_pos;
	update_focus.value(mouse_over_pos); // TODO: only if mouse is not pressed(?)
};

var
mouse_down =
{ |x_pos, y_pos|
	mouse_down_pos = x_pos@y_pos;

	case
	{ focus == 'enc2_widget' } {
		var param_id = get_id_for_displayed_param.value(1);
		if (param_id != nil) {
			~params.set_raw_(param_id, param_widget_value_in_focus);
		};
	}
	{ focus == 'enc3_widget' } {
		var param_id = get_id_for_displayed_param.value(2);
		if (param_id != nil) {
			~params.set_raw_(param_id, param_widget_value_in_focus);
		};
	}
	{ focus == 'page_indicator' } {
		transition_to_page.value(page_in_focus);
	}
	{ focus == 'key2' } {
		~key.value(2, 1);
	}
	{ focus == 'key3' } {
		~key.value(3, 1);
	}
	;

	active = focus;
};

var
mouse_move =
{ |x_pos, y_pos|
	var mouse_move_delta;

	var prev_mouse_move_pos = mouse_move_pos;
	mouse_move_pos = x_pos@y_pos;
	mouse_move_delta = (prev_mouse_move_pos ? mouse_down_pos) - (x_pos@y_pos);
	case
	{ (active == 'enc1_value') || (active == 'enc2_value') || (active == 'enc3_value') } {
		if (mouse_move_delta.y != 0) {
			var divisor;
			if (fine) {
				divisor = 5;
			} {
				divisor = 1;
			};
			~params.delta_(param_in_focus, mouse_move_delta.y/divisor);
		};
	}
	{ active == 'enc2_widget' } {
		if (mouse_move_delta.x != 0) {
			param_widget_value_in_focus = pixel_to_value.value(mouse_move_pos.x - enc2_widget_left - 1, get_enc2_widget_width.value() - 1);
			~params.set_raw_(param_in_focus, param_widget_value_in_focus);
		};
	}
	{ active == 'enc3_widget' } {
		if (mouse_move_delta.x != 0) {
			param_widget_value_in_focus = pixel_to_value.value(mouse_move_pos.x - enc3_widget_left - 1, get_enc3_widget_width.value() - 1);
			~params.set_raw_(param_in_focus, param_widget_value_in_focus);
		};
	};
};

var
mouse_wheel =
{ |x_delta, y_delta|
	if (y_delta != 0) {
		case
		{focus == 'enc1_value'} {
			~enc.value(1, y_delta*(-1));
		}
		{focus == 'enc2_value'} {
			~enc.value(2, y_delta*(-1));
		}
		{focus == 'enc3_value'} {
			~enc.value(3, y_delta*(-1));
		};
	};
};

var
mouse_up =
{ |x_pos, y_pos|
	mouse_move_pos = nil;

	case
	{ active == 'key2' } {
		~key.value(2, 0);
	}
	{ active == 'key3' } {
		~key.value(3, 0);
	};

	active = nil;

	update_focus.value(x_pos@y_pos);
};

var
mouse_leave =
{
	focus = nil;
};

// section: voice allocation

var voice = include_relative.value("lib" +/+ "voice.scd"); // TODO: MOVE UP ??
var voice_new = voice[\voice_new];

var voice_allocator; // TODO: MOVE UP

var polyphony = 5; // TODO: MOVE UP
var note_downs = ();
var note_slots = ();

var note_on = { |note, velocity|
	if (note_slots[note].isNil) {
		var slot = voice_allocator.get__();
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
		voice_allocator.release__(slot);
		note_downs[slot[\id]] = nil;
	};
};

// section: globals

~
engine.name = 'R'
;

~
init =
{
	var visual_buf_size = (round(ui_refresh_rate*visual_trail_duration) max: 1);
	visual_values_dict = (); // create_visual_values_bufs.value(visual_buf_size); TODO: no polls
	voice_allocator = voice_new.value(polyphony);
	init_r_modules.value();
	add_params.value(get_param_specs.value());
	load_settings.value();
	// polls = create_polls.value(get_poll_specs.value(visual_values_dict)); TODO: no polls
	init_ui.value();
	~params.read_();
	//~params.set__("visual_feedback", 2); TODO
	start_after_1_second_delay.value();
};

~
cleanup =
{
	save_settings.value();
	~params.write_();
};

~
redraw =
{
	var page_indicator_level;

	~screen.clear_();
	~screen.font_size_(16);

	if (focus == 'enc1_value') {
		draw_enc1_param.value(mid_level);
	} {
		draw_enc1_param.value(hi_level);
	};

	if (event_indicator_should_be_shown.value()) {
		draw_event_indicator.value();
	};

	get_params_to_draw.value().do { |param_to_draw|
		var param_id = pages[param_to_draw.page_index][param_to_draw.param_index-1]; // 1 to zero based for param_index

		if (param_id != nil) {
			var label_width = param_name_widths[param_id];
			var widget_width = label_width - 2;

			var label = ~params.get_name_(param_id);
			var formatted_value = ~params.string_(param_id);
			var value_level;
			var raw_value = ~params.get_raw_(param_id);
			var visual_values;

			var widget_value_in_focus;

			if (param_to_draw.indicate_focussed_widget) {
				widget_value_in_focus = param_widget_value_in_focus;
			};

			if (param_to_draw.indicate_focussed_value) {
				value_level = mid_level;
			} {
				value_level = hi_level;
			};

			// if (~params.get_("visual_feedback") == 1) { TODO: no polls
			{
				var visual_values_for_param = visual_values_dict[param_id];
				if (visual_values_for_param.notNil) {
					visual_values = visual_values_for_param[\content];
				};
			}.value;
			// }; TODO: no polls

			draw_text.value(
				param_to_draw.label_left,
				param_to_draw.label_bottom,
				lo_level,
				label
			);

			draw_text.value(
				param_to_draw.value_left,
				param_to_draw.value_bottom,
				value_level,
				formatted_value
			);

			draw_param_widget.value(
				param_to_draw.widget_left,
				param_to_draw.widget_top,
				widget_width,
				raw_value,
				visual_values,
				widget_value_in_focus
			);
		};
	};

	page_indicator_level = lo_level;

	if (focus == 'page_indicator') {
		case
		{page_in_focus == current_page} {
			page_indicator_level = mid_level;
		}
		{page_in_focus != current_page} {
			draw_page_indicator.value(page_in_focus, 2);
		};
	};

	draw_page_indicator.value(current_page, page_indicator_level);

	draw_key2_widget.value();

	if (fine) {
		draw_in_between_key2_key3_widget.value();
	};

	draw_key3_widget.value();

	~screen.update_();
};

~
enc =
{ |n, delta|
	var divisor;
	if (fine) {
		divisor = 5;
	} {
		divisor = 1;
	};
	if (n == 1) {
		~params.delta_("main_level", delta/divisor);
	} {
		var param_index = n-1;
		var param_id = get_id_for_displayed_param.value(param_index);
		if (param_id != nil) {
			~params.delta_(get_id_for_displayed_param.value(param_index), delta/divisor);
		};
	};
	ui_dirty = true;
};

~
key =
{ |index, state|
	case
	{index == 2} {
		if (state == 1) {
			transition_to_prev_page.value();
			prev_key_held = true;
		} {
			prev_key_held = false;
		};
	}
	{index == 3} {
		if (state == 1) {
			transition_to_next_page.value();
			next_key_held = true;
		} {
			next_key_held = false
		};
	}
	;

	fine = (prev_key_held and: next_key_held);

	ui_dirty = true;
};

~
mouse =
{ |what ... args|
	case
	{ what == "leave" } {
		mouse_leave.value();
	}
	{ what == "over" } {
		var x_pos = args[0], y_pos = args[1];
		mouse_over.value(x_pos, y_pos);
	}
	{ what == "down" } {
		var x_pos = args[0], y_pos = args[1];
		mouse_down.value(x_pos, y_pos);
	}
	{ what == "move" } {
		var x_pos = args[0], y_pos = args[1];
		mouse_move.value(x_pos, y_pos);
	}
	{ what == "up" } {
		var x_pos = args[0], y_pos = args[1];
		mouse_up.value(x_pos, y_pos);
	}
	{ what == "wheel" } {
		var x_delta = args[0], y_delta = args[1];
		mouse_wheel.value(x_delta, y_delta);
	};

	ui_dirty = true;
};

~
kbdkey =
{ |keycode, z|
	case
	{keycode == 37} {
		if (z == 1) {
			transition_to_prev_page.value();
			prev_key_held = true;
		} {
			prev_key_held = false;
		};
	}
	{keycode == 39} {
		if (z == 1) {
			transition_to_next_page.value();
			next_key_held = true;
		} {
			next_key_held = false
		};
	};
};

};
)
