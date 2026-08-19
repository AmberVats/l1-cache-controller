//=============================================================================
// Module: mshr
// Description: Miss Status Holding Register (MSHR) for Non-Blocking Cache Operation.
//              Tracks up to 4 concurrent in-flight cache misses, enabling
//              Hit-Under-Miss and Miss-Under-Miss execution without processor stalls.
//=============================================================================

`timescale 1ns / 1ps
import cache_pkg::*;

module mshr (
    input  logic                   clk,
    input  logic                   rst_n,

    // Query / Allocation Port
    input  logic [ADDR_WIDTH-1:0]  req_addr,
    input  logic [DATA_WIDTH-1:0]  req_wdata,
    input  logic [DATA_WIDTH/8-1:0]req_wstrb,
    input  logic                   req_is_write,
    input  logic                   allocate_en,
    output logic                   mshr_full,
    output logic                   mshr_match, // Match to pending line (secondary miss)
    output logic [$clog2(MSHR_ENTRIES)-1:0] match_id,

    // AXI Issue Port (Pick oldest pending entry to fetch)
    output logic                   issue_valid,
    output logic [ADDR_WIDTH-1:0]  issue_line_addr,
    output logic [$clog2(MSHR_ENTRIES)-1:0] issue_id,
    input  logic                   issue_ack,

    // Refill Completion Port (Memory refill data returned)
    input  logic                   refill_done,
    input  logic [$clog2(MSHR_ENTRIES)-1:0] refill_id,
    output logic [ADDR_WIDTH-1:0]  completed_addr,
    output logic                   completed_is_write,
    output logic [DATA_WIDTH-1:0]  completed_wdata,
    output logic [DATA_WIDTH/8-1:0]completed_wstrb
);

    localparam int ID_WIDTH = $clog2(MSHR_ENTRIES);

    typedef struct packed {
        logic                  valid;
        logic                  issued;
        logic [TAG_WIDTH-1:0]  tag;
        logic [INDEX_WIDTH-1:0]index;
        logic [OFFSET_WIDTH-1:0]offset;
        logic [DATA_WIDTH-1:0] wdata;
        logic [DATA_WIDTH/8-1:0]wstrb;
        logic                  is_write;
    } mshr_slot_t;

    mshr_slot_t entries [MSHR_ENTRIES];

    logic [TAG_WIDTH-1:0]   incoming_tag;
    logic [INDEX_WIDTH-1:0] incoming_index;

    assign incoming_tag   = get_tag(req_addr);
    assign incoming_index = get_index(req_addr);

    // 1. Secondary Miss Match Detector
    always_comb begin
        mshr_match = 1'b0;
        match_id   = '0;
        for (int i = 0; i < MSHR_ENTRIES; i++) begin
            if (entries[i].valid && 
                (entries[i].tag == incoming_tag) && 
                (entries[i].index == incoming_index)) begin
                mshr_match = 1'b1;
                match_id   = i[ID_WIDTH-1:0];
            end
        end
    end

    // 2. Free Slot Finder & Full Flag
    logic [ID_WIDTH-1:0] free_slot;
    logic                has_free_slot;

    always_comb begin
        has_free_slot = 1'b0;
        free_slot     = '0;
        for (int i = 0; i < MSHR_ENTRIES; i++) begin
            if (!entries[i].valid && !has_free_slot) begin
                has_free_slot = 1'b1;
                free_slot     = i[ID_WIDTH-1:0];
            end
        end
        mshr_full = !has_free_slot;
    end

    // 3. Issue Selector (Oldest un-issued valid entry)
    always_comb begin
        issue_valid     = 1'b0;
        issue_line_addr = '0;
        issue_id        = '0;
        for (int i = 0; i < MSHR_ENTRIES; i++) begin
            if (entries[i].valid && !entries[i].issued && !issue_valid) begin
                issue_valid     = 1'b1;
                issue_id        = i[ID_WIDTH-1:0];
                issue_line_addr = {entries[i].tag, entries[i].index, {OFFSET_WIDTH{1'b0}}};
            end
        end
    end

    // Refill Completion Data
    assign completed_addr     = {entries[refill_id].tag, entries[refill_id].index, entries[refill_id].offset};
    assign completed_is_write = entries[refill_id].is_write;
    assign completed_wdata    = entries[refill_id].wdata;
    assign completed_wstrb    = entries[refill_id].wstrb;

    // Synchronous MSHR Management
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < MSHR_ENTRIES; i++) begin
                entries[i].valid    <= 1'b0;
                entries[i].issued   <= 1'b0;
                entries[i].tag      <= '0;
                entries[i].index    <= '0;
                entries[i].offset   <= '0;
                entries[i].wdata    <= '0;
                entries[i].wstrb    <= '0;
                entries[i].is_write <= 1'b0;
            end
        end else begin
            // Mark entry issued to AXI
            if (issue_valid && issue_ack) begin
                entries[issue_id].issued <= 1'b1;
            end

            // Allocate new miss
            if (allocate_en && has_free_slot) begin
                entries[free_slot].valid    <= 1'b1;
                entries[free_slot].issued   <= 1'b0;
                entries[free_slot].tag      <= incoming_tag;
                entries[free_slot].index    <= incoming_index;
                entries[free_slot].offset   <= get_offset(req_addr);
                entries[free_slot].wdata    <= req_wdata;
                entries[free_slot].wstrb    <= req_wstrb;
                entries[free_slot].is_write <= req_is_write;
            end

            // Deallocate on refill completion
            if (refill_done) begin
                entries[refill_id].valid  <= 1'b0;
                entries[refill_id].issued <= 1'b0;
            end
        end
    end

endmodule
