# MIPS Pipelined Processor with SIMD Extension

A 5-stage pipelined 32-bit MIPS processor with a 4-lane SIMD co-processor and a two-level write-back cache hierarchy, implemented in SystemVerilog.

---

## Features

- **5-stage pipeline** — IF → ID → EX → MEM → WB
- **Full hazard handling** — MEM→EX and WB→EX forwarding, load-use stalls, early branch resolution in Decode with 1-cycle branch stalls
- **SIMD vector extension** — 32-entry × 128-bit vector register file, 4-lane vector ALU (vadd, vsub, vand, vor), 128-bit vector load/store (vlw, vsw)
- **L1 data cache** — direct-mapped, 64 sets, 128-bit lines, write-back/write-allocate
- **L2 unified cache** — 2-way set-associative, 128 sets, LRU replacement, write-back
- **DRAM model** — configurable latency (default 4 cycles), 128-bit block transfers

---

## Instruction Set

| Instruction | Opcode | Operation |
|---|---|---|
| R-type (add/sub/and/or/slt) | `000000` | `rd = rs OP rt` |
| `addi` | `001000` | `rt = rs + imm` |
| `lw` / `sw` | `100011` / `101011` | load / store word |
| `beq` | `000100` | branch if equal |
| `j` | `000010` | jump |
| `slti` | `001010` | set less than immediate |
| `vadd` / `vsub` | `010000` | 4-lane vector add/sub |
| `vlw` / `vsw` | `110011` / `111011` | 128-bit vector load/store |

---

## Running

```bash
# Compile
iverilog -g2012 -o sim vpipelined_tb.sv vpipelined_processor.sv

# Simulate
vvp sim

# View waveforms
gtkwave dump.vcd
```

Expected output:
```
SIMD LOOP SUCCESS! Processed 16 elements across 4 vector iterations!
```

---

## Memory Map

| Address range | Contents |
|---|---|
| `0x00 – 0x3F` | Program (instructions) |
| `0x80 – 0xBF` | Vector array A |
| `0xC0 – 0xFF` | Vector array B |
| `0x100 – 0x13F` | Result array |

The memory file (`vmemfile.dat`) is plain hex, one 32-bit word per line. Unspecified addresses default to zero.

---

## File Overview

| File | Description |
|---|---|
| `vpipelined_processor.sv` | Full processor — pipeline, caches, VALU, hazard unit |
| `vpipelined_tb.sv` | Testbench — checks final VSW result at address 304 |
| `vmemfile.dat` | Program + data — SIMD vector addition loop |
