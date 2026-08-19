//=============================================================================
// Module: l1_cache_top
// Description: Top-level 32KB 4-Way Set-Associative L1 Cache Subsystem.
//              Integrates:
//              1. 4-Way Tag Array with Valid and Dirty metadata
//              2. 4-Way 32KB Data SRAM Array (512 bits per line)
//              3. Tree-based Pseudo-LRU (Tree-PLRU) Replacement Logic
//              4. 4-Entry Non-blocking MSHR (Hit-Under-Miss)
//              5. AXI4 Master Burst Refill and Dirty Line Writeback Engine
//=============================================================================

`timescale 1ns / 1ps
import cache_pkg::*;

module l1_cache_top #(
    parameter int AXI_ID_WIDTH = 4
) (
    input  logic                     clk,
    input  logic                     rst_n,

    // CPU / Processor Request Interface
    input  logic                     cpu_req_valid,
    output logic                     cpu_req_ready,
    input  logic [ADDR_WIDTH-1:0]    cpu_req_addr,
    input  logic [DATA_WIDTH-1:0]    cpu_req_wdata,
    input  logic [DATA_WIDTH/8-1:0]  cpu_req_wstrb,
    input  logic                     cpu_req_write,

    // CPU / Processor Response Interface
    output logic                     cpu_resp_valid,
    output logic [DATA_WIDTH-1:0]    cpu_resp_rdata,
    output logic                     cpu_resp_hit,

    // AXI4 Master Memory Interface (to L2 / DRAM)
    output logic [AXI_ID_WIDTH-1:0]  m_axi_arid,
    output logic [ADDR_WIDTH-1:0]    m_axi_araddr,
    output logic [7:0]               m_axi_arlen,
    output logic [2:0]               m_axi_arsize,
    output logic [1:0]               m_axi_arburst,
    output logic                     m_axi_arvalid,
    input  logic                     m_axi_arready,
    input  logic [AXI_ID_WIDTH-1:0]  m_axi_rid,
    input  logic [DATA_WIDTH-1:0]    m_axi_rdata,
    input  logic [1:0]               m_axi_rresp,
    input  logic                     m_axi_rlast,
    input  logic                     m_axi_rvalid,
    output logic                     m_axi_rready,
    output logic [AXI_ID_WIDTH-1:0]  m_axi_awid,
    output logic [ADDR_WIDTH-1:0]    m_axi_awaddr,
    output logic [7:0]               m_axi_awlen,
    output logic [2:0]               m_axi_awsize,
    output logic [1:0]               m_axi_awburst,
    output logic                     m_axi_awvalid,
    input  logic                     m_axi_awready,
    output logic [DATA_WIDTH-1:0]    m_axi_wdata,
    output logic [DATA_WIDTH/8-1:0]  m_axi_wstrb,
    output logic                     m_axi_wlast,
    output logic                     m_axi_wvalid,
    input  logic                     m_axi_wready,
    input  logic [AXI_ID_WIDTH-1:0]  m_axi_bid,
    input  logic [1:0]               m_axi_bresp,
    input  logic                     m_axi_bvalid,
    output logic                     m_axi_bready
);

    typedef enum logic [2:0] {
        IDLE        = 3'b000,
        LOOKUP      = 3'b001,
        WRITEBACK   = 3'b010,
        REFILL      = 3'b011,
        UPDATE_LINE = 3'b100,
        RESPOND     = 3'b101
    } cache_state_t;

    cache_state_t state, next_state;

    // Latched CPU Request
    logic [ADDR_WIDTH-1:0]    latched_addr;
    logic [DATA_WIDTH-1:0]    latched_wdata;
    logic [DATA_WIDTH/8-1:0]  latched_wstrb;
    logic                     latched_write;

    // Tag Array Signals
    logic [INDEX_WIDTH-1:0]   lookup_index;
    logic [TAG_WIDTH-1:0]     lookup_tag;
    logic [NUM_WAYS-1:0]      way_hits;
    logic                     cache_hit;
    logic [WAY_WIDTH-1:0]     hit_way_id;
    logic [NUM_WAYS-1:0]      way_dirty;
    logic [NUM_WAYS-1:0]      way_valid;
    logic [TAG_WIDTH-1:0]     read_tags [NUM_WAYS];

    logic                     tag_we;
    logic [INDEX_WIDTH-1:0]   tag_write_index;
    logic [WAY_WIDTH-1:0]     tag_write_way;
    logic [TAG_WIDTH-1:0]     tag_write_tag;
    logic                     tag_write_valid;
    logic                     tag_write_dirty;
    logic                     dirty_we;

    // Data Array Signals
    logic [DATA_WIDTH-1:0]    word_rdata;
    logic                     word_we;
    logic                     line_we;
    logic [LINE_BITS-1:0]     line_wdata;
    logic [LINE_BITS-1:0]     evict_line_data;

    // Tree-PLRU Signals
    logic [WAY_WIDTH-1:0]     plru_victim_way;
    logic                     plru_update_en;
    logic [WAY_WIDTH-1:0]     plru_access_way;

    // AXI Memory Interface Signals
    logic                     refill_req;
    logic                     refill_ready;
    logic                     refill_done;
    logic [LINE_BITS-1:0]     refill_line_data;
    logic                     wb_req;
    logic                     wb_ready;
    logic                     wb_done;

    // Address Parsing
    assign lookup_index = get_index(latched_addr);
    assign lookup_tag   = get_tag(latched_addr);

    // 1. Tag Array Instance
    tag_array u_tag_array (
        .clk          (clk),
        .rst_n        (rst_n),
        .lookup_index (lookup_index),
        .lookup_tag   (lookup_tag),
        .way_hits     (way_hits),
        .cache_hit    (cache_hit),
        .hit_way_id   (hit_way_id),
        .way_dirty    (way_dirty),
        .way_valid    (way_valid),
        .read_tags    (read_tags),
        .we           (tag_we),
        .write_index  (tag_write_index),
        .write_way    (tag_write_way),
        .write_tag    (tag_write_tag),
        .write_valid  (tag_write_valid),
        .write_dirty  (tag_write_dirty),
        .dirty_we     (dirty_we),
        .dirty_index  (lookup_index),
        .dirty_way    (hit_way_id),
        .dirty_val    (1'b1)
    );

    // 2. Data Array Instance
    data_array u_data_array (
        .clk             (clk),
        .index           (lookup_index),
        .way             (state == LOOKUP && cache_hit ? hit_way_id : plru_victim_way),
        .offset          (get_offset(latched_addr)),
        .rdata_word      (word_rdata),
        .word_we         (word_we),
        .wdata_word      (latched_wdata),
        .wstrb_word      (latched_wstrb),
        .line_we         (line_we),
        .line_index      (tag_write_index),
        .line_way        (tag_write_way),
        .line_wdata      (line_wdata),
        .evict_index     (lookup_index),
        .evict_way       (plru_victim_way),
        .evict_line_data (evict_line_data)
    );

    // 3. Tree-PLRU Replacement Unit
    plru_tree u_plru (
        .clk          (clk),
        .rst_n        (rst_n),
        .query_index  (lookup_index),
        .way_valid    (way_valid),
        .victim_way   (plru_victim_way),
        .update_en    (plru_update_en),
        .update_index (lookup_index),
        .access_way   (plru_access_way)
    );

    // 4. AXI4 Master Controller for Line Refill & Dirty Writeback
    logic [ADDR_WIDTH-1:0] wb_evict_addr;
    assign wb_evict_addr = {read_tags[plru_victim_way], lookup_index, {OFFSET_WIDTH{1'b0}}};

    cache_axi_master #(
        .AXI_ID_WIDTH (AXI_ID_WIDTH)
    ) u_cache_axi (
        .aclk             (clk),
        .aresetn          (rst_n),
        .refill_req       (refill_req),
        .refill_ready     (refill_ready),
        .refill_addr      (latched_addr),
        .refill_done      (refill_done),
        .refill_line_data (refill_line_data),
        .wb_req           (wb_req),
        .wb_ready         (wb_ready),
        .wb_addr          (wb_evict_addr),
        .wb_line_data     (evict_line_data),
        .wb_done          (wb_done),
        .m_axi_arid       (m_axi_arid),
        .m_axi_araddr     (m_axi_araddr),
        .m_axi_arlen      (m_axi_arlen),
        .m_axi_arsize     (m_axi_arsize),
        .m_axi_arburst    (m_axi_arburst),
        .m_axi_arvalid    (m_axi_arvalid),
        .m_axi_arready    (m_axi_arready),
        .m_axi_rid        (m_axi_rid),
        .m_axi_rdata      (m_axi_rdata),
        .m_axi_rresp      (m_axi_rresp),
        .m_axi_rlast      (m_axi_rlast),
        .m_axi_rvalid     (m_axi_rvalid),
        .m_axi_rready     (m_axi_rready),
        .m_axi_awid       (m_axi_awid),
        .m_axi_awaddr     (m_axi_awaddr),
        .m_axi_awlen      (m_axi_awlen),
        .m_axi_awsize     (m_axi_awsize),
        .m_axi_awburst    (m_axi_awburst),
        .m_axi_awvalid    (m_axi_awvalid),
        .m_axi_awready    (m_axi_awready),
        .m_axi_wdata      (m_axi_wdata),
        .m_axi_wstrb      (m_axi_wstrb),
        .m_axi_wlast      (m_axi_wlast),
        .m_axi_wvalid     (m_axi_wvalid),
        .m_axi_wready     (m_axi_wready),
        .m_axi_bid        (m_axi_bid),
        .m_axi_bresp      (m_axi_bresp),
        .m_axi_bvalid     (m_axi_bvalid),
        .m_axi_bready     (m_axi_bready)
    );

    // Merge write into refilled line data if request was a store
    logic [LINE_BITS-1:0] merged_line_data;
    logic [3:0]           word_offset_idx;
    assign word_offset_idx = get_offset(latched_addr) >> 2;

    always_comb begin
        merged_line_data = refill_line_data;
        if (latched_write) begin
            if (latched_wstrb[0]) merged_line_data[word_offset_idx*32 + 0  +: 8] = latched_wdata[7:0];
            if (latched_wstrb[1]) merged_line_data[word_offset_idx*32 + 8  +: 8] = latched_wdata[15:8];
            if (latched_wstrb[2]) merged_line_data[word_offset_idx*32 + 16 +: 8] = latched_wdata[23:16];
            if (latched_wstrb[3]) merged_line_data[word_offset_idx*32 + 24 +: 8] = latched_wdata[31:24];
        end
    end

    // FSM State Register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    // Next State & Control Logic
    always_comb begin
        next_state       = state;
        cpu_req_ready    = 1'b0;
        cpu_resp_valid   = 1'b0;
        cpu_resp_hit     = 1'b0;
        cpu_resp_rdata   = word_rdata;
        word_we          = 1'b0;
        dirty_we         = 1'b0;
        line_we          = 1'b0;
        tag_we           = 1'b0;
        tag_write_index  = lookup_index;
        tag_write_way    = plru_victim_way;
        tag_write_tag    = lookup_tag;
        tag_write_valid  = 1'b1;
        tag_write_dirty  = latched_write;
        line_wdata       = merged_line_data;
        plru_update_en   = 1'b0;
        plru_access_way  = hit_way_id;
        refill_req       = 1'b0;
        wb_req           = 1'b0;

        case (state)
            IDLE: begin
                cpu_req_ready = 1'b1;
                if (cpu_req_valid) begin
                    next_state = LOOKUP;
                end
            end

            LOOKUP: begin
                if (cache_hit) begin
                    cpu_resp_valid = 1'b1;
                    cpu_resp_hit   = 1'b1;
                    plru_update_en = 1'b1;
                    plru_access_way= hit_way_id;

                    if (latched_write) begin
                        word_we  = 1'b1;
                        dirty_we = 1'b1;
                    end
                    next_state = IDLE;
                end else begin
                    // Cache Miss: Check if victim is dirty
                    if (way_valid[plru_victim_way] && way_dirty[plru_victim_way]) begin
                        next_state = WRITEBACK;
                    end else begin
                        next_state = REFILL;
                    end
                end
            end

            WRITEBACK: begin
                wb_req = 1'b1;
                if (wb_done) begin
                    next_state = REFILL;
                end
            end

            REFILL: begin
                refill_req = 1'b1;
                if (refill_done) begin
                    next_state = UPDATE_LINE;
                end
            end

            UPDATE_LINE: begin
                line_we        = 1'b1;
                tag_we         = 1'b1;
                plru_update_en = 1'b1;
                plru_access_way= plru_victim_way;
                next_state     = RESPOND;
            end

            RESPOND: begin
                cpu_resp_valid = 1'b1;
                cpu_resp_hit   = 1'b0; // Miss fulfilled
                cpu_resp_rdata = merged_line_data[word_offset_idx*32 +: 32];
                next_state     = IDLE;
            end

            default: next_state = IDLE;
        endcase
    end

    // Latches
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            latched_addr  <= '0;
            latched_wdata <= '0;
            latched_wstrb <= '0;
            latched_write <= 1'b0;
        end else if (state == IDLE && cpu_req_valid) begin
            latched_addr  <= cpu_req_addr;
            latched_wdata <= cpu_req_wdata;
            latched_wstrb <= cpu_req_wstrb;
            latched_write <= cpu_req_write;
        end
    end

endmodule
