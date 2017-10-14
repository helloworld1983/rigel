local C = require "examplescommon"
local types = require "types"

return function(t)

  local fn = C.linearPipeline(t,"rigeltop")
  err(fn.inputType==types.null(),"harness: fn should have nil input type")
  err(fn.outputType==types.null(),"harness: fn should have nil output type")
  
  local backend = arg[1]

  if backend=="terra" then

  elseif backend=="verilog" then
    local filename = string.sub(arg[0],1,#arg[0]-4)
    io.output("out/"..filename..".v")
    io.write(fn:toVerilog())
    io.output():close()
  else
    err(false,"unknown build target "..arg[1])
  end

end
