# 4-Way Set-Associative 32KB L1 Cache Controller Specification

## 1. Architectural Overview
The **L1 Cache Controller** implements a high-performance, non-blocking 32KB 4-way set-associative cache with write-back / write-allocate policy, tree-based pseudo-LRU (Tree-PLRU) replacement, and a 4-entry Miss Status Holding Register (MSHR) for hit-under-miss execution.

---

## 2. Cache Organization & Address Partitioning

- **Total Capacity:** 32 KB ($32,768$ Bytes)
- **Associativity:** 4 Ways
- **Line / Block Size:** 64 Bytes ($512$ Bits = $16 \times 32$-bit words)
- **Number of Sets:** $\frac{32768 \text{ Bytes}}{4 \text{ Ways} \times 64 \text{ Bytes}} = 128 \text{ Sets}$

### 32-Bit Address Breakdown:
```
 +-------------------------+--------------------+------------------------+
 |      TAG [31:13]        |    INDEX [12:6]    |   OFFSET [5:0]         |
 |        19 bits          |       7 bits       |     6 bits (64 bytes)  |
 +-------------------------+--------------------+------------------------+
```

---

## 3. Tree-Based Pseudo-LRU (Tree-PLRU)

For a 4-way set-associative cache, true LRU requires $\lceil \log_2(4!) \rceil = 5$ bits per set. Tree-PLRU reduces this to **3 bits per set** using a binary decision tree:

```
                  B0 (Root: Left vs Right)
                 /  \
                /    \
      (Way 0 / 1)    (Way 2 / 3)
          B1              B2
         /  \            /  \
     Way 0  Way 1    Way 2  Way 3
```

- **Bit 0 ($B_0$):** Points to left subtree (Ways 0,1 if 0) or right subtree (Ways 2,3 if 1).
- **Bit 1 ($B_1$):** Points to Way 0 (if 0) or Way 1 (if 1).
- **Bit 2 ($B_2$):** Points to Way 2 (if 0) or Way 3 (if 1).

### Replacement Selection:
- If $B_0 == 0$: victim in left branch. Victim is Way 0 if $B_1 == 0$, else Way 1.
- If $B_0 == 1$: victim in right branch. Victim is Way 2 if $B_2 == 0$, else Way 3.

### Update on Access to Way $W$:
- If Way 0 accessed: $B_0 \leftarrow 1, B_1 \leftarrow 1$
- If Way 1 accessed: $B_0 \leftarrow 1, B_1 \leftarrow 0$
- If Way 2 accessed: $B_0 \leftarrow 0, B_2 \leftarrow 1$
- If Way 3 accessed: $B_0 \leftarrow 0, B_2 \leftarrow 0$

---

## 4. Miss Status Holding Register (MSHR)

To prevent cache blocking on memory latency, an MSHR queue (4 entries) tracks outstanding cache line refills:
- **Hit-Under-Miss:** While a line is being fetched from L2/DRAM via AXI4, hits to other cached lines continue serving processor requests with 0 additional latency.
- **Miss-Under-Miss:** Secondary misses to distinct lines allocate separate MSHR entries.
- **Miss Merging:** Secondary accesses to a line *already* pending in MSHR are merged into the existing entry without issuing duplicate AXI requests.

---

## 5. Main Memory AXI4 Interface

- **Refill Port:** AXI4 burst read ($4 \times 128$-bit or $16 \times 32$-bit beats) to populate a 64-byte line.
- **Writeback Port:** AXI4 burst write to flush dirty victim lines back to main memory before allocating incoming line.
