-- scriptname: moln
-- v1.1.2 @jah

engine.name = 'R'

local R = require 'r/lib/r'
local MusicUtil = require 'musicutil'
local ControlSpec = require 'controlspec'
local Formatters = require 'formatters'
local Voice = require 'voice'

local engine_ready = false
local trigging = false
local fine = false
local lastkeynote

local POLYPHONY = 3
local note_downs = {}
local note_slots = {}

local UI = require 'ui'

local function trig_voice(voicenum, note)
  engine.bulkset("FreqGate"..voicenum..".Gate 1 FreqGate"..voicenum..".Frequency "..MusicUtil.note_num_to_freq(note))
end

local function release_voice(voicenum)
  engine.bulkset("FreqGate"..voicenum..".Gate 0")
end

local function note_on(note, velocity)
  if not note_slots[note] then
    local slot = voice:get()
    local voicenum = slot.id
    trig_voice(voicenum, note)
    slot.on_release = function()
      release_voice(voicenum)
      note_slots[note] = nil
    end
    note_slots[note] = slot
    note_downs[voicenum] = true
    UI.set_screen_dirty()
  end
end

local function note_off(note)
  local slot = note_slots[note]
  if slot then
    voice:release(slot)
    note_downs[slot.id] = false
    UI.set_screen_dirty()
  end
end

local function create_modules()
  R.engine.poly_new("FreqGate", "FreqGate", POLYPHONY)
  R.engine.poly_new("LFO", "SineLFO", POLYPHONY)
  R.engine.poly_new("Env", "ADSREnv", POLYPHONY)
  R.engine.poly_new("OscA", "PulseOsc", POLYPHONY)
  R.engine.poly_new("OscB", "PulseOsc", POLYPHONY)
  R.engine.poly_new("Filter", "LPFilter", POLYPHONY)
  R.engine.poly_new("Amp", "Amp", POLYPHONY)

  engine.new("SoundOut", "SoundOut")
end

local function set_static_module_params()
  R.engine.poly_set("OscA.FM", 1, POLYPHONY)
  R.engine.poly_set("OscB.FM", 1, POLYPHONY)
  R.engine.poly_set("Filter.AudioLevel", 1, POLYPHONY)
end

local function connect_modules()
  R.engine.poly_connect("FreqGate/Frequency", "OscA/FM", POLYPHONY)
  R.engine.poly_connect("FreqGate/Frequency", "OscB/FM", POLYPHONY)
  R.engine.poly_connect("FreqGate/Gate", "Env/Gate", POLYPHONY)
  R.engine.poly_connect("LFO/Out", "OscA/PWM", POLYPHONY)
  R.engine.poly_connect("LFO/Out", "OscB/PWM", POLYPHONY)
  R.engine.poly_connect("Env/Out", "Amp/Lin", POLYPHONY)
  R.engine.poly_connect("Env/Out", "Filter/FM", POLYPHONY)
  R.engine.poly_connect("OscA/Out", "Filter/In", POLYPHONY)
  R.engine.poly_connect("OscB/Out", "Filter/In", POLYPHONY)
  R.engine.poly_connect("Filter/Out", "Amp/In", POLYPHONY)

  for voicenum=1, POLYPHONY do
    engine.connect("Amp"..voicenum.."/Out", "SoundOut/Left")
    engine.connect("Amp"..voicenum.."/Out", "SoundOut/Right")
  end
end

local function create_macros()
  engine.newmacro("osc_a_range", R.util.poly_expand("OscA.Range", POLYPHONY))
  engine.newmacro("osc_a_pulsewidth", R.util.poly_expand("OscA.PulseWidth", POLYPHONY))
  engine.newmacro("osc_b_range", R.util.poly_expand("OscB.Range", POLYPHONY))
  engine.newmacro("osc_b_pulsewidth", R.util.poly_expand("OscB.PulseWidth", POLYPHONY))
  engine.newmacro("osc_a_detune", R.util.poly_expand("OscA.Tune", POLYPHONY))
  engine.newmacro("osc_b_detune", R.util.poly_expand("OscB.Tune", POLYPHONY))
  engine.newmacro("lfo_frequency", R.util.poly_expand("LFO.Frequency", POLYPHONY))
  engine.newmacro("osc_a_pwm", R.util.poly_expand("OscA.PWM", POLYPHONY))
  engine.newmacro("osc_b_pwm", R.util.poly_expand("OscB.PWM", POLYPHONY))
  engine.newmacro("filter_frequency", R.util.poly_expand("Filter.Frequency", POLYPHONY))
  engine.newmacro("filter_resonance", R.util.poly_expand("Filter.Resonance", POLYPHONY))
  engine.newmacro("env_to_filter_fm", R.util.poly_expand("Filter.FM", POLYPHONY))
  engine.newmacro("env_attack", R.util.poly_expand("Env.Attack", POLYPHONY))
  engine.newmacro("env_decay", R.util.poly_expand("Env.Decay", POLYPHONY))
  engine.newmacro("env_sustain", R.util.poly_expand("Env.Sustain", POLYPHONY))
  engine.newmacro("env_release", R.util.poly_expand("Env.Release", POLYPHONY))
