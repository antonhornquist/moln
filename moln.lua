-- scriptname: moln
-- v1.2.1 @jah

local R = require 'r/lib/r'
local r_engine = R.engine
local r_specs = R.specs
local r_util = R.util

local ControlSpec = require 'controlspec'
local Formatters = require 'formatters'
local Voice = require 'voice'

local grid_led_x_spec = ControlSpec.new(1, 16, ControlSpec.WARP_LIN, 1, 0, "")
local grid_led_y_spec = ControlSpec.new(1, 16, ControlSpec.WARP_LIN, 1, 0, "")
local grid_led_l_spec = ControlSpec.new(0, 15, ControlSpec.WARP_LIN, 1, 0, "")
local arc_led_x_spec = ControlSpec.new(1, 64, ControlSpec.WARP_LIN, 1, 0, "")
local arc_led_l_spec = ControlSpec.new(0, 15, ControlSpec.WARP_LIN, 1, 0, "")

local engine_ready = false
local trigging = false
local fine = false
local lastkeynote

local POLYPHONY = 5
local note_downs = {}
local note_slots = {}

local grid_width

local ui_dirty = false

local refresh_rate = 60

local event_flash_duration = 0.15 
local show_event_indicator = false
local event_flash_frame_counter = nil

local
create_modules =
function()
  r_engine.poly_new("FreqGate", "FreqGate", POLYPHONY)
  r_engine.poly_new("LFO", "SineLFO", POLYPHONY)
  r_engine.poly_new("Env", "ADSREnv", POLYPHONY)
  r_engine.poly_new("OscA", "PulseOsc", POLYPHONY)
  r_engine.poly_new("OscB", "PulseOsc", POLYPHONY)
  r_engine.poly_new("Filter", "LPFilter", POLYPHONY)
  r_engine.poly_new("Amp", "Amp", POLYPHONY)

  engine.new("OutputGain", "SGain")
  engine.new("SoundOut", "SoundOut")
end

local
set_static_module_params =
function ()
  r_engine.poly_set("OscA.FM", 1, POLYPHONY)
  r_engine.poly_set("OscB.FM", 1, POLYPHONY)
  r_engine.poly_set("Filter.AudioLevel", 1, POLYPHONY)
end

local
connect_modules =
function()
  r_engine.poly_connect("FreqGate/Frequency", "OscA*FM", POLYPHONY)
  r_engine.poly_connect("FreqGate/Frequency", "OscB*FM", POLYPHONY)
  r_engine.poly_connect("FreqGate/Gate", "Env*Gate", POLYPHONY)
  r_engine.poly_connect("LFO/Out", "OscA*PWM", POLYPHONY)
  r_engine.poly_connect("LFO/Out", "OscB*PWM", POLYPHONY)
  r_engine.poly_connect("Env/Out", "Amp*Lin", POLYPHONY)
  r_engine.poly_connect("Env/Out", "Filter*FM", POLYPHONY)
  r_engine.poly_connect("OscA/Out", "Filter*In", POLYPHONY)
  r_engine.poly_connect("OscB/Out", "Filter*In", POLYPHONY)
  r_engine.poly_connect("Filter/Out", "Amp*In", POLYPHONY)

  for voicenum=1, POLYPHONY do
    engine.connect("Amp"..voicenum.."/Out", "OutputGain*Left")
    engine.connect("Amp"..voicenum.."/Out", "OutputGain*Right")
  end

  engine.connect("OutputGain/Left", "SoundOut*Left")
  engine.connect("OutputGain/Right", "SoundOut*Right")
end

