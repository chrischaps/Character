-- The Dusk Cave: one screen (960x540) of mossy stone under a cave mouth.
--
-- Solids are the only thing physics and navigation see. Everything else is
-- decoration hints for the renderers (where vines hang, where mushrooms grow,
-- which stalactites drip). Kinds: wall, ceiling, floor, ledge, pillar, log.

return {
    width = 960,
    height = 540,
    seed = 3,

    -- Light pours in through the mouth, top right
    mouth = {x = 792, y = 112, rx = 132, ry = 92},

    solids = {
        -- Enclosure
        {id = 'wall_l',   kind = 'wall',    x = -60, y = -60, w = 82,   h = 660},
        {id = 'wall_r',   kind = 'wall',    x = 938, y = -60, w = 82,   h = 660},
        {id = 'ceiling',  kind = 'ceiling', x = -60, y = -60, w = 1080, h = 92},

        -- Uneven cave floor
        {id = 'floor_1',  kind = 'floor',   x = -60, y = 476, w = 310,  h = 124, moss = true},
        {id = 'floor_2',  kind = 'floor',   x = 250, y = 494, w = 270,  h = 106, moss = true},
        {id = 'floor_3',  kind = 'floor',   x = 520, y = 482, w = 180,  h = 118, moss = true},
        {id = 'floor_4',  kind = 'floor',   x = 700, y = 462, w = 320,  h = 138, moss = true},

        -- Mossy staircase up the left wall
        {id = 'ledge_a',  kind = 'ledge',   x = 22,  y = 398, w = 118,  h = 26,  moss = true},
        {id = 'ledge_b',  kind = 'ledge',   x = 176, y = 322, w = 104,  h = 22,  moss = true},
        {id = 'shelf_c',  kind = 'ledge',   x = 22,  y = 238, w = 146,  h = 30,  moss = true},

        -- Centre: stepping stone, pillar, fallen log, mossy boulder
        {id = 'stone',    kind = 'ledge',   x = 318, y = 420, w = 74,   h = 20,  moss = true},
        {id = 'pillar',   kind = 'pillar',  x = 446, y = 332, w = 58,   h = 162, moss = true},
        {id = 'log',      kind = 'log',     x = 504, y = 340, w = 186,  h = 18},
        {id = 'boulder',  kind = 'boulder', x = 700, y = 410, w = 72,   h = 52,  moss = true},

        -- High shelf beneath the mouth
        {id = 'shelf_m',  kind = 'ledge',   x = 790, y = 240, w = 148,  h = 26,  moss = true},

        -- Overhang hanging from the roof (the spider's ceiling walk)
        {id = 'overhang', kind = 'ceiling', x = 286, y = 20,  w = 300,  h = 86},
    },

    -- Hanging vines: anchor point on an underside, segment count
    vines = {
        {x = 318, y = 106, n = 11}, {x = 372, y = 106, n = 7},  {x = 468, y = 106, n = 13},
        {x = 548, y = 106, n = 8},  {x = 52,  y = 268, n = 9},  {x = 128, y = 268, n = 6},
        {x = 838, y = 266, n = 9},  {x = 906, y = 266, n = 6},  {x = 584, y = 358, n = 5},
        {x = 652, y = 358, n = 4},  {x = 196, y = 32,  n = 12}, {x = 238, y = 32,  n = 8},
        {x = 214, y = 344, n = 4},
    },

    -- Glow mushroom clusters: surface x, solid id, count
    mushrooms = {
        {solid = 'ledge_a', x = 46,  n = 3},
        {solid = 'floor_2', x = 424, n = 4},
        {solid = 'shelf_m', x = 912, n = 3},
        {solid = 'floor_4', x = 912, n = 2},
        {solid = 'shelf_c', x = 140, n = 2},
        {solid = 'floor_1', x = 36,  n = 2},
    },

    -- Stalactites: tip hangs from a ceiling at x; length; drips?
    stalactites = {
        {x = 344, y = 106, len = 26, drip = true},
        {x = 418, y = 106, len = 16},
        {x = 506, y = 106, len = 34, drip = true},
        {x = 566, y = 106, len = 14},
        {x = 110, y = 32,  len = 30, drip = true},
        {x = 160, y = 32,  len = 18},
        {x = 640, y = 32,  len = 22},
        {x = 268, y = 32,  len = 24, drip = true},
    },

    -- Where each creature starts (surface x, solid id)
    spawns = {
        worm   = {solid = 'floor_1', x = 120},
        blob   = {solid = 'floor_3', x = 600},
        spider = {solid = 'floor_4', x = 836},
    },
}
