open Riak
open Sys
open Unix
open OUnit

let  (|>) x f = f x

let testbucket() =
  let i = int_of_float(Unix.time()) in
    Random.init i;
    let bucketnum = Random.int 999999999 in
    let tb = ("testbucket_" ^ string_of_int(bucketnum)) in
      tb;;

let test_ip() =
  try
    Sys.getenv("RIAK_OCAML_TEST_IP")
  with Not_found ->
    "127.0.0.1"

let test_port() =
  try
    int_of_string(Sys.getenv("RIAK_OCAML_TEST_PORT"))
  with Not_found ->
    8081

let open_riak_connection clientid =
  try
    let ip = test_ip() in
    let port = test_port() in
    let conn = riak_connect_with_defaults ip port in
      riak_set_client_id conn clientid;
      conn
  with Not_found ->
    riak_connect_with_defaults "127.0.0.1" 8081

let setup _ =
  open_riak_connection "oUnit"


let teardown conn =
  riak_disconnect conn;
  ()

let test_case_ping conn =
  match riak_ping conn with
    | true -> ()
    | false -> assert_failure("Can't connect to Riak")

let test_case_ping_fail _ =
  ()

let test_case_invalid_network _ =
  ()

let test_case_server_info conn =
  let (node, version) = riak_get_server_info conn in
    assert_bool "Non empty node id" (node <> "");
    assert_bool "Non empty version #" (version <> "")

let test_case_client_id conn =
  let test_client_id = testbucket() in
  let _ = riak_set_client_id conn test_client_id in
  let client_id = riak_get_client_id conn in
    assert_equal test_client_id client_id

let show_option v =
  match v with
    | None -> print_endline "NONE"
    | Some x -> print_endline x

let test_case_put_raw conn =
  let bucket = testbucket() in
  let rec putmany n =
    match n with
      | 0 -> ()
      | n ->
          let newkey = "foo" ^ string_of_int(n) in
          let newval = "bar" ^ string_of_int(n) in
          let objs =
            riak_put_raw conn bucket (Some newkey)
              newval [Put_return_body true] None in
          let testval os =
            match os with
              | [] -> assert_failure "No objects returned from put"
              | o :: [] ->
                  (match o.obj_vclock with
                    | Some v -> assert_bool "Invalid vclock" (v <> "")
                    | None -> assert_failure
                          "Put with return_body didn't return any data")
              | o :: tl -> assert_failure "Put returned sublings"
          in
            testval objs;
            putmany (n-1)
  in
  let rec getmany n =
    match n with
      | 0 -> ()
      | n ->
          let getkey = "foo" ^ string_of_int(n) in
          let getval = "bar" ^ string_of_int(n) in
          let obj = riak_get conn bucket getkey [] in
            match obj with
              | Some o ->
                  (match o.obj_value with
                     | Some v ->
                         assert_equal v getval;
                         getmany (n-1)
                     | None -> assert_failure "Invalid value at key")
              | None -> assert_failure "Object not found"
  in
    putmany 1000;
    sleep(5);
    getmany 1000;;

let test_case_put conn =
  let bucket = testbucket() in
  let rec putmany n =
    match n with
      | 0 -> ()
      | n ->
          let newkey = "foo" ^ string_of_int(n) in
          let newval = "bar" ^ string_of_int(n) in
          let objs =
            riak_put conn bucket (Some newkey) newval [Put_return_body true] in
          let testval os =
            match os with
              | [] -> assert_failure "No objects returned from put"
              | o :: [] ->
                  (match o.obj_vclock with
                    | Some v -> assert_bool "Invalid vclock" (v <> "")
                    | None -> assert_failure
                          "Put with return_body didn't return any data")
              | o :: tl -> assert_failure "Put returned sublings"
          in
            testval objs;
            putmany (n-1)
  in
  let rec getmany n =
    match n with
      | 0 -> ()
      | n ->
          let getkey = "foo" ^ string_of_int(n) in
          let getval = "bar" ^ string_of_int(n) in
          let obj = riak_get conn bucket getkey [] in
            match obj with
              | Some o ->
                  (match o.obj_value with
                     | Some v ->
                         assert_equal v getval;
                         getmany (n-1)
                     | None -> assert_failure "Invalid value at key")
              | None -> assert_failure "Object not found"
  in
    putmany 1000;
    sleep(5);
    getmany 1000;;


