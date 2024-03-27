module btb(clk,
	   reset,
	   va,
	   pa,
	   hit,
	   replace,
	   replace_va,
	   replace_pa);
   input logic clk;
   input logic reset;
   input logic [63:0] va;
   output logic [63:0] pa;
   output logic	       hit;

   input logic	       replace;
   input logic [63:0]  replace_va;
   input logic [63:0]  replace_pa;
   
   /* bits 39 down to 12 */

   parameter	       LG_N = 2;
   localparam	       N = 1<<LG_N;

   logic [N-1:0]       r_valid;
   logic [LG_N-1:0]    r_cnt;
   
   logic [27:0]	       r_va_tags[N-1:0];
   logic [51:0]	       r_pa_data[N-1:0];
   
   wire [N-1:0]	       w_hits;
   wire [LG_N:0]	       w_idx;   
   generate
      for(genvar i = 0; i < N; i=i+1)
	begin : hits
	   assign w_hits[i] = r_valid[i] ? (r_va_tags[i] == va[39:12]) : 1'b0;
	end
   endgenerate
   
   find_first_set#(.LG_N(LG_N)) 
   ffs(.in(w_hits),
       .y(w_idx));

   
   always_ff@(posedge clk)
     begin
	r_cnt <= reset ? 'd0 : r_cnt + 'd1;
	hit <= reset ? 1'b0 : |w_hits;
	pa <= {r_pa_data[w_idx[LG_N-1:0]], 12'd0};
     end
   
   always_ff@(posedge clk)
     begin
	if(reset)
	  begin
	     r_valid <= 'd0;
	  end
	else if(replace)
	  begin
	     r_valid[r_cnt] <= 1'b1;
	     r_va_tags[r_cnt] <= replace_va[39:12];
	     r_pa_data[r_cnt] <= replace_pa[63:12];
	  end
     end
   

endmodule
   
   
