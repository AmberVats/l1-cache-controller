//=============================================================================
// Module: cache_axi_master
// Description: AXI4 Master Interface for Cache Line Refill & Dirty Line Writeback.
//              Handles 16-beat 32-bit burst transfers to fetch/flush 64-byte lines.
//=============================================================================

`timescale 1ns / 1ps
import cache_pkg::*;

module cache_axi_master #(
    parameter int AXI_ID_WIDTH = 4
) (
    input  logic                     aclk,
    input  logic                     aresetn,

    // Refill Interface
    input  logic                     refill_req,
    output logic                     refill_ready,
    input  logic [ADDR_WIDTH-1:0]    refill_addr,
    output logic                     refill_done,
    output logic [LINE_BITS-1:0]     refill_line_data,

    // Writeback Interface
    input  logic                     wb_req,
    output logic                     wb_ready,
    input  logic [ADDR_WIDTH-1:0]    wb_addr,
    input  logic [LINE_BITS-1:0]     wb_line_data,
    output logic                     wb_done,

    // AXI4 Read Channels (AR, R)
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

    // AXI4 Write Channels (AW, W, B)
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
        ST_IDLE      = 3'b000,
        ST_SEND_AR   = 3'b001,
        ST_RECV_R    = 3'b010,
        ST_SEND_AW   = 3'b011,
        ST_SEND_W    = 3'b100,
        ST_RECV_B    = 3'b101,
        ST_DONE      = 3'b110
    } state_t;

    state_t state;

    logic [3:0]           beat_count;
    logic [LINE_BITS-1:0] rx_buffer;
    logic [LINE_BITS-1:0] tx_buffer;
    logic [ADDR_WIDTH-1:0]latched_addr;
    logic                 is_writeback;

    // AXI Protocol Constants
    assign m_axi_arid    = '0;
    assign m_axi_arsize  = 3'b010; // 4 bytes per beat
    assign m_axi_arburst = 2'b01;  // INCR burst
    assign m_axi_arlen   = 8'd15;  // 16 beats = 64 bytes

    assign m_axi_awid    = '0;
    assign m_axi_awsize  = 3'b010;
    assign m_axi_awburst = 2'b01;
    assign m_axi_awlen   = 8'd15;
    assign m_axi_wstrb   = 4'b1111;

    // AR Channel
    assign m_axi_araddr  = {latched_addr[ADDR_WIDTH-1:OFFSET_WIDTH], {OFFSET_WIDTH{1'b0}}};
    assign m_axi_arvalid = (state == ST_SEND_AR);

    // R Channel
    assign m_axi_rready  = (state == ST_RECV_R);

    // AW Channel
    assign m_axi_awaddr  = {latched_addr[ADDR_WIDTH-1:OFFSET_WIDTH], {OFFSET_WIDTH{1'b0}}};
    assign m_axi_awvalid = (state == ST_SEND_AW);

    // W Channel
    assign m_axi_wvalid  = (state == ST_SEND_W);
    assign m_axi_wdata   = tx_buffer[beat_count*32 +: 32];
    assign m_axi_wlast   = (beat_count == 4'd15);

    // B Channel
    assign m_axi_bready  = (state == ST_RECV_B);

    // Control Handshakes
    assign refill_ready     = (state == ST_IDLE);
    assign wb_ready         = (state == ST_IDLE) && !refill_req;
    assign refill_done      = (state == ST_DONE) && !is_writeback;
    assign wb_done          = (state == ST_DONE) && is_writeback;
    assign refill_line_data = rx_buffer;

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            state        <= ST_IDLE;
            beat_count   <= 4'd0;
            rx_buffer    <= '0;
            tx_buffer    <= '0;
            latched_addr <= '0;
            is_writeback <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    beat_count <= 4'd0;
                    if (wb_req) begin
                        // Priority writeback of dirty line
                        is_writeback <= 1'b1;
                        latched_addr <= wb_addr;
                        tx_buffer    <= wb_line_data;
                        state        <= ST_SEND_AW;
                    end else if (refill_req) begin
                        // Line fetch
                        is_writeback <= 1'b0;
                        latched_addr <= refill_addr;
                        state        <= ST_SEND_AR;
                    end
                end

                ST_SEND_AR: begin
                    if (m_axi_arvalid && m_axi_arready) begin
                        state <= ST_RECV_R;
                    end
                end

                ST_RECV_R: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        rx_buffer[beat_count*32 +: 32] <= m_axi_rdata;
                        if (m_axi_rlast || (beat_count == 4'd15)) begin
                            state <= ST_DONE;
                        end else begin
                            beat_count <= beat_count + 1'b1;
                        end
                    end
                end

                ST_SEND_AW: begin
                    if (m_axi_awvalid && m_axi_awready) begin
                        state <= ST_SEND_W;
                    end
                end

                ST_SEND_W: begin
                    if (m_axi_wvalid && m_axi_wready) begin
                        if (m_axi_wlast) begin
                            state <= ST_RECV_B;
                        end else begin
                            beat_count <= beat_count + 1'b1;
                        end
                    end
                end

                ST_RECV_B: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        state <= ST_DONE;
                    end
                end

                ST_DONE: begin
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
