local SOC = require "soc"

return function( fn, fileList )
  local terra dosim() 
    if DARKROOM_VERBOSE then cstdio.printf("Start CPU Sim\n") end
    var m:&Module = [&Module](cstdlib.malloc(sizeof(Module))); 
    m:init()
    m:reset();

    [SOC.frameStart:getTerra()]._1 = true
      
    m:process(nil,nil); 
    if DARKROOM_VERBOSE then m:stats();  end
    m:free()
    cstdlib.free(m) 
  end

  dosim()
end