end

local function init_params()
  params:add {
    type="control",
    id="osc_a_range",
    name="Osc A Range",
    controlspec=R.specs.PulseOsc.Range,
    formatter=Formatters.round(1),
    action=function (value)
      engine.macroset("osc_a_range", value)
    end
  }

  local osc_a_pulsewidth_spec = R.specs.PulseOsc.PulseWidth:copy()
  osc_a_pulsewidth_spec.default = 0.88

  params:add {
    type="control",
    id="osc_a_pulsewidth",
    name="Osc A PulseWidth",
    controlspec=osc_a_pulsewidth_spec,
    formatter=Formatters.percentage,
    action=function (value)
      engine.macroset("osc_a_pulsewidth", value)
    end
  }

  params:add {
    type="control",
    id="osc_b_range",
    name="Osc B Range",
    controlspec=R.specs.PulseOsc.Range,
    formatter=Formatters.round(1),
    action=function (value)
      engine.macroset("osc_b_range", value)
    end
  }

  local osc_b_pulsewidth_spec = R.specs.PulseOsc.PulseWidth:copy()
  osc_b_pulsewidth_spec.default = 0.61

  params:add {
    type="control",
    id="osc_b_pulsewidth",
    name="Osc B PulseWidth",
    controlspec=osc_b_pulsewidth_spec,
    formatter=Formatters.percentage,
    action=function (value)
      engine.macroset("osc_b_pulsewidth", value)
    end
  }

  local osc_detune_spec = ControlSpec.UNIPOLAR:copy()
  osc_detune_spec.default = 0.36

  params:add {
    type="control",
    id="osc_detune",
    name="Detune",
    controlspec=osc_detune_spec,
    formatter=Formatters.percentage,
    action=function (value)
      engine.macroset("osc_a_detune", -value*10)
      engine.macroset("osc_b_detune", value*10)
    end
  }

  local lfo_frequency_spec = R.specs.MultiLFO.Frequency:copy()
  lfo_frequency_spec.default = 0.125

  params:add {
    type="control",
    id="lfo_frequency",
    name="PWM Rate",
    controlspec=lfo_frequency_spec,
    formatter=Formatters.round(0.001),
    action=function (value)
      engine.macroset("lfo_frequency", value)
    end
  }

  local lfo_to_osc_pwm_spec = ControlSpec.UNIPOLAR:copy()
  lfo_to_osc_pwm_spec.default = 0.46

  params:add {
    type="control",
    id="lfo_to_osc_pwm",
    name="PWM Depth",
    controlspec=lfo_to_osc_pwm_spec,
    formatter=Formatters.percentage,
    action=function (value)
      engine.macroset("osc_a_pwm", value*0.76)
      engine.macroset("osc_b_pwm", value*0.56)
    end
  }

  local filter_frequency_spec = R.specs.MMFilter.Frequency:copy()
  filter_frequency_spec.maxval = 8000
  filter_frequency_spec.minval = 10
  filter_frequency_spec.default = 500

  params:add {
    type="control",
    id="filter_frequency",
    name="Filter Frequency",
    controlspec=filter_frequency_spec,
    action=function (value)
      engine.macroset("filter_frequency", value)
      UI.set_arc_dirty()
      UI.set_screen_dirty()
    end
  }

  local filter_resonance_spec = R.specs.MMFilter.Resonance:copy()
  filter_resonance_spec.default = 0.2

  params:add {
    type="control",
    id="filter_resonance",
    name="Filter Resonance",
    controlspec=filter_resonance_spec,
    formatter=Formatters.percentage,
    action=function (value)
      engine.macroset("filter_resonance", value)
      UI.set_arc_dirty()
      UI.set_screen_dirty()
    end
  }

  local env_to_filter_fm_spec = R.specs.MMFilter.FM
  env_to_filter_fm_spec.default = 0.35

  params:add {
    type="control",
    id="env_to_filter_fm",
    name="Env > Filter Frequency",
    controlspec=env_to_filter_fm_spec,
    formatter=Formatters.percentage,
    action=function (value)
      engine.macroset("env_to_filter_fm", value)
    end
  }

  local env_attack_spec = R.specs.ADSREnv.Attack:copy()
  env_attack_spec.default = 1

  params:add {
    type="control",
    id="env_attack",
    name="Env Attack",
    controlspec=env_attack_spec,
    action=function (value)
      engine.macroset("env_attack", value)
    end
  }

  local env_decay_spec = R.specs.ADSREnv.Decay:copy()
  env_decay_spec.default = 200

  params:add {
    type="control",
    id="env_decay",
    name="Env Decay",
    controlspec=env_decay_spec,
    action=function (value)
      engine.macroset("env_decay", value)
    end
  }

  local env_sustain_spec = R.specs.ADSREnv.Sustain:copy()
  env_sustain_spec.default = 0.5

  params:add {
    type="control",
    id="env_sustain",
    name="Env Sustain",
    controlspec=env_sustain_spec,
    formatter=Formatters.percentage,
    action=function (value)
      engine.macroset("env_sustain", value)
    end
  }

  local env_release_spec = R.specs.ADSREnv.Release:copy()
  env_release_spec.default = 500

  params:add {
    type="control",
    id="env_release",
    name="Env Release",
    controlspec=env_release_spec,
    action=function (value)
      engine.macroset("env_release", value)
    end
  }
  params:read()
  params:bang()
