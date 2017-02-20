(*
 * OWL - an OCaml numerical library for scientific computing
 * Copyright (c) 2016-2017 Liang Wang <liang.wang@cl.cam.ac.uk>
 *)

module S = Pervasives
module M = Owl_dense_real

type mat = Owl_dense_real.mat

(* type definitions *)

type t =
  | Float  of float
  | Matrix of mat
  | DF     of t * t * int                            (* primal, tangent, tag *)
  | DR     of t * t ref * trace_op * int ref * int   (* primal, adjoint, op, fanout, tag *)
and trace_op =
  | Noop
  | Add_D_D  of t * t
  | Add_D_C  of t * t
  | Add_C_D  of t * t
  | Sub_D_D  of t * t
  | Sub_D_C  of t * t
  | Sub_C_D  of t * t
  | Mul_D_D  of t * t
  | Mul_D_C  of t * t
  | Mul_C_D  of t * t
  | Div_D_D  of t * t
  | Div_D_C  of t * t
  | Div_C_D  of t * t
  | Sin_D    of t
  | Cos_D    of t
  | Signum_D of t
  | Item     of t * int * int
  | AddI_D_D of t * int * int * t
  | AddI_D_C of t * int * int * t
  | AddI_C_D of t * int * int * t


let _global_tag = ref 0
let tag () = _global_tag := !_global_tag + 1; !_global_tag

(* FIXME *)
let cmp_tag ai bi =
  if ai > bi then 1
  else if ai < bi then -1
  else 0

let rec zero = function
  | Float _                 -> Float 0.
  | Matrix ap               -> Matrix M.(zeros (row_num ap) (col_num ap))
  | DF (ap, at, ai)         -> DF ((zero ap), (zero at), ai)  (* FIXME: need to check *)
  | DR (ap, at, ao, af, ai) -> DR ((zero ap), ref (zero !at), Noop, ref !af, ai)

let rec one = function
  | Float _         -> Float 1.
  | DF (ap, at, ai) -> DF ((one ap), (zero at), ai)
  | _               -> failwith "error: one : unknown type"

let primal = function
  | DF (ap, _, _)       -> ap
  | DR (ap, _, _, _, _) -> ap
  | ap                  -> ap

let tangent = function
  | DF (_, at, _) -> at
  | DR _          -> failwith "error: no tangent for DR"
  | ap            -> zero ap

let adjoint = function
  | DF _                -> failwith "error: no adjoint for DF"
  | DR (_, at, _, _, _) -> at
  | ap                  -> ref (zero ap)


(* overload operators *)

