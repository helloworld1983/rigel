local R = require "rigel"
local RM = require "modules"
local types = require("types")
local harness = require "harness"

W = 128
H = 64
T = 8

scaleY = 4
------------
ITYPE = types.array2d( types.uint(8), T )
hsfn = RM.liftHandshake(RM.upsampleYSeq( types.uint(8), W,H,T,scaleY))

harness.axi( "upsampley_wide_handshake", hsfn, "frame_128.raw", nil, nil, ITYPE, T,W,H, ITYPE,T,W,H*scaleY)