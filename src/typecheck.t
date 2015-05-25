-- NOTE: does typechecking in place! ast must be a table that's going to be thrown away!
return function( ast )
  
  if ast.kind=="constant" then
    err( types.isType(ast.type), "missing type for constant, "..ast.loc)
    ast.constLow_1 = ast.value; ast.constHigh_1 = ast.value
  elseif ast.kind=="unary" then
    ast.expr = inputs["expr"]
    
    if ast.op=="-" then
      if ast.expr.type:isUint() then
        darkroom.warning("You're negating a uint, this is probably not what you want to do!", origast:linenumber(), origast:offset(), origast:filename())
      end
      
      ast.type = ast.expr.type
      if type(ast.expr.constLow_1)=="number" then 
        ast.constLow_1 = -ast.expr.constLow_1; ast.constHigh_1 = -ast.expr.constHigh_1; 
        if ast.constLow_1 > ast.constHigh_1 then ast.constLow_1, ast.constHigh_1 = ast.constHigh_1, ast.constLow_1 end
      end
    elseif ast.op=="floor" or ast.op=="ceil" then
      ast.type = darkroom.type.float(32)
    elseif ast.op=="abs" then
      if ast.expr.type:baseType()==darkroom.type.float(32) then
        ast.type = ast.expr.type
      elseif ast.expr.type:baseType()==darkroom.type.float(64) then
        ast.type = ast.expr.type
      elseif ast.expr.type:baseType():isInt() or ast.expr.type:baseType():isUint() then
        -- obv can't make it any bigger
        ast.type = ast.expr.type
      else
        ast.expr.type:print()
        assert(false)
      end
    elseif ast.op=="not" then
      if ast.expr.type:baseType():isBool() or ast.expr.type:baseType():isInt() or ast.expr.type:baseType():isUint() then
        ast.type = ast.expr.type
      else
        darkroom.error("not only works on bools and integers",origast:linenumber(), origast:offset())
        assert(false)
      end
    elseif ast.op=="sin" or ast.op=="cos" or ast.op=="exp" or ast.op=="arctan" or ast.op=="ln" or ast.op=="sqrt" then
      if ast.expr.type==darkroom.type.float(32) then
        ast.type = darkroom.type.float(32)
      elseif ast.expr.type==darkroom.type.float(64) then
        ast.type = darkroom.type.float(64)
      else
        darkroom.error("sin, cos, arctan, ln and exp only work on floating point types, not "..ast.expr.type:str(), origast:linenumber(), origast:offset(), origast:filename() )
      end
    elseif ast.op=="arrayAnd" then
      if ast.expr.type:isArray() and ast.expr.type:arrayOver():isBool() then
        ast.type = darkroom.type.bool()
      else
        darkroom.error("vectorAnd only works on arrays of bools", origast:linenumber(), origast:offset(), origast:filename() )
      end
    elseif ast.op=="print" then
      ast.type = ast.expr.type
    else
      print(ast.op)
      assert(false)
    end
    
  elseif ast.kind=="binop" then
    local lhs = ast.inputs[1]
    local rhs = ast.inputs[2]
    
    assert(lhs.type~=nil)
    assert(rhs.type~=nil)
    
    if type(lhs.constLow_1)=="number" and type(rhs.constLow_1)=="number" then
      local function applyop(lhslow, lhshigh, rhslow, rhshigh, op)
        local a = op(lhslow,rhslow)
        local b = op(lhslow,rhshigh)
        local c = op(lhshigh,rhslow)
        local d = op(lhshigh,rhshigh)
        return math.min(a,b,c,d), math.max(a,b,c,d)
      end

      if ast.op=="+" then
        ast.constLow_1, ast.constHigh_1 = applyop( lhs.constLow_1, lhs.constHigh_1, rhs.constLow_1, rhs.constHigh_1, function(l,r) return l+r end)
      elseif ast.op=="-" then
        ast.constLow_1, ast.constHigh_1 = applyop( lhs.constLow_1, lhs.constHigh_1, rhs.constLow_1, rhs.constHigh_1, function(l,r) return l-r end)
      elseif ast.op=="*" then
        ast.constLow_1, ast.constHigh_1 = applyop( lhs.constLow_1, lhs.constHigh_1, rhs.constLow_1, rhs.constHigh_1, function(l,r) return l*r end)
      elseif ast.op=="/" then
        ast.constLow_1, ast.constHigh_1 = applyop( lhs.constLow_1, lhs.constHigh_1, rhs.constLow_1, rhs.constHigh_1, function(l,r) return l/r end)
      end
    end

    local thistype, lhscast, rhscast = types.meet( lhs.type, rhs.type, ast.op, ast )
    
    if thistype==nil then
      darkroom.error("Type error, inputs to "..ast.op,origast:linenumber(), origast:offset(), origast:filename())
    end
    
    if lhs.type~=lhscast then lhs = newNodeFn({kind="cast",expr=lhs,type=lhscast}):copyMetadataFrom(origast) end
    if rhs.type~=rhscast then rhs = newNodeFn({kind="cast",expr=rhs,type=rhscast}):copyMetadataFrom(origast) end
    
    ast.type = thistype
    ast.inputs = {lhs,rhs}
    
  elseif ast.kind=="position" then
    -- if position is still in the tree at this point, it means it's being used in an expression somewhere
    -- choose a reasonable type...
    ast.type=darkroom.type.int(32)
    ast.scaleN1 = 0; ast.scaleN2 = 0; ast.scaleD1 = 0; ast.scaleD2 = 0; -- meet with any rate
  elseif ast.kind=="select" or ast.kind=="vectorSelect" then
    local cond = inputs["cond"]
    local a = inputs["a"]
    local b = inputs["b"]

    if ast.kind=="vectorSelect" then
      if cond.type:arrayOver()~=darkroom.type.bool() then
        print("IB",cond.type:arrayOver())
        darkroom.error("Error, condition of vectorSelect must be array of booleans. ", origast:linenumber(), origast:offset(), origast:filename() )
        return nil
      end

      if cond.type:isArray()==false or
        a.type:isArray()==false or
        b.type:isArray()==false or
        a.type:arrayLength()~=b.type:arrayLength() or
        cond.type:arrayLength()~=a.type:arrayLength() then
        darkroom.error("Error, all arguments to vectorSelect must be arrays of the same length", origast:linenumber(), origast:offset(), origast:filename() )
        return nil            
      end
    else
      if cond.type ~= darkroom.type.bool() then
        darkroom.error("Error, condition of select must be scalar boolean. Use vectorSelect",origast:linenumber(),origast:offset(),origast:filename())
        return nil
      end

      if a.type:isArray()~=b.type:isArray() then
        darkroom.error("Error, if any results of select are arrays, all results must be arrays",origast:linenumber(),origast:offset())
        return nil
      end
      
      if a.type:isArray() and
        a.type:arrayLength()~=b.type:arrayLength() then
        darkroom.error("Error, array arguments to select must be the same length", origast:linenumber(), origast:offset(), origast:filename() )
        return nil
      end
    end

    local thistype, lhscast, rhscast =  darkroom.type.meet(a.type,b.type, ast.kind, origast)

    if a.type~=lhscast then a = newNodeFn({kind="cast",expr=a,type=lhscast}):copyMetadataFrom(origast) end
    if b.type~=rhscast then b = newNodeFn({kind="cast",expr=b,type=rhscast}):copyMetadataFrom(origast) end
    
    ast.type = thistype
    ast.cond = cond
    ast.a = a
    ast.b = b
    
  elseif ast.kind=="index" then
    local expr = ast.inputs[1]
    
    if expr.type:isArray()==false and expr.type:isUint()==false and expr.type:isInt()==false then
      darkroom.error("Error, you can only index into an array type! Type is "..tostring(expr.type),origast:linenumber(),origast:offset(), origast:filename())
      os.exit()
    end
    
    if expr.type:isUint() or expr.type:isInt() then 
      local maxIdx = expr.type.precision 
      err( ast.idy~=nil, "idy should be nil")
      err( ast.idx<maxIdx, "idx is out of bounds")
    elseif expr.type:isArray() then
      err( ast.idx < (expr.type:arrayLength())[1], "idx is out of bounds, "..tostring(ast.idx).." but should be "..tostring((expr.type:arrayLength())[1]))
      err( ast.idy==nil or ast.idy < (expr.type:arrayLength())[2], "idy is out of bounds")
    else
      assert(false)
    end
    
    if expr.type:isUint() or expr.type:isInt() then
      ast.type = darkroom.type.bool()
    else
      ast.type = expr.type:arrayOver()
    end
  elseif ast.kind=="transform" then
    ast.expr = inputs["expr"]
    
    -- this just gets the value of the thing we're translating
    ast.type = ast.expr.type
    
    local i=1
    while ast["arg"..i] do
      ast["arg"..i] = inputs["arg"..i] 
      i=i+1
    end
    
    -- now make the new transformBaked node out of this
    local newtrans = {kind="transformBaked",expr=ast.expr,type=ast.expr.type}
    
    local noTransform = true

    local i=1
    while ast["arg"..i] do
      -- if we got here we can assume it's valid
      local translate, multN, multD = darkroom.typedAST.synthOffset( inputs["arg"..i], inputs["zeroedarg"..i], darkroom.dimToCoord[i])

      if translate==nil then
        darkroom.error("Error, non-stencil access pattern", origast:linenumber(), origast:offset(), origast:filename())
      end

      assert(type(translate.constLow_1)=="number")
      assert(type(translate.constHigh_1)=="number")
      assert(translate.type:isInt() or translate.type:isUint())

      newtrans["translate"..i]=translate
      newtrans["scaleN"..i]=multD*ast.expr["scaleN"..i]
      newtrans["scaleD"..i]=multN*ast.expr["scaleD"..i]

      if translate~=0 or multD~=1 or multN~=1 then noTransform = false end
      i=i+1
    end
    
    -- at least 2 arguments must be specified. 
    -- the parser was supposed to guarantee this.
    assert(i>2)

    if noTransform then -- eliminate unnecessary transforms early
      ast=ast.expr:shallowcopy()
    else
      ast=newtrans
    end

  elseif ast.kind=="tuple" then
    local ty = map(ast.inputs, function(t) return t.type end )
    ast.type = types.tuple(ty)
  elseif ast.kind=="array" then
    
    local cnt = 1
    while ast["expr"..cnt] do
      ast["expr"..cnt] = inputs["expr"..cnt]
      ast["constLow_"..cnt] = inputs["expr"..cnt].constLow_1
      ast["constHigh_"..cnt] = inputs["expr"..cnt].constHigh_1
      cnt = cnt + 1
    end
    
    local mtype = ast.expr1.type
    local atype, btype
    
    if mtype:isArray() then
      darkroom.error("You can't have nested arrays (index 0 of vector)", origast:linenumber(), origast:offset(), origast:filename() )
    end
    
    local cnt = 2
    while ast["expr"..cnt] do
      if ast["expr"..cnt].type:isArray() then
        darkroom.error("You can't have nested arrays (index "..(i-1).." of vector)")
      end
      
      mtype, atype, btype = darkroom.type.meet( mtype, ast["expr"..cnt].type, "array", origast )
      
      if mtype==nil then
        darkroom.error("meet error")      
      end
      
      -- our type system should have guaranteed this...
      assert(mtype==atype)
      assert(mtype==btype)
      
      cnt = cnt + 1
    end
    
    -- now we've figured out what the type of the array should be
    
    -- may need to insert some casts
    local cnt = 1
    while ast["expr"..cnt] do
      -- meet should have failed if this isn't possible...
      local from = ast["expr"..cnt].type

      if from~=mtype then
        if darkroom.type.checkImplicitCast(from, mtype,origast)==false then
          darkroom.error("Error, can't implicitly cast "..from:str().." to "..mtype:str(), origast:linenumber(), origast:offset())
        end
        
        ast["expr"..cnt] = newNodeFn({kind="cast",expr=ast["expr"..cnt], type=mtype}):copyMetadataFrom(ast["expr"..cnt])
      end

      cnt = cnt + 1
    end
    
    local arraySize = cnt - 1
    ast.type = darkroom.type.array(mtype, arraySize)
    

  elseif ast.kind=="cast" then
    if types.checkExplicitCast( ast.inputs[1].type, ast.type, ast)==false then
      error("Casting from "..tostring(ast.inputs[1].type).." to "..tostring(ast.type).." isn't allowed!")
    end
  else
    error("Internal error, typechecking for "..ast.kind.." isn't implemented! "..ast.loc)
    return nil
  end

  if types.isType(ast.type)==false then print(ast.kind) end
  assert(types.isType(ast.type))
  if type(ast.constLow_1)=="number" then assert(ast.constLow_1<=ast.constHigh_1) end

  return ast
end