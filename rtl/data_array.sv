//=============================================================================
// Module: data_array
// Description: 4-Way 32KB Cache Data SRAM Array (512 bits per line).
//              Supports:
//              1. Single-word 32-bit read and byte-masked write (for CPU hits)
//              2. 512-bit full line burst write (for cache line refill)
//              3. 512-bit full line read (for dirty line eviction writeback)
//=============================================================================

`timescale 1ns / 1ps
import cache_pkg::*;

module data_array (
    input  logic                     clk,

    // Processor Word Access Port
    input  logic [INDEX_WIDTH-1:0]   index,
    input  logic [WAY_WIDTH-1:0]     way,
    input  logic [OFFSET_WIDTH-1:0]  offset,
    output logic [DATA_WIDTH-1:0]    rdata_word,

    // Single Word Write (CPU Store Hit)
    input  logic                     word_we,
    input  logic [DATA_WIDTH-1:0]    wdata_word,
    input  logic [DATA_WIDTH/8-1:0]  wstrb_word,

    // Full Line Refill Port (Memory -> Cache)
    input  logic                     line_we,
    input  logic [INDEX_WIDTH-1:0]   line_index,
    input  logic [WAY_WIDTH-1:0]     line_way,
    input  logic [LINE_BITS-1:0]     line_wdata,

    // Full Line Readback Port (Cache -> Memory Writeback)
    input  logic [INDEX_WIDTH-1:0]   evict_index,
    input  logic [WAY_WIDTH-1:0]     evict_way,
    output logic [LINE_BITS-1:0]     evict_line_data
);

    // Data storage: [NUM_SETS][NUM_WAYS][WORDS_PER_LINE]
    logic [31:0] data_ram [NUM_SETS][NUM_WAYS][WORDS_PER_LINE];

    logic [3:0] word_idx;
    assign word_idx = offset[OFFSET_WIDTH-1 : 2]; // 16 words per 64-byte line

    // Word Read (Combinational read out)
    assign rdata_word = data_ram[index][way][word_idx];

    // Full Line Evict Readback
    always_comb begin
        for (int i = 0; i < WORDS_PER_LINE; i++) begin
            evict_line_data[i*32 +: 32] = data_ram[evict_index][evict_way][i];
        end
    end

    // Synchronous Writes
    always_ff @(posedge clk) begin
        // 1. Full Line Refill Write
        if (line_we) begin
            for (int i = 0; i < WORDS_PER_LINE; i++) begin
                data_ram[line_index][line_way][i] <= line_wdata[i*32 +: 32];
            end
        end
        // 2. CPU Store Hit Word Write with Byte Enables
        else if (word_we) begin
            if (wstrb_word[0]) data_ram[index][way][word_idx][7:0]   <= wdata_word[7:0];
            if (wstrb_word[1]) data_ram[index][way][word_idx][15:8]  <= wdata_word[15:8];
            if (wstrb_word[2]) data_ram[index][way][word_idx][23:16] <= wdata_word[23:16];
            if (wstrb_word[3]) data_ram[index][way][word_idx][31:24] <= wdata_word[31:24];
        end
    end

endmodule
