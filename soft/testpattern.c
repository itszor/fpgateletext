#include <stdio.h>

int main(void)
{
  FILE *f;
  int i;

  f = fopen ("pattern.bin", "w");
  for (i = 0; i < 65536; i++)
    {
      int row = i / 40;
      int col = i % 40;
      int chr = '0' + ((row + col) % 10);
      fprintf (f, "%c", chr);
    }

  fclose (f);
}
