local IR = require("ir")
local types = require("types")
local cmath = terralib.includec("math.h")

local fixed = {}

local function getloc()
--  return debug.getinfo(3).source..":"..debug.getinfo(3).currentline
  return debug.traceback()
end

function fixed.isFixedType(ty)
  assert(types.isType(ty))
  if ty:isTuple()==false or ty.list[2]:isOpaque()==false then return false end
  local str = ty.list[2].str:sub(1,5)
  if str=="fixed" then return true end
  return false
end

function fixed.extract(ty)
  if fixed.isFixedType(ty) then
    return ty.list[1]
  end
  return ty
end

function fixed.type( signed, precision, exp )
  assert(type(signed)=="boolean")
  assert(type(precision)=="number")
  assert(type(exp)=="number")
  local name = "fixed"..tonumber(exp)
  if signed then
    return types.tuple{types.int(precision),types.opaque(name)}
  else
    return types.tuple{types.uint(precision),types.opaque(name)}
  end
end

fixedASTFunctions = {}
setmetatable(fixedASTFunctions,{__index=IR.IRFunctions})

fixedASTMT={__index = fixedASTFunctions,
__add=function(l,r)
  err(l:signed()==r:signed(), "+: sign must match")
  err(l:exp()==r:exp(), "+: exp must match")
  local p = math.max(l:precision(),r:precision())+1
  return fixed.new({kind="binop",op="+",inputs={l,r}, type=fixed.type( l:signed(), p, l:exp() ), loc=getloc()})
end, 
__sub=function(l,r) 
  err(l:signed() and r:signed(), "-: must be signed")
  err(l:exp()==r:exp(), "-: exp must match")
  local p = math.max(l:precision(),r:precision())+1
  return fixed.new({kind="binop",op="-",inputs={l,r}, type=fixed.type( true, p, l:exp() ), loc=getloc()})
 end,
__mul=function(l,r) 
  err(l:isSigned() == r:isSigned(), "*: lhs/rhs sign must match but is ("..tostring(l:isSigned())..","..tostring(r:isSigned())..")")
  local exp = l:exp() + r:exp()
  local p = l:precision() + r:precision()
  local ty = fixed.type( l:isSigned(), p, l:exp()+r:exp() )
  return fixed.new({kind="binop",op="*",inputs={l,r}, type=ty, loc=getloc()})
 end,
  __newindex = function(table, key, value)
                    error("Attempt to modify systolic AST node")
                  end}

function fixed.isAST(ast)
  return getmetatable(ast)==fixedASTMT
end

