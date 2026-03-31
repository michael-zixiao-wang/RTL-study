#!/bin/bash

TOP=$1 # the top module name
FILE=$2 # the source files

OUTDIR=synth # the output dir
if [ ! -d "$OUTDIR" ]; then
	echo "create dir $OUTDIR"
	mkdir ./$OUTDIR/
fi

yosys -p "read_verilog -sv $FILE; hierarchy -top $TOP; proc; write_json ./$OUTDIR/$TOP.json"
# yosys -p "read_verilog -sv $FILE; hierarchy -top $TOP; proc; opt; write_json netlist.json"

netlistsvg ./$OUTDIR/$TOP.json -o ./$OUTDIR/$TOP.svg
convert ./$OUTDIR/$TOP.svg -background white ./$OUTDIR/$TOP.png
xdg-open ./$OUTDIR/$TOP.png
