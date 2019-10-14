-- small utility library for single-grid, single-arc, single-midi device script UIs
-- written to track dirty states of UI, provide a generic refresh function
-- written to not be directly dependent on norns global variables

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

  if UI.arc_inited then
    UI.check_arc_connected()
      
    if UI.arc_dirty then
      if UI.arc_refresh_callback then
        UI.arc_refresh_callback(UI.arc_device)
      end
      UI.arc_device:refresh()
      UI.arc_dirty = false
    end
  end

  if UI.grid_inited then
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

  if UI.midi_inited then
    UI.check_midi_connected()
  end

  if UI.screen_dirty then
    if UI.refresh_screen_callback then
      UI.refresh_screen_callback()
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

local EVENT_FLASH_FRAMES = 10
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
    else
      if not UI.show_event_indicator then
        UI.show_event_indicator = true
        UI.set_dirty()
      end
    end
  end
end

-- arc

function UI.init_arc(config)
  local arc_device = config.device

  -- TODO: throw error if arc_device is nil

  UI.arc_delta_callback = config.delta_callback
  arc_device.delta = function(n, delta)
    UI.flash_event()
    UI.arc_delta_callback(n, delta)
  end
  UI.arc_device = arc_device
  UI.arc_refresh_callback = config.refresh_callback
  UI.arc_inited = true
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
  local grid_device = config.device

  -- TODO: throw error if grid_device is nil

  UI.grid_key_callback = config.key_callback
  grid_device.key = function(x, y, s)
    UI.flash_event()
    UI.grid_key_callback(x, y, s)
  end
  UI.grid_device = grid_device
  UI.grid_refresh_callback = config.refresh_callback
  UI.grid_width_changed_callback = config.width_changed_callback -- TODO: consider just updating grid_width in UI table, defer check for this to scripts
  UI.grid_inited = true
end

function UI.update_grid_width()
  if UI.grid_device.device then
    if UI.grid_width ~= UI.grid_device.cols then
      UI.grid_width = UI.grid_device.cols
      if UI.grid_width_changed_callback then
        UI.grid_width_changed_callback(UI.grid_width)
      end
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
  local midi_device = config.device

  -- TODO: throw error if midi_device is nil

  UI.midi_event_callback = config.event_callback
  midi_device.event = function(data)
    UI.flash_event()
    UI.midi_event_callback(data)
  end
  UI.midi_device = midi_device
  UI.midi_inited = true
end

function UI.check_midi_connected()
  local midi_device_check = UI.midi_device.device ~= nil
  if UI.midi_device_connected ~= midi_device_check then
    UI.midi_device_connected = midi_device_check
  end
end

-- screen

function UI.init_screen(config)
  UI.refresh_screen_callback = config.refresh_callback
end

return UI
