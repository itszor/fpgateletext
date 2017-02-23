#!/bin/sh
set -e
if [ -z "$1" ]; then
  echo Usage: $0 "filename.a65"
  exit 1
fi
A65=$1
BIN=$(echo $A65 | sed s/\.a65/\.bin/)
XES=$(echo $A65 | sed s/\.a65/\.xes/)
VER=$(echo $A65 | sed s/\.a65/\.v/)
xa -w $A65 -o $BIN
./layout $BIN $XES
./printram $BIN > $VER
