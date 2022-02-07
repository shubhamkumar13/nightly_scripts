#!/usr/bin/env ocaml
#use "topfind";;
#require "bos";;
#require "fpath";;
#require "unix";;
#require "str";;
module Bos = Bos;;
module Fpath = Fpath;;
module Unix = Unix;;
module Str = Str;;

(* Commands used *)
let mkdir = Bos.Cmd.v "mkdir"
let date = Bos.Cmd.v "date"
let git = Bos.Cmd.v "git"
let cp = Bos.Cmd.v "cp"
let make = Bos.Cmd.v "make"
let eval = Bos.Cmd.v "eval"

let sandmark_nightly_workspace = Fpath.(v (Unix.getenv "HOME") / "sandmark_nightly_workspace")
let sandmark_nightly = Fpath.(sandmark_nightly_workspace / "sandmark-nightly")
let sandmark = Fpath.(sandmark_nightly_workspace / "sandmark")
let opam_env =
  let opam = Bos.Cmd.v "opam" in
  let opam_env = Bos.Cmd.(opam % "env") in
  Bos.OS.Cmd.(run_out opam_env |> to_string)
  |> Result.get_ok


let does_sandmark_nightly_workspace_exists () : bool = 
  match (Bos.OS.Path.exists sandmark_nightly, Bos.OS.Path.exists sandmark) with
  | Error _, Error _ -> failwith "Something went wrong with function -> does_sandmark_nightly_workspace_exists\n"
  | Error _, Ok _ -> failwith "Something went wrong with function -> does_sandmark_nightly_workspace_exists\n"
  | Ok _, Error _ -> failwith "Something went wrong with function -> does_sandmark_nightly_workspace_exists\n"
  | Ok x, Ok y -> x && y

let create_dir (sandmark_nightly : Fpath.t) (type_of_benchmark : string) (hostname : string) (timestamp : string) (ocaml_variant : string) : unit =
  let path = Fpath.to_string @@ Fpath.(sandmark_nightly / type_of_benchmark / hostname / timestamp / ocaml_variant) in
  let dir = Bos.Cmd.(mkdir % "-p" % path) in
  let _ = Bos.OS.Cmd.(run dir) in
  ()

(* Get the ocaml trunk repo commit *)
let ocaml_trunk_commit_id (repo : string) (branch : string) : string =
  let git_ls_remote = Bos.Cmd.(git % "ls-remote") in
  let git_ls_remote = Bos.Cmd.(git_ls_remote % repo) in
  let git_ls_remote = Bos.Cmd.(git_ls_remote % branch) in
  let commit_ids = Result.get_ok @@ Bos.OS.Cmd.(run_out git_ls_remote |> to_lines) in
  let latest_commit_id = List.nth (Str.split (Str.regexp "[ \n\r\x0c\t]+") (List.nth commit_ids 0)) 0 in
  latest_commit_id


(* Get the ocaml stable repo link using the json file *)
let ocaml_stable_commit_id (repo : string) : string =
  let commit_id = Str.split (Str.regexp "[/]") repo |> fun lst -> List.nth lst ((List.length lst) - 1) in
  let commit_id =  List.nth (Str.split (Str.regexp "[.]") commit_id) 0 in
  commit_id

(* The hostname *)
let hostname = "local"

(* Timestamp *)
let timestamp () : string =
  let time = Bos.Cmd.(date % "+%Y%m%d_%H%M%S") in
  let time = Bos.OS.Cmd.(run_out time) in
  match Bos.OS.Cmd.(to_string time) with
  | Ok s -> s
  | Error _ -> failwith "Something went wrong with -> timestamp"

let get_latest_sandmark () : unit =
  let _ = Bos.OS.Dir.set_current sandmark in
  let git_checkout = Bos.Cmd.(git % "checkout" % "main") in
  let git_pull = Bos.Cmd.(git % "pull" % "origin" % "main") in
  let make_clean = Bos.Cmd.(make % "clean") in
  let eval_opam_env = Bos.Cmd.(eval % opam_env) in
  let _ = Bos.OS.Cmd.(run git_checkout) in
  let _ = Bos.OS.Cmd.(run git_pull) in
  let _ = Bos.OS.Cmd.(run make_clean) in
  let _ = Bos.OS.Cmd.(run eval_opam_env) in
  ()

let run_sequential_benchmark () =
  (* Check if sandmark nightly workspace exists *)
  (* if does_sandmark_nightly_workspace_exists () then begin *)
    (* If it does exist then create a directory *)
      (* creating a directory requires
        1. sandmark_nightly_workspace dir info
        2. sequential or parallel
        3. hostname
        4. commit_id info for that particular repo *)
  let trunk_commit = ocaml_trunk_commit_id "https://github.com/ocaml/ocaml.git" "trunk" in
  let stable_commit = ocaml_stable_commit_id "https://github.com/ocaml/ocaml/archive/b73cbbea4bc40ffd26a459d594a39b99cec4273d.zip" in
  let _ = create_dir sandmark_nightly "sequential" hostname (timestamp ()) trunk_commit in
  let _ = create_dir sandmark_nightly "sequential" hostname (timestamp ()) stable_commit in
  let _ = get_latest_sandmark () in
  let _ = Bos.OS.Dir.set_current sandmark in
  let _ = Bos.OS.Env.set_var "TAG" (Some "\"macro_bench\"") in
  let run_config_filtered = Bos.Cmd.(make % "run_config_filtered.json") in
  let _ = Bos.OS.Cmd.(run run_config_filtered) in
  let _ = Bos.OS.Env.set_var "USE_SYS_DUNE_HACK" (Some "1") in
  let _ = Bos.OS.Env.set_var "RUN_CONFIG_JSON" (Some "run_config_filtered.json") in
  let run_sequential_trunk_benchmark = Bos.Cmd.(make % "ocaml-versions/5.00.0+trunk.bench") in
  let run_sequential_stable_benchmark = Bos.Cmd.(make % "ocaml-versions/5.00.0+stable.bench") in
  let _ = Bos.OS.Cmd.(run run_sequential_trunk_benchmark) in
  let _ = Bos.OS.Cmd.(run run_sequential_stable_benchmark) in
  ()

let run_parallel_benchmark = ()

(* Set current directory to sandmark nightly workspace directory
  and run the benchmarks individually 
  1. set dir to sandmark nightly workspace
  2. set to sandmark_nightly_workspace/sandmark
  3. run the sequential benchmarks
  4. run the parallel benchmarks
*)

let _ =
  (* match Bos.OS.Dir.current () with
  | Error _ -> Printf.printf "error current\n"
  | Ok x -> Printf.printf "%s\n" (Fpath.to_string x);
  Bos.OS.Dir.set_current @@ Fpath.add_seg (Result.get_ok @@ Bos.OS.Dir.current ()) "test" |> fun dir ->
  match dir with
  | Error _ -> Printf.printf "error change\n"
  | Ok _ -> 
    Printf.printf "%s\n" 
    @@ (Fpath.to_string @@ Result.get_ok @@ Bos.OS.Dir.current ());
  Printf.printf "%s\n" @@ Fpath.to_string @@ sandmark_nightly_workspace *)
  (* let ls = Bos.Cmd.v "ls" in
  let ls = Bos.OS.Cmd.(run_out ls) in
  Printf.printf "%s\n" @@ Result.get_ok @@ Bos.OS.Cmd.(to_string ls) *)
  run_sequential_benchmark ()