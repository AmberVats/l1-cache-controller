# 4-Way Set-Associative 32KB L1 Cache Controller with MSHR

[![SystemVerilog](https://img.shields.io/badge/Language-SystemVerilog-blue.svg)](https://en.wikipedia.org/wiki/SystemVerilog)
[![Verification](https://img.shields.io/badge/Verification-SystemVerilog%20%7C%20Cocotb-green.svg)](https://www.cocotb.org/)
[![PDK](https://img.shields.io/badge/PDK-SkyWater%20130nm-red.svg)](https://github.com/google/skywater-pdk)
[![Status](https://img.shields.io/badge/Status-Completed%20(All%20Phases)-brightgreen.svg)]()
[![License](https://img.shields.io/badge/License-MIT-purple.svg)](LICENSE)

A synthesizable 32KB 4-way set-associative L1 Cache Controller featuring non-blocking architecture (4-entry MSHR), Tree-based Pseudo-LRU (Tree-PLRU) replacement policy, write-back / write-allocate coherency, and an AXI4 memory refill/writeback engine optimized for SkyWater 130nm standard cells.

---

## 🏗️ Cache Microarchitecture

```
                        +---------------------------------------+
                        |            L1 Cache Top               |
                        |                                       |
  CPU Load/Store Request ---> [ Tag Parallel Match (4 Ways) ]  |
                              |              |                  |
                       +------+-------+      v                  |
                       |  HIT PATH    |   [ Tree-PLRU Unit ]    |
                       | (1 Cycle)    |      | (3 bits/set)     |
                       +------+-------+      v                  |
                              |        [ 4-Entry MSHR Queue ]   |
                              |        (Hit-Under-Miss Engine)  |
                              |              |                  |
                              v              v                  |
                        [ 32KB 4-Way Data SRAM Array (512b) ]   |
                                       |                        |
                                       v                        |
                        [ AXI4 Burst Refill & Writeback Master ]===> AXI4 (L2/DRAM)
                        +---------------------------------------+
```

---

## 📁 Repository Structure

```
l1-cache-controller/
├── docs/
│   └── cache_spec.md            # Comprehensive cache microarchitecture spec
├── rtl/
│   ├── cache_pkg.sv             # Parameter & type definitions
│   ├── tag_array.sv             # 4-way parallel tag array (valid/dirty)
│   ├── data_array.sv            # 32KB 4-way data SRAM array (512 bits/line)
│   ├── plru_tree.sv             # Tree-based Pseudo-LRU replacement unit
│   ├── mshr.sv                  # 4-entry Miss Status Holding Register
│   ├── cache_axi_master.sv      # AXI4 burst line refill & writeback master
│   └── l1_cache_top.sv          # Top-level integrated cache controller
├── tb/
│   └── tb_l1_cache.sv           # Comprehensive self-checking verification TB
├── synth/
│   └── sky130_synth.ys          # Yosys synthesis script targeting Sky130 PDK
└── README.md
```

---

## 🚦 Roadmap & Implementation Phases

- [x] **Phase 2.1: Cache Storage Structures**
  - [x] 4-way Tag RAM array with valid/dirty bit tracking (`tag_array.sv`)
  - [x] 512-bit wide 32KB Data SRAM array with byte enables (`data_array.sv`)
- [x] **Phase 2.2: Tree-PLRU Replacement & Controller FSM**
  - [x] O(1) 3-bit binary tree Pseudo-LRU unit (`plru_tree.sv`)
  - [x] 1-cycle hit path and dirty tracking
- [x] **Phase 2.3: Non-Blocking MSHR**
  - [x] 4-entry Miss Status Holding Register array (`mshr.sv`)
  - [x] Secondary miss detection & store merging logic
- [x] **Phase 2.4: AXI4 Memory Interface**
  - [x] 16-beat 32-bit burst line refills
  - [x] 16-beat 32-bit burst dirty victim writebacks
- [x] **Phase 2.5: Physical Synthesis & Verification**
  - [x] Full self-checking testbench (`tb_l1_cache.sv`)
  - [x] SkyWater 130nm Yosys synthesis automation script (`sky130_synth.ys`)

---

## 🔬 Simulation

Run the self-checking testbench:
```bash
cd tb
iverilog -g2012 -o sim_l1_cache ../rtl/*.sv tb_l1_cache.sv
vvp sim_l1_cache
```