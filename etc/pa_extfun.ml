(* camlp5r *)
(* pa_extfun.ml,v *)
(* Copyright (c) INRIA 2007-2017 *)

#load "q_MLast.cmo";
#load "pa_extend.cmo";

open Pcaml;

value not_impl name x = do {
  let desc =
    if Obj.is_block (Obj.repr x) then
      "tag = " ^ string_of_int (Obj.tag (Obj.repr x))
    else "int_val = " ^ string_of_int (Obj.magic x)
  in
  print_newline ();
  failwith ("pa_extfun: not impl " ^ name ^ " " ^ desc)
};

value rec mlongid li acc =
  let loc = MLast.loc_of_longid li in
  match li with [
    <:extended_longident< $uid:id$ >> ->
      <:expr< [(Extfun.Econ $str:id$) :: $acc$] >>

  | <:extended_longident< $longid:li$ . $uid:id$ >> ->
      mlongid li <:expr< [(Extfun.Econ $str:id$) :: $acc$] >>
  | <:extended_longident< $longid:_$ ( $longid:_$ ) >> -> failwith "mlongid: LiApp not allowed"
  | _ -> assert False
  ]
;

value rec conv_list f loc =
  fun
  [ [] -> <:expr< [] >>
  | [e :: el] -> <:expr< [$f e$ :: $conv_list f loc el$] >> ]
;

value rec mexpr p =
  let loc = MLast.loc_of_patt p in
  match p with
  [ <:patt< $p1$ $p2$ >> ->
      loop <:expr< [$mexpr p2$] >> p1 where rec loop el =
        fun
        [ <:patt< $p1$ $p2$ >> -> loop <:expr< [$mexpr p2$ :: $el$] >> p1
        | p -> <:expr< Extfun.Eapp [$mexpr p$ :: $el$] >> ]
  | <:patt< $longid:li$ . $p$ >> ->
      let l = mlongid li <:expr< [$mexpr p$] >> in
      <:expr< Extfun.Eacc $l$ >>

  | <:patt< $longid:li$ >> ->
      let l = mlongid li <:expr< [] >> in
      <:expr< Extfun.Eacc $l$ >>

  | <:patt< ($list:pl$) >> -> <:expr< Extfun.Etup $conv_list mexpr loc pl$ >>
  | <:patt< ` $id$ >> -> <:expr< Extfun.Econ $str:id$ >>
  | <:patt< $int:s$ >> -> <:expr< Extfun.Eint $str:s$ >>
  | <:patt< $str:s$ >> -> <:expr< Extfun.Estr $str:s$ >>
  | <:patt< ($p1$ as $_$) >> -> mexpr p1
  | <:patt< $lid:_$ >> -> <:expr< Extfun.Evar () >>
  | <:patt< _ >> -> <:expr< Extfun.Evar () >>
  | <:patt< { $list:l$ } >> -> 
    let mpair (p1,p2) = <:expr< ( $mexpr p1$, $mexpr p2$ ) >> in
    <:expr< Extfun.Erec $conv_list mpair loc l$ >>
  | <:patt< $p1$ | $p2$ >> ->
      Ploc.raise loc (Failure "or patterns not allowed in extfun")
  | p -> not_impl "mexpr" p ]
;

value rec catch_any =
  fun
  [ <:patt< $uid:id$ >> -> False
  | <:patt< ` $_$ >> -> False
  | <:patt< $lid:_$ >> -> True
  | <:patt< _ >> -> True
  | <:patt< ($list:pl$) >> -> List.for_all catch_any pl
  | <:patt< { $list:lpl$ } >> -> List.for_all (fun (_, p) -> catch_any p) lpl
  | <:patt< $p1$ $p2$ >> -> False
  | <:patt< $p1$ | $p2$ >> -> False
  | <:patt< $int:_$ >> -> False
  | <:patt< $str:_$ >> -> False
  | <:patt< ($p1$ as $_$) >> -> catch_any p1
  | p -> not_impl "catch_any" p ]
;

value conv (p, wo, e) =
  let tst = mexpr p in
  let loc = Ploc.encl (MLast.loc_of_patt p) (MLast.loc_of_expr e) in
  let e =
    if wo = None && catch_any p then <:expr< fun $p$ -> Some $e$ >>
    else <:expr< fun [ $p$ $opt:wo$ -> Some $e$ | _ -> None ] >>
  in
  let has_when =
    match wo with
    [ Some _ -> <:expr< True >>
    | None -> <:expr< False >> ]
  in
  <:expr< ($tst$, $has_when$, $e$) >>
;

value rec conv_list tl =
  fun
  [ [pe :: pel] ->
      let loc = MLast.loc_of_expr tl in
      <:expr< [$conv pe$ :: $conv_list tl pel$] >>
  | [] -> tl ]
;

value rec split_or =
  fun
  [ [(<:patt< $p1$ | $p2$ >>, wo, e) :: pel] ->
      split_or [(p1, wo, e); (p2, wo, e) :: pel]
  | [(<:patt< ($p1$ | $p2$ as $p$) >>, wo, e) :: pel] ->
      let p1 =
        let loc = MLast.loc_of_patt p1 in
        <:patt< ($p1$ as $p$) >>
      in
      let p2 =
        let loc = MLast.loc_of_patt p2 in
        <:patt< ($p2$ as $p$) >>
      in
      split_or [(p1, wo, e); (p2, wo, e) :: pel]
  | [pe :: pel] -> [pe :: split_or pel]
  | [] -> [] ]
;

EXTEND
  GLOBAL: expr;
  expr: LEVEL "top"
    [ [ "extfun"; e = SELF; "with"; "["; list = match_case_list; "]" ->
          <:expr< Extfun.extend $e$ $list$ >> ] ]
  ;
  match_case_list:
    [ [ pel = LIST0 match_case SEP "|" ->
          conv_list <:expr< [] >> (split_or pel) ] ]
  ;
  match_case:
    [ [ p = patt; aso = OPT [ "as"; p = patt -> p ];
        w = OPT [ "when"; e = expr -> e ]; "->"; e = expr ->
          let p =
            match aso with
            [ Some p2 -> <:patt< ($p$ as $p2$) >>
            | _ -> p ]
          in
          (p, w, e) ] ]
  ;
END;
