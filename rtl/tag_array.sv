//=============================================================================
// Module: tag_array
// Description: 4-Way Associative Tag Memory Array with Valid and Dirty bit tracking.
//              Performs simultaneous parallel tag matching across all 4 ways.
//=============================================================================

`timescale 1ns / 1ps
import cache_pkg::*;

module tag_array (
    input  logic                   clk,
    input  logic                   rst_n,

    // Lookup Port
    input  logic [INDEX_WIDTH-1:0] lookup_index,
    input  logic [TAG_WIDTH-1:0]   lookup_tag,
    output logic [NUM_WAYS-1:0]    way_hits,
    output logic                   cache_hit,
    output logic [WAY_WIDTH-1:0]   hit_way_id,
    output logic [NUM_WAYS-1:0]    way_dirty,
    output logic [NUM_WAYS-1:0]    way_valid,
    output logic [TAG_WIDTH-1:0]   read_tags [NUM_WAYS],

    // Update / Write Port
    input  logic                   we,
    input  logic [INDEX_WIDTH-1:0] write_index,
    input  logic [WAY_WIDTH-1:0]   write_way,
    input  logic [TAG_WIDTH-1:0]   write_tag,
    input  logic                   write_valid,
    input  logic                   write_dirty,

    // Dirty Update Only Port (for write hits)
    input  logic                   dirty_we,
    input  logic [INDEX_WIDTH-1:0] dirty_index,
    input  logic [WAY_WIDTH-1:0]   dirty_way,
    input  logic                   dirty_val
);

    // Storage Structures
    logic [TAG_WIDTH-1:0] tags   [NUM_SETS][NUM_WAYS];
    logic                 valid  [NUM_SETS][NUM_WAYS];
    logic                 dirty  [NUM_SETS][NUM_WAYS];

    // Read Out & Tag Matching (Combinational / Asynchronous read)
    always_comb begin
        for (int w = 0; w < NUM_WAYS; w++) begin
            read_tags[w] = tags[lookup_index][w];
            way_valid[w] = valid[lookup_index][w];
            way_dirty[w] = dirty[lookup_index][w];
            way_hits[w]  = valid[lookup_index][w] && (tags[lookup_index][w] == lookup_tag);
        end

        cache_hit = |way_hits;

        // Encode hit way
        hit_way_id = '0;
        if (way_hits[0])      hit_way_id = 2'd0;
        else if (way_hits[1]) hit_way_id = 2'd1;
        else if (way_hits[2]) hit_way_id = 2'd2;
        else if (way_hits[3]) hit_way_id = 2'd3;
    end

    // Synchronous Update
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int s = 0; s < NUM_SETS; s++) begin
                for (int w = 0; w < NUM_WAYS; w++) begin
                    valid[s][w] <= 1'b0;
                    dirty[s][w] <= 1'b0;
                    tags[s][w]  <= '0;
                end
            end
        end else begin
            // Tag + Valid + Dirty write (on refill)
            if (we) begin
                tags[write_index][write_way]  <= write_tag;
                valid[write_index][write_way] <= write_valid;
                dirty[write_index][write_way] <= write_dirty;
            end else if (dirty_we) begin
                // Update dirty bit on write hit
                dirty[dirty_index][dirty_way] <= dirty_val;
            end
        end
    end

endmodule
