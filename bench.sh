# Note: This is currently just a "works on Thomas's machine" type script.
# Dependencies undocumented.
# Feel free to fix it up and PR a proper benchmark script.

set -e
zig run src/tools/programs/hello.zig
zig build -Doptimize=ReleaseFast
ls -lh zig-out/bin
mkdir -p yafie
gcc -Ofast -o yafie/ivm_emu ../../../github.com/immortalvm/yet-another-fast-ivm-emulator/ivm_emu.c
gcc -Ofast -DVERBOSE=4 -o yafie/ivm_emu_debug ../../../github.com/immortalvm/yet-another-fast-ivm-emulator/ivm_emu.c
# zig build-exe -lc -O ReleaseFast -DVERBOSE=4 ../../../github.com/immortalvm/yet-another-fast-ivm-emulator/ivm_emu.c --name ivm_emu_debug
# zig build-exe -lc -O ReleaseFast -DVERBOSE=0 ../../../github.com/immortalvm/yet-another-fast-ivm-emulator/ivm_emu.c --name ivm_emu
strace ./zig-out/bin/ivm-zig hello.ivm 2>ivm-zig_trace.log >/dev/null
strace ./yafie/ivm_emu hello.ivm 2>yafie_trace.log >/dev/null
sudo strace $(which poop)\
 "./zig-out/bin/ivm-zig hello.ivm"\
 "./yafie/ivm_emu hello.ivm"
sudo strace $(which poop)\
 "./zig-out/bin/ivm-zig-debug hello.ivm"\
 "./yafie/ivm_emu_debug hello.ivm"
hyperfine --shell none --warmup 32 --export-markdown BENCH_MAIN.md\
 -n ivm-zig "./zig-out/bin/ivm-zig hello.ivm"\
 -n yet-another-fast-ivm-emulator "./yafie/ivm_emu hello.ivm"
hyperfine --shell none --warmup 4 --export-markdown BENCH_DEBUG.md\
 -n ivm-zig-debug "./zig-out/bin/ivm-zig-debug hello.ivm"\
 -n yet-another-fast-ivm-emulator-debug "./yafie/ivm_emu_debug hello.ivm"
rm BENCH.md
echo "# Main" >> BENCH.md
cat BENCH_MAIN.md >> BENCH.md
echo "# Debug" >> BENCH.md
cat BENCH_DEBUG.md >> BENCH.md
rm BENCH_MAIN.md BENCH_DEBUG.md
deno fmt BENCH.md
