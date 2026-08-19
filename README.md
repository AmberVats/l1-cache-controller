# 4-Way Set-Associative 32KB L1 Cache Controller with MSHR

[![SystemVerilog](https://img.shields.io/badge/Language-SystemVerilog-blue.svg)](https://en.wikipedia.org/wiki/SystemVerilog)
[![Verification](https://img.shields.io/badge/Verification-SystemVerilog%20%7C%20Cocotb-green.svg)](https://www.cocotb.org/)
[![PDK](https://img.shields.io/badge/PDK-SkyWater%20130nm-red.svg)](https://github.com/google/skywater-pdk)
[![Status](https://img.shields.io/badge/Status-Completed%20(All%20Phases)-brightgreen.svg)]()
[![License](https://img.shields.io/badge/License-MIT-purple.svg)](LICENSE)

---

## 📖 Executive Summary & Project Description

In high-performance processor microarchitectures, memory access latency is the primary bottleneck preventing compute cores from achieving peak IPC (Instructions Per Cycle). This project implements a synthesizable, high-frequency **32KB 4-Way Set-Associative Level-1 (L1) Cache Controller** designed in SystemVerilog and optimized for the open-source **SkyWater 130nm standard cell library**.

The cache features a **non-blocking microarchitecture** enabled by a **4-entry Miss Status Holding Register (MSHR)** array supporting **Hit-Under-Miss** and **Miss-Under-Miss** execution. Victim eviction is managed by an area-efficient **Tree-based Pseudo-LRU (Tree-PLRU)** replacement engine requiring only 3 state bits per set. The memory subsystem adheres to **write-back** and **write-allocate** coherency policies, using an integrated **AXI4 master engine** for 16-beat burst line refills and dirty victim flushes.

---

## 🌟 Key Architectural Highlights

- **Cache Geometry & Organization:**
  - Total Capacity: **32 KB** ($32,768$ Bytes).
  - Associativity: **4-Way Set-Associative** (128 Sets).
  - Line / Block Size: **64 Bytes** ($512$ Bits = $16 \times 32$-bit words).
  - Address Breakdown: Tag = 19 bits `[31:13]`, Set Index = 7 bits `[12:6]`, Byte Offset = 6 bits `[5:0]`.

- **Ultra Low-Latency Hit Path:**
  - **1-Cycle Read Hit Latency:** Combinational parallel tag comparison across all 4 ways with simultaneous data array indexing.
  - **Write Hit Byte Masking:** Word-level write strobes (`wstrb`) allowing granular byte, halfword, and word store updates.
  - **Dirty Bit State Tracking:** Individual dirty metadata bits per cache line to minimize writeback traffic to main memory.

- **Tree-Based Pseudo-LRU (Tree-PLRU):**
  - Binary decision tree algorithm reducing state storage to **3 bits per set** compared to true LRU ($\lceil \log_2(4!) \rceil = 5$ bits).
  - Instant $O(1)$ victim way evaluation and single-cycle state tree update on cache hits.

- **Non-Blocking MSHR Subsystem:**
  - 4 independent Miss Status Holding Register slots tracking concurrent outstanding misses.
  - **Hit-Under-Miss:** Serves subsequent processor hits while memory line refills are in-flight without stalling the pipeline.
  - **Secondary Miss Merging:** Detects secondary accesses targeting in-flight refill addresses and merges requests to eliminate redundant AXI transactions.

- **Full AXI4 Memory Protocol:**
  - 16-beat 32-bit burst reads for 64-byte line refills from DRAM / L2 cache.
  - 16-beat 32-bit burst writes for dirty victim eviction writebacks.

- **ASIC Implementation Ready:**
  - Synthesizable RTL verified with Yosys for the SkyWater 130nm PDK.

---

## 🏗️ Cache Microarchitecture Block Diagram

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

## 🚦 Implementation & Verification Status

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

## 🔬 Running Simulations

Run the complete self-checking testbench (verifies compulsory misses, read hits, write hits, write-allocate refills, 4-way Tree-PLRU eviction cycles, and dirty line writebacks):
```bash
cd tb
iverilog -g2012 -o sim_l1_cache ../rtl/*.sv tb_l1_cache.sv
vvp sim_l1_cache
```

### ASIC Synthesis (SkyWater 130nm):
```bash
cd synth
yosys -s sky130_synth.ys
```