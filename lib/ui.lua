-- prerequisites: screen, metro, midi, arc, grid, redraw globals defined

---- UI (start) ----

local UI = {}

-- refresh logic

function UI.init(rate)
  UI.refresh_metro = metro.init()
  UI.refresh_metro.event = UI.tick
  UI.refresh_metro.time = 1/(rate or 60)
  UI.refresh_metro:start()
end

function UI.tick() -- TODO: make a local in separate UI lib?
  UI.update_arc_connected()
  UI.update_grid_width()
  UI.update_grid_connected()
  UI.update_event_indicator()
    
  if UI.arc_dirty then
    if UI.refresh_arc_callback then
      UI.refresh_arc_callback(UI.my_arc)
    end
    UI.my_arc:refresh()
    UI.arc_dirty = false
  end

  if UI.grid_dirty then
    if UI.refresh_grid_callback then
      UI.refresh_grid_callback(UI.my_grid)
    end
    UI.my_grid:refresh()
    UI.grid_dirty = false
  end

  if UI.screen_dirty then
    redraw() -- TODO: weirdly hard wired to redraw()
    UI.screen_dirty = false
  end
end

-- event flash

local EVENT_FLASH_LENGTH = 10
UI.show_event_indicator = false
local event_flash_counter = nil

function UI.flash_event()
  event_flash_counter = EVENT_FLASH_LENGTH
end
  
function UI.update_event_indicator()
  if event_flash_counter then
    event_flash_counter = event_flash_counter - 1
    if event_flash_counter == 0 then
      event_flash_counter = nil
      UI.show_event_indicator = false
      UI.set_screen_dirty()
    else
      if not UI.show_event_indicator then
        UI.show_event_indicator = true
        UI.set_screen_dirty()
      end
    end
  end
end

-- arc

UI.arc_connected = false
UI.arc_dirty = false

function UI.set_arc_dirty()
  UI.arc_dirty = true
end

function UI.setup_arc(delta_callback, refresh_callback)
  local my_arc = arc.connect() -- TODO: rename to arc or devices.arc?
  my_arc.delta = delta_callback
  UI.my_arc = my_arc
  UI.refresh_arc_callback = refresh_callback
end

function UI.update_arc_connected()
  local arc_check = UI.my_arc.device ~= nil
  if UI.arc_connected ~= arc_check then
    UI.arc_connected = arc_check
    UI.set_arc_dirty()
  end
end
  
-- grid

UI.grid_connected = false
UI.grid_dirty = false
UI.grid_width = 16

function UI.set_grid_dirty()
  UI.grid_dirty = true
end

function UI.setup_grid(key_callback, refresh_callback)
  local my_grid = grid.connect()
  my_grid.key = key_callback
  UI.my_grid = my_grid
  UI.refresh_grid_callback = refresh_callback
end

function UI.update_grid_width()
  if UI.my_grid.device then
    if UI.grid_width ~= UI.my_grid.cols then
      UI.grid_width = UI.my_grid.cols
      UI.set_grid_dirty()
    end
  end
end

function UI.update_grid_connected()
  local grid_check = UI.my_grid.device ~= nil
  if UI.grid_connected ~= grid_check then
    UI.grid_connected = grid_check
    UI.set_grid_dirty()
  end
end

-- midi

function UI.setup_midi(event_callback)
  local my_midi_device = midi.connect()
  my_midi_device.event = event_callback
  UI.my_midi_device = my_midi_device
end

-- screen refresh

function UI.set_screen_dirty()
  UI.screen_dirty = true
end

-- screen refresh

local hi_level = 15
local lo_level = 4

local enc1_x = 0
local enc1_y = 12

local enc2_x = 10
local enc2_y = 32

local enc3_x = enc2_x+65
local enc3_y = enc2_y

local key2_x = 0
local key2_y = 63

local key3_x = key2_x+65
local key3_y = key2_y

local function redraw_enc1_widget()
  screen.move(enc1_x, enc1_y)
  screen.level(lo_level)
  screen.text("LEVEL")
  screen.move(enc1_x+45, enc1_y)
  screen.level(hi_level)
  screen.text(util.round(mix:get_raw("output")*100, 1))
end

local function redraw_event_flash_widget()
  screen.level(lo_level)
  screen.rect(122, enc1_y-7, 5, 5)
  screen.fill()
end

local function redraw_enc2_widget()
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

local function redraw_enc3_widget()
  screen.move(enc3_x, enc3_y)
  screen.level(lo_level)
  screen.text("RES")
  screen.move(enc3_x, enc3_y+12)
  screen.level(hi_level)
  
  screen.text(util.round(params:get("filter_resonance")*100, 1))
  screen.text("%")
end
  
local function redraw_key2_widget()
  screen.move(key2_x, key2_y)
  
  if fine then
    screen.level(hi_level)
    screen.text("FINE")
  else
    screen.level(lo_level)
    screen.text("COARSE")
  end
end

local function redraw_key3_widget()
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

---- UI (fin) ----

return UI