module Maths = struct

  let rec noop _ = ()

  and op_d_d a ff fd df r =
    match a with
    | DF (ap, at, ai)      -> let cp = fd ap in DF (cp, (df cp ap at), ai)
    | DR (ap, _, _, _, ai) -> let cp = fd ap in DR (cp, ref (zero cp), r a, ref 0, ai)
    | ap                   -> ff ap

  and op_d_d_d a b ff fd df_da df_db df_dab r_d_d r_d_c r_c_d =
    match a, b with
    | Float ap, DF (bp, bt, bi)                  -> let cp = fd a bp in DF (cp, (df_db cp bp bt), bi)
    | DF (ap, at, ai), Float bp                  -> let cp = fd ap b in DF (cp, (df_da cp ap at), ai)
    | Matrix ap, DF (bp, bt, bi)                 -> let cp = fd a bp in DF (cp, (df_db cp bp bt), bi)
    | DF (ap, at, ai), Matrix bp                 -> let cp = fd ap b in DF (cp, (df_da cp ap at), ai)
    | Float ap, DR (bp, _, _, _, bi)             -> let cp = fd a bp in DR (cp, ref (zero cp), r_c_d a b, ref 0, bi)
    | DR (ap, _, _, _, ai), Float bp             -> let cp = fd ap b in DR (cp, ref (zero cp), r_d_c a b, ref 0, ai)
    | Matrix ap, DR (bp, _, _, _, bi)            -> let cp = fd a bp in DR (cp, ref (zero cp), r_c_d a b, ref 0, bi)
    | DR (ap, _, _, _, ai), Matrix bp            -> let cp = fd ap b in DR (cp, ref (zero cp), r_d_c a b, ref 0, ai)
    | DF (ap, at, ai), DR (bp, _, _, _, bi)      -> (
        match cmp_tag ai bi with
        | 1  -> let cp = fd ap b in DF (cp, df_da cp ap at, ai)
        | -1 -> let cp = fd a bp in DR (cp, ref (zero cp), r_c_d a b, ref 0, bi)
        | _  -> failwith "error: forward and reverse clash at the same level"
      )
    | DR (ap, _, _, _, ai), DF (bp, bt, bi)      -> (
        match cmp_tag ai bi with
        | -1 -> let cp = fd a bp in DF (cp, df_db cp bp bt, bi)
        | 1  -> let cp = fd ap b in DR (cp, ref (zero cp), r_d_c a b, ref 0, ai)
        | _  -> failwith "error: forward and reverse clash at the same level"
      )
    | DF (ap, at, ai), DF (bp, bt, bi)           -> (
        match cmp_tag ai bi with
        | 0 -> let cp = fd ap bp in DF (cp, (df_dab cp ap at bp bt), ai)
        | 1 -> let cp = fd ap b  in DF (cp, (df_da cp ap at), ai)
        | _ -> let cp = fd a bp  in DF (cp, (df_db cp bp bt), bi)
      )
    | DR (ap, _, _, _, ai), DR (bp, _, _, _, bi) -> (
        match cmp_tag ai bi with
        | 0 -> let cp = fd ap bp in DR (cp, ref (zero cp), r_d_d a b, ref 0, ai)
        | 1 -> let cp = fd ap b  in DR (cp, ref (zero cp), r_d_c a b, ref 0, ai)
        | _ -> let cp = fd a bp  in DR (cp, ref (zero cp), r_c_d a b, ref 0, bi)
      )
    | a, b                                       -> ff a b

  and ( +. ) a b = add a b
  and add a b =
    let ff a b =
      match a, b with
      | Float a, Float b   -> Float S.(a +. b)
      | Float a, Matrix b  -> Matrix M.(a $+ b)
      | Matrix a, Float b  -> Matrix M.(a +$ b)
      | Matrix a, Matrix b -> Matrix M.(a +@ b)
      | _                  -> failwith "error: add: ff"
    in
    let fd a b = a +. b
    in
    let df_da cp ap at = at
    in
    let df_db cp bp bt = bt
    in
    let df_dab cp ap at bp bt = at +. bt
    in
    let r_d_d a b = Add_D_D (a, b)
    in
    let r_d_c a b = Add_D_C (a, b)
    in
    let r_c_d a b = Add_C_D (a, b)
    in
    op_d_d_d a b ff fd df_da df_db df_dab r_d_d r_d_c r_c_d

  and ( -. ) a b = sub a b
  and sub a b =
    let ff a b =
      match a, b with
      | Float a, Float b   -> Float S.(a -. b)
      | Float a, Matrix b  -> Matrix M.(a $- b)
      | Matrix a, Float b  -> Matrix M.(a -$ b)
      | Matrix a, Matrix b -> Matrix M.(a -@ b)
      | _                  -> failwith "error: sub: ff"
    in
    let fd a b = a -. b
    in
    let df_da cp ap at = at
    in
    let df_db cp bp bt = Float 0. -. bt
    in
    let df_dab cp ap at bp bt = at -. bt
    in
    let r_d_d a b = Sub_D_D (a, b)
    in
    let r_d_c a b = Sub_D_C (a, b)
    in
    let r_c_d a b = Sub_C_D (a, b)
    in
    op_d_d_d a b ff fd df_da df_db df_dab r_d_d r_d_c r_c_d

  and ( *. ) a b = mul a b
  and mul a b =
    let ff a b =
      match a, b with
      | Float a, Float b   -> Float S.(a *. b)
      | Float a, Matrix b  -> Matrix M.(a $* b)
      | Matrix a, Float b  -> Matrix M.(a *$ b)
      | Matrix a, Matrix b -> Matrix M.(a *@ b)
      | _                  -> failwith "error: mul: ff"
    in
    let fd a b = a *. b
    in
    let df_da cp ap at = at *. b
    in
    let df_db cp bp bt = a *. bt
    in
    let df_dab cp ap at bp bt = (ap *. bt) +. (at *. bp)
    in
    let r_d_d a b = Mul_D_D (a, b)
    in
    let r_d_c a b = Mul_D_C (a, b)
    in
    let r_c_d a b = Mul_C_D (a, b)
    in
    op_d_d_d a b ff fd df_da df_db df_dab r_d_d r_d_c r_c_d

  and ( /. ) a b = div a b
  and div a b =
    let ff a b =
      match a, b with
      | Float a, Float b   -> Float S.(a /. b)
      | Float a, Matrix b  -> Matrix M.(a $/ b)
      | Matrix a, Float b  -> Matrix M.(a /$ b)
      | Matrix a, Matrix b -> Matrix M.(a /@ b)
      | _                  -> failwith "error: div: ff"
    in
    let fd a b = a /. b
    in
    let df_da cp ap at = at /. b
    in
    let df_db cp bp bt = (Float 0.) -. (bt *. cp /. bp)
    in
    let df_dab cp ap at bp bt = (at -. bt *. cp) /. bp
    in
    let r_d_d a b = Div_D_D (a, b)
    in
    let r_d_c a b = Div_D_C (a, b)
    in
    let r_c_d a b = Div_C_D (a, b)
    in
    op_d_d_d a b ff fd df_da df_db df_dab r_d_d r_d_c r_c_d

  and signum a =
    let ff = function
      | Float a  -> Float Owl_maths.(signum a)
      | Matrix a -> Matrix M.(signum a)
      | _        -> failwith "error: signum: ff"
    in
    let fd a = signum a
    in
    let df cp ap at = zero ap
    in
    let r a = Signum_D a
    in
    op_d_d a ff fd df r

  and sin a =
    let ff = function
      | Float a  -> Float S.(sin a)
      | Matrix a -> Matrix M.(sin a)
      | _        -> failwith "error: sin: ff"
    in
    let fd a = sin a
    in
    let df cp ap at = at *. cos ap
    in
    let r a = Sin_D a
    in
    op_d_d a ff fd df r

  and cos a =
    let ff = function
      | Float a  -> Float S.(cos a)
      | Matrix a -> Matrix M.(cos a)
      | _        -> failwith "error: cos: ff"
    in
    let fd a = cos a
    in
    let df cp ap at = Float 0. -. (at *. sin ap)
    in
    let r a = Cos_D a
    in
    op_d_d a ff fd df r

  and item a i j =
    match a with
    | Matrix ap            -> Float (M.get ap i j)
    | DF (ap, at, ai)      -> DF (item ap i j, item at i j, ai)
    | DR (ap, _, _, _, ai) -> DR (item ap i j, ref (Float 0.), Item (a, i, j), ref 0, ai)
    | _                    -> failwith "error: item"

  and add_item a i j b =
    let ff a b = match a, b with
      | Matrix a, Float b -> let aa = M.clone a in aa.{i,j} <- S.(aa.{i,j} +. b); Matrix aa
      | _                 -> failwith "error: add_item: ff"
    in
    let fd a b = add_item a i j b
    in
    let df_da cp ap at = at
    in
    let df_db cp bp bt = add_item (zero a) i j bt
    in
    let df_dab cp ap at bp bt = add_item at i j bt
    in
    let r_d_d a b = AddI_D_D (a, i, j, b)
    in
    let r_d_c a b = AddI_D_C (a, i, j, b)
    in
    let r_c_d a b = AddI_C_D (a, i, j, b)
    in
    op_d_d_d a b ff fd df_da df_db df_dab r_d_d r_d_c r_c_d

