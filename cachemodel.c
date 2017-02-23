/*

xxxx_xxxx_xxxx_xxxx_xxxx_xxxx
...._...._...._...._...._xxxx
...._...._...._.xxx_xxxx_....
xxxx_xxxx_xxxx_x..._...._....

*/

char cached_data[128][16];
int validate[128];  /* Interested in 13 bits!  */
bool dirty[128];

char
read_mem (int address)
{
  int line = (address >> 4) & 0x7f;
  char optimistic = cached_data[line][address & 0xf];
  int valid_bits = validate[line];
  
  if ((address >> 11) == valid_bits)
    return optimistic;
  
  halt_cpu ();
  if (dirty[line])
    store_to_sdram (address, cached_data[line]);
  load_from_sdram (cached_data[line], address);
  validate[line] = address >> 11;
  dirty[line] = 0;
  restart_cpu ();
  
  /* May be a short cut from "load_from_sdram" above.  */
  return cached_data[line][address & 0xf];
}

void
write_mem (int address, char wdata)
{
  int line = (address >> 4) & 0x7f;
  int valid_bits = validate[line];
  
  if ((address >> 11) == valid_bits)
    {
      cached_data[line][address & 0xf] = wdata;
      return;
    }
  
  halt_cpu ();
  if (dirty[line])
    store_to_sdram (address, cached_data[line]);
  load_from_sdram (cached_data[line], address);
  validate[line] = address >> 11;
  cached_data[line][address & 0xf] = wdata;
  dirty[line] = 1;
  restart_cpu ();
}
