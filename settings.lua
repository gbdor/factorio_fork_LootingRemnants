local constants = require("lua/constants")




data:extend({
  {
    type = "double-setting",
    name = constants.MOD_NAME .. "-loot-proba",
    setting_type = "runtime-global",
    default_value = 0.8,
    minimum_value = 0,
    maximum_value = 1,
    order = "a",
  },{
    type = "double-setting",
    name = constants.MOD_NAME .. "-loot-min",
    setting_type = "runtime-global",
    default_value = 0.3,
    minimum_value = 0,
    maximum_value = 1,
    order = "a",
  },{
    type = "double-setting",
    name = constants.MOD_NAME .. "-loot-max",
    setting_type = "runtime-global",
    default_value = 1,
    minimum_value = 0,
    maximum_value = 1,
    order = "a",
  }
})
