(* Double-space bytes in program given as argument.  *)

type r =
  {
    mutable num : int;
    mutable bytes : int list;
    mutable addr : int32
  }

let dump_record fout record =
  if record.num > 0 then begin
    Printf.fprintf fout "+ %.2x %.8lx" record.num record.addr;
    List.fold_right
      (fun byt _ -> Printf.fprintf fout " %.2x" byt)
      record.bytes ();
    Printf.fprintf fout "\n";
    record.addr <- Int32.add record.addr (Int32.of_int record.num);
    record.bytes <- [];
    record.num <- 0
  end

let accumulate fout byte record =
  record.bytes <- byte :: record.bytes;
  record.num <- record.num + 1;
  if record.num = 16 then
    dump_record fout record

let _ =
  let fin = open_in_bin Sys.argv.(1) in
  let fout = open_out Sys.argv.(2) in
  let rek = { num = 0; bytes = []; addr = 0l } in
  try
    while true do
      let byte1 = input_byte fin in
      let byte2 = input_byte fin in
      accumulate fout byte2 rek;
      accumulate fout byte1 rek;
      (*accumulate fout byte rek;*)
    done;
    dump_record fout rek
  with End_of_file ->
    close_in fin;
    close_out fout;
