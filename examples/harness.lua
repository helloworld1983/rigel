local R = require "rigel"
local RM = require "modules"
local C = require "examplescommon"
local types = require("types")
--local fixed = require("fixed")
local SDFRate = require "sdfrate"
local J = require "common"
local err = J.err

local function writeMetadata(filename, tab)
  err(type(filename)=="string")
  err(type(tab)=="table")

  io.output(filename)

  local res = {}
  for k,v in pairs(tab) do
    if type(v)=="number" then
      table.insert(res,k.."="..tostring(v))
    else
      table.insert(res,k.."='"..tostring(v).."'")
    end
  end

  io.write( "return {"..table.concat(res,",").."}" )
  -- io.close()
end

local function expectedCycles(hsfn,inputCount,outputCount,underflowTest,slackPercent)
  assert(type(outputCount)=="number")
  assert(type(slackPercent)=="number")

  local EC_RAW = inputCount*(hsfn.sdfInput[1][2]/hsfn.sdfInput[1][1])
  EC_RAW = math.ceil(EC_RAW)

  if DARKROOM_VERBOSE then print("Expected cycles:",EC_RAW,"IC",inputCount,hsfn.sdfInput[1][1],hsfn.sdfInput[1][2]) end

  local EC = math.floor(EC_RAW*slackPercent) -- slack
  if underflowTest then EC = 1 end
  return EC, EC_RAW
end

local function harnessAxi( hsfn, inputCount, outputCount, underflowTest, inputType, tapType, earlyOverride)


  local outputBytes = J.upToNearest(128,outputCount*8) -- round to axi burst
  local inputBytes = J.upToNearest(128,inputCount*8) -- round to axi burst

  err(outputBytes==outputCount*8, "NYI - non-burst-aligned output counts")
  err(inputBytes==inputCount*8, "NYI - non-burst-aligned input counts")

  local ITYPE = inputType
  --if tapType~=nil then ITYPE = types.tuple{inputType,tapType} end

  local inpSymb = R.input( R.Handshake(ITYPE) )
  local inpdata
  local inptaps

--  if tapType==nil then
    inpdata = inpSymb
--  else
--    inpdata = R.apply("inpdata", RM.makeHandshake(C.index(ITYPE,0)), inpSymb)
--    inptaps = R.apply("inptaps", RM.makeHandshake(C.index(ITYPE,1)), inpSymb)
--  end

  local EC
  if type(earlyOverride)=="number" then
    EC=earlyOverride
  else
    EC = expectedCycles(hsfn,inputCount,outputCount,underflowTest,1.85)
  end
  
  local inpdata = R.apply("underflow_US", RM.underflow( R.extractData(inputType), inputBytes/8, EC, true ), inpdata)

  local hsfninp

--  if tapType==nil then
    hsfninp = inpdata
--  else
--    hsfninp = R.apply("HFN",RM.packTuple({inputType,tapType}), R.concat("hsfninp",{inpdata,inptaps}))
--  end

  -- add a FIFO to all pipelines. Some user's pipeline may not have any FIFOs in them.
  -- you would think it would be OK to have no FIFOs, but for some reason, sometimes wiring the AXI read port and write port
  -- directly won't work. The write port ready seizes up (& the underflow_US is needed to prevent deadlock, but then the image is incorrect).
  -- The problem is intermittent.
  local regs, out
  local stats = {}
  local EXTRA_FIFO = false

  if EXTRA_FIFO then
      regs = {R.instantiateRegistered("f1",RM.fifo(R.extractData(hsfn.inputType),256))}
      stats[2] = R.applyMethod("s1",regs[1],"store",hsfninp)
      hsfninp = R.applyMethod("l1",regs[1],"load")
  end

  local pipelineOut = R.apply("hsfna",hsfn,hsfninp)

  if EXTRA_FIFO then
     regs[2] = R.instantiateRegistered("f2",RM.fifo(R.extractData(hsfn.outputType),256))
     out = R.applyMethod("l2",regs[2],"load")
     stats[3] = R.applyMethod("s2",regs[2],"store",pipelineOut)
  else
     out = pipelineOut
  end

  out = R.apply("overflow", RM.liftHandshake(RM.liftDecimate(RM.overflow(R.extractData(hsfn.outputType), outputCount))), out)
  out = R.apply("underflow", RM.underflow(R.extractData(hsfn.outputType), outputBytes/8, EC, false ), out)
  out = R.apply("cycleCounter", RM.cycleCounter(R.extractData(hsfn.outputType), outputBytes/8 ), out)

  if EXTRA_FIFO then
     stats[1] = out
     out = R.statements(stats)
  end

  return RM.lambda( "harnessaxi", inpSymb, out, regs )
