docker run --rm -v $(pwd):/src -w /src davidsiaw/yosys-docker:latest /bin/bash -c "
  yosys -p 'synth_ice40 -abc9 -top top -json synth.json' top.v && \
  nextpnr-ice40 --up5k --package sg48 --json synth.json --pcf io.pcf --asc synth.asc && \
  icepack synth.asc program.bin
" && cp program.bin /Volumes/iCELink/
