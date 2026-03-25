-- ============================================================================
-- General configuration: Change anything here without touching the functions
-- ============================================================================
local config      = {
  -- Trigger
  hotkey         = { mods = { "ctrl" }, key = "tab" },

  -- Layout
  screenRatio    = 0.85, -- max panel width as fraction of screen
  minIconSize    = 36,   -- minimum icon size in px before we stop shrinking
  maxIconSize    = 132,  -- starting/ideal icon size
  paddingRatio   = 0.06, -- spacing between icons as fraction of icon size

  -- Panel appearance
  panelColor     = { red = 0.18, green = 0.18, blue = 0.20, alpha = 0.8 },
  panelRadius    = 60,
  panelPadding   = 25, -- inner padding around icons

  -- Label
  showLabel      = false,
  labelFont      = "SF Pro Display",
  labelColor     = { white = 1, alpha = 0.85 },
  labelSizeRatio = 0.13, -- label font size as fraction of icon size
  labelMinSize   = 9,

  -- Badge (hint letter)
  badgeFont      = "SF Pro Display",
  badgeSizeRatio = 0.25, -- badge size as fraction of icon size
  badgeMinSize   = 16,
  badgeBgColor   = { red = 0.10, green = 0.10, blue = 0.12, alpha = 0.75 },
  badgeTextColor = { white = 1, alpha = 1 },
  badgeRadius    = 5,

  -- Keys assigned to apps, in order
  hintKeys       = "asdfghjklqwertyuiopzxcvbnm",
}
-- ============================================================

local hints       = {}
local hintWindows = {}
local appList     = {}
local hintMode    = false
local keyTap      = nil
local overlayBg   = nil

local function getKeyName(keycode)
  for name, code in pairs(hs.keycodes.map) do
    if code == keycode then return name end
  end

  return nil
end

local function clearHints()
  for _, w in ipairs(hintWindows) do w:delete() end

  hintWindows = {}
  hints       = {}
  appList     = {}

  if overlayBg then
    overlayBg:delete()
    overlayBg = nil
  end
end

local function stopHintMode()
  clearHints()

  hintMode = false

  if keyTap then
    keyTap:stop()
    keyTap = nil
  end
end

local function showAppHints()
  clearHints()

  local screen    = hs.screen.mainScreen():frame()

  -- Two constraints → whichever hits first is the limit
  local maxPanelW = screen.w * config.screenRatio
  local padding   = math.floor(config.maxIconSize * config.paddingRatio)
  local limit1    = #config
  .hintKeys                                                                                            -- The total hint keys
  local limit2    = math.floor((maxPanelW - config.panelPadding * 2) / (config.minIconSize + padding)) -- The size screen
  local maxApps   = math.min(limit1, limit2)

  -- Collect visible apps
  local apps      = hs.application.runningApplications()
  local idx       = 0

  for _, app in ipairs(apps) do
    local hasVisible = false

    for _, win in ipairs(app:allWindows()) do
      if not win:isMinimized() and win:isVisible() then
        hasVisible = true

        break
      end
    end

    if app:kind() == 1 and hasVisible then
      idx = idx + 1

      if idx > maxApps then break end

      local key = config.hintKeys:sub(idx, idx)

      hints[key] = app
      table.insert(appList, { key = key, app = app })
    end
  end

  -- Adaptive sizing: start at max, shrink to fit if needed
  local totalApps  = #appList
  local iconSize   = config.maxIconSize
  padding          = math.floor(iconSize * config.paddingRatio)
  local panelInner = config.panelPadding * 2
  local panelW     = totalApps * (iconSize + padding) + panelInner

  if panelW > maxPanelW then
    iconSize = math.floor((maxPanelW - panelInner) / totalApps - padding)
    iconSize = math.max(iconSize, config.minIconSize)
    padding  = math.floor(iconSize * config.paddingRatio)
    panelW   = totalApps * (iconSize + padding) + panelInner
  end

  -- labelH drives everything — 0 when hidden, compact panel when 0
  local labelH    = (config.showLabel and iconSize >= 48)
      and math.floor(iconSize * 0.30)
      or 0
  local badgeSize = math.max(config.badgeMinSize, math.floor(iconSize * config.badgeSizeRatio))
  local panelH    = iconSize + config.panelPadding * (config.showLabel and 1.25 or 2.0) + labelH
  local panelX    = screen.x + (screen.w - panelW) / 2
  local panelY    = screen.y + (screen.h - panelH) / 2

  -- Background panel
  overlayBg       = hs.canvas.new({ x = panelX, y = panelY, w = panelW, h = panelH })
  overlayBg[1]    = {
    type             = "rectangle",
    fillColor        = config.panelColor,
    roundedRectRadii = { xRadius = config.panelRadius, yRadius = config.panelRadius },
  }
  overlayBg:level(hs.canvas.windowLevels.overlay)
  overlayBg:show()

  -- Draw each app
  for i, item in ipairs(appList) do
    local iconX = panelX + config.panelPadding + (i - 1) * (iconSize + padding)
    local iconY = panelY + config.panelPadding

    -- Canvas height is tight, no wasted space when label is hidden
    local w = hs.canvas.new({ x = iconX, y = iconY, w = iconSize, h = iconSize + labelH })

    local img = item.app:bundleID() and
        hs.image.imageFromAppBundle(item.app:bundleID()) or
        hs.image.imageFromName("NSApplicationIcon")

    -- w[1]: Icon
    w[1] = {
      type         = "image",
      image        = img,
      frame        = { x = 0, y = 0, w = iconSize, h = iconSize },
      imageScaling = "scaleProportionally",
    }

    -- w[2]: Label always assigned to avoid index gaps
    -- Frame height = labelH, so when labelH = 0 it's invisible and takes no space
    w[2] = {
      type          = "text",
      text          = item.app:name(),
      textFont      = config.labelFont,
      textSize      = math.max(config.labelMinSize, math.floor(iconSize * config.labelSizeRatio)),
      textColor     = config.labelColor,
      textAlignment = "center",
      frame         = { x = 0, y = iconSize + 4, w = iconSize, h = labelH },
    }

    -- w[3]: Badge background, dark pill, top-left corner of icon
    w[3] = {
      type             = "rectangle",
      fillColor        = config.badgeBgColor,
      roundedRectRadii = { xRadius = config.badgeRadius, yRadius = config.badgeRadius },
      frame            = { x = 0, y = 0, w = badgeSize, h = badgeSize },
    }

    -- w[4]: Badge letter
    w[4] = {
      type          = "text",
      text          = item.key:upper(),
      textFont      = config.badgeFont,
      textSize      = math.max(config.labelMinSize, math.floor(badgeSize * 0.55)),
      textColor     = config.badgeTextColor,
      textAlignment = "center",
      frame         = { x = 0, y = math.floor(badgeSize * 0.12), w = badgeSize, h = badgeSize },
    }

    w:level(hs.canvas.windowLevels.overlay)
    w:show()

    table.insert(hintWindows, w)
  end
end

local function activateHintMode()
  if hintMode then
    stopHintMode()

    return
  end

  hintMode = true
  showAppHints()

  keyTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(e)
    local key = getKeyName(e:getKeyCode())

    if key == "escape" then
      stopHintMode()

      return true
    end

    if key and hints[key] then
      hints[key]:activate()
      stopHintMode()

      return true
    end

    return true
  end)

  keyTap:start()
end

hs.hotkey.bind(config.hotkey.mods, config.hotkey.key, activateHintMode)