end

local H = {}


if terralib~=nil then
  --harnessWrapperFn = underoverWrapper
  H.terraOnly = require("harnessTerra")
end

function H.sim(filename, hsfn, inputFilename, tapType, tapValue, inputType, inputT, inputW, inputH, outputType, outputT, outputW, outputH, underflowTest, earlyOverride, X)
  assert(X==nil)
  assert( tapType==nil or types.isType(tapType) )
  assert( types.isType(inputType) )
  assert( types.isType(outputType) )
  assert(type(outputH)=="number")
  assert(type(inputFilename)=="string")


  local inputCount = (inputW*inputH)/inputT
  local outputCount = (outputW*outputH)/outputT

--  H.terraOnly(filename, hsfn, inputFilename, tapType, tapValue, inputType, inputT, inputW, inputH, outputType, outputT, outputW, outputH, X)

  local frames = 2
  local simInputH = inputH*frames
  local simOutputH = outputH*frames
  local simInputCount = (inputW*simInputH)/inputT
  local simOutputCount = (outputW*simOutputH)/outputT

  local cycleCountPixels = (128*8)/(outputType:verilogBits())
  ------
  for i=1,2 do
    local ext=""
    if i==2 then ext="_half" end
    local f = RM.seqMapHandshake( underoverWrapper(hsfn, "../"..inputFilename..".dup", inputType, tapType, "out/"..filename..ext, filename..ext..".isim.raw",outputType,2+i, simInputCount, simOutputCount, frames, underflowTest, earlyOverride), inputType, tapType, tapValue, simInputCount, simOutputCount+cycleCountPixels*frames, false, i )
    io.output("out/"..filename..ext..".isim.v")
    io.write(f:toVerilog())
    io.output():close()
  end

end

function H.verilogOnly(filename, hsfn, inputFilename, tapType, tapValue, inputType, inputT, inputW, inputH, outputType, outputT, outputW, outputH,simCycles,harnessOption,X)

  assert(X==nil)
  assert( types.isType(inputType) )
  assert( tapType==nil or types.isType(tapType) )
  if tapType~=nil then tapType:checkLuaValue(tapValue) end
  assert( types.isType(outputType) )
  assert(type(inputW)=="number")
  assert(type(outputH)=="number")
  assert(type(inputFilename)=="string")
  err(R.isFunction(hsfn), "second argument to harness.axi must be function")
  --assert(earlyOverride==nil or type(earlyOverride)=="number")

------------------------
-- verilator just uses the top module directly
  io.output("out/"..filename..".v")
  io.write(hsfn:toVerilog())
  io.output():close()

end

local function axiRateWrapper(fn)
  --err(tapType==nil or types.isType(tapType),"tapType should be type or nil")

  R.expectHandshake(fn.inputType)

  local iover = R.extractData(fn.inputType)
  
--  if tapType~=nil then
--    -- taps have tap value packed into argument
--    assert(iover.list[2]==tapType)
--    iover = iover.list[1]
--  end

  R.expectHandshake(fn.outputType)
  oover = R.extractData(fn.outputType)

  if iover:verilogBits()==64 and oover:verilogBits()==64 then
