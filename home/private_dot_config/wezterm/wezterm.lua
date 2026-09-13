local wezterm = require 'wezterm'

local config = {}

-- === Appearance ===
config.color_scheme = "Catppuccin Macchiato"  -- Set color scheme
config.front_end = "WebGpu"  -- Render via Metal instead of OpenGL (smoother scrolling, lower GPU overhead on macOS)
config.font = wezterm.font_with_fallback({
  "Hack Nerd Font Mono",  -- Primary font for English
  "Noto Sans CJK SC",     -- Fallback for Simplified Chinese
  "Noto Sans CJK TC",     -- Fallback for Traditional Chinese
})
config.font_size = 12.0  -- Set font size
config.window_background_opacity = 0.9  -- Set transparency (0.0 is fully transparent, 1.0 is fully opaque)
config.macos_window_background_blur = 30  -- Blur whatever shows through the transparency
config.scrollback_lines = 10000  -- Scrollback buffer (default 3500)
config.check_for_updates = false  -- WezTerm is managed by Homebrew (cask 'wezterm')

-- Dim panes that are not focused (helps spot the active split)
config.colors = {
  inactive_pane_hsb = {
    saturation = 0.9,
    brightness = 0.7,
  },
}

-- === Cursor Settings ===
config.hide_mouse_cursor_when_typing = true  -- Hide mouse cursor while typing
config.default_cursor_style = "BlinkingBar"  -- Cursor style (a blinking bar for active typing)
config.cursor_thickness = "0.07cell"  -- Set cursor thickness (in terms of cells)
config.cursor_blink_rate = 700  -- Cursor blink rate in milliseconds
config.cursor_blink_ease_in = "Constant"  -- Cursor blink fade-in behavior (no fading)
config.cursor_blink_ease_out = "Constant"  -- Cursor blink fade-out behavior (no fading)

-- === Window Behavior ===
config.window_decorations = "RESIZE"  -- Set window decorations (integrated buttons with resize)
config.native_macos_fullscreen_mode = false  -- Disables native fullscreen for macOS, use WezTerm's own fullscreen
config.use_fancy_tab_bar = true  -- This separates tabs from titlebar controls
config.tab_bar_at_bottom = false  -- Set to true if you want tabs at bottom
config.hide_tab_bar_if_only_one_tab = true  -- No tab strip while only one tab is open

-- === Keybindings ===
config.keys = {
  -- Vertical split using Control + Option + Shift + Down Arrow
  {
    key = 'DownArrow',
    mods = 'CTRL|OPT|SHIFT',
    action = wezterm.action{SplitVertical={domain="CurrentPaneDomain"}},
  },

  -- Horizontal split using Control + Option + Shift + Right Arrow
  {
    key = 'RightArrow',
    mods = 'CTRL|OPT|SHIFT',
    action = wezterm.action{SplitHorizontal={domain="CurrentPaneDomain"}},
  },

  -- Focus neighbouring panes with Cmd+Ctrl + h/j/k/l (vim-style)
  { key = 'h', mods = 'SUPER|CTRL', action = wezterm.action.ActivatePaneDirection 'Left' },
  { key = 'j', mods = 'SUPER|CTRL', action = wezterm.action.ActivatePaneDirection 'Down' },
  { key = 'k', mods = 'SUPER|CTRL', action = wezterm.action.ActivatePaneDirection 'Up' },
  { key = 'l', mods = 'SUPER|CTRL', action = wezterm.action.ActivatePaneDirection 'Right' },

  -- Resize panes with Cmd+Ctrl+Shift + h/j/k/l
  { key = 'h', mods = 'SUPER|CTRL|SHIFT', action = wezterm.action.AdjustPaneSize { 'Left', 3 } },
  { key = 'j', mods = 'SUPER|CTRL|SHIFT', action = wezterm.action.AdjustPaneSize { 'Down', 3 } },
  { key = 'k', mods = 'SUPER|CTRL|SHIFT', action = wezterm.action.AdjustPaneSize { 'Up', 3 } },
  { key = 'l', mods = 'SUPER|CTRL|SHIFT', action = wezterm.action.AdjustPaneSize { 'Right', 3 } },

  -- Command palette (Ctrl+Shift+P is the default, this adds the macOS-style Cmd+P)
  { key = 'p', mods = 'SUPER', action = wezterm.action.ActivateCommandPalette },
}

-- === Session Restore (resurrect.wezterm) ===
-- Snapshots of window/tab/pane layout stored as JSON in ~/.local/share/wezterm/resurrect/.
-- WezTerm always starts clean; restoring is manual (CMD+SHIFT+R).
-- Full reset: rm -rf ~/.local/share/wezterm/resurrect
local resurrect = wezterm.plugin.require('https://github.com/MLFlexer/resurrect.wezterm')

-- Pin the snapshot dir explicitly (default depends on a helper plugin's path lookup)
resurrect.state_manager.change_state_save_dir(wezterm.home_dir .. '/.local/share/wezterm/resurrect')

-- Autosave the workspace every 15 minutes (crash/reboot safety net)
resurrect.state_manager.periodic_save()

local session_keys = {
  -- CMD+SHIFT+S: snapshot the current workspace
  {
    key = 's',
    mods = 'SUPER|SHIFT',
    action = wezterm.action_callback(function(win, pane)
      resurrect.state_manager.save_state(resurrect.workspace_state.get_workspace_state())
    end),
  },
  -- CMD+SHIFT+R: restore from a snapshot via fuzzy picker
  -- (plain CMD+R stays free for WezTerm's default ReloadConfiguration)
  {
    key = 'r',
    mods = 'SUPER|SHIFT',
    action = wezterm.action_callback(function(win, pane)
      resurrect.fuzzy_loader.fuzzy_load(win, pane, function(id, label)
        local type = string.match(id, '^([^/]+)')  -- match before '/'
        id = string.match(id, '([^/]+)$')          -- match after '/'
        id = string.match(id, '(.+)%..+$')         -- remove file extension
        local opts = {
          relative = true,
          restore_text = true,
          on_pane_restore = resurrect.tab_state.default_on_pane_restore,
        }
        if type == 'workspace' then
          local state = resurrect.state_manager.load_state(id, 'workspace')
          resurrect.workspace_state.restore_workspace(state, opts)
        elseif type == 'window' then
          local state = resurrect.state_manager.load_state(id, 'window')
          resurrect.window_state.restore_window(pane:window(), state, opts)
        elseif type == 'tab' then
          local state = resurrect.state_manager.load_state(id, 'tab')
          resurrect.tab_state.restore_tab(pane:tab(), state, opts)
        end
      end)
    end),
  },
  -- CMD+Shift+D: delete a saved snapshot
  {
    key = 'd',
    mods = 'SUPER|SHIFT',
    action = wezterm.action_callback(function(win, pane)
      resurrect.fuzzy_loader.fuzzy_load(win, pane, function(id)
        -- fuzzy ids look like "workspace/my_ws.json"; delete_state() expects exactly that relative path
        resurrect.state_manager.delete_state(id)
      end, {
        title = 'Delete State',
        description = 'Select State to Delete and press Enter = accept, Esc = cancel, / = filter',
        fuzzy_description = 'Search State to Delete: ',
        is_fuzzy = true,
      })
    end),
  },
}
for _, key in ipairs(session_keys) do table.insert(config.keys, key) end

return config