local
create_macros =
function ()
  engine.newmacro("osc_a_range", r_util.poly_expand("OscA.Range", POLYPHONY))
  engine.newmacro("osc_a_pulsewidth", r_util.poly_expand("OscA.PulseWidth", POLYPHONY))
  engine.newmacro("osc_b_range", r_util.poly_expand("OscB.Range", POLYPHONY))
  engine.newmacro("osc_b_pulsewidth", r_util.poly_expand("OscB.PulseWidth", POLYPHONY))
  engine.newmacro("osc_a_detune", r_util.poly_expand("OscA.Tune", POLYPHONY))
  engine.newmacro("osc_b_detune", r_util.poly_expand("OscB.Tune", POLYPHONY))
  engine.newmacro("lfo_frequency", r_util.poly_expand("LFO.Frequency", POLYPHONY))
  engine.newmacro("osc_a_pwm", r_util.poly_expand("OscA.PWM", POLYPHONY))
  engine.newmacro("osc_b_pwm", r_util.poly_expand("OscB.PWM", POLYPHONY))
  engine.newmacro("filter_frequency", r_util.poly_expand("Filter.Frequency", POLYPHONY))
  engine.newmacro("filter_resonance", r_util.poly_expand("Filter.Resonance", POLYPHONY))
  engine.newmacro("env_to_filter_fm", r_util.poly_expand("Filter.FM", POLYPHONY))
  engine.newmacro("env_attack", r_util.poly_expand("Env.Attack", POLYPHONY))
  engine.newmacro("env_decay", r_util.poly_expand("Env.Decay", POLYPHONY))
  engine.newmacro("env_sustain", r_util.poly_expand("Env.Sustain", POLYPHONY))
  engine.newmacro("env_release", r_util.poly_expand("Env.Release", POLYPHONY))
end

local
init_osc_a_range_param =
function()
  params:add {
    type="control",
    id="osc_a_range",
    name="Osc A Range",
    controlspec=r_specs.PulseOsc.Range,
    formatter=Formatters.round(1),
    action=function (value)
      engine.macroset("osc_a_range", value)
    end
  }
end

local
init_osc_a_pulsewidth_param =
function ()
  local spec = r_specs.PulseOsc.PulseWidth:copy()
  spec.default = 0.88

  params:add {
    type="control",
    id="osc_a_pulsewidth",
    name="Osc A PulseWidth",
    controlspec=spec,
    formatter=Formatters.percentage,
    action=function (value)
      engine.macroset("osc_a_pulsewidth", value)
    end
  }
end

local
init_osc_b_range_param =
function()
  params:add {
    type="control",
    id="osc_b_range",
    name="Osc B Range",
    controlspec=r_specs.PulseOsc.Range,
    formatter=Formatters.round(1),
    action=function (value)
      engine.macroset("osc_b_range", value)
    end
  }
end

local
init_osc_b_pulsewidth_param =
function()
  local spec = r_specs.PulseOsc.PulseWidth:copy()
  spec.default = 0.61

  params:add {
    type="control",
    id="osc_b_pulsewidth",
    name="Osc B PulseWidth",
    controlspec=spec,
    formatter=Formatters.percentage,
    action=function (value)
      engine.macroset("osc_b_pulsewidth", value)
    end
  }
end

local
init_osc_detune_param =
function()
  local spec = ControlSpec.UNIPOLAR:copy()
  spec.default = 0.36

  params:add {
    type="control",
    id="osc_detune",
    name="Detune",
    controlspec=spec,
    formatter=Formatters.percentage,
    action=function (value)
      engine.macroset("osc_a_detune", -value*10)
      engine.macroset("osc_b_detune", value*10)
    end
  }
end

local
init_lfo_frequency_param =
function()
  local spec = r_specs.MultiLFO.Frequency:copy()
  spec.default = 0.125

  params:add {
    type="control",
    id="lfo_frequency",
    name="PWM Rate",
    controlspec=spec,
    formatter=Formatters.round(0.001),
    action=function (value)
      engine.macroset("lfo_frequency", value)
    end
  }
end

local
init_lfo_to_osc_pwm_param =
function()
  local spec = ControlSpec.UNIPOLAR:copy()
  spec.default = 0.46

  params:add {
    type="control",
    id="lfo_to_osc_pwm",
    name="PWM Depth",
    controlspec=spec,
    formatter=Formatters.percentage,
    action=function (value)
      engine.macroset("osc_a_pwm", value*0.76)
      engine.macroset("osc_b_pwm", value*0.56)
    end
  }
end

