#include <stdio.h>

int
main (int argc, char* argv[])
{
  FILE *f = fopen ("teletext-font.pbm", "rw");
  char buf[96 * 10 * 6];
  int row, col, i, j;

  fread (buf, 1, 96 * 10 * 6, f);

  fclose (f);

  for (row = 0; row < 6; row++)
    for (col = 0; col < 16; col++)
      {
	for (j = 8; j >= 0; j--)
          {
            for (i = 4; i >= 0; i--)
              {
		int idx = row * 960 + col * 6 + j * 96 + i;

		printf ("%c", buf[idx] == '0' ? '1' : '0');
              }
	  }
	printf ("\n");
      }

  return 0;
}
