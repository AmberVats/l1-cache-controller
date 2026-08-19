//=============================================================================
// Package: cache_pkg
// Description: Type definitions, address splitting, and configuration parameters
//              for the 32KB 4-Way Set-Associative L1 Cache.
//=============================================================================

`timescale 1ns / 1ps

package cache_pkg;

    // Cache Geometry Parameters
    localparam int ADDR_WIDTH    = 32;
    localparam int DATA_WIDTH    = 32;
    localparam int NUM_WAYS      = 4;
    localparam int NUM_SETS      = 128;
    localparam int LINE_BYTES    = 64;
    localparam int LINE_BITS     = LINE_BYTES * 8; // 512 bits
    localparam int WORDS_PER_LINE= LINE_BYTES / 4;  // 16 words

    // Address Breakdown Widths
    localparam int OFFSET_WIDTH  = 6;  // 2^6 = 64 bytes
    localparam int INDEX_WIDTH   = 7;  // 2^7 = 128 sets
    localparam int TAG_WIDTH     = ADDR_WIDTH - INDEX_WIDTH - OFFSET_WIDTH; // 19 bits
    localparam int WAY_WIDTH     = $clog2(NUM_WAYS); // 2 bits
    localparam int MSHR_ENTRIES  = 4;

    // Cache Command Types
    typedef enum logic [1:0] {
        REQ_READ  = 2'b00,
        REQ_WRITE = 2'b01,
        REQ_FLUSH = 2'b10
    } req_type_t;

    // Processor Request Structure
    typedef struct packed {
        logic [ADDR_WIDTH-1:0]   addr;
        logic [DATA_WIDTH-1:0]   wdata;
        logic [DATA_WIDTH/8-1:0] wstrb;
        req_type_t               req_type;
        logic                    valid;
    } cache_req_t;

    // Processor Response Structure
    typedef struct packed {
        logic [DATA_WIDTH-1:0] rdata;
        logic                  hit;
        logic                  ready;
        logic                  valid;
    } cache_resp_t;

    // Address Slicing Helper Functions
    function automatic logic [TAG_WIDTH-1:0] get_tag(input logic [ADDR_WIDTH-1:0] addr);
        return addr[ADDR_WIDTH-1 : INDEX_WIDTH + OFFSET_WIDTH];
    endfunction

    function automatic logic [INDEX_WIDTH-1:0] get_index(input logic [ADDR_WIDTH-1:0] addr);
        return addr[INDEX_WIDTH + OFFSET_WIDTH - 1 : OFFSET_WIDTH];
    endfunction

    function automatic logic [OFFSET_WIDTH-1:0] get_offset(input logic [ADDR_WIDTH-1:0] addr);
        return addr[OFFSET_WIDTH-1 : 0];
    endfunction

endpackage