let test_case_get conn =
  let bucket = testbucket() in
  let gt = "get_test" in
  let tv = "test_value" in
    riak_put_raw conn bucket (Some gt) tv [] None |> ignore;
    let result = riak_get conn bucket gt [] in
      match result with
        | None -> assert_failure "Get value not found"
        | Some value ->
            match value.obj_value with
               | Some v -> assert_equal v tv
               | None -> assert_failure "Get value empty"

let test_case_get_with_siblings _ =
  let conn0 = open_riak_connection "Foo" in
  let conn1 = open_riak_connection "Bar" in
  let bucket = testbucket() in
  let gst = "get_sibling_test" in
    riak_set_bucket conn0 bucket None (Some true);
    sleep(1);
    riak_put_raw conn0 bucket (Some gst) "test_sibling_value_1" [] None |> ignore;
    riak_put_raw conn1 bucket (Some gst) "test_sibling_value_2" [] None |> ignore;
    (* make sure the default resolver throws exception when 
     * siblings are found *)
    try
      riak_get conn1 bucket gst [] |> ignore;
      assert_failure "Default sibling resolution should throw an exception"
    with RiakSiblingException s ->
      (* this is good *)
      ()

let test_case_del conn =
  let bucket = testbucket() in
  let gt = "del_test" in
  let tv = "test_value" in
    riak_put_raw conn bucket (Some gt) tv [] None |> ignore;
    sleep(3);
    riak_del conn bucket "del_test" [] |> ignore;
    match riak_get conn bucket gt [] with
      | None -> ()
      | Some _ -> assert_failure "Deleted value found. Sad panda"

let test_case_list_buckets conn =
  let bucket = testbucket() in
  let gt = "bucket_test" in
  let tv = "test_value" in
    riak_put_raw conn bucket (Some gt) tv [] None |> ignore;
    sleep(1);
    let buckets = riak_list_buckets conn in
      assert_bool "Buckets length > 0" (List.length buckets > 0);
      assert_bool "Find a specific bucket"
        (List.exists (fun x -> x = bucket) buckets)

let test_case_list_keys conn =
  let bucket = testbucket() in
  let rec put_many num =
    match num with
      | 0 -> ()
      | n -> (let tk = "bucket_test" ^ string_of_int(n) in
              let tv = "test_value" in
                riak_put_raw conn bucket (Some tk) tv [] None |> ignore;
                put_many (n-1))
  in
    put_many 66;
    let keys = riak_list_keys conn bucket in
      assert_equal 66 (List.length keys);
      assert_bool "Find a key"
        (List.exists (fun x -> x = "bucket_test54") keys)

let test_case_get_bucket conn =
  let bucket = testbucket() in
  let gt = "bucket_test" in
  let tv = "test_value" in
    riak_put_raw conn bucket (Some gt) tv [] None |> ignore;
    sleep(1);
    let (n, multi) = riak_get_bucket conn bucket in
      (match n with
        | Some nval -> assert_bool "Valid bucket n value" (nval > 0l)
        | None -> assert_failure "Unexpected default N value");
      (match multi with
        | Some multival -> assert_equal false multival
        | None -> assert_failure "Unexpected default multi value")

let test_case_set_bucket conn =
  let bucket = testbucket() in
  let gt = "bucket_test" in
  let tv = "test_value" in
    riak_put_raw conn bucket (Some gt) tv [] None |> ignore;
    sleep(1);
    riak_set_bucket conn bucket (Some 2l) (Some true);
    sleep(1);
    let (n, multi) = riak_get_bucket conn bucket in
      (match n with
         | Some nval -> assert_equal 2l nval
         | None -> assert_failure "Unexpected N value");
      (match multi with
         | Some multival -> assert_equal true multival
         | None -> ());
      riak_set_bucket conn bucket (Some 1l) (None);
      sleep(1);
      let (n, multi) = riak_get_bucket conn bucket in
        (match n with
           | Some nval -> assert_equal 1l nval
           | None -> assert_failure "Unexpected N value");
        (match multi with
           | Some multival -> assert_equal true multival
           (* passing None doesn't overwrite the previous
           * value *)
           | None -> ())