end


(* core of the reverse mode *)

let reverse_reset x =
  let rec reset xs =
    match xs with
    | [] -> ()
    | x :: t -> (
        match x with
        | DR (ap, aa, ao, af, ai) -> (
          aa := zero !aa;
          af := !af + 1;
          if !af = 1 then (
            match ao with
            | Add_D_D (a, b)        -> reset (a :: b :: t)
            | Add_D_C (a, _)        -> reset (a :: t)
            | Add_C_D (_, b)        -> reset (b :: t)
            | Sub_D_D (a, b)        -> reset (a :: b :: t)
            | Sub_D_C (a, _)        -> reset (a :: t)
            | Sub_C_D (_, b)        -> reset (b :: t)
            | Mul_D_D (a, b)        -> reset (a :: b :: t)
            | Mul_D_C (a, _)        -> reset (a :: t)
            | Mul_C_D (_, b)        -> reset (b :: t)
            | Div_D_D (a, b)        -> reset (a :: b :: t)
            | Div_D_C (a, _)        -> reset (a :: t)
            | Div_C_D (_, b)        -> reset (b :: t)
            | Sin_D a               -> reset (a :: t)
            | Cos_D a               -> reset (a :: t)
            | Item (a, _, _)        -> reset (a :: t)
            | AddI_D_D (a, _, _, b) -> reset (a :: b :: t)
            | AddI_D_C (a, _, _, _) -> reset (a :: t)
            | AddI_C_D (_, _, _, b) -> reset (b :: t)
            | _                     -> reset t
            )
          else reset t
          )
        | _ -> reset t
      )
  in
  reset [x]

