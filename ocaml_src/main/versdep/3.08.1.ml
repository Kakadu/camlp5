(* camlp5r pa_macro.cmo *)
(* This file has been generated by program: do not edit! *)
(* Copyright (c) INRIA 2007-2010 *)

(* #load "q_MLast.cmo" *)

open MLast;;
open Parsetree;;
open Longident;;
open Asttypes;;

(* *)

(* *)

(* *)

(* *)

let ov = Sys.ocaml_version in
let oi =
  let rec loop i =
    if i = String.length ov then i
    else
      match ov.[i] with
        ' ' | '+' -> i
      | _ -> loop (i + 1)
  in
  loop 0
in
let ov = String.sub ov 0 oi in
if ov <> Pconfig.ocaml_version then
  begin
    flush stdout;
    Printf.eprintf "\n";
    Printf.eprintf "This ocaml and this camlp5 are not compatible:\n";
    Printf.eprintf "- OCaml version is %s\n" Sys.ocaml_version;
    Printf.eprintf "- Camlp5 compiled with ocaml %s\n" Pconfig.ocaml_version;
    Printf.eprintf "\n";
    Printf.eprintf "You need to recompile camlp5.\n";
    Printf.eprintf "\n";
    flush stderr;
    failwith "bad version"
  end;;

let fast = ref false;;
let no_constructors_arity = ref false;;

let get_tag x =
  if Obj.is_block (Obj.repr x) then Obj.tag (Obj.repr x) else Obj.magic x
;;

let error loc str = Ploc.raise loc (Failure str);;

let char_of_char_token loc s =
  try Plexing.eval_char s with Failure _ as exn -> Ploc.raise loc exn
;;

let string_of_string_token loc s =
  try Plexing.eval_string loc s with Failure _ as exn -> Ploc.raise loc exn
;;

let glob_fname = ref "";;

let mkloc loc =
  let bp = Ploc.first_pos loc in
  let ep = Ploc.last_pos loc in
  let lnum = Ploc.line_nb loc in
  let bolp = Ploc.bol_pos loc in
  let loc_at n =
    {Lexing.pos_fname = if lnum = -1 then "" else !glob_fname;
     Lexing.pos_lnum = lnum; Lexing.pos_bol = bolp; Lexing.pos_cnum = n}
  in
  {Location.loc_start = loc_at bp; Location.loc_end = loc_at ep;
   Location.loc_ghost = bp = 0 && ep = 0}
;;

let mktyp loc d = {ptyp_desc = d; ptyp_loc = mkloc loc};;
let mkpat loc d = {ppat_desc = d; ppat_loc = mkloc loc};;
let mkexp loc d = {pexp_desc = d; pexp_loc = mkloc loc};;
let mkmty loc d = {pmty_desc = d; pmty_loc = mkloc loc};;
let mksig loc d = {psig_desc = d; psig_loc = mkloc loc};;
let mkmod loc d = {pmod_desc = d; pmod_loc = mkloc loc};;
let mkstr loc d = {pstr_desc = d; pstr_loc = mkloc loc};;
let mkfield loc d = {pfield_desc = d; pfield_loc = mkloc loc};;
let mkcty loc d = {pcty_desc = d; pcty_loc = mkloc loc};;
let mkpcl loc d = {pcl_desc = d; pcl_loc = mkloc loc};;
let mkpolytype t =
  match t with
    MLast.TyPol (_, _, _) -> t
  | _ -> let loc = MLast.loc_of_ctyp t in MLast.TyPol (loc, [], t)
;;

let lident s = Lident s;;
let ldot l s = Ldot (l, s);;

let conv_con =
  let t = Hashtbl.create 73 in
  List.iter (fun (s, s') -> Hashtbl.add t s s')
    ["True", "true"; "False", "false"; " True", "True"; " False", "False"];
  fun s -> try Hashtbl.find t s with Not_found -> s
;;

let conv_lab =
  let t = Hashtbl.create 73 in
  List.iter (fun (s, s') -> Hashtbl.add t s s') ["val", "contents"];
  fun s -> try Hashtbl.find t s with Not_found -> s
;;

let array_function str name =
  ldot (lident str) (if !fast then "unsafe_" ^ name else name)
;;

let uv c =
  match c, "" with
    c, "" -> c
  | _ -> invalid_arg "Ast2pt.uv"
;;

let mkrf =
  function
    true -> Recursive
  | false -> Nonrecursive
;;

let mkli s =
  let rec loop f =
    function
      i :: il -> loop (fun s -> ldot (f i) s) il
    | [] -> f s
  in
  loop (fun s -> lident s)
;;

let long_id_of_string_list loc sl =
  match List.rev sl with
    [] -> error loc "bad ast"
  | s :: sl -> mkli s (List.rev sl)
;;

let rec ctyp_fa al =
  function
    TyApp (_, f, a) -> ctyp_fa (a :: al) f
  | f -> f, al
;;

let rec ctyp_long_id =
  function
    MLast.TyAcc (_, m, MLast.TyLid (_, s)) ->
      let (is_cls, li) = ctyp_long_id m in is_cls, ldot li s
  | MLast.TyAcc (_, m, MLast.TyUid (_, s)) ->
      let (is_cls, li) = ctyp_long_id m in is_cls, ldot li s
  | MLast.TyApp (_, m1, m2) ->
      let (is_cls, li1) = ctyp_long_id m1 in
      let (_, li2) = ctyp_long_id m2 in is_cls, Lapply (li1, li2)
  | MLast.TyUid (_, s) -> false, lident s
  | MLast.TyLid (_, s) -> false, lident s
  | TyCls (loc, sl) -> true, long_id_of_string_list loc (uv sl)
  | t -> error (loc_of_ctyp t) "incorrect type"
;;

let rec ctyp =
  function
    TyAcc (loc, _, _) as f ->
      let (is_cls, li) = ctyp_long_id f in
      if is_cls then mktyp loc (Ptyp_class (li, [], []))
      else mktyp loc (Ptyp_constr (li, []))
  | TyAli (loc, t1, t2) ->
      let (t, i) =
        match t1, t2 with
          t, MLast.TyQuo (_, s) -> t, s
        | MLast.TyQuo (_, s), t -> t, s
        | _ -> error loc "incorrect alias type"
      in
      mktyp loc (Ptyp_alias (ctyp t, i))
  | TyAny loc -> mktyp loc Ptyp_any
  | TyApp (loc, _, _) as f ->
      let (f, al) = ctyp_fa [] f in
      let (is_cls, li) = ctyp_long_id f in
      if is_cls then mktyp loc (Ptyp_class (li, List.map ctyp al, []))
      else mktyp loc (Ptyp_constr (li, List.map ctyp al))
  | TyArr (loc, TyLab (loc1, lab, t1), t2) ->
      mktyp loc (Ptyp_arrow (uv lab, ctyp t1, ctyp t2))
  | TyArr (loc, TyOlb (loc1, lab, t1), t2) ->
      let t1 =
        let loc = loc1 in MLast.TyApp (loc, MLast.TyLid (loc, "option"), t1)
      in
      mktyp loc (Ptyp_arrow ("?" ^ uv lab, ctyp t1, ctyp t2))
  | TyArr (loc, t1, t2) -> mktyp loc (Ptyp_arrow ("", ctyp t1, ctyp t2))
  | TyObj (loc, fl, v) -> mktyp loc (Ptyp_object (meth_list loc (uv fl) v))
  | TyCls (loc, id) ->
      mktyp loc (Ptyp_class (long_id_of_string_list loc (uv id), [], []))
  | TyLab (loc, _, _) -> error loc "labeled type not allowed here"
  | TyLid (loc, s) -> mktyp loc (Ptyp_constr (lident (uv s), []))
  | TyMan (loc, _, _) -> error loc "type manifest not allowed here"
  | TyOlb (loc, lab, _) -> error loc "labeled type not allowed here"
  | TyPol (loc, pl, t) -> mktyp loc (Ptyp_poly (uv pl, ctyp t))
  | TyQuo (loc, s) -> mktyp loc (Ptyp_var (uv s))
  | TyRec (loc, _) -> error loc "record type not allowed here"
  | TySum (loc, _) -> error loc "sum type not allowed here"
  | TyTup (loc, tl) -> mktyp loc (Ptyp_tuple (List.map ctyp (uv tl)))
  | TyUid (loc, s) -> mktyp loc (Ptyp_constr (lident (uv s), []))
  | TyVrn (loc, catl, ool) ->
      let catl =
        List.map
          (function
             PvTag (c, a, t) -> Rtag (uv c, uv a, List.map ctyp (uv t))
           | PvInh t -> Rinherit (ctyp t))
          (uv catl)
      in
      let (clos, sl) =
        match ool with
          None -> true, None
        | Some None -> false, None
        | Some (Some sl) -> true, Some (uv sl)
      in
      mktyp loc (Ptyp_variant (catl, clos, sl))
and meth_list loc fl v =
  match fl with
    [] -> if uv v then [mkfield loc Pfield_var] else []
  | (lab, t) :: fl ->
      mkfield loc (Pfield (lab, ctyp (mkpolytype t))) :: meth_list loc fl v
;;

let mktype loc tl cl tk tm =
  let (params, variance) = List.split tl in
  {ptype_params = List.map uv params; ptype_cstrs = cl; ptype_kind = tk;
   ptype_manifest = tm; ptype_loc = mkloc loc; ptype_variance = variance}
;;
let mkmutable m = if m then Mutable else Immutable;;
let mkprivate m = if m then Private else Public;;
let mktrecord (loc, n, m, t) = n, mkmutable m, ctyp (mkpolytype t);;
let mkvariant (loc, c, tl) = conv_con (uv c), List.map ctyp (uv tl);;

let type_decl tl priv cl =
  function
    TyMan (loc, t, MLast.TyRec (_, ltl)) ->
      mktype loc tl cl (Ptype_record (List.map mktrecord ltl, priv))
        (Some (ctyp t))
  | TyMan (loc, t, MLast.TySum (_, ctl)) ->
      mktype loc tl cl (Ptype_variant (List.map mkvariant ctl, priv))
        (Some (ctyp t))
  | TyRec (loc, ltl) ->
      mktype loc tl cl (Ptype_record (List.map mktrecord (uv ltl), priv)) None
  | TySum (loc, ctl) ->
      mktype loc tl cl (Ptype_variant (List.map mkvariant (uv ctl), priv))
        None
  | t ->
      let m =
        match t with
          MLast.TyQuo (_, s) ->
            if List.exists (fun (t, _) -> s = uv t) tl then Some (ctyp t)
            else None
        | _ -> Some (ctyp t)
      in
      mktype (loc_of_ctyp t) tl cl Ptype_abstract m
;;

let mkvalue_desc t p = {pval_type = ctyp t; pval_prim = p};;

let option f =
  function
    Some x -> Some (f x)
  | None -> None
;;

let expr_of_lab loc lab =
  function
    Some e -> e
  | None -> MLast.ExLid (loc, lab)
;;

let patt_of_lab loc lab =
  function
    Some p -> p
  | None -> MLast.PaLid (loc, lab)
;;

let paolab loc lab peoo =
  let lab =
    match lab, peoo with
      "",
      Some
        ((MLast.PaLid (_, i) | MLast.PaTyc (_, MLast.PaLid (_, i), _)), _) ->
        i
    | "", _ -> error loc "bad ast"
    | _ -> lab
  in
  let (p, eo) =
    match peoo with
      Some (p, eo) -> p, uv eo
    | None -> MLast.PaLid (loc, lab), None
  in
  lab, p, eo
;;

let rec same_type_expr ct ce =
  match ct, ce with
    MLast.TyLid (_, s1), MLast.ExLid (_, s2) -> s1 = s2
  | MLast.TyUid (_, s1), MLast.ExUid (_, s2) -> s1 = s2
  | MLast.TyAcc (_, t1, t2), MLast.ExAcc (_, e1, e2) ->
      same_type_expr t1 e1 && same_type_expr t2 e2
  | _ -> false
;;

let rec common_id loc t e =
  match t, e with
    MLast.TyLid (_, s1), MLast.ExLid (_, s2) when s1 = s2 -> lident s1
  | MLast.TyUid (_, s1), MLast.ExUid (_, s2) when s1 = s2 -> lident s1
  | MLast.TyAcc (_, t1, MLast.TyLid (_, s1)),
    MLast.ExAcc (_, e1, MLast.ExLid (_, s2))
    when s1 = s2 ->
      ldot (common_id loc t1 e1) s1
  | MLast.TyAcc (_, t1, MLast.TyUid (_, s1)),
    MLast.ExAcc (_, e1, MLast.ExUid (_, s2))
    when s1 = s2 ->
      ldot (common_id loc t1 e1) s1
  | _ -> error loc "this expression should repeat the class id inherited"
;;

let rec type_id loc t =
  match t with
    MLast.TyLid (_, s1) -> lident s1
  | MLast.TyUid (_, s1) -> lident s1
  | MLast.TyAcc (_, t1, MLast.TyLid (_, s1)) -> ldot (type_id loc t1) s1
  | MLast.TyAcc (_, t1, MLast.TyUid (_, s1)) -> ldot (type_id loc t1) s1
  | _ -> error loc "type identifier expected"
;;

let rec module_type_long_id =
  function
    MLast.MtAcc (_, m, MLast.MtUid (_, s)) -> ldot (module_type_long_id m) s
  | MLast.MtAcc (_, m, MLast.MtLid (_, s)) -> ldot (module_type_long_id m) s
  | MtApp (_, m1, m2) ->
      Lapply (module_type_long_id m1, module_type_long_id m2)
  | MLast.MtLid (_, s) -> lident s
  | MLast.MtUid (_, s) -> lident s
  | t -> error (loc_of_module_type t) "bad module type long ident"
;;

let rec module_expr_long_id =
  function
    MLast.MeAcc (_, m, MLast.MeUid (_, s)) -> ldot (module_expr_long_id m) s
  | MLast.MeUid (_, s) -> lident s
  | t -> error (loc_of_module_expr t) "bad module expr long ident"
;;

let mkwithc =
  function
    WcTyp (loc, id, tpl, pf, ct) ->
      let (params, variance) = List.split (uv tpl) in
      let tk = Ptype_abstract in
      long_id_of_string_list loc (uv id),
      Pwith_type
        {ptype_params = List.map uv params; ptype_cstrs = []; ptype_kind = tk;
         ptype_manifest = Some (ctyp ct); ptype_loc = mkloc loc;
         ptype_variance = variance}
  | WcMod (loc, id, m) ->
      long_id_of_string_list loc (uv id), Pwith_module (module_expr_long_id m)
;;

let rec patt_fa al =
  function
    PaApp (_, f, a) -> patt_fa (a :: al) f
  | f -> f, al
;;

let rec mkrangepat loc c1 c2 =
  if c1 > c2 then mkrangepat loc c2 c1
  else if c1 = c2 then mkpat loc (Ppat_constant (Const_char c1))
  else
    mkpat loc
      (Ppat_or
         (mkpat loc (Ppat_constant (Const_char c1)),
          mkrangepat loc (Char.chr (Char.code c1 + 1)) c2))
;;

let rec patt_long_id il =
  function
    MLast.PaAcc (_, p, MLast.PaUid (_, i)) -> patt_long_id (i :: il) p
  | p -> p, il
;;

let rec patt_label_long_id =
  function
    MLast.PaAcc (_, m, MLast.PaLid (_, s)) ->
      ldot (patt_label_long_id m) (conv_lab s)
  | MLast.PaAcc (_, m, MLast.PaUid (_, s)) -> ldot (patt_label_long_id m) s
  | MLast.PaUid (_, s) -> lident s
  | MLast.PaLid (_, s) -> lident (conv_lab s)
  | p -> error (loc_of_patt p) "bad label"
;;

let rec patt =
  function
    PaAcc (loc, p1, p2) ->
      let p =
        match patt_long_id [] p1 with
          MLast.PaUid (_, i), il ->
            begin match p2 with
              MLast.PaUid (_, s) ->
                Ppat_construct
                  (mkli (conv_con s) (i :: il), None,
                   not !no_constructors_arity)
            | _ -> error (loc_of_patt p2) "bad access pattern"
            end
        | _ -> error (loc_of_patt p2) "bad pattern"
      in
      mkpat loc p
  | PaAli (loc, p1, p2) ->
      let (p, i) =
        match p1, p2 with
          p, MLast.PaLid (_, s) -> p, s
        | MLast.PaLid (_, s), p -> p, s
        | _ -> error loc "incorrect alias pattern"
      in
      mkpat loc (Ppat_alias (patt p, i))
  | PaAnt (_, p) -> patt p
  | PaAny loc -> mkpat loc Ppat_any
  | PaApp (loc, _, _) as f ->
      let (f, al) = patt_fa [] f in
      let al = List.map patt al in
      begin match (patt f).ppat_desc with
        Ppat_construct (li, None, _) ->
          if !no_constructors_arity then
            let a =
              match al with
                [a] -> a
              | _ -> mkpat loc (Ppat_tuple al)
            in
            mkpat loc (Ppat_construct (li, Some a, false))
          else
            let a = mkpat loc (Ppat_tuple al) in
            mkpat loc (Ppat_construct (li, Some a, true))
      | Ppat_variant (s, None) ->
          let a =
            match al with
              [a] -> a
            | _ -> mkpat loc (Ppat_tuple al)
          in
          mkpat loc (Ppat_variant (s, Some a))
      | _ ->
          error (loc_of_patt f)
            "this is not a constructor, it cannot be applied in a pattern"
      end
  | PaArr (loc, pl) -> mkpat loc (Ppat_array (List.map patt (uv pl)))
  | PaChr (loc, s) ->
      mkpat loc (Ppat_constant (Const_char (char_of_char_token loc (uv s))))
  | PaInt (loc, s, "") ->
      mkpat loc (Ppat_constant (Const_int (int_of_string (uv s))))
  | PaInt (loc, _, _) -> error loc "special int not impl in patt"
  | PaFlo (loc, s) -> mkpat loc (Ppat_constant (Const_float (uv s)))
  | PaLab (loc, _, _) -> error loc "labeled pattern not allowed here"
  | PaLaz (loc, p) -> error loc "lazy patterns not in this version"
  | PaLid (loc, s) -> mkpat loc (Ppat_var (uv s))
  | PaOlb (loc, _, _) -> error loc "labeled pattern not allowed here"
  | PaOrp (loc, p1, p2) -> mkpat loc (Ppat_or (patt p1, patt p2))
  | PaRng (loc, p1, p2) ->
      begin match p1, p2 with
        PaChr (loc1, c1), PaChr (loc2, c2) ->
          let c1 = char_of_char_token loc1 (uv c1) in
          let c2 = char_of_char_token loc2 (uv c2) in mkrangepat loc c1 c2
      | _ -> error loc "range pattern allowed only for characters"
      end
  | PaRec (loc, lpl) -> mkpat loc (Ppat_record (List.map mklabpat (uv lpl)))
  | PaStr (loc, s) ->
      mkpat loc
        (Ppat_constant (Const_string (string_of_string_token loc (uv s))))
  | PaTup (loc, pl) -> mkpat loc (Ppat_tuple (List.map patt (uv pl)))
  | PaTyc (loc, p, t) -> mkpat loc (Ppat_constraint (patt p, ctyp t))
  | PaTyp (loc, sl) ->
      mkpat loc (Ppat_type (long_id_of_string_list loc (uv sl)))
  | PaUid (loc, s) ->
      let ca = not !no_constructors_arity in
      mkpat loc (Ppat_construct (lident (conv_con (uv s)), None, ca))
  | PaVrn (loc, s) -> mkpat loc (Ppat_variant (uv s, None))
and mklabpat (lab, p) = patt_label_long_id lab, patt p;;

let rec expr_fa al =
  function
    ExApp (_, f, a) -> expr_fa (a :: al) f
  | f -> f, al
;;

let rec class_expr_fa al =
  function
    CeApp (_, ce, a) -> class_expr_fa (a :: al) ce
  | ce -> ce, al
;;

let rec sep_expr_acc l =
  function
    MLast.ExAcc (_, e1, e2) -> sep_expr_acc (sep_expr_acc l e2) e1
  | MLast.ExUid (_, s) as e ->
      let loc = MLast.loc_of_expr e in
      begin match l with
        [] -> [loc, [], e]
      | (loc2, sl, e) :: l -> (Ploc.encl loc loc2, s :: sl, e) :: l
      end
  | e -> (loc_of_expr e, [], e) :: l
;;

let class_info class_expr ci =
  let (params, variance) = List.split (uv (snd ci.ciPrm)) in
  {pci_virt = if uv ci.ciVir then Virtual else Concrete;
   pci_params = List.map uv params, mkloc (fst ci.ciPrm);
   pci_name = uv ci.ciNam; pci_expr = class_expr ci.ciExp;
   pci_loc = mkloc ci.ciLoc; pci_variance = variance}
;;

let bigarray_get loc e el =
  match el with
    [c1] ->
      MLast.ExApp
        (loc,
         MLast.ExApp
           (loc,
            MLast.ExAcc
              (loc,
               MLast.ExAcc
                 (loc, MLast.ExUid (loc, "Bigarray"),
                  MLast.ExUid (loc, "Array1")),
               MLast.ExLid (loc, "get")),
            e),
         c1)
  | [c1; c2] ->
      MLast.ExApp
        (loc,
         MLast.ExApp
           (loc,
            MLast.ExApp
              (loc,
               MLast.ExAcc
                 (loc,
                  MLast.ExAcc
                    (loc, MLast.ExUid (loc, "Bigarray"),
                     MLast.ExUid (loc, "Array2")),
                  MLast.ExLid (loc, "get")),
               e),
            c1),
         c2)
  | [c1; c2; c3] ->
      MLast.ExApp
        (loc,
         MLast.ExApp
           (loc,
            MLast.ExApp
              (loc,
               MLast.ExApp
                 (loc,
                  MLast.ExAcc
                    (loc,
                     MLast.ExAcc
                       (loc, MLast.ExUid (loc, "Bigarray"),
                        MLast.ExUid (loc, "Array3")),
                     MLast.ExLid (loc, "get")),
                  e),
               c1),
            c2),
         c3)
  | _ ->
      MLast.ExApp
        (loc,
         MLast.ExApp
           (loc,
            MLast.ExAcc
              (loc,
               MLast.ExAcc
                 (loc, MLast.ExUid (loc, "Bigarray"),
                  MLast.ExUid (loc, "Genarray")),
               MLast.ExLid (loc, "get")),
            e),
         MLast.ExArr (loc, el))
;;

let bigarray_set loc e el v =
  match el with
    [c1] ->
      MLast.ExApp
        (loc,
         MLast.ExApp
           (loc,
            MLast.ExApp
              (loc,
               MLast.ExAcc
                 (loc,
                  MLast.ExAcc
                    (loc, MLast.ExUid (loc, "Bigarray"),
                     MLast.ExUid (loc, "Array1")),
                  MLast.ExLid (loc, "set")),
               e),
            c1),
         v)
  | [c1; c2] ->
      MLast.ExApp
        (loc,
         MLast.ExApp
           (loc,
            MLast.ExApp
              (loc,
               MLast.ExApp
                 (loc,
                  MLast.ExAcc
                    (loc,
                     MLast.ExAcc
                       (loc, MLast.ExUid (loc, "Bigarray"),
                        MLast.ExUid (loc, "Array2")),
                     MLast.ExLid (loc, "set")),
                  e),
               c1),
            c2),
         v)
  | [c1; c2; c3] ->
      MLast.ExApp
        (loc,
         MLast.ExApp
           (loc,
            MLast.ExApp
              (loc,
               MLast.ExApp
                 (loc,
                  MLast.ExApp
                    (loc,
                     MLast.ExAcc
                       (loc,
                        MLast.ExAcc
                          (loc, MLast.ExUid (loc, "Bigarray"),
                           MLast.ExUid (loc, "Array3")),
                        MLast.ExLid (loc, "set")),
                     e),
                  c1),
               c2),
            c3),
         v)
  | _ ->
      MLast.ExApp
        (loc,
         MLast.ExApp
           (loc,
            MLast.ExApp
              (loc,
               MLast.ExAcc
                 (loc,
                  MLast.ExAcc
                    (loc, MLast.ExUid (loc, "Bigarray"),
                     MLast.ExUid (loc, "Genarray")),
                  MLast.ExLid (loc, "set")),
               e),
            MLast.ExArr (loc, el)),
         v)
;;

(* *)

let rec expr =
  function
    ExAcc (loc, x, MLast.ExLid (_, "val")) ->
      mkexp loc
        (Pexp_apply (mkexp loc (Pexp_ident (Lident "!")), ["", expr x]))
  | ExAcc (loc, _, _) as e ->
      let (e, l) =
        match sep_expr_acc [] e with
          (loc, ml, MLast.ExUid (_, s)) :: l ->
            let ca = not !no_constructors_arity in
            mkexp loc (Pexp_construct (mkli s ml, None, ca)), l
        | (loc, ml, MLast.ExLid (_, s)) :: l ->
            mkexp loc (Pexp_ident (mkli s ml)), l
        | (_, [], e) :: l -> expr e, l
        | _ -> error loc "bad ast"
      in
      let (_, e) =
        List.fold_left
          (fun (loc1, e1) (loc2, ml, e2) ->
             match e2 with
               MLast.ExLid (_, s) ->
                 let loc = Ploc.encl loc1 loc2 in
                 loc, mkexp loc (Pexp_field (e1, mkli (conv_lab s) ml))
             | _ -> error (loc_of_expr e2) "lowercase identifier expected")
          (loc, e) l
      in
      e
  | ExAnt (_, e) -> expr e
  | ExApp (loc, _, _) as f ->
      let (f, al) = expr_fa [] f in
      let al = List.map label_expr al in
      begin match (expr f).pexp_desc with
        Pexp_construct (li, None, _) ->
          let al = List.map snd al in
          if !no_constructors_arity then
            let a =
              match al with
                [a] -> a
              | _ -> mkexp loc (Pexp_tuple al)
            in
            mkexp loc (Pexp_construct (li, Some a, false))
          else
            let a = mkexp loc (Pexp_tuple al) in
            mkexp loc (Pexp_construct (li, Some a, true))
      | Pexp_variant (s, None) ->
          let al = List.map snd al in
          let a =
            match al with
              [a] -> a
            | _ -> mkexp loc (Pexp_tuple al)
          in
          mkexp loc (Pexp_variant (s, Some a))
      | _ -> mkexp loc (Pexp_apply (expr f, al))
      end
  | ExAre (loc, e1, e2) ->
      mkexp loc
        (Pexp_apply
           (mkexp loc (Pexp_ident (array_function "Array" "get")),
            ["", expr e1; "", expr e2]))
  | ExArr (loc, el) -> mkexp loc (Pexp_array (List.map expr (uv el)))
  | ExAss (loc, e, v) ->
      begin match e with
        ExAcc (loc, x, MLast.ExLid (_, "val")) ->
          mkexp loc
            (Pexp_apply
               (mkexp loc (Pexp_ident (Lident ":=")),
                ["", expr x; "", expr v]))
      | ExAcc (loc, _, _) ->
          begin match (expr e).pexp_desc with
            Pexp_field (e, lab) -> mkexp loc (Pexp_setfield (e, lab, expr v))
          | _ -> error loc "bad record access"
          end
      | ExAre (_, e1, e2) ->
          mkexp loc
            (Pexp_apply
               (mkexp loc (Pexp_ident (array_function "Array" "set")),
                ["", expr e1; "", expr e2; "", expr v]))
      | ExBae (loc, e, el) -> expr (bigarray_set loc e (uv el) v)
      | MLast.ExLid (_, lab) -> mkexp loc (Pexp_setinstvar (lab, expr v))
      | ExSte (_, e1, e2) ->
          mkexp loc
            (Pexp_apply
               (mkexp loc (Pexp_ident (array_function "String" "set")),
                ["", expr e1; "", expr e2; "", expr v]))
      | _ -> error loc "bad left part of assignment"
      end
  | ExAsr (loc, MLast.ExUid (_, "False")) -> mkexp loc Pexp_assertfalse
  | ExAsr (loc, e) -> mkexp loc (Pexp_assert (expr e))
  | ExBae (loc, e, el) -> expr (bigarray_get loc e (uv el))
  | ExChr (loc, s) ->
      mkexp loc (Pexp_constant (Const_char (char_of_char_token loc (uv s))))
  | ExCoe (loc, e, t1, t2) ->
      mkexp loc (Pexp_constraint (expr e, option ctyp t1, Some (ctyp t2)))
  | ExFlo (loc, s) -> mkexp loc (Pexp_constant (Const_float (uv s)))
  | ExFor (loc, i, e1, e2, df, el) ->
      let e3 = MLast.ExSeq (loc, uv el) in
      let df = if uv df then Upto else Downto in
      mkexp loc (Pexp_for (uv i, expr e1, expr e2, df, expr e3))
  | ExFun (loc, pel) ->
      begin match uv pel with
        [PaLab (_, lab, po), w, e] ->
          mkexp loc
            (Pexp_function
               (uv lab, None,
                [patt (patt_of_lab loc (uv lab) po), when_expr e (uv w)]))
      | [PaOlb (_, lab, peoo), w, e] ->
          let (lab, p, eo) = paolab loc (uv lab) peoo in
          mkexp loc
            (Pexp_function
               ("?" ^ lab, option expr eo, [patt p, when_expr e (uv w)]))
      | pel -> mkexp loc (Pexp_function ("", None, List.map mkpwe pel))
      end
  | ExIfe (loc, e1, e2, e3) ->
      mkexp loc (Pexp_ifthenelse (expr e1, expr e2, Some (expr e3)))
  | ExInt (loc, s, "") ->
      mkexp loc (Pexp_constant (Const_int (int_of_string (uv s))))
  | ExInt (loc, s, "l") ->
      mkexp loc (Pexp_constant (Const_int32 (Int32.of_string (uv s))))
  | ExInt (loc, s, "L") ->
      mkexp loc (Pexp_constant (Const_int64 (Int64.of_string (uv s))))
  | ExInt (loc, s, "n") ->
      mkexp loc (Pexp_constant (Const_nativeint (Nativeint.of_string (uv s))))
  | ExInt (loc, _, _) -> error loc "special int not implemented"
  | ExLab (loc, _, _) -> error loc "labeled expression not allowed here"
  | ExLaz (loc, e) -> mkexp loc (Pexp_lazy (expr e))
  | ExLet (loc, rf, pel, e) ->
      mkexp loc (Pexp_let (mkrf (uv rf), List.map mkpe (uv pel), expr e))
  | ExLid (loc, s) -> mkexp loc (Pexp_ident (lident (uv s)))
  | ExLmd (loc, i, me, e) ->
      mkexp loc (Pexp_letmodule (uv i, module_expr me, expr e))
  | ExMat (loc, e, pel) ->
      mkexp loc (Pexp_match (expr e, List.map mkpwe (uv pel)))
  | ExNew (loc, id) ->
      mkexp loc (Pexp_new (long_id_of_string_list loc (uv id)))
  | ExObj (loc, po, cfl) ->
      let p =
        match uv po with
          Some p -> p
        | None -> PaAny loc
      in
      let cil = List.fold_right class_str_item (uv cfl) [] in
      mkexp loc (Pexp_object (patt p, cil))
  | ExOlb (loc, _, _) -> error loc "labeled expression not allowed here"
  | ExOvr (loc, iel) -> mkexp loc (Pexp_override (List.map mkideexp (uv iel)))
  | ExRec (loc, lel, eo) ->
      let lel = uv lel in
      if lel = [] then error loc "empty record"
      else
        let lel = lel in
        let eo =
          match eo with
            Some e -> Some (expr e)
          | None -> None
        in
        mkexp loc (Pexp_record (List.map mklabexp lel, eo))
  | ExSeq (loc, el) ->
      let rec loop =
        function
          [] -> expr (MLast.ExUid (loc, "()"))
        | [e] -> expr e
        | e :: el ->
            let loc = Ploc.encl (loc_of_expr e) loc in
            mkexp loc (Pexp_sequence (expr e, loop el))
      in
      loop (uv el)
  | ExSnd (loc, e, s) -> mkexp loc (Pexp_send (expr e, uv s))
  | ExSte (loc, e1, e2) ->
      mkexp loc
        (Pexp_apply
           (mkexp loc (Pexp_ident (array_function "String" "get")),
            ["", expr e1; "", expr e2]))
  | ExStr (loc, s) ->
      mkexp loc
        (Pexp_constant (Const_string (string_of_string_token loc (uv s))))
  | ExTry (loc, e, pel) ->
      mkexp loc (Pexp_try (expr e, List.map mkpwe (uv pel)))
  | ExTup (loc, el) -> mkexp loc (Pexp_tuple (List.map expr (uv el)))
  | ExTyc (loc, e, t) ->
      mkexp loc (Pexp_constraint (expr e, Some (ctyp t), None))
  | ExUid (loc, s) ->
      let ca = not !no_constructors_arity in
      mkexp loc (Pexp_construct (lident (conv_con (uv s)), None, ca))
  | ExVrn (loc, s) -> mkexp loc (Pexp_variant (uv s, None))
  | ExWhi (loc, e1, el) ->
      let e2 = MLast.ExSeq (loc, uv el) in
      mkexp loc (Pexp_while (expr e1, expr e2))
and label_expr =
  function
    ExLab (loc, lab, eo) -> uv lab, expr (expr_of_lab loc (uv lab) eo)
  | ExOlb (loc, lab, eo) -> "?" ^ uv lab, expr (expr_of_lab loc (uv lab) eo)
  | e -> "", expr e
and mkpe (p, e) = patt p, expr e
and mkpwe (p, w, e) = patt p, when_expr e (uv w)
and when_expr e =
  function
    Some w -> mkexp (loc_of_expr e) (Pexp_when (expr w, expr e))
  | None -> expr e
and mklabexp (lab, e) = patt_label_long_id lab, expr e
and mkideexp (ide, e) = ide, expr e
and mktype_decl td =
  let priv = if uv td.tdPrv then Private else Public in
  let cl =
    List.map
      (fun (t1, t2) ->
         let loc = Ploc.encl (loc_of_ctyp t1) (loc_of_ctyp t2) in
         ctyp t1, ctyp t2, mkloc loc)
      (uv td.tdCon)
  in
  uv (snd td.tdNam), type_decl (uv td.tdPrm) priv cl td.tdDef
and module_type =
  function
    MtAcc (loc, _, _) as f -> mkmty loc (Pmty_ident (module_type_long_id f))
  | MtApp (loc, _, _) as f -> mkmty loc (Pmty_ident (module_type_long_id f))
  | MtFun (loc, n, nt, mt) ->
      mkmty loc (Pmty_functor (uv n, module_type nt, module_type mt))
  | MtLid (loc, s) -> mkmty loc (Pmty_ident (lident (uv s)))
  | MtQuo (loc, _) -> error loc "abstract module type not allowed here"
  | MtSig (loc, sl) ->
      mkmty loc (Pmty_signature (List.fold_right sig_item (uv sl) []))
  | MtUid (loc, s) -> mkmty loc (Pmty_ident (lident (uv s)))
  | MtWit (loc, mt, wcl) ->
      mkmty loc (Pmty_with (module_type mt, List.map mkwithc (uv wcl)))
and sig_item s l =
  match s with
    SgCls (loc, cd) ->
      mksig loc (Psig_class (List.map (class_info class_type) (uv cd))) :: l
  | SgClt (loc, ctd) ->
      mksig loc
        (Psig_class_type (List.map (class_info class_type) (uv ctd))) ::
      l
  | SgDcl (loc, sl) -> List.fold_right sig_item (uv sl) l
  | SgDir (loc, _, _) -> l
  | SgExc (loc, n, tl) ->
      mksig loc (Psig_exception (uv n, List.map ctyp (uv tl))) :: l
  | SgExt (loc, n, t, p) ->
      mksig loc (Psig_value (uv n, mkvalue_desc t (uv p))) :: l
  | SgInc (loc, mt) -> mksig loc (Psig_include (module_type mt)) :: l
  | SgMod (loc, rf, ntl) ->
      if not (uv rf) then
        List.fold_right
          (fun (n, mt) l ->
             mksig loc (Psig_module (uv n, module_type mt)) :: l)
          (uv ntl) l
      else
        let ntl = List.map (fun (n, mt) -> uv n, module_type mt) (uv ntl) in
        mksig loc (Psig_recmodule ntl) :: l
  | SgMty (loc, n, mt) ->
      let si =
        match mt with
          MtQuo (_, _) -> Pmodtype_abstract
        | _ -> Pmodtype_manifest (module_type mt)
      in
      mksig loc (Psig_modtype (uv n, si)) :: l
  | SgOpn (loc, id) ->
      mksig loc (Psig_open (long_id_of_string_list loc (uv id))) :: l
  | SgTyp (loc, tdl) ->
      mksig loc (Psig_type (List.map mktype_decl (uv tdl))) :: l
  | SgUse (loc, fn, sl) ->
      Ploc.call_with glob_fname fn
        (fun () -> List.fold_right (fun (si, _) -> sig_item si) sl l) ()
  | SgVal (loc, n, t) -> mksig loc (Psig_value (uv n, mkvalue_desc t [])) :: l
and module_expr =
  function
    MeAcc (loc, _, _) as f -> mkmod loc (Pmod_ident (module_expr_long_id f))
  | MeApp (loc, me1, me2) ->
      mkmod loc (Pmod_apply (module_expr me1, module_expr me2))
  | MeFun (loc, n, mt, me) ->
      mkmod loc (Pmod_functor (uv n, module_type mt, module_expr me))
  | MeStr (loc, sl) ->
      mkmod loc (Pmod_structure (List.fold_right str_item (uv sl) []))
  | MeTyc (loc, me, mt) ->
      mkmod loc (Pmod_constraint (module_expr me, module_type mt))
  | MeUid (loc, s) -> mkmod loc (Pmod_ident (lident (uv s)))
and str_item s l =
  match s with
    StCls (loc, cd) ->
      mkstr loc (Pstr_class (List.map (class_info class_expr) (uv cd))) :: l
  | StClt (loc, ctd) ->
      mkstr loc
        (Pstr_class_type (List.map (class_info class_type) (uv ctd))) ::
      l
  | StDcl (loc, sl) -> List.fold_right str_item (uv sl) l
  | StDir (loc, _, _) -> l
  | StExc (loc, n, tl, sl) ->
      let si =
        match uv tl, uv sl with
          tl, [] -> Pstr_exception (uv n, List.map ctyp tl)
        | [], sl -> Pstr_exn_rebind (uv n, long_id_of_string_list loc sl)
        | _ -> error loc "bad exception declaration"
      in
      mkstr loc si :: l
  | StExp (loc, e) -> mkstr loc (Pstr_eval (expr e)) :: l
  | StExt (loc, n, t, p) ->
      mkstr loc (Pstr_primitive (uv n, mkvalue_desc t (uv p))) :: l
  | StInc (loc, me) -> mkstr loc (Pstr_include (module_expr me)) :: l
  | StMod (loc, rf, nel) ->
      if not (uv rf) then
        List.fold_right
          (fun (n, me) l ->
             mkstr loc (Pstr_module (uv n, module_expr me)) :: l)
          (uv nel) l
      else
        let nel =
          List.map
            (fun (n, me) ->
               let (me, mt) =
                 match me with
                   MeTyc (_, me, mt) -> me, mt
                 | _ ->
                     error (MLast.loc_of_module_expr me)
                       "module rec needs module types constraints"
               in
               uv n, module_type mt, module_expr me)
            (uv nel)
        in
        mkstr loc (Pstr_recmodule nel) :: l
  | StMty (loc, n, mt) -> mkstr loc (Pstr_modtype (uv n, module_type mt)) :: l
  | StOpn (loc, id) ->
      mkstr loc (Pstr_open (long_id_of_string_list loc (uv id))) :: l
  | StTyp (loc, tdl) ->
      mkstr loc (Pstr_type (List.map mktype_decl (uv tdl))) :: l
  | StUse (loc, fn, sl) ->
      Ploc.call_with glob_fname fn
        (fun () -> List.fold_right (fun (si, _) -> str_item si) sl l) ()
  | StVal (loc, rf, pel) ->
      mkstr loc (Pstr_value (mkrf (uv rf), List.map mkpe (uv pel))) :: l
and class_type =
  function
    CtCon (loc, id, tl) ->
      mkcty loc
        (Pcty_constr
           (long_id_of_string_list loc (uv id), List.map ctyp (uv tl)))
  | CtFun (loc, TyLab (_, lab, t), ct) ->
      mkcty loc (Pcty_fun (uv lab, ctyp t, class_type ct))
  | CtFun (loc, TyOlb (loc1, lab, t), ct) ->
      let t =
        let loc = loc1 in MLast.TyApp (loc, MLast.TyLid (loc, "option"), t)
      in
      mkcty loc (Pcty_fun ("?" ^ uv lab, ctyp t, class_type ct))
  | CtFun (loc, t, ct) -> mkcty loc (Pcty_fun ("", ctyp t, class_type ct))
  | CtSig (loc, t_o, ctfl) ->
      let t =
        match uv t_o with
          Some t -> t
        | None -> TyAny loc
      in
      let cil = List.fold_right class_sig_item (uv ctfl) [] in
      mkcty loc (Pcty_signature (ctyp t, cil))
and class_sig_item c l =
  match c with
    CgCtr (loc, t1, t2) -> Pctf_cstr (ctyp t1, ctyp t2, mkloc loc) :: l
  | CgDcl (loc, cl) -> List.fold_right class_sig_item (uv cl) l
  | CgInh (loc, ct) -> Pctf_inher (class_type ct) :: l
  | CgMth (loc, s, pf, t) ->
      Pctf_meth (uv s, mkprivate (uv pf), ctyp (mkpolytype t), mkloc loc) :: l
  | CgVal (loc, s, b, t) ->
      Pctf_val (uv s, mkmutable (uv b), Some (ctyp t), mkloc loc) :: l
  | CgVir (loc, s, b, t) ->
      Pctf_virt (uv s, mkprivate (uv b), ctyp (mkpolytype t), mkloc loc) :: l
and class_expr =
  function
    CeApp (loc, _, _) as c ->
      let (ce, el) = class_expr_fa [] c in
      let el = List.map label_expr el in
      mkpcl loc (Pcl_apply (class_expr ce, el))
  | CeCon (loc, id, tl) ->
      mkpcl loc
        (Pcl_constr
           (long_id_of_string_list loc (uv id), List.map ctyp (uv tl)))
  | CeFun (loc, PaLab (_, lab, po), ce) ->
      mkpcl loc
        (Pcl_fun
           (uv lab, None, patt (patt_of_lab loc (uv lab) po), class_expr ce))
  | CeFun (loc, PaOlb (_, lab, peoo), ce) ->
      let (lab, p, eo) = paolab loc (uv lab) peoo in
      mkpcl loc (Pcl_fun ("?" ^ lab, option expr eo, patt p, class_expr ce))
  | CeFun (loc, p, ce) ->
      mkpcl loc (Pcl_fun ("", None, patt p, class_expr ce))
  | CeLet (loc, rf, pel, ce) ->
      mkpcl loc
        (Pcl_let (mkrf (uv rf), List.map mkpe (uv pel), class_expr ce))
  | CeStr (loc, po, cfl) ->
      let p =
        match uv po with
          Some p -> p
        | None -> PaAny loc
      in
      let cil = List.fold_right class_str_item (uv cfl) [] in
      mkpcl loc (Pcl_structure (patt p, cil))
  | CeTyc (loc, ce, ct) ->
      mkpcl loc (Pcl_constraint (class_expr ce, class_type ct))
and class_str_item c l =
  match c with
    CrCtr (loc, t1, t2) -> Pcf_cstr (ctyp t1, ctyp t2, mkloc loc) :: l
  | CrDcl (loc, cl) -> List.fold_right class_str_item (uv cl) l
  | CrInh (loc, ce, pb) -> Pcf_inher (class_expr ce, uv pb) :: l
  | CrIni (loc, e) -> Pcf_init (expr e) :: l
  | CrMth (loc, s, b, e, t) ->
      let t = option (fun t -> ctyp (mkpolytype t)) (uv t) in
      let e = mkexp loc (Pexp_poly (expr e, t)) in
      Pcf_meth (uv s, mkprivate (uv b), e, mkloc loc) :: l
  | CrVal (loc, s, b, e) ->
      Pcf_val (uv s, mkmutable (uv b), expr e, mkloc loc) :: l
  | CrVir (loc, s, b, t) ->
      Pcf_virt (uv s, mkprivate (uv b), ctyp (mkpolytype t), mkloc loc) :: l
;;

let interf fname ast = glob_fname := fname; List.fold_right sig_item ast [];;

let implem fname ast = glob_fname := fname; List.fold_right str_item ast [];;

let directive loc =
  function
    None -> Pdir_none
  | Some (MLast.ExStr (_, s)) -> Pdir_string s
  | Some (MLast.ExInt (_, i, "")) -> Pdir_int (int_of_string i)
  | Some (MLast.ExUid (_, "True")) -> Pdir_bool true
  | Some (MLast.ExUid (_, "False")) -> Pdir_bool false
  | Some e ->
      let sl =
        let rec loop =
          function
            MLast.ExLid (_, i) | MLast.ExUid (_, i) -> [i]
          | MLast.ExAcc (_, e, MLast.ExLid (_, i)) |
            MLast.ExAcc (_, e, MLast.ExUid (_, i)) ->
              loop e @ [i]
          | e -> Ploc.raise (loc_of_expr e) (Failure "bad ast")
        in
        loop e
      in
      Pdir_ident (long_id_of_string_list loc sl)
;;

let phrase =
  function
    StDir (loc, d, dp) -> Ptop_dir (uv d, directive loc (uv dp))
  | si -> Ptop_def (str_item si [])
;;

module Ast2pt =
  struct
    let interf = interf;;
    let implem = implem;;
    let phrase = phrase;;
    let mkloc = mkloc;;
    let fast = fast;;
    let no_constructors_arity = no_constructors_arity;;
  end
;;