return fn
  end

  local inputP
  if iover:isArray() then
    inputP = iover:channels()
    iover = iover:arrayOver()
  else
    inputP = 1 -- just assume pointwise...
  end


  local outputP
  if oover:isArray() then
    outputP = oover:channels()
    oover = oover:arrayOver()
  else
    outputP = 1
  end

  local targetInputP = (64/iover:verilogBits())
  err( targetInputP==math.floor(targetInputP), "axiRateWrapper error: input type does not divide evenly into axi bus size ("..tostring(fn.inputType)..") iover:"..tostring(iover).." inputP:"..tostring(inputP))
  
  local inp = R.input( R.Handshake(types.array2d(iover,targetInputP)) )
  local out = inp

  if fn.inputType:verilogBits()~=64 then
    out = R.apply("harnessCR", RM.liftHandshake(RM.changeRate(iover, 1, targetInputP, inputP )), inp)
  end

  if R.extractData(fn.inputType):isArray()==false then out = R.apply("harnessPW",RM.makeHandshake(C.index(types.array2d(iover,1),0)),out) end
  out = R.apply("HarnessHSFN",fn,out) --{input=out, toModule=fn}
  if R.extractData(fn.outputType):isArray()==false then out = R.apply("harnessPW0",RM.makeHandshake(C.arrayop(oover,1)),out) end

  local targetOutputP = (64/oover:verilogBits())
  err( targetOutputP==math.floor(targetOutputP), "axiRateWrapper error: output type does not divide evenly into axi bus size")

  if fn.outputType:verilogBits()~=64 then
    out = R.apply("harnessCREnd", RM.liftHandshake(RM.changeRate(oover,1,outputP,targetOutputP)),out)
  end

  local outFn =  RM.lambda("hsfnAxiRateWrapper",inp,out)

  err( R.extractData(outFn.inputType):verilogBits()==64, "axi rate wrapper: failed to make input type 64 bit (originally "..tostring(fn.inputType)..")")
  err( R.extractData(outFn.outputType):verilogBits()==64, "axi rate wrapper: failed to make output type 64 bit")

  return outFn
end

-- AXI must have T=8
function H.axi(filename, hsfn, inputFilename, tapType, tapValue, inputType, inputT, inputW, inputH, outputType, outputT, outputW, outputH,underflowTest,earlyOverride,X)

  assert(X==nil)
  assert( types.isType(inputType) )
  assert( tapType==nil or types.isType(tapType) )
  if tapType~=nil then tapType:checkLuaValue(tapValue) end
  assert( types.isType(outputType) )
  assert(type(inputW)=="number")
  assert(type(outputH)=="number")
  assert(type(inputFilename)=="string")
  assert(type(filename)=="string")
  err(R.isFunction(hsfn), "second argument to harness.axi must be function")
  assert(earlyOverride==nil or type(earlyOverride)=="number")

  err(inputType:verilogBits()==64, "input type must be 64 bits for AXI bus, but is "..tostring(inputType:verilogBits()))
  err(outputType:verilogBits()==64, "output type must be 64 bits for AXI bus")

  local inputCount = (inputW*inputH)/inputT
  local outputCount = (outputW*outputH)/outputT

-- axi runs the sim as well
--H.sim(filename, hsfn,inputFilename, tapType,tapValue, inputType, inputT, inputW, inputH, outputType, outputT, outputW, outputH, underflowTest,earlyOverride)
  local inputCount = (inputW*inputH)/inputT
  local axifn = harnessAxi(hsfn, inputCount, (outputW*outputH)/outputT, underflowTest, inputType, tapType, earlyOverride)
local cycleCountPixels = 128/8
--local fnaxi = RM.seqMapHandshake( axifn, inputType, tapType, tapValue, inputCount, outputCount+cycleCountPixels, true )
io.output("out/"..filename..".axi.v")
io.write(axifn:toVerilog())
io.close()
--------
end

function guessP(ty, tapType)
  err(tapType==nil or types.isType(tapType),"tapType should be type or nil")

  -- if user didn't pass us type, try to guess it
  -- if array: then it is an array with P=array size
  -- if not array: then it is P=1
  local ty = R.extractData(ty)


--  if tapType~=nil then
--      assert(ty.list[2]==tapType)
--      ty = ty.list[1]
--  end

  local iover, inputP

  if ty:isArray() then
      iover = ty
      inputP = ty:channels()
  else
      iover = ty
      inputP = 1
  end

  return iover, inputP
end

