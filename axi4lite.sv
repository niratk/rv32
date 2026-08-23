`default_nettype none

module axi4lite #(
    parameter AWIDTH  = 12,
    parameter IAWIDTH = 10
) (
    output logic [   IAWIDTH-1:0] iaddr,
    input  logic [4+AWIDTH*2-1:0] instr,
    input  logic                  instr_val,

    // AXI4-lite master memory interface
    // address write channel
    output logic        axi_awvalid,
    input  logic        axi_awready,
    output logic [31:0] axi_awaddr,
    output logic [ 2:0] axi_awprot,
    // data write channel
    output logic        axi_wvalid,
    input  logic        axi_wready,
    output logic [31:0] axi_wdata,
    output logic [ 3:0] axi_wstrb,
    // response channel
    input  logic        axi_bvalid,
    output logic        axi_bready,
    input  logic [ 1:0] axi_bresp,
    // address read channel
    output logic        axi_arvalid,
    input  logic        axi_arready,
    output logic [31:0] axi_araddr,
    output logic [ 2:0] axi_arprot,
    // read data channel
    input  logic        axi_rvalid,
    output logic        axi_rready,
    input  logic [31:0] axi_rdata,
    input  logic [ 1:0] axi_rresp,

    output logic data_rdy,
    input  logic clk,
    input  logic rstn
);

  typedef enum logic [1:0] {
    S_WAIT,
    S_LOAD,
    S_STORE,
    S_END
  } state_t;

  typedef struct packed {
    logic [3:0] opcode;
    logic [AWIDTH-1:0] dst;
    logic [AWIDTH-1:0] src;
  } instr_t;

  instr_t decoded_instr;
  assign decoded_instr = instr;
  state_t state;

  localparam logic [3:0] OP_MOVE = 4'b0000;
  localparam logic [1:0] AXI_RESP_OKAY = 2'b00;

  function automatic logic [31:0] to_baddr(input logic [AWIDTH-1:0] addr);
    return {{(32 - AWIDTH - 2) {1'b0}}, addr, 2'b00};
  endfunction

  always @(posedge clk) begin
    if (~rstn) begin
      iaddr       <= 'd0;
      axi_awvalid <= 'd0;
      axi_awaddr  <= 'd0;
      axi_awprot  <= 'd0;
      axi_wvalid  <= 'd0;
      axi_wdata   <= 'd0;
      axi_wstrb   <= 'd0;
      axi_bready  <= 'd0;
      axi_arvalid <= 'd0;
      axi_araddr  <= 'd0;
      axi_arprot  <= 'd0;
      axi_rready  <= 'd0;
      data_rdy    <= 'd0;
      state       <= S_WAIT;
    end else begin
      case (state)
        S_WAIT: begin
          if (instr_val) begin
            if (decoded_instr.opcode == OP_MOVE) begin
              axi_araddr <= to_baddr(decoded_instr.src);
              axi_arprot <= 3'd0;
              axi_arvalid <= 1'b1;
              axi_rready <= 1'b1;
              state <= S_LOAD;
            end else begin
              state <= S_END;
            end
          end
        end
        S_LOAD: begin
          if (axi_arready) begin
            axi_arvalid <= 1'b0;
          end
          if (axi_rvalid) begin
            axi_rready <= 1'b0;
            if (axi_rresp == AXI_RESP_OKAY) begin
              axi_awaddr <= to_baddr(decoded_instr.dst);
              axi_awprot <= 3'd0;
              axi_awvalid <= 1'b1;
              axi_bready <= 1'b1;
              axi_wdata <= axi_rdata;
              axi_wstrb <= 4'b1111;
              axi_wvalid <= 1'b1;
              state <= S_STORE;
              iaddr <= iaddr + 1;
            end else begin
              state <= S_END;
            end
          end
        end
        S_STORE: begin
          if (axi_awready) begin
            axi_awvalid <= 1'b0;
          end
          if (axi_wready) begin
            axi_wvalid <= 1'b0;
          end
          if (axi_bvalid) begin
            axi_bready <= 1'b0;
            if (axi_bresp == AXI_RESP_OKAY) begin
              if (decoded_instr.opcode == OP_MOVE) begin
                axi_araddr <= to_baddr(decoded_instr.src);
                axi_arprot <= 3'd0;
                axi_arvalid <= 1'b1;
                axi_rready <= 1'b1;
                state <= S_LOAD;
              end else begin
                state <= S_END;
              end
            end else begin
              state <= S_END;
            end
          end
        end
        S_END: begin
          data_rdy <= 1'b1;
        end
        default: begin
          state <= S_END;
        end
      endcase
    end
  end

endmodule

`default_nettype wire
