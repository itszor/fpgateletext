#!/bin/sh
set -e
xa filltest.a65 -o filltest.bin
./printram filltest.bin > filltest.inc
