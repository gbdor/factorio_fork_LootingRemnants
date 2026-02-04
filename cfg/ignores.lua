local ignores = {

  -- Names of items that should never be spawned if value is true
  ---@type {string=>bool} 
  ITEMS_NEVER_SPAWN = {
    ["electric-energy-interface"]  = true,
    ["linked-chest"]               = true,
    ["infinity-chest"]             = true,
    ["infinity-pipe"]              = true,
    ["infinity-cargo-wagon"]       = true,
    ["heat-interface"]             = true,
    ["proxy-container"]            = true,
    ["bottomless-chest"]           = true,
    ["linked-belt"]                = true,
  }

}

return ignores