local
init_filter_frequency_param =
function()
  local spec = r_specs.MMFilter.Frequency:copy()
  spec.maxval = 8000
  spec.minval = 10
  spec.default = 500

  params:add {
    type="control",
    id="filter_frequency",
    name="Filter Frequency",
    controlspec=spec,
    action=function (value)
      engine.macroset("filter_frequency", value)
      ui_dirty = true
    end
  }
end

local
init_filter_resonance_param =
function()
  local spec = r_specs.MMFilter.Resonance:copy()
  spec.default = 0.2

  params:add {
    type="control",
    id="filter_resonance",
    name="Filter Resonance",
    controlspec=spec,
    formatter=Formatters.percentage,
    action=function (value)
      engine.macroset("filter_resonance", value)
      ui_dirty = true
    end
  }
end

local
init_env_to_filter_fm_param =
function()
  local spec = r_specs.MMFilter.FM
  spec.default = 0.35

  params:add {
    type="control",
    id="env_to_filter_fm",
    name="Env > Filter Frequency",
    controlspec=spec,
    formatter=Formatters.percentage,
    action=function (value)
      engine.macroset("env_to_filter_fm", value)
    end
  }
end

local
init_env_attack_param =
function()
  local spec = r_specs.ADSREnv.Attack:copy()
  spec.default = 1

  params:add {
    type="control",
    id="env_attack",
    name="Env Attack",
    controlspec=spec,
    action=function (value)
      engine.macroset("env_attack", value)
    end
  }
end

local
init_env_decay_param =
function()
  local spec = r_specs.ADSREnv.Decay:copy()
  spec.default = 200

  params:add {
    type="control",
    id="env_decay",
    name="Env Decay",
    controlspec=spec,
    action=function (value)
      engine.macroset("env_decay", value)
    end
  }
end

local
init_env_sustain_param =
function()
  local spec = r_specs.ADSREnv.Sustain:copy()
  spec.default = 0.5

  params:add {
    type="control",
    id="env_sustain",
    name="Env Sustain",
    controlspec=spec,
    formatter=Formatters.percentage,
    action=function (value)
      engine.macroset("env_sustain", value)
    end
  }
end

local
init_env_release_param =
function()
  local spec = r_specs.ADSREnv.Release:copy()
  spec.default = 500

  params:add {
    type="control",
    id="env_release",
    name="Env Release",
    controlspec=spec,
    action=function (value)
      engine.macroset("env_release", value)
    end
  }
end

local
init_main_output_level_param =
function()
  local spec = r_specs.SGain.Gain:copy()
  spec.default = -10

  params:add {
    type="control",
    id="main_output_level",
    name="Output Level",
    controlspec=spec,
    formatter=Formatters.round(0.1),
    action=function (value)
      engine.set("OutputGain.Gain", value)
    end
  }
end

local
init_params =
function()
  init_osc_a_range_param()
  init_osc_a_pulsewidth_param()
  init_osc_b_range_param()
  init_osc_b_pulsewidth_param()
  init_osc_detune_param()
  init_lfo_frequency_param()
  init_lfo_to_osc_pwm_param()
  init_filter_frequency_param()
  init_filter_resonance_param()
  init_env_to_filter_fm_param()
  init_env_attack_param()
  init_env_decay_param()
  init_env_sustain_param()
  init_env_release_param()
  init_main_output_level_param()
end

local
release_voice =
function(voicenum)
  engine.bulkset("FreqGate"..voicenum..".Gate 0")
end

local
to_hz =
function(note)
  local exp = (note - 21) / 12
  return 27.5 * 2^exp
end

local
trig_voice =
function(voicenum, note)
  engine.bulkset("FreqGate"..voicenum..".Gate 1 FreqGate"..voicenum..".Frequency "..to_hz(note))
end

local
note_on =
function(note, velocity)
  if not note_slots[note] then
    local slot = voice_allocator:get()
    local voicenum = slot.id
    trig_voice(voicenum, note)
    slot.on_release = function()
      release_voice(voicenum)
      note_slots[note] = nil
    end
    note_slots[note] = slot
    note_downs[voicenum] = note
    ui_dirty = true
  end
