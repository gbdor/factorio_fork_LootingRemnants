local CONSTANTS = require("cfg/constants")


-- TODO: add manual ignores

data:extend({
  {
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
