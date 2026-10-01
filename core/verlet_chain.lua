-- Backwards compatibility wrapper - use lib/verlet.lua for new projects
local Verlet = require('lib.verlet')
return Verlet.VerletChain