let reverse_push v x =
  let open Maths in
  let rec push xs =
    match xs with
    | [] -> ()
    | (v, x) :: t -> (
        match x with
        | DR (ap, aa, ao, af, ai) -> (
          aa := Maths.(!aa +. v);
          af := !af - 1;
          if !af = 0 then (
            match ao with
            | Add_D_D (a, b)        -> push ((!aa, a) :: (!aa, b) :: t)
            | Add_D_C (a, _)        -> push ((!aa, a) :: t)
            | Add_C_D (_, b)        -> push ((!aa, b) :: t)
            | Sub_D_D (a, b)        -> push ((!aa, a) :: (Float 0. -. !aa, b) :: t)
            | Sub_D_C (a, _)        -> push ((!aa, a) :: t)
            | Sub_C_D (_, b)        -> push ((Float 0. -. !aa, b) :: t)
            | Mul_D_D (a, b)        -> push (((!aa *. primal b), a) :: ((!aa *. primal a), b) :: t)
            | Mul_D_C (a, b)        -> push (((!aa *. b), a) :: t)
            | Mul_C_D (a, b)        -> push (((!aa *. a), b) :: t)
            | Div_D_D (a, b)        -> push (((!aa /. (primal b)), a) :: ((!aa *. ((Float 0. -. (primal a)) /. ((primal b) *. (primal b)))), b) :: t)
            | Div_D_C (a, b)        -> push (((!aa /. b), a) :: t)
            | Div_C_D (a, b)        -> push (((!aa *. ((Float 0. -. (primal a)) /. ((primal b) *. (primal b)))), b) :: t)
            | Sin_D a               -> push (((!aa *. cos (primal a)), a) :: t)
            | Cos_D a               -> push (((!aa *. (Float 0. -. sin (primal a))), a) :: t)
            | Item (a, i, j)        -> (adjoint a) := add_item !(adjoint a) i j !aa; push ((zero a, a) :: t)
            | AddI_D_D (a, i, j, b) -> push ((!aa, a) :: (item !aa i j, b) :: t)
            | AddI_D_C (a, _, _, _) -> push ((!aa, a) :: t)
            | AddI_C_D (_, i, j, b) -> push ((item !aa i j, b) :: t)
            | _                     -> push t
            )
          else push t
          )
        | _ -> push t
      )
  in
  push [(v, x)]


(* convenient wrappers *)

let make_forward p t i = DF (p, t, i)

let make_reverse p i = DR (p, ref (zero p), Noop, ref 0, i)

let diff f = fun x ->
  let x = make_forward x (one x) (tag ()) in
  f x |> tangent

let grad' f = fun x ->
  let x = make_reverse x (tag ()) in
  let y = f x in
  reverse_reset y;
  reverse_push (Float 1.) y;
  primal y, !(x |> adjoint)

let grad f = fun x -> grad' f x |> snd