(* Copyright (C) 1997-1999 NEC Research Institute.
 * Please see the file LICENSE for license information.
 *)
functor Useless (S: USELESS_STRUCTS): USELESS = 
struct

open S
type int = Int.t
   
(* useless thing elimination
 *  remove components of tuples that are constants (use unification)
 *  remove function arguments that are constants
 *  build some kind of dependence graph where 
 *    - a value of ground type is useful if it is an arg to a primitive
 *    - a tuple is useful if it contains a useful component
 *    - a conapp is useful if it contains a useful component
 *                            or is used in a case
 *
 * If a useful tuple is coerced to another useful tuple,
 *   then all of their components must agree (exactly).
 * It is trivial to convert a useful value to a useless one.
 *
 * It is also trivial to convert a useful tuple to one of its
 *  useful components -- but this seems hard
 *)

(* Suppose that you have a ref/array/vector that is useful, but the
 * components aren't -- then the components are converted to type unit, and
 * any primapp args must be as well.
 *)

(* Weirdness with raise/handle.
 * There must be a uniform "calling convention" for raise and handle.
 * Hence, just because some of a handlers args are useless, that doesn't mean
 * that it can drop them, since they may be useful to another handler, and
 * hence every raise will pass them along.  The problem is that it is not
 * possible to tell solely from looking at a function declaration whether it is
 * a handler or not, and in fact, there is nothing preventing a jump being used
 * in both ways.  So, maybe the right thing is for the handler wrapper to
 * do
 * Another solution would be to unify all handler args.
 *)
   
