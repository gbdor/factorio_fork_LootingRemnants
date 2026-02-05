local CONSTANTS = require("cfg/constants")


-- TODO: add manual ignores

data:extend({
  {
    type = "bool-setting",
    name = CONSTANTS.MOD_NAME .. "-verbose-logging",
    setting_type = "startup",
    default_value = false,
    order = "aa",
  },{
    type = "double-setting",
    name = CONSTANTS.MOD_NAME .. "-loot-proba",
    setting_type = "startup",
    default_value = 0.8,
    minimum_value = 0,
    maximum_value = 1,
    order = "a",
  },{
    type = "double-setting",
    name = CONSTANTS.MOD_NAME .. "-loot-min",
    setting_type = "startup",
    default_value = 0.3,
    minimum_value = 0,
    maximum_value = 100,
    order = "a",
  },{
    type = "double-setting",
    name = CONSTANTS.MOD_NAME .. "-loot-max",
    setting_type = "startup",
    default_value = 1,
    minimum_value = 0,
    maximum_value = 100,
    order = "a",
  },{
    type = "string-setting",
    name = CONSTANTS.MOD_NAME .. "-extra-nospawn-items",
    setting_type = "startup",
    default_value = "",
    allow_blank = true,
    order = "a",
  }
})



-- Expose settings for other mods to modify
if mods["lib-settings"] then

  L("Exposing settings through settings-lib")

  local lib-settings = require("__lib-settings__/lib")

  lib-settings.exposeSetting(CONSTANTS.MOD_NAME .. "-loot-proba", {auto_hide_modified = true})
  lib-settings.exposeSetting(CONSTANTS.MOD_NAME .. "-loot-min", {auto_hide_modified = true})
  lib-settings.exposeSetting(CONSTANTS.MOD_NAME .. "-loot-max", {auto_hide_modified = true})
  lib-settings.exposeSetting(CONSTANTS.MOD_NAME .. "-extra-nospawn-items", {auto_hide_modified = true})
end


