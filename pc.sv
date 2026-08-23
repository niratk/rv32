`default_nettype none

module pc #(
    PCWIDTH = 32
) (
    input logic clk,
    input logic [PCWIDTH-1:0] pc_next,
    output logic [PCWIDTH-1:0] pc
);

  always_ff @(posedge clk) begin
    pc <= pc_next;
  end

endmodule

`default_nettype wire
