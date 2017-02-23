let _ =
  let fh = open_in_bin Sys.argv.(1) in
  let buf = String.create 512 in
  really_input fh buf 0 512;
  for line = 0 to 15 do
    Printf.printf "\t\t.INIT_%.2X(256'h" line;
    for byte = 0 to 31 do
      let idx = line * 32 + 31 - byte in
      Printf.printf "%.2x" (Char.code buf.[idx])
    done;
    if line = 15 then
      print_endline ")"
    else
      print_endline "),"
  done