let show_int_option v =
  match v with
    | None -> print_endline "NONE"
    | Some x -> print_endline (Int32.to_string x)


let test_case_mapreduce conn =
  let bucket = testbucket() in
    riak_put_raw conn bucket (Some "foo")
      "pizza data goes here" [] None |> ignore;
    riak_put_raw conn bucket (Some "bar")
      "pizza pizza pizza pizza" [] None |> ignore;
    riak_put_raw conn bucket (Some "baz")
      "nothing to see here" [] None |> ignore;
    riak_put_raw conn bucket (Some "bam")
      "pizza pizza pizza" [] None |> ignore;
    sleep(1);
    let query = "{\"inputs\":\"" ^ bucket ^ "\", \"query\":[{\"map\":{\"language\":\"javascript\", " ^
                "\"source\":\"function(riakObject) { var m =  riakObject.values[0].data.match(/pizza/g);" ^
                "return  [[riakObject.values[0].data, (m ? m.length : 0 )]]; }\"}}]}" in
    let results = riak_mapred conn query Riak_MR_Json in
        assert_equal 4 (List.length results);
        assert_bool "Check for match 3"
          (List.exists (fun (v,p) ->
                          v = (Some "[[\"pizza pizza pizza\",3]]")) results);
        assert_bool "Check for match 0"
          (List.exists (fun (v,p) ->
                          v = (Some "[[\"nothing to see here\",0]]")) results);
        assert_bool "Check for match 4"
          (List.exists (fun (v,p) ->
                          v = (Some "[[\"pizza pizza pizza pizza\",4]]")) results);
        assert_bool "Check for match 1"
          (List.exists (fun (v,p) ->
                          v = (Some "[[\"pizza data goes here\",1]]")) results)

let test_case_with_connection _ =
  let ip = test_ip() in
  let port = test_port() in
  let with_connection = riak_exec ip port in
  with_connection (fun conn -> riak_ping conn) |> ignore

(* TODO: Index, Search *)
(*
let test_case_search conn =
  let _ = riak_search_query conn "fox" "phrases_custom" [] in
    ()
 *)

(* TODO: clean up test buckets when complete? *)
(* these don't all need to be bracketed *)
let suite = "Riak" >:::
[
  "test_case_ping" >:: (bracket setup test_case_ping teardown);
  "test_case_ping_fail" >:: (bracket setup test_case_ping_fail teardown);
  "test_case_invalid_network" >::
  (bracket setup test_case_invalid_network teardown);
  "test_case_client_id" >:: (bracket setup test_case_client_id teardown);
  "test_case_server_info" >:: (bracket setup test_case_server_info teardown);
  "test_case_put" >:: (bracket setup test_case_put teardown);
  "test_case_put_raw" >:: (bracket setup test_case_put_raw teardown);
  "test_case_get" >:: (bracket setup test_case_get teardown);
  "test_case_get_with_siblings" >:: (bracket setup test_case_get_with_siblings teardown);
  "test_case_del" >:: (bracket setup test_case_del teardown);
  "test_case_list_buckets" >:: (bracket setup test_case_list_buckets teardown);
  "test_case_list_keys" >:: (bracket setup test_case_list_keys teardown);
  "test_case_get_bucket" >:: (bracket setup test_case_get_bucket teardown);
  "test_case_set_bucket" >:: (bracket setup test_case_set_bucket teardown);
  "test_case_mapreduce" >:: (bracket setup test_case_mapreduce teardown);
  "test_case_with_connection" >:: test_case_with_connection;
]

let _ = run_test_tt_main suite