function harnessTop(t)
  err(type(t.inFile)=="string", "expected input filename to be string")
  err(type(t.outFile)=="string", "expected output filename to be string")

  local backend = t.backend
  if backend==nil then backend = arg[1] end
  if backend==nil then backend = "verilog" end

  if(backend=="axi") then
    t.fn = axiRateWrapper(t.fn, t.tapType)
  end

  -- if user explicitly passes us the the info, just trust them...
  local iover, inputP, oover, outputP, fn = t.inType, t.inP, t.outType, t.outP, t.fn

  if iover==nil or inputP==nil then
    iover, inputP = guessP(fn.inputType,t.tapType)
  end

  if oover==nil or outputP==nil then
    oover, outputP = guessP(fn.outputType)
  end

  err(types.isType(iover) and type(inputP)=="number","Error, could not derive input type and P from arguments to harness, type was "..tostring(fn.inputType))
  err(types.isType(oover) and type(outputP)=="number","Error, could not derive output type and P from arguments to harness, type was "..tostring(fn.outputType))

  err( R.isBasic(iover), "Harness error: iover ended up being handshake?")
  err( R.isBasic(oover), "Harness error: oover ended up being handshake?")

  err( (t.inSize[1]*t.inSize[2]) % inputP == 0, "Error, # of input tokens is non-integer, inSize={"..tostring(t.inSize[1])..","..tostring(t.inSize[2]).."}, inputP="..tostring(inputP))
  local inputCount = (t.inSize[1]*t.inSize[2])/inputP
  err( (t.outSize[1]*t.outSize[2]) % outputP == 0, "Error, # of output tokens is non-integer, outSize:"..tostring(t.outSize[1]).."x"..tostring(t.outSize[2]).." outputP:"..tostring(outputP) )

  local outputCountFrac = {t.outSize[1]*t.outSize[2], outputP}

  if R.SDF and iover~=types.null() then
    local expectedOutputCountFrac = {inputCount*fn.sdfOutput[1][1]*fn.sdfInput[1][2],fn.sdfOutput[1][2]*fn.sdfInput[1][1]}

    err( SDFRate.fracEq(expectedOutputCountFrac,outputCountFrac), "Error, SDF predicted output tokens ("..tostring(SDFRate.fracToNumber(expectedOutputCountFrac))..") does not match stated output tokens ("..tostring(SDFRate.fracToNumber(outputCountFrac))..")")
  end

  if backend=="verilog" or backend=="verilator" then
    H.verilogOnly( t.outFile, fn, t.inFile, t.tapType, t.tapValue, iover, inputP, t.inSize[1], t.inSize[2], oover, outputP, t.outSize[1], t.outSize[2], t.simCycles, t.harness )
  elseif(backend=="axi") then
    H.axi( t.outFile, fn, t.inFile, t.tapType, t.tapValue, iover, inputP, t.inSize[1], t.inSize[2], oover, outputP, t.outSize[1], t.outSize[2], t.underflowTest, t.earlyOverride )
  elseif(backend=="isim") then
    H.sim( t.outFile, fn, t.inFile, t.tapType, t.tapValue, iover, inputP, t.inSize[1], t.inSize[2], oover, outputP, t.outSize[1], t.outSize[2], t.underflowTest, t.earlyOverride )
  elseif backend=="terra" then
    H.terraOnly( t.outFile, fn, t.inFile, t.tapType, t.tapValue, iover, inputP, t.inSize[1], t.inSize[2], oover, outputP, t.outSize[1], t.outSize[2], t.underflowTest, t.earlyOverride,  t.doHalfTest, t.simCycles, t.harness, t.ramFile )
  elseif backend=="metadata" then
    local tapValueString = "x"
    local tapBits = 0
    if t.tapType~=nil then
      err(t.tapType:toCPUType()==t.tapType, "NYI - tap type must be a CPU type")
      tapValueString = t.tapType:valueToHex(t.tapValue)
      tapBits = t.tapType:verilogBits()
    end

    local harnessOption = t.harness
    if harnessOption==nil then harnessOption=1 end

    local MD = {inputBitsPerPixel=R.extractData(iover):verilogBits()/(inputP), inputWidth=t.inSize[1], inputHeight=t.inSize[2], outputBitsPerPixel=oover:verilogBits()/(outputP), outputWidth=t.outSize[1], outputHeight=t.outSize[2], inputImage=t.inFile, topModule= fn.name, inputP=inputP, outputP=outputP, simCycles=t.simCycles, tapBits=tapBits, tapValue=tapValueString, harness=harnessOption, ramFile=t.ramFile}
    if t.ramType~=nil then MD.ramBits = t.ramType:verilogBits() end

    writeMetadata("out/"..t.outFile..".metadata.lua", MD)
  else
    print("unknown build target "..arg[1])
    assert(false)
  end

end

return harnessTop
