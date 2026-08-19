//=============================================================================
// Module: plru_tree
// Description: Tree-based Pseudo-LRU (Least Recently Used) replacement policy unit
//              for 4-way set-associative cache.
//              Uses 3 bits per set to track replacement order with O(1) area/timing.
//=============================================================================

`timescale 1ns / 1ps
import cache_pkg::*;

module plru_tree (
    input  logic                   clk,
    input  logic                   rst_n,

    // Query Port (Get victim way for a set)
    input  logic [INDEX_WIDTH-1:0] query_index,
    input  logic [NUM_WAYS-1:0]    way_valid,
    output logic [WAY_WIDTH-1:0]   victim_way,

    // Update Port (Called on hit or line install)
    input  logic                   update_en,
    input  logic [INDEX_WIDTH-1:0] update_index,
    input  logic [WAY_WIDTH-1:0]   access_way
);

    // 3 bits per set:
    // bit [0]: Root (0: left subtree Ways 0,1; 1: right subtree Ways 2,3)
    // bit [1]: Left child (0: Way 0; 1: Way 1)
    // bit [2]: Right child (0: Way 2; 1: Way 3)
    logic [2:0] tree_state [0:NUM_SETS-1];

    // Combinational Victim Selection
    always_comb begin
        // Prioritize any invalid / empty ways first
        if (!way_valid[0]) begin
            victim_way = 2'd0;
        end else if (!way_valid[1]) begin
            victim_way = 2'd1;
        end else if (!way_valid[2]) begin
            victim_way = 2'd2;
        end else if (!way_valid[3]) begin
            victim_way = 2'd3;
        end else begin
            // All ways valid: traverse Tree-PLRU
            if (tree_state[query_index][0] == 1'b0) begin
                // Point to left branch (Ways 0 or 1)
                victim_way = (tree_state[query_index][1] == 1'b0) ? 2'd0 : 2'd1;
            end else begin
                // Point to right branch (Ways 2 or 3)
                victim_way = (tree_state[query_index][2] == 1'b0) ? 2'd2 : 2'd3;
            end
        end
    end

    // Synchronous Tree Update on Cache Access
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_SETS; i++) begin
                tree_state[i] <= 3'b000;
            end
        end else if (update_en) begin
            case (access_way)
                2'd0: begin
                    tree_state[update_index][0] <= 1'b1; // Point away to right
                    tree_state[update_index][1] <= 1'b1; // Point away to way 1
                end
                2'd1: begin
                    tree_state[update_index][0] <= 1'b1; // Point away to right
                    tree_state[update_index][1] <= 1'b0; // Point away to way 0
                end
                2'd2: begin
                    tree_state[update_index][0] <= 1'b0; // Point away to left
                    tree_state[update_index][2] <= 1'b1; // Point away to way 3
                end
                2'd3: begin
                    tree_state[update_index][0] <= 1'b0; // Point away to left
                    tree_state[update_index][2] <= 1'b0; // Point away to way 2
                end
            endcase
        end
    end

endmodule