end

local
note_off =
function(note)
  local slot = note_slots[note]
  if slot then
    voice_allocator:release(slot)
    note_downs[slot.id] = nil
    ui_dirty = true
  end
end

local
gridkey_to_note =
function(x, y, grid_width)
  if grid_width == 16 then
    return x * 8 + y
  else
    return (4 + x) * 8 + y
  end
end

local
note_to_gridkey =
function(note, grid_width)
  if grid_width == 16 then
    return math.floor((note - 1) / 8), ((note - 1) % 8) + 1
  else
    return math.floor((note - 1) / 8) - 4, ((note - 1) % 8) + 1
  end
end

local
init_engine_init_delay_metro =
function()
  local engine_init_delay_metro = metro.init()
  engine_init_delay_metro.event = function()
    engine_ready = true
    ui_dirty = true
    engine_init_delay_metro:stop()
  end
  engine_init_delay_metro.time = 1
  engine_init_delay_metro:start()
end

local
init_ui_refresh_metro =
function()
  local ui_refresh_metro = metro.init()
  ui_refresh_metro.event = refresh_ui
  ui_refresh_metro.time = 1/refresh_rate
  ui_refresh_metro:start()
end

local
flash_event =
function()
  event_flash_frame_counter = event_flash_duration * refresh_rate
end
  
local
update_event_indicator =
function()
  if event_flash_frame_counter then
    event_flash_frame_counter = event_flash_frame_counter - 1
    if event_flash_frame_counter == 0 then
      event_flash_frame_counter = nil
      show_event_indicator = false
      ui_dirty = true
    else
      if not show_event_indicator then
        show_event_indicator = true
        ui_dirty = true
      end
    end
  end
end

local
update_grid_width =
function()
  if grid_device.device then
    if grid_width ~= grid_device.cols then
      grid_width = grid_device.cols
    end
  end
end

local
refresh_arc =
function()
  arc_device:all(0)
  arc_device:led(1, arc_led_x_spec:map(params:get_raw("filter_frequency")), arc_led_l_spec.maxval)
  arc_device:led(2, arc_led_x_spec:map(params:get_raw("filter_resonance")), arc_led_l_spec.maxval)
  arc_device:refresh()
end

local
refresh_grid =
function()
  grid_device:all(0)
  for voicenum=1,POLYPHONY do
    local note = note_downs[voicenum]
    if note then
      local x, y = note_to_gridkey(note, grid_width)
      grid_device:led(grid_led_x_spec:constrain(x), grid_led_y_spec:constrain(y), grid_led_l_spec.maxval)
    end
  end
  grid_device:refresh()
end

function refresh_ui()
  update_event_indicator()
  update_grid_width()

  if ui_dirty then
    redraw()
    refresh_arc()
    refresh_grid()
    ui_dirty = false
  end
end

local
init_arc =
function()
  arc_device = arc.connect()
  arc_device.delta = function(n, delta)
    local delta_scaled

    flash_event()

    if fine then
      delta_scaled = delta/5
    else
      delta_scaled = delta
    end
    if n == 1 then
      local val = params:get_raw("filter_frequency")
      params:set_raw("filter_frequency", val+delta_scaled/500)
    elseif n == 2 then
      local val = params:get_raw("filter_resonance")
      params:set_raw("filter_resonance", val+delta_scaled/500)
    end

    ui_dirty = true
  end
end

local
init_grid =
function()
  grid_device = grid.connect()
  grid_device.key = function(x, y, state)
    flash_event()
    if engine_ready then
      local note = gridkey_to_note(x, y, grid_width)
      if state == 1 then
        note_on(note, 5)
      else
        note_off(note)
      end
      ui_dirty = true
    end
  end
end

local
init_midi =
function()
  midi_device = midi.connect()
  midi_device.event = function(data)
    flash_event()
    if engine_ready then
      if #data == 0 then return end
      local msg = midi.to_msg(data)
      if msg.type == "note_off" then
        note_off(msg.note)
      elseif msg.type == "note_on" then
        note_on(msg.note, msg.vel / 127)
      end
      ui_dirty = true
    end
  end