structure Value =
   struct
      structure Set = DisjointSet

      structure Exists =
	 struct
	    structure L = TwoPointLattice (val bottom = "not exists"
					   val top = "exists")
	    open L
	    val mustExist = makeTop
	    val doesExist = isTop
	 end

      structure Useful =
	 struct
	    structure L = TwoPointLattice (val bottom = "useless"
					   val top = "useful")
	    open L
	    val makeUseful = makeTop
	    val isUseful = isTop
	 end
      
      datatype t =
	 T of {
	       ty: Type.t,
	       new: (Type.t * bool) option ref,
	       value: value
	       } Set.t
      and value =
	 Array of {useful: Useful.t,
		   length: t,
		   elt: slot}
	| Ground of Useful.t
	| Ref of {useful: Useful.t,
		  arg: slot}
	| Tuple of slot vector
	| Vector of {length: t,
		     elt: slot}
      withtype slot = t * Exists.t

      local
	 fun make sel (T s) = sel (Set.value s)
      in
	 val value = make #value
	 val ty = make #ty
      end
   
      local
	 open Layout
      in
	 fun layout (T s) =
	    let val {value, ...} = Set.value s
	    in case value of
	       Ground g => seq [str "ground ", Useful.layout g]
	     | Tuple vs => Vector.layout layoutSlot vs
	     | Ref {arg, useful, ...} =>
		  seq [str "ref ",
		       record [("useful", Useful.layout useful),
			       ("slot", layoutSlot arg)]]
	     | Vector {elt, length} =>
		  seq [str "vector", tuple [layout length, layoutSlot elt]]
	     | Array {elt, length, ...} =>
		  seq [str "array", tuple [layout length, layoutSlot elt]]
	    end
	 and layoutSlot (v, e) =
	    tuple [Exists.layout e, layout v]
      end

      fun unify (T s, T s') =
	 if Set.equals (s, s')
	    then ()
	 else let val {value = v, ...} = Set.value s
		  val {value = v', ...} = Set.value s'
	      in Set.union (s, s')
		 ; (case (v, v') of
		       (Ground g, Ground g') => Useful.== (g, g')
		     | (Tuple vs, Tuple vs') =>
			  Vector.foreach2 (vs, vs', unifySlot)
		     | (Ref {useful = u, arg = a},
			Ref {useful = u', arg = a'}) =>
			  (Useful.== (u, u'); unifySlot (a, a'))
			| (Array {length = n, elt = e, ...},
			   Array {length = n', elt = e', ...}) =>
			  (unify (n, n'); unifySlot (e, e'))
			| (Vector {length = n, elt = e},
			   Vector {length = n', elt = e'}) =>
			  (unify (n, n'); unifySlot (e, e'))
			 | _ => Error.bug "strange unify")
	      end
      and unifySlot ((v, e), (v', e')) = (unify (v, v'); Exists.== (e, e'))
	 
      fun coerce {from = from as T sfrom, to = to as T sto}: unit =
	 if Set.equals (sfrom, sto)
	    then ()
	 else
	    let
	       fun coerceSlot ((v, e), (v', e')) =
		  (coerce {from = v, to = v'}
		   ; Exists.== (e, e'))
	    in case (value from, value to) of
	       (Ground to, Ground from) => Useful.<= (from, to)
	     | (Tuple vs, Tuple vs') =>
		  Vector.foreach2 (vs, vs', coerceSlot)
	     | (Ref _, Ref _) => unify (from, to)
	     | (Array _, Array _) => unify (from, to)
	     | (Vector {length = n, elt = e}, Vector {length = n', elt = e'}) =>
		  (coerce {from = n, to = n'}
		   ; coerceSlot (e, e'))
	     | _ => Error.bug "strange coerce"
	    end

      val coerce =
	 Trace.trace ("Useless.coerce",
		      fn {from, to} => let open Layout
				       in record [("from", layout from),
						  ("to", layout to)]
				       end,
				    Unit.layout) coerce

      fun coerces {from, to} =
	 Vector.foreach2 (from, to, fn (from, to) =>
			 coerce {from = from, to = to})

      fun foreach (v: t, f: Useful.t -> unit): unit  =
	 let
	    fun loop (v: t): unit =
	       case value v of
		  Ground u => f u
		| Vector {length, elt} => (loop length; slot elt)
		| Array {length, elt, useful} =>
		     (f useful; loop length; slot elt)
		| Ref {useful, arg} => (f useful; slot arg)
		| Tuple vs => Vector.foreach (vs, slot)
	    and slot (v, _) = loop v
	 in loop v
	 end
      
      (* Coerce every ground value in v to u. *)
      fun deepCoerce (v: t, u: Useful.t): unit =
	 foreach (v, fn u' => Useful.<= (u', u))

      val deepCoerce =
	 Trace.trace2 ("Useless.deepCoerce", layout, Useful.layout, Unit.layout)
	 deepCoerce
	 
      fun isGround (v: t): bool =
	 case value v of
	    Ground g => true
	  | _ => false
	       
      fun deground (v: t): Useful.t =
	 case value v of
	    Ground g => g
	  | _ => Error.bug "deground"

      fun someUseful (v: t): Useful.t option =
	 case value v of
	    Ground u => SOME u
	  | Array {useful = u, ...} => SOME u
	  | Ref {useful = u, ...} => SOME u
	  | Tuple slots => Vector.peekMap (slots, someUseful o #1)
	  | Vector {length, ...} => SOME (deground length)

      fun allOrNothing (v: t): Useful.t option =
	 case someUseful v of
	    NONE => NONE
	  | SOME u => (foreach (v, fn u' => Useful.== (u, u'))
		       ; SOME u)

      fun fromType (t: Type.t): t =
	 let
	    fun loop (t: Type.t, es: Exists.t list): t =
	       let
		  fun useful () =
		     let val u = Useful.new ()
		     in Useful.addHandler
			(u, fn () => List.foreach (es, Exists.mustExist))
			; u
		     end
		  fun slot t =
		     let val e = Exists.new ()
		     in (loop (t, e :: es), e)
		     end
		  val loop = fn t => loop (t, es)
		  val value =
		     case Type.dest t of
			Type.Ref t => Ref {useful = useful (),
					   arg = slot t}
		      | Type.Array t =>
			   let val elt as (_, e) = slot t
			      val length = loop Type.int
			   in Exists.addHandler
			      (e, fn () => Useful.makeUseful (deground length))
			      ; Array {useful = useful (),
				       length = length,
				       elt = elt}
			   end
		      | Type.Vector t => Vector {length = loop Type.int,
						 elt = slot t}
		      | Type.Tuple ts => Tuple (Vector.map (ts, slot))
		      | _ => Ground (useful ())
	       in T (Set.singleton {ty = t,
				    new = ref NONE,
				    value = value})
	       end
	 in loop (t, [])
	 end

      val const = fromType o Type.ofConst

      fun detupleSlots (v: t): slot vector =
	 case value v of
	    Tuple ss => ss
	  | _ => Error.bug "detuple"
      fun detuple v = Vector.map (detupleSlots v, #1)
      fun tuple (vs: t vector): t =
	 let
	    val t = Type.tuple (Vector.map (vs, ty))
	    val v = fromType t
	 in Vector.foreach2 (vs, detuple v, fn (v, v') =>
			     coerce {from = v, to = v'})
	    ; v
	 end
      val unit = tuple (Vector.new0 ())
      fun select {tuple, offset, resultType} =
	 let val v = fromType resultType
	 in coerce {from = Vector.sub (detuple tuple, offset), to = v}
	    ; v
	 end
      local
	 fun make (err, sel) v =
	    case value v of
	       Vector fs => sel fs
	     | _ => Error.bug err
      in val devector = make ("devector", #1 o #elt)
	 val vectorLength = make ("vectorLength", #length)
      end
      local
	 fun make (err, sel) v =
	    case value v of
	       Array fs => sel fs
	     | _ => Error.bug err
      in val dearray: t -> t = make ("dearray", #1 o #elt)
	 val arrayLength = make ("arrayLength", #length)
	 val arrayUseful = make ("arrayUseful", #useful)
      end

      fun deref (r: t): t =
	 case value r of
	    Ref {arg, ...} => #1 arg
	  | _ => Error.bug "deref"

      fun newType (v: t): Type.t = #1 (getNew v)
      and isUseful (v: t): bool = #2 (getNew v)
      and getNew (T s): Type.t * bool =
	 let val {value, ty, new, ...} = Set.value s
	 in case !new of
	    SOME z => z
	  | NONE =>
	       let 
		  fun slot (arg: t, e: Exists.t) =
		     let val (t, b) = getNew arg
		     in (if Exists.doesExist e then t else Type.unit, b)
		     end
		  fun wrap ((t, b), f) = (f t, b)
		  fun or ((t, b), b') = (t, b orelse b')
		  fun maybe (u: Useful.t, s: slot, make: Type.t -> Type.t) =
		     wrap (or (slot s, Useful.isUseful u), make)
		  val z =
		     case value of
			Ground u => (ty, Useful.isUseful u)
		      | Ref {useful, arg, ...} => maybe (useful, arg, Type.reff)
		      | Array {useful, elt, length, ...} =>
			   or (wrap (slot elt, Type.array),
			       Useful.isUseful useful orelse isUseful length)
		      | Vector {elt, length, ...} =>
			   or (wrap (slot elt, Type.vector), isUseful length)
		      | Tuple vs =>
			   let
			      val (v, b) =
				 Vector.mapAndFold
				 (vs, false, fn ((v, e), useful) =>
				  let
				     val (t, u) = getNew v
				     val t =
					if Exists.doesExist e
					   then SOME t
					else NONE
				  in (t, u orelse useful)
				  end)
			      val v = Vector.keepAllMap (v, fn t => t)
			   in (Type.tuple v, b)
			   end
	       in new := SOME z; z
	       end
	 end

      val getNew =
	 Trace.trace ("getNew", layout, Layout.tuple2 (Type.layout, Bool.layout))
	 getNew

      val newType = Trace.trace ("newType", layout, Type.layout) newType
	 
      fun newTypes (vs: t vector): Type.t vector =
	 Vector.keepAllMap (vs, fn v =>
			    let val (t, b) = getNew v
			    in if b then SOME t else NONE
			    end)
   end

structure Exists = Value.Exists

fun useless (program as Program.T {datatypes, globals, functions, main}) =
   let
      val {get = conInfo: Con.t -> {args: Value.t vector,
				    argTypes: Type.t vector,
				    value: unit -> Value.t},
	   set = setConInfo, ...} =
	 Property.getSetOnce (Con.plist, Property.initRaise ("arg", Con.layout))
      val {get = tyconInfo: Tycon.t -> {useful: bool ref,
					cons: Con.t vector},
	   set = setTyconInfo, ...} =
	 Property.getSetOnce (Tycon.plist,
			      Property.initRaise ("cons", Tycon.layout))
      local open Value
      in
	 val _ =
	    Vector.foreach
	    (datatypes, fn {tycon, cons} =>
	     let
		val _ =
		   setTyconInfo (tycon, {useful = ref false,
					 cons = Vector.map (cons, #con)})
		fun value () = fromType (Type.con (tycon, Vector.new0 ()))
	     in Vector.foreach
		(cons, fn {con, args} =>
		 setConInfo (con, {value = value,
				   argTypes = args,
				   args = Vector.map (args, fromType)}))
	     end)
	 val conArgs = #args o conInfo
	 fun conApp {con: Con.t,
		     args: Value.t vector} =
	    let val {args = args', value, ...} = conInfo con
	    in coerces {from = args, to = args'}
	       ; value ()
	    end
	 fun filter (v: Value.t, con: Con.t, to: Value.t vector): unit =
	    case value v of
	       Ground g =>
		  (Useful.makeUseful g
		   ; coerces {from = conArgs con, to = to})
	     | _ => Error.bug "filter of non ground"
	 fun filterGround (v: Value.t): unit =
	    case value v of
	       Ground g => Useful.makeUseful g
	     | _ => Error.bug "filterInt of non ground"
	 val filter =
	    Trace.trace3 ("Useless.filter",
			  Value.layout,
			  Con.layout,
			  Vector.layout Value.layout,
			  Unit.layout)
	    filter
	 (* This is used for primitive args, since we have no idea what
	  * components of its args that a primitive will look at.
	  *)
	 fun deepMakeUseful v =
	    let val slot = deepMakeUseful o #1
	    in case value v of
	       Ground u =>
		  (Useful.makeUseful u
		   (* Make all constructor args of this tycon useful *)
		   ; (case Type.dest (ty v) of
			 Type.Datatype tycon =>
			    let val {useful, cons} = tyconInfo tycon
			    in if !useful
				  then ()
			       else (useful := true
				     ; Vector.foreach (cons, fn con =>
						       Vector.foreach
						       (#args (conInfo con),
							deepMakeUseful)))
			    end
		       | _ => ()))
	     | Tuple vs => Vector.foreach (vs, slot)
	     | Ref {useful, arg} => (Useful.makeUseful useful; slot arg)
	     | Vector {length, elt} => (deepMakeUseful length; slot elt)
	     | Array {useful, length, elt} => (Useful.makeUseful useful
					       ; deepMakeUseful length
					       ; slot elt)
	    end

	 type value = t

	 fun primApp {prim, targs, args: t vector, resultVar, resultType} =
	    let
	       val result = fromType resultType
	       fun return v = coerce {from = v, to = result}
	       infix dependsOn
	       fun v1 dependsOn v2 = deepCoerce (v2, deground v1)
	       fun arg i = Vector.sub (args, i)
	       fun sub () =
		  (arg 1 dependsOn result
		   ; return (dearray (arg 0)))
	       fun update () =
		  let
		     val a = dearray (arg 0)
		  in arg 1 dependsOn a
		     ; coerce {from = arg 2, to = a}
		  end
	       datatype z = datatype Prim.Name.t
	       val _ =
		  case Prim.name prim of
		     Array_array =>
			coerce {from = arg 0, to = arrayLength result}
		   | Array_array0 => ()
		   | Array_length => return (arrayLength (arg 0))
		   | Array_sub => sub ()
		   | Array_update => update ()
		   | MLton_equal => Vector.foreach (args, deepMakeUseful)
		   | Ref_assign => coerce {from = arg 1, to = deref (arg 0)}
		   | Ref_deref => return (deref (arg 0))
		   | Ref_ref => coerce {from = arg 0, to = deref result}
		   | Vector_fromArray =>
			(case (value (arg 0), value result) of
			    (Array {length = l, elt = e, ...},
			     Vector {length = l', elt = e', ...}) =>
			    (unify (l, l'); unifySlot (e, e'))
			   | _ => Error.bug "strange Vector_fromArray")
		   | Vector_length => return (vectorLength (arg 0))
		   | Vector_sub => (arg 1 dependsOn result
				    ; return (devector (arg 0)))
		   | Word8Array_subWord => sub ()
		   | Word8Array_updateWord => update ()
		   | _ =>
			let (* allOrNothing so the type doesn't change *)
			   val res = allOrNothing result
			in if Prim.maySideEffect prim
			      then Vector.foreach (args, deepMakeUseful)
			   else
			      Vector.foreach (args, fn a =>
					      case (allOrNothing a, res) of
						 (NONE, _) => ()
					       | (SOME u, SOME u') =>
						    Useful.<= (u', u)
					       | _ => ())
			end
	    in
	       result
	    end
	 val primApp =
	    Trace.trace
	    ("Useless.primApp",
	     fn {prim, args, ...} =>
	     Layout.seq [Prim.layout prim,
			 Vector.layout layout args],
	     layout)
	    primApp
      end
      val {value, func, jump, exnVals, ...} =
	 analyze {
		  coerce = Value.coerce,
		  conApp = conApp,
		  const = Value.const,
		  copy = Value.fromType o Value.ty,
		  filter = filter,
		  filterChar = filterGround,
		  filterInt = filterGround,
		  filterWord = filterGround,
		  filterWord8 = filterGround,
		  fromType = Value.fromType,
		  layout = Value.layout,
		  primApp = primApp,
		  program = program,
		  select = Value.select,
		  tuple = Value.tuple,
		  useFromTypeOnBinds = true
		  }
      open Dec PrimExp Transfer
      (* Unify all handler args so that raise/handle has a consistent calling
       * convention.
       *)
      val exnVals = fn () => (case exnVals of
				 NONE => Error.bug "no exnVals"
			       | SOME vs => vs)
      val _ =
	 Vector.foreach
	 (functions, fn Function.T {body, ...} =>
	  Exp.foreach'
	  (body,
	   {handleTransfer = fn _ => (),
	    handleDec = fn HandlerPush j => Vector.foreach2 (jump j, exnVals (),
							    Value.unify)
	  | _ => ()}))
      val _ =
	 Control.diagnostics
	 (fn display =>
	  let open Layout
	  in
	     Vector.foreach
	     (datatypes, fn {tycon, cons} =>
	      display
	      (align
	       [Tycon.layout tycon,
		indent (Vector.layout
			(fn {con, ...} =>
			 seq [Con.layout con, str " ",
			      Vector.layout Value.layout (conArgs con)])
			cons,
			2)]))
	     ; (Program.foreachVar
		(program, fn (x, _) => display (seq [Var.layout x,
						     str " ",
						     Value.layout (value x)])))
	  end)
      val varExists = Value.isUseful o value
      val unitVar = Var.newString "unit"
      val bogusGlobals: {var: Var.t, ty: Type.t, exp: PrimExp.t} list ref =
	 ref []
      val {get = bogus, ...} =
	 Property.get
	 (Type.plist,
	  Property.initFun
	  (fn ty =>
	   let val var = Var.newString "bogus"
	   in List.push (bogusGlobals,
			 {var = var, ty = ty,
			  exp = PrimApp {prim = Prim.bogus,
					 info = PrimInfo.None,
					 targs = Vector.new1 ty,
					 args = Vector.new0 ()}})
	      ; var
	   end))
      fun keepUseful (xs: Var.t vector, vs: Value.t vector): Var.t vector =
	 Vector.keepAllMap2
	 (xs, vs, fn (x, v) =>
	  let val (t, b) = Value.getNew v
	  in if b
		then SOME (if varExists x then x else bogus t)
	     else NONE
	  end)
      fun keepUsefulArgs (xts: (Var.t * Type.t) vector) =
	 Vector.keepAllMap
	 (xts, fn (x, _) =>
	  let val (t, b) = Value.getNew (value x)
	  in if b
		then SOME (x, t)
	     else NONE
	  end)
      val keepUsefulArgs =
	 Trace.trace ("keepUsefulArgs",
		      Vector.layout (Layout.tuple2 (Var.layout, Type.layout)),
		      Vector.layout (Layout.tuple2 (Var.layout, Type.layout)))
	 keepUsefulArgs
      fun dropUseless (vs: Value.t vector,
		       vs': Value.t vector,
		       makeTrans: Var.t vector -> Transfer.t): Jump.t * Dec.t =
	 let
	    val j = Jump.newNoname ()
	    val (formals, actuals) =
	       Vector.unzip
	       (Vector.map2
		(vs, vs', fn (v, v') =>
		 if Value.isUseful v
		   then let val x = Var.newNoname ()
			in (SOME (x, Value.newType v),
			    if Value.isUseful v'
			       then SOME x
			    else NONE)
			end
		 else (NONE, NONE)))
	    val body =
	       Exp.make {decs = [],
			 transfer = makeTrans (Vector.keepAllSome actuals)}
	 in (j, Fun {name = j,
		     args = Vector.keepAllSome formals,
		     body = body})
	 end
      (* Returns true if the component is the only component of the tuple
       * that exists.
       *)
      fun newOffset (bs: bool vector, n: int): int * bool =
	 let
	    val len = Vector.length bs
	    fun loop (pos, n, i) =
	       let val b = Vector.sub (bs, pos)
	       in if n = 0
		     then (i, (i = 0
			       andalso not (Int.exists (pos + 1, len, fn i =>
							Vector.sub (bs, i)))))
		  else loop (pos + 1, n - 1, if b then i + 1 else i)
	       end
	 in loop (0, n, 0)
	 end
      fun loopPrimExp (e: PrimExp.t, resultType: Type.t, resultValue: Value.t) =
	 case e of
	    Const _ => e
	  | Var _ => e
	  | Tuple xs =>
	       let
		  val slots = Value.detupleSlots resultValue
		  val xs =
		     Vector.keepAllMap2
		     (xs, slots, fn (x, (v, e)) =>
		      if Exists.doesExist e
			 then SOME (if varExists x then x
				    else bogus (Value.newType v))
		      else NONE)
	       in
		  if 1 = Vector.length xs
		     then Var (Vector.sub (xs, 0))
		  else Tuple xs
	       end
	  | Select {tuple, offset} =>
	       let
		  val (offset, isOne) =
		     newOffset (Vector.map (Value.detupleSlots (value tuple),
					   Exists.doesExist o #2),
				offset)
	       in if isOne
		     then Var tuple
		  else Select {tuple = tuple,
			       offset = offset}
	       end
	  | ConApp {con, args} =>
	       ConApp {con = con,
		       args = keepUseful (args, conArgs con)}
	  | PrimApp {prim, info = info, args, ...} => 
	       let
		  val (args, argTypes) =
		     Vector.unzip
		     (Vector.map (args, fn x =>
				 let val (t, b) = Value.getNew (value x)
				 in if b then (x, t)
				    else (unitVar, Type.unit)
				 end))
	       in PrimApp
		  {prim = prim,
		   info = info,
		   args = args,
		   targs = Prim.extractTargs {prim = prim,
					      args = argTypes,
					      result = resultType,
					      dearray = Type.dearray,
					      dearrow = Type.dearrow,
					      deref = Type.deref,
					      devector = Type.devector}}
	       end
      val loopPrimExp =
 	 Trace.trace3 ("Useless.loopPrimExp",
		       PrimExp.layout, Layout.ignore, Layout.ignore,
		       PrimExp.layout) loopPrimExp
      fun loopBind {var, exp, ty} =
	 let
	    val v = value var
	    fun yes ty =
	       SOME {var = var, ty = ty, exp = loopPrimExp (exp, ty, v)}
	    val (t, b) = Value.getNew v
	 in
	    if b
	       then yes t
	    else
	       case exp of
		  PrimApp {prim, args, ...} =>
		     if Prim.maySideEffect prim
			andalso let
				   fun arg i = Vector.sub (args, i)
				   fun array () =
				      Value.isUseful
				      (Value.dearray (value (arg 0)))
				   datatype z = datatype Prim.Name.t
				in case Prim.name prim of
				   Array_update => array ()
				 | Ref_assign =>
				      Value.isUseful
				      (Value.deref (value (arg 0)))
				 | Word8Array_updateWord => array ()
				 | _ => true
				end
			then yes t
		     else NONE
				 | _ => NONE
	 end
      val loopBind =
	 Trace.trace ("Useless.loopBind", layoutBind, Option.layout layoutBind)
	 loopBind
      fun agree (vs: Value.t vector, vs': Value.t vector): bool =
	 Vector.forall2 (vs, vs', fn (v, v') =>
			not (Value.isUseful v) orelse Value.isUseful v')
      fun loopTransfer (t: Transfer.t, returns: Value.t vector)
	 : Dec.t list * Transfer.t =
	 case t of
	    (* May need to insert a wrapper around the cont
	     * to translate between the expected returns of
	     * the function and the useful args of the func.
	     * Yucko! - what about tail calls?
	     * It's entirely possible that my returns are less useful
	     * than my callees, in which case I need I need to drop
	     * some of them.
	     *)
	    Call {func = f, args, cont} =>
	       let
		  val {args = fargs, returns = freturns} = func f
		  fun wrapper (vs: Value.t vector,
			       cont: Jump.t option,
			       makeTrans: Var.t vector -> Transfer.t) =
		     if agree (freturns, vs)
			then ([], cont)
		     else
			let
			   val (j, d) =
			      dropUseless (freturns, vs, makeTrans)
			in ([d], SOME j)
			end
		  val (decs, cont) =
		     case cont of
			NONE => wrapper (returns, NONE, Return)
		      | SOME c =>
			   wrapper (jump c, SOME c,
				    fn args => Jump {dst = c, args = args})
	       in (decs,
		   Call {func = f, cont = cont,
			 args = keepUseful (args, fargs)})
	       end
	  | Case (r as {test, cases, default, cause}) =>
	       let
		  (* The test may be useless if there are no cases or default,
		   * thus we must eliminate the case.
		   *)
		  fun doit v =
		     case (Vector.length v, default) of
			(0, NONE) => ([], Bug)
		      | _ => ([], Case r)
		  datatype z = datatype Cases.t
	       in case cases of
		  Char l => doit l
		| Int l => doit l
		| Word l => doit l
		| Word8 l => doit l
		| Con cases =>
		     case (Vector.length cases, default) of
			(0, NONE) => ([], Bug)
		      | _ => 
			   let
			      val (cases, decs) =
				 Vector.mapAndFold
				 (cases, [], fn ((c, j), decs) =>
				  let
				     val args = jump j
				  in if Vector.forall (args, Value.isUseful)
					then ((c, j), decs)
				     else
					let
					   val (j', d) =
					      dropUseless
					      (conArgs c, args, fn args =>
					       Jump {dst = j, args = args})
					in ((c, j'), d :: decs)
					end
				  end)
			   in (decs, Case {test = test, cases = Cases.Con cases,
					   default = default, cause = cause})
			   end
	       end
	  | Jump {dst, args} =>
	       ([], Jump {dst = dst, args = keepUseful (args, jump dst)})
	  | Raise xs => ([], Raise (keepUseful (xs, exnVals ())))
	  | Return xs => ([], Return (keepUseful (xs, returns)))
	  | _ => ([], t)
      val loopTransfer =
	 Trace.trace2 ("Useless.loopTransfer",
		       Transfer.layout,
		       Vector.layout Value.layout,
		       Layout.tuple2 (List.layout Dec.layout, Transfer.layout))
	 loopTransfer
      val traceLoopExp =
	 Trace.trace2
	 ("Useless.loopExp", Exp.layout, Vector.layout Value.layout, Exp.layout)
      fun loopExp arg : Exp.t =
	 traceLoopExp
	 (fn (e: Exp.t, returns: Value.t vector) =>
	  let val {decs, transfer} = Exp.dest e
	     val decs =
		List.rev
		(List.fold
		 (decs, [], fn (d, ds) =>
		  case d of
		     Fun {name, args, body} =>
			Fun {name = name,
			     args = keepUsefulArgs args,
			     body = loopExp (body, returns)} :: ds
		   | Bind b => (case loopBind b of
				   NONE => ds
				 | SOME b => Bind b :: ds)
		   | _ => d :: ds))
	     val (decs', transfer) = loopTransfer (transfer, returns)
	  in Exp.make {decs = List.append (decs, decs'),
		       transfer = transfer}
	  end) arg
      val datatypes =
	 Vector.map
	 (datatypes, fn {tycon, cons} =>
	  {tycon = tycon,
	   cons = Vector.map (cons, fn {con, args} =>
			     {con = con,
			      args = Value.newTypes (conArgs con)})})
      val globals =
	 Vector.concat
	 [Vector.new1 {var = unitVar,
		      ty = Type.unit,
		      exp = PrimExp.unit},
	  Vector.keepAllMap (globals, loopBind)]
      val shrinkExp = shrinkExp globals
      (*       val shrinkExp =
       * 	 Trace.trace ("Useless.shrinkExp", Exp.layout, Exp.layout) shrinkExp
       *)
      val functions =
	 Vector.map
	 (functions, fn Function.T {name, args, body, ...} =>
	  let
	     val {args = argvs, returns = returnvs} = func name
	  in
	     Function.T {name = name,
			 args = keepUsefulArgs args,
			 body = shrinkExp (loopExp (body, returnvs)),
			 returns = Value.newTypes returnvs}
	  end)
      val globals = Vector.concat [Vector.fromList (!bogusGlobals),
				   globals]
      val program =
	 Program.T {datatypes = datatypes,
		    globals = globals,
		    functions = functions,
		    main = main}
      val _ = Program.clear program
   in
      program
   end

end