function fixed.new(tab)
  assert(type(tab)=="table")
  assert(type(tab.inputs)=="table")
  assert(#tab.inputs==keycount(tab.inputs))
  assert(type(tab.loc)=="string")
  assert(types.isType(tab.type))
  return setmetatable(tab,fixedASTMT)
end

function fixed.parameter( name, type )
  return fixed.new{kind="parameter",name=name, type=type,inputs={},loc=getloc()}
end

function fixed.constant( value, signed, precision, exp )
  return fixed.new{kind="constant", value=value, type=fixed.type(signed,precision,exp),inputs={},loc=getloc()}
end

function fixedASTFunctions:lift(exponant)
  err(fixed.isFixedType(self.type)==false, "expected non-fixed type: "..self.loc)
  if self.type:isUint() then
    local ty = fixed.type(false,self.type.precision,exponant)
    return fixed.new{kind="lift",type=ty,inputs={self},loc=getloc()}
  else
    assert(false)
  end
end

function fixedASTFunctions:normalize(precision)
  err( fixed.isFixedType(self.type), "expected fixed type: "..self.loc)
  local expshift = self:precision()-precision
  local ty = fixed.type(self:isSigned(), precision, self:exp()+expshift)
  return fixed.new{kind="normalize", type=ty,inputs={self},loc=getloc()}
end

-- throw out information!
function fixedASTFunctions:truncate(precision)
  err( fixed.isFixedType(self.type), "expected fixed type: "..self.loc)
  local ty = fixed.type(self:isSigned(), precision, self:exp())
  return fixed.new{kind="truncate", type=ty,inputs={self},loc=getloc()}
end

-- removes exponant.
-- this may throw out data! if exp<0
function fixedASTFunctions:denormalize()
  err( fixed.isFixedType(self.type), "expected fixed type: "..self.loc)
  local prec = self:precision()+self:exp()
  err( prec>0, "denormalize: this value is purely fractional! all data will be lost")
  return fixed.new{kind="denormalize", type=fixed.type(self:isSigned(), prec, 0),inputs={self},loc=getloc()}
end

function fixedASTFunctions:hist(name)
  assert(type(name)=="string")
  err( fixed.isFixedType(self.type), "expected fixed type: "..self.loc)

  return fixed.new{kind="hist", type=self.type, name=name,inputs={self},loc=getloc()}
end

function fixedASTFunctions:lower()
  err( fixed.isFixedType(self.type), "expected fixed type: "..self.loc)
  err( self:exp()==0, "attempting to lower a value with nonzero exp")
  return fixed.new{kind="lower", type=fixed.extract(self.type),inputs={self},loc=getloc()}
end

function fixedASTFunctions:rshift(N)
  err( fixed.isFixedType(self.type), "expected fixed type: "..self.loc)
  return fixed.new{kind="rshift", type=fixed.type(self:isSigned(), self:precision(), self:exp()-N),shift=N,inputs={self},loc=getloc()}
end

function fixedASTFunctions:isSigned()
  err(fixed.isFixedType(self.type), "expected fixed point type: "..self.loc)
  return self.type.list[1]:isInt()
end

function fixedASTFunctions:exp()
  err(fixed.isFixedType(self.type), "expected fixed point type: "..self.loc)
  local op = self.type.list[2]
  return tonumber(op.str:sub(6))
end

function fixedASTFunctions:precision()
  err(fixed.isFixedType(self.type), "expected fixed point type: "..self.loc)
  return self.type.list[1].precision
end

function fixedASTFunctions:toSystolic()
  local inp
  local res = self:visitEach(
    function( n, args )
      local res
      if n.kind=="parameter" then
        inp = S.parameter(n.name, n.type)
        res = inp
        if fixed.isFixedType(n.type) then
          -- remove wrapper
          res = S.index(res,0)
        end
      elseif n.kind=="binop" then
        local l = S.cast(args[1], fixed.extract(n.type))
        local r = S.cast(args[2], fixed.extract(n.type))
        if n.op=="+" then res = l+r
        elseif n.op=="-" then res = l-r
        elseif n.op=="*" then res = l*r
        else
          assert(false)
        end
        --res = S.ast.new({kind="binop",op=n.op,inputs={args[1],args[2]},loc=n.loc,type=fixed.extract(n.type)})
      elseif n.kind=="rshift" then
        --res = S.rshift(args[1],S.constant( n.shift, fixed.extract(n.inputs[1].type)))
        res = args[1]
      elseif n.kind=="truncate" then
        res = S.cast(args[1],fixed.extract(n.type))
      elseif n.kind=="lift" or n.kind=="lower" then
        -- don't actually do anything: we only add the wrapper at the very end
        res = args[1]
      elseif n.kind=="constant" then
        res = S.constant( n.value, fixed.extract(n.type) )
      elseif n.kind=="normalize" or n.kind=="denormalize" then
        local dp = n.inputs[1]:precision()-n:precision()
        if dp==0 then
          res = args[1]
        elseif dp>0 then
          res = S.rshift(args[1], S.constant(dp, fixed.extract(n.inputs[1].type)) )
          res = S.cast(res,fixed.extract(n.type))
        elseif dp<0 then
          -- make larger
          res = S.cast( args[1], fixed.extract(n.type) )
          res = S.lshift( res, S.constant(-dp, fixed.extract(n.inputs[1].type)) )
        else
          assert(false)
        end
      elseif n.kind=="hist" then
        return args[1] -- cpu only
      else
        print(n.kind)
        assert(false)
      end

      return res
    end)

  if fixed.isFixedType(self.type) then
    local c = S.constant(0, self.type.list[2])
    res = S.tuple{res,c}
  end

  return res, inp
end

local hists = {}
function fixed.printHistograms()
  for k,v in pairs(hists) do v() end
end

function fixedASTFunctions:toTerra()
  local inp
  local res = self:visitEach(
    function( n, args )
      local res
      if n.kind=="parameter" then
        inp = symbol(&n.type:toTerraType(), n.name)
        res = `@inp
        if fixed.isFixedType(n.type) then
          res = `res._0
        end
      elseif n.kind=="binop" then
        local l = `[fixed.extract(n.type):toTerraType()]([args[1]])
        local r = `[fixed.extract(n.type):toTerraType()]([args[2]])
        if n.op=="+" then res = `l+r
        elseif n.op=="-" then res = `l-r
        elseif n.op=="*" then res = `l*r
        else
          print("OP",n.op)
          assert(false)
        end
      elseif n.kind=="lift" or n.kind=="lower" then
        -- noop: we only add wrapper at very end
        res = args[1]
      elseif n.kind=="constant" then
        res = `[fixed.extract(n.type):toTerraType()](n.value)
      elseif n.kind=="rshift" then
        --res = `[fixed.extract(n.type):toTerraType()]([args[1]]>>n.shift)
        res = args[1]
      elseif n.kind=="truncate" then
        -- notice that we don't bother bitmasking here.
        -- "in theory" all of the ops in this language _never_ lose precision. So the ops themselves can't overflow.
        -- We will have extra garbage in the upper bits compared to HW, but as long as we don't intentially examine it,
        -- it should stay in the upper bits and never affect the result.
        res = `[fixed.extract(n.type):toTerraType()]([args[1]])
      elseif n.kind=="normalize" or n.kind=="denormalize" then
        local dp = n.inputs[1]:precision()-n:precision()
        if dp==0 then return args[1]
        elseif dp > 0 then res = `[fixed.extract(n.type):toTerraType()]([args[1]]>>dp)
        else res = `[fixed.extract(n.type):toTerraType()]([args[1]]<<[-dp]) end
      elseif n.kind=="hist" then
        local g = global(uint[n:precision()])
        local gbits = global(uint[n:precision()])
        local terra tfn()
          cstdio.printf("--------------------- %s, exp %d, prec %d\n",n.name, [n:exp()],[n:precision()])
          for i=0,[n:precision()] do
            var r = i+[n:exp()]
            if i==0 then
              -- this always includes 0, and things less than smallest type
              cstdio.printf("0+: %d\n", g[i])
            elseif r<0 then
              cstdio.printf("1/%d: %d\n", i, g[i])
            else
              cstdio.printf("%d-%d: %d\n", [uint](cmath.pow(2,r)), [uint](cmath.pow(2,r+1)-1), g[i])
            end
          end

          cstdio.printf("--------------------- %s BITS\n",n.name)
          for i=0,[n:precision()] do
            cstdio.printf("%d: %d\n", i, gbits[i])
          end
        end
        table.insert(hists, tfn)
        res = quote 
          var v : uint = 0
          if [args[1]]>0 then v = [uint](cmath.floor(cmath.log([args[1]])/cmath.log(2.f))) end
          g[v] = g[v] + 1
          --cstdio.printf("%d %d\n",[args[1]],v)
          ------
          for i=0,[n:precision()] do
            var mask = [fixed.extract(n.type):toTerraType()](1) << i
            if ([args[1]] and mask) > 0 then
              gbits[i] = gbits[i] + 1
            end
          end
          in [args[1]] end
      else
        print(n.kind)
        assert(false)
      end

      assert(terralib.isquote(res) or terralib.issymbol(res))
      return res
    end)

  if fixed.isFixedType(self.type) then
    res = `{res,nil}
  end

  return res, inp
end

function fixedASTFunctions:toDarkroom(name,X)
  assert(type(name)=="string")
  assert(X==nil)

  local out, inp = self:toSystolic()
  local terraout, terrainp = self:toTerra()

  local terra tfn([terrainp], out:&out.type:toTerraType())
    @out = terraout
  end
  tfn:printpretty(true,false)
  return darkroom.lift( name, inp.type, out.type, 1, tfn, inp, out )
end

return fixed