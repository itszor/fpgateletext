#!/bin/sh
set -e
xa hello.a65 -o hello.bin
./layout hello.bin hello.xes
