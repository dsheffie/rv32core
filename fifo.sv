module fifo#(parameter W = 32, parameter LG_D = 3)(clk, reset, in, out, push, pop, empty, full);
   input logic clk;
   input logic reset;
   input logic [W-1:0] in;
   output logic [W-1:0] out;
   input logic		push;
   input logic		pop;
   output logic		empty;
   output logic		full;

   logic [LG_D:0]	r_rd_idx, n_rd_idx, 
			r_wr_idx, n_wr_idx;

   localparam		D = 1<<LG_D;
      
   logic [W-1:0]	r_ram [D-1:0];

   always_ff@(negedge clk)
     begin
	if(pop & empty)
	  $stop();
	if(push & full)
	  $stop();
     end
   
   always_comb
     begin
	n_rd_idx = r_rd_idx;
	n_wr_idx = r_wr_idx;
	
	empty = (r_rd_idx == r_wr_idx);
	full = (r_rd_idx[LG_D-1:0] == r_wr_idx[LG_D-1:0]) &
	       (r_rd_idx[LG_D] != r_wr_idx[LG_D]);
	if(push)
	  begin
	     n_wr_idx = r_wr_idx + 'd1;
	  end
	if(pop)
	  begin
	     n_rd_idx = r_rd_idx + 'd1;
	  end
	out = r_ram[r_rd_idx[LG_D-1:0]];
     end // always_comb

   always@(posedge clk)
     begin
	if(push)
	  begin
	     r_ram[r_wr_idx[LG_D-1:0]] <= in;
	  end
     end
   
   always@(posedge clk)
     begin
	if(reset)
	  begin
	     r_rd_idx <= 'd0;
	     r_wr_idx <= 'd0;
	  end
	else
	  begin
	     r_rd_idx <= n_rd_idx;
	     r_wr_idx <= n_wr_idx;
	  end
     end // always@ (posedge clk)
   
   
   

endmodule // fifo

   
   