end

local function init_engine_init_delay_metro()
  engine_init_delay_metro = metro.init()
  engine_init_delay_metro.event = function()
    engine_ready = true

    UI.set_arc_dirty() -- TODO: UI.set_all_dirty()
    UI.set_grid_dirty()
    UI.set_screen_dirty()

    engine_init_delay_metro:stop()
  end
  engine_init_delay_metro.time = 1
  engine_init_delay_metro:start()
end

function init()
  voice = Voice.new(POLYPHONY)

  create_modules()
  set_static_module_params()
  connect_modules()
  create_macros()

  init_params()
  
  UI.setup_midi(
    function (data)
      if engine_ready then
        if #data == 0 then return end
        local msg = midi.to_msg(data)
        if msg.type == "note_off" then
          note_off(msg.note)
        elseif msg.type == "note_on" then
          note_on(msg.note, msg.vel / 127)
        end
        UI.flash_event()
        UI.set_screen_dirty()
      end
    end
  )

  UI.setup_grid(
    function(x, y, state)
      if engine_ready then
        local note
        if UI.grid_width == 16 then
          note = x * 8 + y
        else
          note = (4+x) * 8 + y
        end
        if state == 1 then
          note_on(note, 5)
          UI.my_grid:led(x, y, 15) -- TODO: refactor to refresh
        else
          note_off(note)
          UI.my_grid:led(x, y, 0) -- TODO: refactor to refresh
        end
        UI.my_grid:refresh() -- TODO: refactor to refresh
        UI.flash_event()

        UI.set_grid_dirty()
        UI.set_screen_dirty()
      end
    end
  )

  UI.setup_arc(
    function(n, delta)
      local d
      if fine then
        d = delta/5
      else
        d = delta
      end
      if n == 1 then
        local val = params:get_raw("filter_frequency")
        params:set_raw("filter_frequency", val+d/500)
      elseif n == 2 then
        local val = params:get_raw("filter_resonance")
        params:set_raw("filter_resonance", val+d/500)
      end
      UI.flash_event()

      UI.set_arc_dirty()
      UI.set_screen_dirty()
    end,
    function(my_arc)
      my_arc:all(0)
      my_arc:led(1, util.round(params:get_raw("filter_frequency")*64), 15)
      my_arc:led(2, util.round(params:get_raw("filter_resonance")*64), 15)
    end
  )

  UI.init()

  init_engine_init_delay_metro()
end

function cleanup()
  params:write()
end

function redraw()
  screen.font_size(16)
  screen.clear()

  redraw_enc1_widget()

  if UI.show_event_indicator then
    redraw_event_flash_widget()
  end

  redraw_enc2_widget()
  redraw_enc3_widget()
  redraw_key2_widget()
  redraw_key3_widget()

  screen.update()
end

function enc(n, delta)
  local d
  if fine then
    d = delta/5
  else
    d = delta
  end
  if n == 1 then
    mix:delta("output", d)
    UI.set_screen_dirty()
  elseif n == 2 then
    params:delta("filter_frequency", d)
  elseif n == 3 then
    params:delta("filter_resonance", d)
  end
end

function key(n, z)
  if n == 2 then
    if z == 1 then
      fine = true
    else
      fine = false
    end
    UI.set_screen_dirty()
  elseif n == 3 then
    if engine_ready then
      if z == 1 then
        lastkeynote = math.random(60) + 20
        note_on(lastkeynote, 100)
        trigging = true
        UI.set_screen_dirty()
      else
        if lastkeynote then
          note_off(lastkeynote)
          trigging = false
          UI.set_screen_dirty()
        end
      end
    end
  end
end
