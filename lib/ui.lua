-- utility library for single-grid, single-arc, single-midi device script UIs
-- written to track when UI is invalidated and needs to be refreshed
-- no dependency to norns global variables
--
-- main entry points:
-- UI.init_arc - invoked if an arc is to be used. has to be passed a device (ie. return value from arc.connect()), and optionally sets up callbacks for receiving enc delta messages (on_delta) and refreshing arc leds (on_refresh) when arc UI is invalidated
-- UI.init_grid - invoked if a grid is to be used. has to be passed a device (ie. return value from grid.connect()), and optionally sets up callbacks for receiving grid key messages (on_key) and refreshing grid leds (on_refresh) when grid UI is invalidated
-- UI.init_midi - invoked if a midi device is to be used. has to be passed a device (ie. return value from midi.connect()), and optionally a callback for receiving incoming midi messages (on_event)
-- UI.init_screen - invoked if norns screen is to be used. has to be passed a callback for refreshing screen (on_refresh) when screen UI is invalidated.
-- UI.refresh - to be triggered from script recurringly, will check and refresh invalidated UIs and refresh tracked device properties (whether device is connected, device bounds). additionally a flag for whether an incoming event was recently handled (UI.show_event_indicator) is continuously updated.

local UI = {
  -- event indicator flag
  show_event_indicator = false,
  -- arc handling
  arc_connected = false,
  arc_dirty = false,
  -- grid handling
  grid_connected = false,
  grid_dirty = false,
  grid_width = nil,
  -- midi handling
  midi_device_connected = false,
  -- screen handling
  screen_dirty = false
}

-- refresh logic

function UI.refresh()
  UI.update_event_indicator()

  if UI.arc_is_inited then
    UI.check_arc_connected()
      
    if UI.arc_dirty then
      if UI.arc_refresh_callback then
        UI.arc_refresh_callback(UI.arc_device)
      end
      UI.arc_device:refresh()
      UI.arc_dirty = false
    end
  end

  if UI.grid_is_inited then
    UI.check_grid_connected()
    UI.update_grid_width()

    if UI.grid_dirty then
      if UI.grid_refresh_callback then
        UI.grid_refresh_callback(UI.grid_device)
      end
      UI.grid_device:refresh()
      UI.grid_dirty = false
    end
  end

  if UI.midi_is_inited then
    UI.check_midi_connected()
  end

  if UI.screen_dirty then
    if UI.screen_refresh_callback then
      UI.screen_refresh_callback()
    end
    screen.update()
    UI.screen_dirty = false
  end
end

function UI.set_dirty()
  UI.arc_dirty = true
  UI.grid_dirty = true
  UI.screen_dirty = true
end

-- event flash

local EVENT_FLASH_FRAMES = 20
local event_flash_frame_counter = nil

function UI.flash_event()
  event_flash_frame_counter = EVENT_FLASH_FRAMES
end
  
function UI.update_event_indicator()
  if event_flash_frame_counter then
    event_flash_frame_counter = event_flash_frame_counter - 1
    if event_flash_frame_counter == 0 then
      event_flash_frame_counter = nil
      UI.show_event_indicator = false
      UI.set_dirty()
    elseif not UI.show_event_indicator then
      UI.show_event_indicator = true
      UI.set_dirty()
    end
  end
end

-- arc

function UI.init_arc(config)
  if config.device == nil then
    error("init_arc: device is mandatory")
  end

  local arc_device = config.device

  UI.arc_delta_callback = config.on_delta
  arc_device.delta = function(n, delta)
    UI.flash_event()
    UI.arc_delta_callback(n, delta)
  end
  UI.arc_device = arc_device
  UI.arc_refresh_callback = config.on_refresh
  UI.arc_is_inited = true
end

function UI.check_arc_connected()
  local arc_check = UI.arc_device.device ~= nil
  if UI.arc_connected ~= arc_check then
    UI.arc_connected = arc_check
    UI.arc_dirty = true
  end
end
  
-- grid

function UI.init_grid(config)
  if config.device == nil then
    error("init_grid: device is mandatory")
  end

  local grid_device = config.device

  UI.grid_key_callback = config.on_key
  grid_device.key = function(x, y, s)
    UI.flash_event()
    UI.grid_key_callback(x, y, s)
  end
  UI.grid_device = grid_device
  UI.grid_refresh_callback = config.on_refresh
  UI.grid_is_inited = true
end

function UI.update_grid_width()
  if UI.grid_device.device then
    if UI.grid_width ~= UI.grid_device.cols then
      UI.grid_width = UI.grid_device.cols
    end
  end
end

function UI.check_grid_connected()
  local grid_check = UI.grid_device.device ~= nil
  if UI.grid_connected ~= grid_check then
    UI.grid_connected = grid_check
    UI.grid_dirty = true
  end
end

-- midi

function UI.init_midi(config)
  if config.device == nil then
    error("init_midi: device is mandatory")
  end

  local midi_device = config.device

  UI.midi_event_callback = config.on_event
  midi_device.event = function(data)
    UI.flash_event()
    UI.midi_event_callback(data)
  end
  UI.midi_device = midi_device
  UI.midi_is_inited = true
end

function UI.check_midi_connected()
  local midi_device_check = UI.midi_device.device ~= nil
  if UI.midi_device_connected ~= midi_device_check then
    UI.midi_device_connected = midi_device_check
  end
end

-- screen

function UI.init_screen(config)
  UI.screen_refresh_callback = config.on_refresh
end

return UI
