#!/usr/bin/env bash
# Builds pong.nes from pong.s + generated chr.bin.
set -e

cd "$(dirname "$0")"

python3 chrgen.py chr.bin
ca65 pong.s -o pong.o
ld65 pong.o -C nes.cfg -o pong.nes

size=$(wc -c < pong.nes)
echo "Built pong.nes ($size bytes)"
