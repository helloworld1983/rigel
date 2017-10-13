local R = require "rigel"
local RM = require "modules"
local J = require "common"
local SOC = {}

local PORTS = 4

SOC.frameStart = R.newGlobal("frameStart","input",rigel.Handshake(types.null()),{nil,false})

SOC.readAddrs = J.map(J.range(0,PORTS-1),function(i) return R.newGlobal("readAddr"..tostring(i),"output",R.Handshake(types.uint(32)),{0,false}) end)
SOC.readData = J.map(J.range(0,PORTS-1),function(i) return R.newGlobal("readData"..tostring(i),"input",R.Handshake(types.bits(64))) end)

SOC.writeAddrs = J.map(J.range(0,PORTS-1),function(i) return R.newGlobal("writeAddr"..tostring(i),"output",R.Handshake(types.uint(32)),{0,false}) end)
SOC.writeData = J.map(J.range(0,PORTS-1),function(i) return R.newGlobal("writeData"..tostring(i),"output",R.Handshake(types.bits(64)),{0,false}) end)
  
-- does a 128 byte burst
-- uint25 addr -> bits(64)
SOC.bulkRamRead = memoize(function(port)
  if port==nil then return SOC.bulkRamRead(0) end
  err( type(port)=="number", "bulkRamRead: port must be number" )
  err( port<PORTS,"bulkRamRead: port out of range" )
      
  local H = require "rigelhll"
  local brri = rigel.input(types.uint(25))
  brri = H.cast(H.u32)(brri)
  brri = H.lshift(brri,H.c(u8,7))
  local pipelines = {R.writeGlobal( SOC.readAddrs[port], brri )}

  return RM.lambda("bulkRamRead_"..tostring(port),brri,R.readGlobal(SOC.readData[port]),nil,pipelines)
end)

-- {Handshake(uint25),Handshake(bits(64))}
-- you need to write 16 data chunks per address!!
SOC.bulkRamWrite = RM.lambda()

SOC.readScanline = memoize(function(filename,W,H,ty)
  local fs = R.readGlobal(SOC.frameStart)

  local totalBytes = W*H*ty:verilogBits()/8
  err( totalBytes % 128 == 0,"NYI - non burst aligned reads")

  local addr = R.apply("addr",RM.counter(types.uint(25),totalBytes/128),fs)
  local out = R.apply("ramRead",SOC.bulkRamRead,addr)

  out = R.apply("underflow_US", RM.underflow( R.extractData(inputType), inputBytes/8, EC, true ), out)
  
  return RM.lambda("readScanline",nil,out)
end)

SOC.writeScanline = memoize(function(filename,W,H,ty)
  local I = R.input(ty)

  ----------------
  local out = R.apply("overflow", RM.liftHandshake(RM.liftDecimate(RM.overflow(R.extractData(hsfn.outputType), outputCount))), I)
  out = R.apply("underflow", RM.underflow(R.extractData(hsfn.outputType), outputBytes/8, EC, false ), out)
  out = R.apply("cycleCounter", RM.cycleCounter(R.extractData(hsfn.outputType), outputBytes/8 ), out)

  ---------------
  local fs = R.readGlobal(SOC.frameStart)

  local totalBytes = W*H*ty:verilogBits()/8
  err( totalBytes % 128 == 0,"NYI - non burst aligned write")

  local addr = R.apply("addr",RM.counter(types.uint(25),totalBytes/128),fs)
  ---------------

  out = R.apply("write",SOC.bulkRamWrite, R.concat("w",{addr,out}) )
  
  return RM.lambda("writeScanline",I,out)
end)