end

local
init_ui =
function()
  init_arc()
  init_grid()
  init_midi()
  init_ui_refresh_metro()
  init_engine_init_delay_metro()
end

engine.name = 'R'

init =
function()
  voice_allocator = Voice.new(POLYPHONY)

  create_modules()
  set_static_module_params()
  connect_modules()
  create_macros()

  init_params()
  init_ui()

  params:read()
  params:bang()
end

cleanup =
function()
  params:write()
end

redraw =
function()
  local hi_level = 15
  local lo_level = 4

  local enc1_x = 1
  local enc1_y = 12

  local enc2_x = 10
  local enc2_y = 32

  local enc3_x = enc2_x+65
  local enc3_y = enc2_y

  local key2_x = 1
  local key2_y = 63

  local key3_x = key2_x+65
  local key3_y = key2_y

  local
  redraw_enc1_widget =
  function()
    screen.move(enc1_x, enc1_y)
    screen.level(lo_level)
    screen.text("LEVEL")
    screen.move(enc1_x+45, enc1_y)
    screen.level(hi_level)
    screen.text(util.round(params:get_raw("main_output_level")*100, 1))
  end

  local
  redraw_event_flash_widget =
  function()
    screen.level(lo_level)
    screen.rect(122, enc1_y-7, 5, 5)
    screen.fill()
  end

  local
  redraw_enc2_widget =
  function()
    screen.move(enc2_x, enc2_y)
    screen.level(lo_level)
    screen.text("FREQ")
    screen.move(enc2_x, enc2_y+12)
    screen.level(hi_level)
    
    local freq_str
    local freq = params:get("filter_frequency")
    if util.round(freq, 1) >= 10000 then
      freq_str = util.round(freq/1000, 1) .. "kHz"
    elseif util.round(freq, 1) >= 1000 then
      freq_str = util.round(freq/1000, 0.1) .. "kHz"
    else
      freq_str = util.round(freq, 1) .. "Hz"
    end
    screen.text(freq_str)
  end

  local
  redraw_enc3_widget =
  function()
    screen.move(enc3_x, enc3_y)
    screen.level(lo_level)
    screen.text("RES")
    screen.move(enc3_x, enc3_y+12)
    screen.level(hi_level)
    
    screen.text(util.round(params:get("filter_resonance")*100, 1))
    screen.text("%")
  end
    
  local
  redraw_key2_widget =
  function()
    screen.move(key2_x, key2_y)
    
    if fine then
      screen.level(hi_level)
      screen.text("FINE")
    else
      screen.level(lo_level)
      screen.text("COARSE")
    end
  end

  local
  redraw_key3_widget =
  function()
    screen.move(key3_x, key3_y)
    
    if engine_ready then
      if trigging then
        screen.level(hi_level)
      else
        screen.level(lo_level)
      end
      screen.text("TRIG")
    end
  end

  screen.font_size(16)
  screen.clear()

  redraw_enc1_widget()

  if show_event_indicator then
    redraw_event_flash_widget()
  end

  redraw_enc2_widget()
  redraw_enc3_widget()
  redraw_key2_widget()
  redraw_key3_widget()

  screen.update()
end

enc =
function(n, delta)
  local delta_scaled
  if fine then
    delta_scaled = delta/5
  else
    delta_scaled = delta
  end
  if n == 1 then
    params:delta("main_output_level", delta_scaled)
    ui_dirty = true
  elseif n == 2 then
    params:delta("filter_frequency", delta_scaled)
  elseif n == 3 then
    params:delta("filter_resonance", delta_scaled)
  end
end

key =
function(n, z)
  if n == 2 then
    if z == 1 then
      fine = true
    else
      fine = false
    end
    ui_dirty = true
  elseif n == 3 then
    if engine_ready then
      if z == 1 then
        lastkeynote = math.random(60) + 20
        note_on(lastkeynote, 100)
        trigging = true
        ui_dirty = true
      else
        if lastkeynote then
          note_off(lastkeynote)
          trigging = false
          ui_dirty = true
        end
      end
    end
  end
end
