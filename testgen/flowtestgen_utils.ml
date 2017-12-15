(**
 * Copyright (c) 2013-present, Facebook, Inc.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

(* This file contains util functions*)
module S = Ast.Statement;;
module E = Ast.Expression;;
module T = Ast.Type;;
module P = Ast.Pattern;;
module F = Ast.Function;;

module StrSet = Set.Make(struct
    type t = string
    let compare = Pervasives.compare
  end)

let random_choice (arr : 'a array) : 'a = arr.(Random.int (Array.length arr))

(* Generate a sequence of numbers *)
let sequence i j =
  let rec helper n acc =
    if n < i then acc else helper (n - 1) (n :: acc) in
  helper j [];;

(* Read all lines from the in_channel *)
let read_all ic : string list =
  let lines = ref [] in
  try
    while true; do
      lines := input_line ic :: !lines
    done; !lines
  with End_of_file ->
    close_in ic;
    List.rev !lines

(* Read from a file into a string *)
let read_file filename =
  let ic = open_in filename in
  let lines = read_all ic in
  String.concat "\n" lines

(* convert an AST into a string for printing *)
    (*
let string_of_ast endline func =
  fun (ast) ->
    let layout = func (Loc.none, ast) in
    let open Layout_printer in
    let s = (Source.contents (PrettyPrinter.print layout)) in
    if endline then s
    else s |> Str.global_replace (Str.regexp "\n") "";;
let string_of_stmt =
  string_of_ast true Js_layout_generator.statement;;
let string_of_expr =
  string_of_ast false Js_layout_generator.expression;;
let string_of_type =
  string_of_ast false Js_layout_generator.type_;;
*)


(* A hacky version of string_of function for AST nodes.
   This will be replaced once we have a better solution.
*)
let rec string_of_pattern (pattern : Loc.t P.t') =
  match pattern with
  | P.Identifier id ->
    let open P.Identifier in
    (snd id.name) ^
    (if id.optional then "?" else "") ^ " " ^
    (match id.typeAnnotation with
     | Some (_, (_, t)) -> " : " ^ (string_of_type t)
     | None -> "")
  | P.Expression (_, e) -> string_of_expr e
  | P.Assignment assign ->
    let open P.Assignment in
    (string_of_pattern (snd assign.left)) ^
    " = " ^
    (string_of_expr (snd assign.right))
  | _ -> failwith "[string_of_pattern] unsupported pattern"

and string_of_expr (expr : Loc.t E.t') =
  let string_of_proplist plist =
    let helper prop = match prop with
      | E.Object.Property (_, E.Object.Property.Init p) ->
        let open E.Object.Property in
        (match p.key, p.value with
         | Identifier (_, name), (_, e) -> name ^ " : " ^ (string_of_expr e)
         | _ -> failwith "Unsupported expression")
      | _ -> failwith "Unsupported property" in
    String.concat ", " (List.map helper plist) in

  let string_of_assign_op op =
    let open E.Assignment in
    match op with
    | Assign -> "="
    | PlusAssign -> "+="
    | MinusAssign -> "-="
    | MultAssign -> "*="
    | ExpAssign -> "^="
    | DivAssign -> "/="
    | _ -> failwith "unsupported assign" in

  match expr with
  | E.Object o ->
    "{" ^ (string_of_proplist E.Object.(o.properties)) ^ "}"
  | E.Literal lit -> Ast.Literal.(lit.raw)
  | E.Assignment assign ->
    let open E.Assignment in
    [(string_of_pattern (snd assign.left));
     (string_of_assign_op assign.operator);
     (string_of_expr (snd assign.right))]
    |> String.concat " "
  | E.Call call ->
    let open E.Call in
    let callee_str = string_of_expr (snd call.callee) in
    let arglist_str =
      call.arguments
      |> List.map (fun a -> match a with
          | E.Expression (_, e) -> e
          | E.Spread _ -> failwith "[string_of_expr] call does not support spread argument.")
      |> List.map string_of_expr
      |> String.concat ", " in
    callee_str ^ "(" ^ arglist_str ^ ")"
  | E.Identifier (_, id) -> id
  | E.Member mem ->
    let open E.Member in
    let obj_str = string_of_expr (snd mem._object) in
    let prop_str = match mem.property with
      | PropertyIdentifier (_, id) -> id
      | PropertyExpression (_, e) -> string_of_expr e
      | PropertyPrivateName (_, (_, id)) -> id in
    obj_str ^ "." ^ prop_str
  | E.TypeCast cast ->
    let open E.TypeCast in
    (string_of_expr (snd cast.expression)) ^
    " : " ^
    (string_of_type (snd (snd cast.typeAnnotation)))
  | E.Array array ->
    let open E.Array in
    "[" ^
    (List.map (fun elt -> match elt with
         | Some (E.Expression (_, e)) -> string_of_expr e
         | Some (E.Spread (_, e)) -> string_of_expr (E.SpreadElement.((snd e.argument)))
         | None -> "") array.elements
     |> (String.concat ", ")) ^
      "]"
  | _ -> failwith "unknown expr"

and string_of_stmt (stmt : Loc.t S.t') =
  match stmt with
  | S.Block b ->
    S.Block.(b.body)
    |> List.map snd
    |> List.map string_of_stmt
    |> String.concat "\n"
  | S.Empty -> "\n"
  | S.FunctionDeclaration func ->
    let open Ast.Function in
    let fname = match func.id with
      | Some (_, n) -> n
      | None -> "" in
    let params_str =
      let (_, { Ast.Function.Params.params; rest = _ }) = func.params in
      params
      |> List.map snd
      |> List.map string_of_pattern
      |> String.concat ", " in
    let body_str = match func.body with
      | BodyBlock (_, s) -> string_of_stmt (S.Block s)
      | BodyExpression (_, e) -> string_of_expr e in
    let ret_type_str = match func.returnType with
      | Some (_, (_, t)) -> ": " ^ string_of_type t
      | None -> "" in
    "function " ^ fname ^ "(" ^ params_str ^ ") " ^ ret_type_str ^ " {\n" ^
    body_str ^
    "}\n"
  | S.Return r ->
    let open S.Return in
    (match r.argument with
     | Some (_, e) -> "return " ^ (string_of_expr e) ^ "\n;"
     | None -> "return;\n")
  | S.VariableDeclaration decl ->
    let open S.VariableDeclaration in
    let string_of_dtor dtor =
      let open S.VariableDeclaration.Declarator in
      let init_str = match dtor.init with
        | Some (_, e) -> "= " ^ (string_of_expr e)
        | None -> "" in
      (string_of_pattern (snd dtor.id)) ^ init_str in
    let kind_str = match decl.kind with
      | Var -> "var"
      | Let -> "let"
      | Const -> "const" in
    let dlist = List.map snd decl.declarations in
    let dlist_str = String.concat ", " (List.map string_of_dtor dlist) in
    kind_str ^ " " ^ dlist_str ^ "\n"
  | S.Expression e ->
    let open S.Expression in
    (string_of_expr (snd e.expression)) ^ ";\n"
  | _ -> failwith "[string_of_stmt] Unspported stmt"

and string_of_type (t : Loc.t T.t') =

  match t with
  | T.Any -> "any"
  | T.Mixed -> "mixed"
  | T.Empty -> "empty"
  | T.Void -> "void"
  | T.Null -> "null"
  | T.Number -> "number"
  | T.String -> "string"
  | T.Boolean -> "boolean"
  | T.Object ot ->
    let open T.Object in
    let string_of_prop prop = match prop with
      | T.Object.Property (_, p) ->
        let open T.Object.Property in
        let key_str = match p.key with
          | E.Object.Property.Literal (_, lit)  -> Ast.Literal.(lit.raw)
          | E.Object.Property.Identifier (_, name) -> name
          | E.Object.Property.PrivateName (_, (_, name)) -> name
          | E.Object.Property.Computed (_, e) -> string_of_expr e in
        let t_str = match p.value with
          | Init (_, init_t) -> string_of_type init_t
          | Get (_, ft) -> string_of_type (T.Function ft)
          | Set (_, ft) -> string_of_type (T.Function ft) in
        let opt = if p.optional then "?" else "" in
        key_str ^ opt ^ " : " ^ t_str
      | _ -> failwith "[string_of_prop] unsupported property" in
    let prop_str_list = ot.properties
      |> List.map string_of_prop
      |> String.concat ", " in
    if ot.exact then "{|" ^ prop_str_list ^ "|}"
    else "{" ^ prop_str_list ^ "}"
  | T.Union ((_, t1), (_, t2), trest) ->
    let t_strlist =
      [(string_of_type t1); (string_of_type t2)]
      @ (trest |> (List.map snd) |> (List.map string_of_type)) in
    String.concat " | " t_strlist
  | T.StringLiteral st -> Ast.StringLiteral.(st.raw)
  | T.NumberLiteral nt -> Ast.NumberLiteral.(nt.raw)
  | T.BooleanLiteral bt -> if bt then "true" else "false"
  | T.Function func ->
    let open T.Function in
    let string_of_param param =
      let open T.Function.Param in
      let opt_str = if param.optional then "?" else "" in
      let name_str = match param.name with
        | Some (_, id) -> id ^ opt_str ^ " : "
        | None -> "" in
      name_str ^ (string_of_type (snd param.typeAnnotation)) in
    let params_str =
      let (_, { T.Function.Params.params; rest = _ }) = func.params in
      params
      |> List.map snd
      |> List.map string_of_param
      |> String.concat ", " in
    let ret_type_str = (string_of_type (snd func.returnType)) in
    "(" ^ params_str ^ ") => " ^ ret_type_str
  | _ -> failwith "[string_of_type] unsupported type"


(* A generator function for creating functions that makes variables and
 * properties
 *)
let mk_gen (prefix : string) =
  let count = ref 0 in
  fun () ->
    let vname : string = prefix ^ (string_of_int !count) in
    count := !count + 1;
    vname;;

(* A function that makes unique names. *)
let mk_var = mk_gen "v_";;
let mk_prop = mk_gen "p_";;
let mk_func = mk_gen "f";;
let mk_obj_cons = mk_gen "Obj";;

(* Convert a code and its dependencies into a list
   CAUTION: This function will lose some independencies between
   codes *)
let list_of_code (code : Code.t) : Loc.t Ast.Statement.t list =
  let open Code in
  let rec helper acc lst = match lst with
    | [] -> acc
    | hd :: tl ->
      hd.stmt :: (helper (helper acc hd.stmt_deps) tl) in
  (code.stmt :: (helper [] code.stmt_deps)) |> List.rev


(* Convert a list of statements into a code object. Dependencies
   are based on the order of the statements. Thus, it will create
   unnecessary dependnecies. USE THIS WITH CAUTION. *)
let code_of_stmt_list (slist : Loc.t Ast.Statement.t list) : Code.t option =
  let open Code in

  let rec helper lst = match lst with
    | [] -> failwith "List is empty, but this cannot happen"
    | hd :: [] -> {stmt = hd; stmt_deps = []}
    | hd :: tl -> {stmt = hd; stmt_deps = [helper tl]} in

  if (List.length slist) = 0 then None
  else
    let rev_slist = List.rev slist in
    Some (helper rev_slist)

(* We also remove redundant assignment as well. Redundant
   assignments will appear after empty object init.
*)
let rm_prop_write
    (prop : Loc.t E.Member.t)
    (clist : Code.t list) : Code.t list =
  let open S.Expression in
  let open Code in
  let is_target (code : Code.t) : bool =
    match code.stmt with
    | (_, S.Expression {expression = (_, E.Assignment assign);
                        directive = _}) ->
      (match E.Assignment.(assign.left) with
       | (_, P.Expression (_, E.Member p)) when p = prop -> false
      | _ -> true)
    | _ -> true in
  List.filter is_target clist;;

(* Remove variable declaration from a list of code where vname is
 * defined
 *)
let rm_vardecl
    (vname : string)
    (clist : Code.t list) : Code.t list =
  let open S.VariableDeclaration.Declarator in
  let open S.VariableDeclaration in

  (* Check whether this declaration defines the target variable *)
  let is_target (decl : Loc.t S.VariableDeclaration.Declarator.t) =
    let decl' = (snd decl) in
    match decl'.id with
    | (_, P.Identifier { P.Identifier.name = (_, name); _;})
      -> name != vname
    | _ -> true in

  let open Code in
  List.fold_left (fun acc code -> match code.stmt with
      | (loc, S.VariableDeclaration {declarations = decls; kind = k;}) ->
        (* Remove vname's decls *)
        (match List.filter is_target decls with
         (* No declarators. We remove this statement *)
         | [] -> acc
          (* Create a new var decl statement *)
         | lst ->
           let new_stmt = {declarations = lst; kind = k} in
           let new_code =
             {stmt = (loc, (S.VariableDeclaration new_stmt));
              stmt_deps = code.stmt_deps} in
           new_code :: acc)
      | _ -> code :: acc) [] clist |> List.rev


(* This is the JSON config library. It loads a JSON file into a list
   of (name, value) pairs. Simply provide load_config a JSON filename
   and access the values through the get functions.

   This module provides simple and easy value retrieval by supporting
   accessing using strings as key names separated by dots, since
   config might be recursive. For example, if we have a config like
   this:

   {"n" : 100, "o" : {"foo" : "bar"}}

   we can just provide "o.foo" to access "foo" inside "o". Therefore,
   dots are not allowed inside key names.

   In order to benefit from type checking, it is highly recommended to
   convert the config into a domain-specific record type once the JSON
   config is loaded. Try to limit the number of get function calls,
   because it is very easy to get runtime error.
*)

module Config = struct

  (* config type *)
  type value =
      Int of int
    | Str of string
    | Bool of bool
    | Obj of t
  and t = (string * value) list;;

  (* Convert a JSON ast into a config *)
  let rec to_config (ast : Loc.t E.Object.t) : t =

    (* get config value from an expression *)
    let get_value (expr : Loc.t E.t') : value = match expr with
      | E.Object o -> Obj (to_config o)
      | E.Literal lit -> let open Ast.Literal in
        (match lit.value with
         | String s -> Str s
         | Boolean b -> Bool b
         | Number n -> Int (int_of_float n)
         | _ -> failwith "We only support string, bool, and int as config vals.")
      | _ -> failwith "Unknown AST type for config" in

    let open E.Object in

    (* get all the properties *)
    let prop_list = (List.map (fun p -> match p with
        | Property (_, E.Object.Property.Init { key = k; value = (_, e); _ }) ->
          let k = (match k with
              | E.Object.Property.Literal (_, id) -> Ast.Literal.(match id.value with
                  | String s ->
                    if String.contains s '.' then
                      failwith ("Config key '" ^
                                s ^
                                "' contains dots which are not allowed");
                    s
                  | _ -> failwith "Config key can only be a string")
              | _ -> failwith "Config key can only be a string literal.") in
          let v = get_value e in
          (k, v)
        | Property (_, E.Object.Property.Get _) ->
          failwith "Getter properties are not allowed"
        | Property (_, E.Object.Property.Set _) ->
          failwith "Setter properties are not allowed"
        | _ ->
          failwith "Spread properties are not allowed"
    ) ast.properties) in
    prop_list

  (* Convert a config into an expression ast. Mainly used for printing *)
  let rec ast_of_config (c : t) : Loc.t E.Object.t =

    let expr_of_value (v : value) : Loc.t E.t' = let open Ast.Literal in
      match v with
      | Int i -> E.Literal {value = Number (float_of_int i); raw = string_of_int i}
      | Str s -> E.Literal {value = String s; raw = "\"" ^ s ^ "\""}
      | Bool b -> E.Literal {value = Boolean b; raw = string_of_bool b}
      | Obj o -> E.Object (ast_of_config o) in

    (* Convert all properties into object properties *)
    let open E.Object in
    let prop_list =
      let open E.Object.Property in
      List.map (fun (k, v) ->
          let key = Identifier (Loc.none, "\"" ^ k ^ "\"") in
          let value = Loc.none, expr_of_value v in
          Property (Loc.none, Init {key;
                               value;
                               shorthand = false})) c in
    {properties = prop_list};;

  (* Convert a config into string for printing *)
  let string_of_config (c : t) : string =
    let ast = ast_of_config c in
    string_of_expr (E.Object ast)

  (* Return an empty config *)
  let empty () : t =
    let open E.Object in
    to_config {properties = []};;

  (* Get a value from the config given a string.*)
  let get (conf : t) (prop_name : string) : value =
    let name_list = Str.split (Str.regexp "\\.") prop_name in

    let rec helper (c : t) (slist : string list) = match slist with
      | [] -> failwith "Config is empty"
      | hd :: [] -> List.assoc hd c
      | hd :: tl -> (match List.assoc hd c with
          | Obj o -> helper o tl
          | _ -> failwith "It has to be a config type") in
    try
      helper conf name_list
    with
      Not_found -> failwith ("No config value for '" ^ prop_name)

  (* Normal get function requires users to do type conversion. That's
     why we are creating these functions. It checks types as well.
  *)
  let get_int ?default (conf : t) (prop_name : string) : int =
    match get conf prop_name with
    | Int i -> i
    | _ -> (match default with
        | None -> failwith ("Config '" ^ prop_name ^ "' is not an int.")
        | Some i -> i);;
  let get_str ?default (conf : t) (prop_name : string) : string =
    match get conf prop_name with
    | Str s -> s
    | _ -> (match default with
        | None -> failwith ("Config '" ^ prop_name ^ "' is not a string.")
        | Some s -> s);;
  let get_bool ?default (conf : t) (prop_name : string) : bool =
    match get conf prop_name with
    | Bool b -> b
    | _ -> (match default with
        | None -> failwith ("Config '" ^ prop_name ^ "' is not a boolean.")
        | Some b -> b);;

  (* load a config from a string *)
  let load_json_config_string ?filename json_str : t =
    let expr_ast = Parser_flow.json_file
        json_str
        (match filename with
         | None -> None
         | Some f -> (Some (File_key.JsonFile f))) in
    to_config (match (fst expr_ast) with
        | (_, E.Object o) -> o
        | _ -> failwith "Can only be an object")

  (* Load a config into _config *)
  let load_json_config (filename : string) : t =
    let content = read_file filename in
    load_json_config_string ~filename content;;
end

(* Metadata for involing flow type checking *)
let stub_metadata ~root ~checked = { Context.
  local_metadata = { Context.
    checked;
    munge_underscores = false;
    (*
    verbose = Some { Verbose.depth = 2; indent = 2 };
       *)
    verbose = None;
    weak = false;
    jsx = None;
    strict = true;
  };
  global_metadata = { Context.
    enable_const_params = false;
    enforce_strict_type_args = true;
    enforce_strict_call_arity = true;
    esproposal_class_static_fields = Options.ESPROPOSAL_ENABLE;
    esproposal_class_instance_fields = Options.ESPROPOSAL_ENABLE;
    esproposal_decorators = Options.ESPROPOSAL_ENABLE;
    esproposal_export_star_as = Options.ESPROPOSAL_ENABLE;
    facebook_fbt = None;
    ignore_non_literal_requires = false;
    max_trace_depth = 0;
    max_workers = 0;
    root;
    strip_root = true;
    suppress_comments = [];
    suppress_types = SSet.empty;
  };
}

(* Invoke flow for type checking *)
let flow_check (code : string) : string option =
  if code = "" then
    None
  else
    try
      let root = Path.dummy_path in
      let master_cx = Flow_js.fresh_context
          (stub_metadata ~root ~checked:false)
          File_key.Builtins
          Files.lib_module_ref in

      (* Merge builtins *)
      let builtin_metadata = stub_metadata ~root ~checked:true in
      let lint_severities = LintSettings.default_severities in
      let builtins_ast, _ = Parser_flow.program (read_file "lib/core.js") in
      let builtins_file_sig = match File_sig.program ~ast:builtins_ast with
      | Ok file_sig -> file_sig
      | Error _ -> failwith "error calculating builtins file sig"
      in
      let builtins_cx, _ = Type_inference_js.infer_lib_file   (* The crucial bit *)
          ~metadata:builtin_metadata ~exclude_syms:SSet.empty ~lint_severities
          ~file_sig:builtins_file_sig File_key.Builtins builtins_ast in
      let _ = Merge_js.merge_lib_file builtins_cx master_cx in
      let reason = Reason.builtin_reason (Reason.RCustom "module") in
      let builtin_module = Obj_type.mk master_cx reason in
      Flow_js.flow_t master_cx (builtin_module, Flow_js.builtins master_cx);
      Merge_js.ContextOptimizer.sig_context master_cx [Files.lib_module_ref] |> ignore;

      (* Merge the input program into the context *)
      let strict_mode = StrictModeSettings.empty in
      let stub_docblock = { Docblock.
                            flow = Docblock.(Some OptIn);
                            preventMunge = None;
                            providesModule = None;
                            isDeclarationFile = false;
                            jsx = None;
                          } in
      let input_ast, _ = Parser_flow.program code in
      let filename = File_key.SourceFile "/tmp/foo.js" in
      let file_sig = match File_sig.program ~ast:input_ast with
      | Ok file_sig -> file_sig
      | Error _ -> failwith "error calculating implementation file sig"
      in
      let file_sigs = Utils_js.FilenameMap.singleton filename file_sig in
      let reqs = Merge_js.Reqs.empty in
      (* WARNING: This line might crash. That's why we put the entire block into a try catch *)
      let final_cx, _other_cxs = Merge_js.merge_component_strict
          ~metadata:builtin_metadata ~lint_severities ~strict_mode ~file_sigs
          ~get_ast_unsafe:(fun _ -> input_ast)
          ~get_docblock_unsafe:(fun _ -> stub_docblock)
          [filename] reqs [] master_cx in  (* merge_component_strict expects the master's sig context here. *)
      let errors, warnings, _, _ = Error_suppressions.filter_suppressed_errors
          Error_suppressions.empty (ExactCover.default_file_cover filename) (Context.errors final_cx)
      in
      let error_num = Errors.ErrorSet.cardinal errors in
      if error_num = 0 then
        None
      else begin

        (* This is used for pringing errors *)
        let string_of_errors (json : Hh_json.json) : string =
          let open Hh_json in
          let string_of_error (error_json : json) : string =
            let error = get_object_exn error_json in
            let msg_helper (msg_json : json) : string =
              let msg = get_object_exn msg_json in
              let desc = get_string_exn (List.assoc "descr" msg) in
              let loc = get_object_exn (List.assoc "loc" msg) in
              let start =
                let start_json = get_object_exn (List.assoc "start" loc) in
                (Printf.sprintf
                   "line %d\tcolumn %d\toffset %d"
                   (int_of_string (get_number_exn (List.assoc "line" start_json)))
                   (int_of_string (get_number_exn (List.assoc "column" start_json)))
                   (int_of_string (get_number_exn (List.assoc "offset" start_json)))) in
              let eend =
                let end_json = get_object_exn (List.assoc "end" loc) in
                (Printf.sprintf
                   "line %d\tcolumn %d\toffset %d"
                   (int_of_string (get_number_exn (List.assoc "line" end_json)))
                   (int_of_string (get_number_exn (List.assoc "column" end_json)))
                   (int_of_string (get_number_exn (List.assoc "offset" end_json)))) in
              Printf.sprintf "Error: %sStart: %s\nEnd: %s\n" desc start eend
            in
            String.concat "" (List.map msg_helper (get_array_exn (List.assoc "message" error)))
          in
          (List.assoc "errors" (get_object_exn json))
          |> get_array_exn
          |> List.map string_of_error
          |> String.concat "\n"
        in

        (* Return error message *)
        let error_msg =
          let stdin_file = None in
          let strip_root = None in
          let profiling = None in
          let suppressed_errors = [] in
          let res = Errors.Json_output.full_status_json_of_errors ~strip_root ~profiling ~stdin_file
              ~suppressed_errors ~errors ~warnings () in
        (*
        Printf.printf "%s\n" (Hh_json.json_to_string ~pretty:false res);
           *)
          string_of_errors res in
    (*
      Printf.printf "'%s'\n" error_msg;
  Errors.Cli_output.print_errors stdout Errors.Cli_output.default_error_flags None errors warnings ();
       *)
        Some error_msg
      end
    with _ -> Some "Failed to type check."

let assert_func = "
// from http://tinyurl.com/y93dykzv
const util = require('util');
function assert_type(actual: any, expected: any) {
    if(typeof(actual) != 'object' || typeof(expected) != 'object') {
        if(Array.isArray(expected)) {
            if(expected.indexOf(actual) === -1) {
                var message = '';
                var expected_str = expected.toString();

                var actual_str = 'null';
                if(actual != null) {
                    actual_str = actual.toString();
                }
                message = message.concat('Not contain: ',
                                         'Actual : ',
                                         actual_str,
                                         ' != Expected: ',
                                         expected_str);
                console.log(message);
                throw new Error(message);
            }
        } else if(actual != expected) {
            var expected_str = 'null';
            if(expected != null) {
                expected_str = expected.toString();
            }

            var actual_str = 'null';
            if(actual != null) {
                actual_str = actual.toString();
            }
            var message = '';
            message = message.concat('Not equal: ',
                                     'Actual : ',
                                     actual_str,
                                     ' != Expected: ',
                                     expected_str);
            console.log(message);
            throw new Error(message);
        }
    } else {
        for(var prop in expected) {
            if(expected.hasOwnProperty(prop)) {
                if(!actual.hasOwnProperty(prop)) {
                    var message = '';
                    message = message.concat('Missing property: ', prop.toString());
                    console.log(message);
                    throw new Error(message);
                }
                assert_type(actual[prop], expected[prop]);
            }
        }
    }
}
function check_opt_prop(obj_list : any, actual : any, expected : any) {
    var len = obj_list.length;
    for(var i = 0; i < len; ++i) {
        if(obj_list[i] === undefined) {
            return;
        }
    }
    if(actual === undefined) {
        return;
    }
    assert_type(actual, expected);
}
\n\n
";;

(* type check a piece of code.
 * Return true if this code doesn't have type error.
 *)
let type_check (code : string) : string option =
  (Printf.sprintf "/* @flow */\n%s\n" (assert_func ^ code))
  |> flow_check

let is_typecheck engine_name = engine_name = "union"

(* Run Javascript programs in batch mode *)
let batch_run (code_list : string list) : (string option) list =
  (* Wrap the input program into a stand alont scope with try-catch block *)
  let to_stmt (code : string) : string =
    Printf.sprintf
"(function () {
    try {
      %s
      console.log('Done');
    } catch (_err_) {
      console.log(_err_.message);
    }
})();\n" code in

  (* Split the batch run output into a list of single-program outputs *)
  let to_msg_list (output : string) : (string option) list =
    let msg_list = Str.split (Str.regexp "====\n") output in
    List.map (fun m -> if (String.trim m) = "Done" then None else Some m) msg_list in

  (* Convert all programs into a string for batch run *)
  let progs = List.map to_stmt code_list in
  let progs_string = String.concat "console.log('====');\n" progs in

  (* run all the programs *)
  let cmd = "./node_modules/.bin/flow-remove-types" ^ " -a -p | node" in
  let content = progs_string in
  let ic, oc = Unix.open_process cmd in
  let out_str = Printf.sprintf "/* @flow */\n%s\n" (assert_func ^ content) in
  Printf.fprintf oc "%s" out_str;
  close_out oc;
  let lines = read_all ic in
  close_in ic;
  let _  = match (Unix.close_process (ic, oc)) with
    | Unix.WEXITED code -> code
    | _ -> failwith "Command exited abnormally." in
  String.concat "\n" lines |> to_msg_list