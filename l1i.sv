`include "machine.vh"
`include "rob.vh"
`include "uop.vh"

`ifdef VERILATOR
import "DPI-C" function void record_fetch(int push1, int push2, int push3, int push4,
					  longint pc0, longint pc1, longint pc2, longint pc3,
					  int bubble, int fq_full);

`endif

module predecode(insn_, pd);
   input logic [31:0] insn_;
   output logic [3:0] pd;

   logic [31:0]       insn;
   
   always_comb
     begin
	pd = 4'd0;
	insn = bswap32(insn_);
	case(insn[31:26])
	  6'd0: /* rtype */
	    begin
	       if(insn[5:0] == 6'd8) /* pdr */
		 begin
		    pd = (insn[25:21] == 5'd31) ? 4'd7 : 4'd4;
		 end
	       else if(insn[5:0] == 6'd9)
		 begin
		    pd = 4'd6;
		 end
	    end
	  6'd1:
	    begin
	       case(insn[20:16])
		 'd0:
		   begin
		      pd = 4'd1;
		   end
		 'd1:
		   begin
		      pd = 4'd1;
		   end
		 'd2:
		   begin
		      pd = 4'd2;
		   end
		 'd3:
		   begin
		      pd = 4'd2;
		   end
		 'd17:
		   begin
		      pd = 4'd9;
		   end
		 default:
		   begin
		   end
	       endcase // case (rt)	  
	    end
	  6'd2:
	    begin
	       pd = 4'd3;
	    end   
	  6'd3:
	    begin
	       pd = 4'd5;
	    end
	  6'd4:
	    begin
	       pd = ((insn[25:21] == 'd0) && (insn[20:16] == 'd0)) ? 4'd8 : 4'd1;
	    end
	  6'd5:
	    begin
	       pd = 4'd1;
	    end
	  6'd6:
	    begin
	       pd = 4'd1;
	    end
	  6'd7:
	    begin
	       pd = 4'd1;
	    end
	  6'd17:
	    begin
	       if(insn[25:21]==5'd8)
		 begin
		    case(insn[17:16])
		      2'b00: //bc1f
			begin
			   pd = 4'd1;
			end
		      2'b01: //bc1t
			begin
			   pd = 4'd1;
			end
		      2'b10: //bc1fl;
			begin
			   pd = 4'd2;
			end
		      2'b11: //bc1tl
			begin
			   pd = 4'd2;
			end	       
		    endcase // case (insn[17:16])
		 end // if (insn[25:21]==5'd8)
	    end
	  6'd20:
	    begin
	       pd = 4'd2;
	    end
	  6'd21:
	    begin
	       pd = 4'd2;
	    end
	  6'd22:
	    begin
	       pd = 4'd2;
	    end
	  6'd23:
	    begin
	       pd = 4'd2;
	    end     
	  default:
	    begin
	       pd = 4'd0;
	    end
	endcase // case (opcode)   
     end // always_comb
endmodule // predecode




module l1i(clk,
	   reset,
	   flush_req,
	   flush_complete,
	   restart_pc,
	   restart_src_pc,
	   restart_src_is_indirect,
	   restart_valid,
	   restart_ack,
	   retire_valid,
	   retired_call,
	   retired_ret,
	   retire_reg_ptr,
	   retire_reg_data,
	   retire_reg_valid,
	   branch_pc_valid,
	   took_branch,
	   branch_pht_idx,
	   
	   insn,
	   insn_valid,
	   insn_ack,
	   
	   insn_two,
	   insn_valid_two,
	   insn_ack_two,
	   
	   //output to the memory system
	   mem_req_ack,
	   mem_req_valid, 
	   mem_req_addr, 
	   mem_req_tag,
	   mem_req_opcode,
	   //reply from memory system
	   mem_rsp_valid,
	   mem_rsp_load_data,
	   cache_accesses,
	   cache_hits
	   );

   input logic clk;
   input logic reset;
   input logic 	      flush_req;
   output logic       flush_complete;
   //restart signals
   input logic [31:0] restart_pc;
   input logic [31:0] restart_src_pc;
   input logic 	      restart_src_is_indirect;
   input logic 	      restart_valid;
   output logic       restart_ack;
   //return stack signals
   input logic 			retire_valid;
   input logic 			retired_call;
   input logic 			retired_ret;

   input logic [4:0] 		retire_reg_ptr;
   input logic [31:0] 		retire_reg_data;
   input logic 			retire_reg_valid;

   input logic 			branch_pc_valid;
   input logic 			took_branch;
   input logic [`LG_PHT_SZ-1:0] branch_pht_idx;
   
   output insn_fetch_t insn;
   output logic insn_valid;
   input logic 	insn_ack;
   
   output 	insn_fetch_t insn_two;
   output logic insn_valid_two;
   input logic 	insn_ack_two;

   input logic 	mem_req_ack;
   output logic mem_req_valid;
   
   localparam L1I_NUM_SETS = 1 << `LG_L1D_NUM_SETS;
   localparam L1I_CL_LEN = 1 << `LG_L1D_CL_LEN;
   localparam L1I_CL_LEN_BITS = 1 << (`LG_L1D_CL_LEN + 3);
   localparam LG_WORDS_PER_CL = `LG_L1D_CL_LEN - 2;
   localparam WORDS_PER_CL = 1<<LG_WORDS_PER_CL;
   localparam N_TAG_BITS = `M_WIDTH - `LG_L1D_NUM_SETS - `LG_L1D_CL_LEN;
   localparam IDX_START = `LG_L1D_CL_LEN;
   localparam IDX_STOP  = `LG_L1D_CL_LEN + `LG_L1D_NUM_SETS;
   localparam WORD_START = 2;
   localparam WORD_STOP = WORD_START+LG_WORDS_PER_CL;
   localparam N_FQ_ENTRIES = 1 << `LG_FQ_ENTRIES;
   localparam RETURN_STACK_ENTRIES = 1 << `LG_RET_STACK_ENTRIES;
   localparam PHT_ENTRIES = 1 << `LG_PHT_SZ;
   localparam BTB_ENTRIES = 1 << `LG_BTB_SZ;

   output logic [(`M_WIDTH-1):0] mem_req_addr;
   output logic [`LG_MEM_TAG_ENTRIES-1:0] mem_req_tag;
   output logic [3:0] 			  mem_req_opcode;
   input logic 				  mem_rsp_valid;
   input logic [L1I_CL_LEN_BITS-1:0] 	  mem_rsp_load_data;
   output logic [63:0] 			  cache_accesses;
   output logic [63:0] 			  cache_hits;
      
   logic [N_TAG_BITS-1:0] 		  t_cache_tag, r_cache_tag, r_tag_out;

   logic 				  r_pht_update;
   logic [1:0] 				  r_pht_out, r_pht_update_out;
   logic [1:0] 				  t_pht_val;
   logic 				  t_do_pht_wr;
   
   logic [`LG_PHT_SZ-1:0] 		  n_pht_idx,r_pht_idx;
   logic [`LG_PHT_SZ-1:0] 		  r_pht_update_idx;
   logic 				  r_take_br;
   
   logic [(`M_WIDTH-1):0] 		  r_btb[BTB_ENTRIES-1:0];
   logic [BTB_ENTRIES-1:0] 		  r_btb_valid;
   
   
   logic [(4*WORDS_PER_CL)-1:0] 	  r_jump_out;
   
   logic [`LG_L1D_NUM_SETS-1:0] 	    t_cache_idx, r_cache_idx;   
   logic [L1I_CL_LEN_BITS-1:0] 		    r_array_out;   
   logic 				    r_mem_req_valid, n_mem_req_valid;
   logic [(`M_WIDTH-1):0] 		    r_mem_req_addr, n_mem_req_addr;
   

   insn_fetch_t r_fq[N_FQ_ENTRIES-1:0];
   
   logic [`LG_FQ_ENTRIES:0] r_fq_head_ptr, n_fq_head_ptr;
   logic [`LG_FQ_ENTRIES:0] r_fq_next_head_ptr, n_fq_next_head_ptr;
   logic [`LG_FQ_ENTRIES:0] r_fq_next_tail_ptr, n_fq_next_tail_ptr;
   logic [`LG_FQ_ENTRIES:0] r_fq_next3_tail_ptr, n_fq_next3_tail_ptr;
   logic [`LG_FQ_ENTRIES:0] r_fq_next4_tail_ptr, n_fq_next4_tail_ptr;
   
   logic [`LG_FQ_ENTRIES:0] r_fq_tail_ptr, n_fq_tail_ptr;
   logic 		    r_resteer_bubble, n_resteer_bubble;
   
   
   logic 		    fq_full, fq_next_empty, fq_empty;
   logic 		    fq_full2, fq_full3, fq_full4;
   
   
   logic [(`M_WIDTH-1):0]   r_spec_return_stack [RETURN_STACK_ENTRIES-1:0];
   logic [(`M_WIDTH-1):0]   r_arch_return_stack [RETURN_STACK_ENTRIES-1:0];
   logic [`LG_RET_STACK_ENTRIES-1:0] n_arch_rs_tos, r_arch_rs_tos;
   logic [`LG_RET_STACK_ENTRIES-1:0] n_spec_rs_tos, r_spec_rs_tos, t_next_spec_rs_tos;   
   
   logic [`GBL_HIST_LEN-1:0] 	     n_arch_gbl_hist, r_arch_gbl_hist;
   logic [`GBL_HIST_LEN-1:0] 	     n_spec_gbl_hist, r_spec_gbl_hist;
   logic [`GBL_HIST_LEN-1:0] 	     t_xor_pc_hist;


   logic [LG_WORDS_PER_CL-1:0] 	     t_insn_idx;
   
   logic [63:0] 			 n_cache_accesses, r_cache_accesses;
   logic [63:0] 			 n_cache_hits, r_cache_hits;
   
function logic [31:0] select_cl32(logic [L1I_CL_LEN_BITS-1:0] cl, logic[LG_WORDS_PER_CL-1:0] pos);
   logic [31:0] 			 w32;
   case(pos)
     2'd0:
       w32 = cl[31:0];
     2'd1:
       w32 = cl[63:32];
     2'd2:
       w32 = cl[95:64];
     2'd3:
       w32 = cl[127:96];
   endcase // case (pos)
   return w32;
endfunction

function logic [3:0] select_pd(logic [15:0] cl, logic[LG_WORDS_PER_CL-1:0] pos);
   logic [3:0] j;
   case(pos)
     2'd0:
       j = cl[3:0];
     2'd1:
       j = cl[7:4];
     2'd2:
       j = cl[11:8];
     2'd3:
       j = cl[15:12];
   endcase // case (pos)
   return j;
endfunction

function logic is_nop(logic [31:0] insn);
   return (insn == 32'd0);
endfunction // is_nop
      
      
   
   typedef enum logic [2:0] {INITIALIZE = 'd0,
			     IDLE = 'd1,
                             ACTIVE = 'd2,
                             INJECT_RELOAD = 'd3,
			     RELOAD_TURNAROUND = 'd4,
                             FLUSH_CACHE = 'd5,
			     WAIT_FOR_NOT_FULL = 'd6,
			     INIT_PHT = 'd7
			    } state_t;
   
   logic [(`M_WIDTH-1):0] r_pc, n_pc, r_miss_pc, n_miss_pc;
   logic [(`M_WIDTH-1):0] r_cache_pc, n_cache_pc;
   logic [(`M_WIDTH-1):0] r_btb_pc;
   
   
   state_t n_state, r_state;
   logic 		  r_restart_req, n_restart_req;
   logic 		  r_restart_ack, n_restart_ack;
   logic 		  r_req, n_req;
   logic 		  r_valid_out;
   logic 		  t_miss, t_hit;
   logic 		  t_push_insn, t_push_insn2,
			  t_push_insn3, t_push_insn4;
   
   logic 		  t_clear_fq;
   logic 		  r_flush_req, n_flush_req;
   logic 		  r_flush_complete, n_flush_complete;
   logic 		  n_delay_slot, r_delay_slot;
   logic 		  t_take_br, t_is_cflow;
   logic 		  t_update_spec_hist;
   
   logic [31:0] 	  t_insn_data, t_insn_data2, t_insn_data3, t_insn_data4;
   logic [`M_WIDTH-1:0]   t_simm;
   logic 		  t_is_call, t_is_ret;
   logic [2:0] 		  t_branch_cnt;
   logic [4:0] 		  t_branch_marker, t_spec_branch_marker;
   logic [2:0] 		  t_first_branch;

   logic 		  t_init_pht;
   logic [`LG_PHT_SZ-1:0] r_init_pht_idx, n_init_pht_idx;
   

   
   //always_ff@(negedge clk)
   //begin
   //$display("r_cache_pc = %x, t_branch_locs = %b, t_insn_idx = %d, t_branch_marker = %b, first_branch = %d",
   //r_cache_pc,t_branch_locs, t_insn_idx, t_branch_marker, t_first_branch);
   //end
   
   
   localparam SEXT = `M_WIDTH-16;
   insn_fetch_t t_insn, t_insn2, t_insn3, t_insn4;
   logic [3:0] t_pd;

   
   logic [63:0] 	  r_cycle;
   always_ff@(posedge clk)
     begin
	r_cycle <= reset ? 'd0 : r_cycle + 'd1;
     end

   assign flush_complete = r_flush_complete;
   
   assign insn_valid = !fq_empty;
   assign insn_valid_two = !(fq_next_empty || fq_empty);

   
   assign restart_ack = r_restart_ack;

   assign mem_req_valid = r_mem_req_valid;
   assign mem_req_addr = r_mem_req_addr;
   assign mem_req_tag = 'd0;
   assign mem_req_opcode = MEM_LW;
   assign cache_hits = r_cache_hits;
   assign cache_accesses = r_cache_accesses;
   
   always_comb
     begin
	n_fq_tail_ptr = r_fq_tail_ptr;
	n_fq_head_ptr = r_fq_head_ptr;
	n_fq_next_head_ptr = r_fq_next_head_ptr;
	n_fq_next_tail_ptr = r_fq_next_tail_ptr;
	n_fq_next3_tail_ptr = r_fq_next3_tail_ptr;
	n_fq_next4_tail_ptr = r_fq_next4_tail_ptr;
	
	fq_empty = (r_fq_head_ptr == r_fq_tail_ptr);
	fq_next_empty = (r_fq_next_head_ptr == r_fq_tail_ptr);
	
	fq_full = (r_fq_head_ptr != r_fq_tail_ptr) &&
		  (r_fq_head_ptr[`LG_FQ_ENTRIES-1:0] == r_fq_tail_ptr[`LG_FQ_ENTRIES-1:0]);
	
	fq_full2 = (r_fq_head_ptr != r_fq_next_tail_ptr) &&
		   (r_fq_head_ptr[`LG_FQ_ENTRIES-1:0] == r_fq_next_tail_ptr[`LG_FQ_ENTRIES-1:0]) || fq_full;
	
	fq_full3 = (r_fq_head_ptr != r_fq_next3_tail_ptr) &&
		   (r_fq_head_ptr[`LG_FQ_ENTRIES-1:0] == r_fq_next3_tail_ptr[`LG_FQ_ENTRIES-1:0]) || fq_full2;
	
	fq_full4 = (r_fq_head_ptr != r_fq_next4_tail_ptr) &&
		   (r_fq_head_ptr[`LG_FQ_ENTRIES-1:0] == r_fq_next4_tail_ptr[`LG_FQ_ENTRIES-1:0]) || fq_full3;
	
	insn = r_fq[r_fq_head_ptr[`LG_FQ_ENTRIES-1:0]];
	insn_two = r_fq[r_fq_next_head_ptr[`LG_FQ_ENTRIES-1:0]];

	if(t_push_insn4)
	  begin
	     n_fq_tail_ptr = r_fq_tail_ptr + 'd4;
	     n_fq_next_tail_ptr = r_fq_next_tail_ptr + 'd4;
	     n_fq_next3_tail_ptr = r_fq_next3_tail_ptr + 'd4;
	     n_fq_next4_tail_ptr = r_fq_next4_tail_ptr + 'd4;
	  end
	else if(t_push_insn3)
	  begin
	     n_fq_tail_ptr = r_fq_tail_ptr + 'd3;
	     n_fq_next_tail_ptr = r_fq_next_tail_ptr + 'd3;
	     n_fq_next3_tail_ptr = r_fq_next3_tail_ptr + 'd3;
	     n_fq_next4_tail_ptr = r_fq_next4_tail_ptr + 'd3;
	  end
	else if(t_push_insn2)
	  begin
	     n_fq_tail_ptr = r_fq_tail_ptr + 'd2;
	     n_fq_next_tail_ptr = r_fq_next_tail_ptr + 'd2;
	     n_fq_next3_tail_ptr = r_fq_next3_tail_ptr + 'd2;
	     n_fq_next4_tail_ptr = r_fq_next4_tail_ptr + 'd2;
	  end
	else if(t_push_insn)
	  begin
	     n_fq_tail_ptr = r_fq_tail_ptr + 'd1;
	     n_fq_next_tail_ptr = r_fq_next_tail_ptr + 'd1;
	     n_fq_next3_tail_ptr = r_fq_next3_tail_ptr + 'd1;
	     n_fq_next4_tail_ptr = r_fq_next4_tail_ptr + 'd1;
	  end
	
	if(insn_ack && !insn_ack_two)
	  begin
	     n_fq_head_ptr = r_fq_head_ptr + 'd1;
	     n_fq_next_head_ptr = r_fq_next_head_ptr + 'd1;
	  end
	else if(insn_ack && insn_ack_two)
	  begin
	     n_fq_head_ptr = r_fq_head_ptr + 'd2;
	     n_fq_next_head_ptr = r_fq_next_head_ptr + 'd2;
	  end
     end // always_comb

   always_ff@(posedge clk)
     begin
	if(t_push_insn)
	  begin
	     //$display("t_insn.pc = %x, t_clear_fq=%b", t_insn.pc,t_clear_fq);
	     r_fq[r_fq_tail_ptr[`LG_FQ_ENTRIES-1:0]] <= t_insn;
	  end
	else if(t_push_insn2)
	  begin
	     //$display("t_insn.pc = %x, t_clear_fq=%b", t_insn.pc,t_clear_fq);
	     //$display("t_insn2.pc = %x", t_insn2.pc);	     
	     r_fq[r_fq_tail_ptr[`LG_FQ_ENTRIES-1:0]] <= t_insn;
	     r_fq[r_fq_next_tail_ptr[`LG_FQ_ENTRIES-1:0]] <= t_insn2;
	  end
	else if(t_push_insn3)
	  begin
	     //$display("t_insn.pc = %x, t_clear_fq=%b", t_insn.pc,t_clear_fq);	     	     
	     //$display("t_insn2.pc = %x", t_insn2.pc);
	     //$display("t_insn3.pc = %x", t_insn3.pc);	     	     	     
	     r_fq[r_fq_tail_ptr[`LG_FQ_ENTRIES-1:0]] <= t_insn;
	     r_fq[r_fq_next_tail_ptr[`LG_FQ_ENTRIES-1:0]] <= t_insn2;
	     r_fq[r_fq_next3_tail_ptr[`LG_FQ_ENTRIES-1:0]] <= t_insn3;	  	     
	  end
	else if(t_push_insn4)
	  begin
	     //$display("push4 cycle = %d, r_valid_out =%b, r_tag_out =%d, r_cache_tag = %d, r_cache_pc = %x", r_cycle, r_valid_out,r_tag_out,r_cache_tag,r_cache_pc);
	     //$display("t_insn.pc = %x,  bytes = %x, t_clear_fq=%b,hit=%b", t_insn.pc,t_insn.data,t_clear_fq,t_hit);	     
	     //$display("t_insn2.pc = %x, bytes = %x", t_insn2.pc,t_insn2.data);
	     //$display("t_insn3.pc = %x", t_insn3.pc);
	     //$display("t_insn4.pc = %x", t_insn4.pc);	     	     	     
	     r_fq[r_fq_tail_ptr[`LG_FQ_ENTRIES-1:0]] <= t_insn;
	     r_fq[r_fq_next_tail_ptr[`LG_FQ_ENTRIES-1:0]] <= t_insn2;
	     r_fq[r_fq_next3_tail_ptr[`LG_FQ_ENTRIES-1:0]] <= t_insn3;
	     r_fq[r_fq_next4_tail_ptr[`LG_FQ_ENTRIES-1:0]] <= t_insn4;	  	     	     
	  end
     end // always_ff@ (posedge clk)

   always_ff@(posedge clk)
     begin
	if(reset) 
	  begin
	     r_btb_valid <= 'd0;
	  end
	else if(restart_valid && restart_src_is_indirect)
	  begin
	     r_btb_valid[restart_src_pc[(`LG_BTB_SZ+1):2]] <= 1'b1;
	  end
     end // always_ff@ (posedge clk)

   
   always_ff@(posedge clk)
     begin
	if(restart_valid && restart_src_is_indirect)
	  begin
	     r_btb[restart_src_pc[(`LG_BTB_SZ+1):2]] <= restart_pc;
	  end	
     end // always_ff@ (posedge clk)

   always_ff@(posedge clk)
     begin
	r_btb_pc <= reset ? 'd0 : 
		    r_btb_valid[n_cache_pc[(`LG_BTB_SZ+1):2]] ? r_btb[n_cache_pc[(`LG_BTB_SZ+1):2]] : 32'd0;
	
     end

      
   always_comb
     begin
	n_pc = r_pc;
	n_miss_pc = r_miss_pc;
	n_cache_pc = 'd0;
	n_state = r_state;
	n_restart_ack = 1'b0;
	n_flush_req = r_flush_req | flush_req;
	n_flush_complete = 1'b0;
	n_delay_slot = r_delay_slot;
	t_cache_idx = 'd0;
	t_cache_tag = 'd0;
	n_req = 1'b0;
	n_mem_req_valid = 1'b0;
	n_mem_req_addr = r_mem_req_addr;
	n_resteer_bubble = 1'b0;
	t_next_spec_rs_tos = r_spec_rs_tos+'d1;
	n_restart_req = restart_valid | r_restart_req;
	t_miss = r_req && !(r_valid_out && (r_tag_out == r_cache_tag));
	t_hit = r_req && (r_valid_out && (r_tag_out == r_cache_tag));

	t_insn_idx = r_cache_pc[WORD_STOP-1:WORD_START];
	
	t_pd = select_pd(r_jump_out, t_insn_idx);

	t_insn_data  = select_cl32(r_array_out, t_insn_idx);
	t_insn_data2 = select_cl32(r_array_out, t_insn_idx + 2'd1);
	t_insn_data3 = select_cl32(r_array_out, t_insn_idx + 2'd2);
	t_insn_data4 = select_cl32(r_array_out, t_insn_idx + 2'd3);


	t_branch_marker = {1'b1,
			   select_pd(r_jump_out, 'd3) != 4'd0,
                           select_pd(r_jump_out, 'd2) != 4'd0,
                           select_pd(r_jump_out, 'd1) != 4'd0,
                           select_pd(r_jump_out, 'd0) != 4'd0
                           } >> t_insn_idx;

	t_spec_branch_marker = ({1'b1,
				select_pd(r_jump_out, 'd3) != 4'd0,
				select_pd(r_jump_out, 'd2) != 4'd0,
				select_pd(r_jump_out, 'd1) != 4'd0,
				select_pd(r_jump_out, 'd0) != 4'd0
				} >> t_insn_idx) & 
			       {4'b1111, !((t_pd == 4'd1) && !r_pht_out[1])};

	
	t_first_branch = 'd7;
	casez(t_spec_branch_marker)
	  5'b????1:
	    t_first_branch = 'd0;
	  5'b???10:
	    t_first_branch = 'd1;
	  5'b??100:
	    t_first_branch = 'd2;
	  5'b?1000:
	    t_first_branch = 'd3;
	  5'b10000:
	    t_first_branch = 'd4;
	  default:
	    t_first_branch = 'd7;
	endcase

	t_branch_cnt = {2'd0, select_pd(r_jump_out, 'd0) != 4'd0} +
		       {2'd0, select_pd(r_jump_out, 'd1) != 4'd0} +
		       {2'd0, select_pd(r_jump_out, 'd2) != 4'd0} +
		       {2'd0, select_pd(r_jump_out, 'd3) != 4'd0};
	
		
	t_simm = {{SEXT{t_insn_data[15]}},t_insn_data[15:0]};
	t_clear_fq = 1'b0;
	t_push_insn = 1'b0;
	t_push_insn2 = 1'b0;
	t_push_insn3 = 1'b0;
	t_push_insn4 = 1'b0;
	t_take_br = 1'b0;
	t_is_cflow = 1'b0;
	t_update_spec_hist = 1'b0;
	t_is_call = 1'b0;
	t_is_ret = 1'b0;
	t_init_pht = 1'b0;
	n_init_pht_idx = r_init_pht_idx;
	
	case(r_state)
	  INITIALIZE:
	    begin
	       n_state = INIT_PHT;
	    end
	  INIT_PHT:
	    begin
	       t_init_pht = 1'b1;
	       n_init_pht_idx = r_init_pht_idx + 'd1;
	       if(r_init_pht_idx == (PHT_ENTRIES-1))
		 begin
		    n_state = FLUSH_CACHE;	       
		    t_cache_idx = 0;
		 end
	    end
	  IDLE:
	    begin
	       if(n_restart_req)
		 begin
		    n_restart_ack = 1'b1;
		    n_restart_req = 1'b0;
		    n_pc = restart_pc;
		    n_state = ACTIVE;
		    t_clear_fq = 1'b1;
		 end
	    end	  
	  ACTIVE:
	    begin
	       t_cache_idx = r_pc[IDX_STOP-1:IDX_START];
	       t_cache_tag = r_pc[(`M_WIDTH-1):IDX_STOP];
	       /* accessed with this address */
	       n_cache_pc = r_pc;
	       n_req = 1'b1;
	       n_pc = r_pc + 'd4;
	       if(r_resteer_bubble)
		 begin
		    //do nothing?
		 end
	       else if(n_flush_req)
		 begin
		    n_flush_req = 1'b0;
		    t_clear_fq = 1'b1;
		    n_state = FLUSH_CACHE;
		    t_cache_idx = 0;
		 end
	       else if(n_restart_req)
		 begin
		    n_restart_ack = 1'b1;
		    n_restart_req = 1'b0;
		    n_delay_slot = 1'b0;
		    n_pc = restart_pc;
		    n_req = 1'b0;
		    n_state = ACTIVE;
		    t_clear_fq = 1'b1;
		 end // if (n_restart_req)
	       else if(t_miss)
		 begin
		    n_state = INJECT_RELOAD;
		    n_mem_req_addr = {r_cache_pc[`M_WIDTH-1:`LG_L1D_CL_LEN], {`LG_L1D_CL_LEN{1'b0}}};
		    n_mem_req_valid = 1'b1;
		    n_miss_pc = r_cache_pc;
		    n_pc = r_pc;
		 end
	       else if(t_hit && !fq_full)
		 begin
		    t_update_spec_hist = (t_pd != 4'd0);
		    if(t_pd == 4'd5 || t_pd == 4'd3)
		      begin
			 t_is_cflow = 1'b1;
			 n_delay_slot = 1'b1;
			 t_take_br = 1'b1;
			 t_is_call = (t_pd == 4'd5);
			 //if(t_is_call) $display("predict jal at %x will return to %x",
			 //r_cache_pc, r_cache_pc+'d8);
			 n_pc = {r_cache_pc[`M_WIDTH-1:28], t_insn_data[25:0], 2'd0};
		      end
		    else if(t_pd == 4'd8)
		      begin
			 t_is_cflow = 1'b1;			 
			 n_delay_slot = 1'b1;
			 t_take_br = 1'b1;
			 n_pc = ((r_cache_pc + 'd4) + {t_simm[`M_WIDTH-3:0], 2'd0});
		      end
		    else if(t_pd == 4'd2)
		      begin
			 //$display("decoded likely branch @ %x", r_cache_pc);
			 //treat as always taken for simplicity
			 t_is_cflow = 1'b1;			 
			 n_delay_slot = 1'b1;
			 t_take_br = 1'b1;
			 n_pc = ((r_cache_pc + 'd4) + {t_simm[`M_WIDTH-3:0], 2'd0});
		      end
		    else if(t_pd == 4'd9)
		      begin
			 //check if insn is bal or cond branch thinks its gonna be taken
			 if(r_pht_out[1] || t_insn_data[25:21] == 5'd0)
			   begin
			      t_is_cflow = 1'b1;
			      n_delay_slot = 1'b1;			      
			      n_pc = ((r_cache_pc + 'd4) + {t_simm[`M_WIDTH-3:0], 2'd0});
			      t_is_call = 1'b1;
			      t_take_br = 1'b1;
			      //$display("some flavor of branch and link, predicting target %x", n_pc);
			   end
		      end
		    else if(t_pd == 4'd1 && r_pht_out[1])
		      begin
			 t_is_cflow = 1'b1;			 
			 n_delay_slot = 1'b1;
			 t_take_br = 1'b1;
			 n_pc = ((r_cache_pc + 'd4) + {t_simm[`M_WIDTH-3:0], 2'd0});
			 //if(t_insn_idx != 'd3 && !fq_full2)
			 //begin
			 //t_push_insn2 = 1'b1;
			 //n_resteer_bubble = 1'b1;
			 //n_delay_slot = 1'b0;
			 // end
		      end
		    else if(t_pd == 4'd7)
		      begin
			 t_is_cflow = 1'b1;
			 t_is_ret = 1'b1;
			 n_delay_slot = 1'b1;
			 t_take_br = 1'b1;
			 n_pc = r_spec_return_stack[t_next_spec_rs_tos];
		      end // if (t_pd == 4'd7)
		    else if(t_pd == 4'd4 || t_pd == 4'd6)
		      begin
			 t_is_cflow = 1'b1;			 
			 n_delay_slot = 1'b1;
			 t_take_br = 1'b1;
			 t_is_call = (t_pd == 4'd6);
			 n_pc = r_btb_pc;
			 //$display("predicted target for %x is %x", r_cache_pc, n_pc);			 
		      end
		    
		    if(r_delay_slot)
		      begin
			 n_delay_slot = 1'b0;
		      end
		    
		    //initial push multiple logic
		    if(!(t_is_cflow || r_delay_slot))
		      begin
			 if(t_first_branch == 'd4 && !fq_full4)
			   begin
			      t_push_insn4 = 1'b1;
			      t_cache_idx = r_cache_idx + 'd1;
			      n_cache_pc = r_cache_pc + 'd16;
			      t_cache_tag = n_cache_pc[(`M_WIDTH-1):IDX_STOP];
			      n_pc = r_cache_pc + 'd20;
			   end
			 else if(t_first_branch == 'd3 && !fq_full3)
			   begin
			      t_push_insn3 = 1'b1;
			      n_cache_pc = r_cache_pc + 'd12;
			      n_pc = r_cache_pc + 'd16;
			      t_cache_tag = n_cache_pc[(`M_WIDTH-1):IDX_STOP];
			      if(t_insn_idx != 0)
				begin
				   t_cache_idx = r_cache_idx + 'd1;
				end
			      //n_resteer_bubble = 1'b1;
			   end
			 else if(t_first_branch == 'd2 && !fq_full2)
			   begin
			      //$display("t_branch_locs = %b", t_branch_locs);
			      t_push_insn2 = 1'b1;
			      n_pc = r_cache_pc + 'd8;
			      //guaranteed to end-up on another cacheline
			      n_cache_pc = r_cache_pc + 'd8;
			      t_cache_tag = n_cache_pc[(`M_WIDTH-1):IDX_STOP];
			      n_pc = r_cache_pc + 'd12;
			      if(t_insn_idx == 2)
				begin
				   t_cache_idx = r_cache_idx + 'd1;
				end
			   end
			 else
			   begin
			      t_push_insn = 1'b1;
			   end // else: !if(t_first_branch == 'd2 && !fq_full2)
		      end // if (!(t_is_cflow || r_delay_slot))
		    //else if(t_is_cflow && !r_delay_slot && t_insn_idx != 'd3 && !fq_full2)
		    //begin
		    //branch delay slot is on the same cacheline
		    //end
		    else
		      begin
			 t_push_insn = 1'b1;
		      end
		 end // if (t_hit && !fq_full)
	       else if(t_hit && fq_full)
		 begin
		    //$display("full insn queue at cycle %d", r_cycle);
		    n_pc = r_pc;
		    n_miss_pc = r_cache_pc;
		    n_state = WAIT_FOR_NOT_FULL;
		 end
	    end
	  INJECT_RELOAD:
	    begin
	       if(mem_rsp_valid)
		 begin
		    n_state = RELOAD_TURNAROUND;
		 end
	    end
	  RELOAD_TURNAROUND:
	    begin
	       t_cache_idx = r_miss_pc[IDX_STOP-1:IDX_START];
	       t_cache_tag = r_miss_pc[(`M_WIDTH-1):IDX_STOP];
	       if(n_flush_req)
		 begin
		    n_flush_req = 1'b0;
		    t_clear_fq = 1'b1;
		    n_state = FLUSH_CACHE;
		    t_cache_idx = 0;
		 end
	       else if(n_restart_req)
		 begin
		    n_restart_ack = 1'b1;
		    n_restart_req = 1'b0;
		    n_delay_slot = 1'b0;
		    n_pc = restart_pc;
		    n_req = 1'b0;
		    n_state = ACTIVE;
		    t_clear_fq = 1'b1;
		 end // if (n_restart_req)
	       else if(!fq_full)
		 begin
		    /* accessed with this address */
		    n_cache_pc = r_miss_pc;
		    n_req = 1'b1;
		    n_state = ACTIVE;
		 end
	    end
	  FLUSH_CACHE:
	    begin
	       if(r_cache_idx == (L1I_NUM_SETS-1))
		 begin
		    //$display("REQ FLUSHING COMPLETE at %d", r_cycle);
		    n_flush_complete = 1'b1;
		    n_state = IDLE;
		 end
	       t_cache_idx = r_cache_idx + 'd1;
	    end
	  WAIT_FOR_NOT_FULL:
	    begin
	       t_cache_idx = r_miss_pc[IDX_STOP-1:IDX_START];
	       t_cache_tag = r_miss_pc[(`M_WIDTH-1):IDX_STOP];
	       n_cache_pc = r_miss_pc;
	       if(!fq_full)
		 begin
		    n_req = 1'b1;
		    n_state = ACTIVE;
		 end
	       else if(n_flush_req)
		 begin
		    n_flush_req = 1'b0;
		    //n_flush_complete = 1'b1;
		    t_clear_fq = 1'b1;
		    n_state = FLUSH_CACHE;
		    t_cache_idx = 0;		    
		 end
	       else if(n_restart_req)
		 begin
		    n_restart_ack = 1'b1;
		    n_restart_req = 1'b0;
		    n_delay_slot = 1'b0;
		    n_pc = restart_pc;
		    n_req = 1'b0;
		    n_state = ACTIVE;
		    t_clear_fq = 1'b1;
		 end // if (n_restart_req)
	    end
	  default:
	    begin
	    end
	endcase // case (r_state)
     end // always_comb

   always_comb
     begin
	n_cache_accesses = r_cache_accesses;
	n_cache_hits = r_cache_hits;	
	if(t_hit)
	  begin
	     n_cache_hits = r_cache_hits + 'd1;
	  end
	if(r_req)
	  begin
	     n_cache_accesses = r_cache_accesses + 'd1;
	  end
     end
   
   always_comb
     begin
	t_insn.data = t_insn_data;
	t_insn.pc = r_cache_pc;
	t_insn.pred_target = n_pc;
	t_insn.pred = t_take_br;
	t_insn.pht_idx = r_pht_idx;
`ifdef	ENABLE_CYCLE_ACCOUNTING
	t_insn.fetch_cycle = r_cycle;
`endif
	t_insn2.data = t_insn_data2;
	t_insn2.pc = r_cache_pc + 'd4;
	t_insn2.pred_target = 'd0;
	t_insn2.pred = 1'b0;
	t_insn2.pht_idx = 'd0;
`ifdef	ENABLE_CYCLE_ACCOUNTING
	t_insn2.fetch_cycle = r_cycle;
`endif
	t_insn3.data = t_insn_data3;
	t_insn3.pc = r_cache_pc + 'd8;
	t_insn3.pred_target = 'd0;
	t_insn3.pred = 1'b0;
	t_insn3.pht_idx = 'd0;
`ifdef	ENABLE_CYCLE_ACCOUNTING
	t_insn3.fetch_cycle = r_cycle;
`endif
	t_insn4.data = t_insn_data4;
	t_insn4.pc = r_cache_pc + 'd12;
	t_insn4.pred_target = 'd0;
	t_insn4.pred = 1'b0;
	t_insn4.pht_idx = 'd0;
`ifdef	ENABLE_CYCLE_ACCOUNTING
	t_insn4.fetch_cycle = r_cycle;
`endif
     end // always_comb
   
   logic t_wr_valid_ram_en, t_valid_ram_value;
   logic [`LG_L1D_NUM_SETS-1:0] t_valid_ram_idx;

   always_comb
     begin
	t_wr_valid_ram_en = mem_rsp_valid || r_state == FLUSH_CACHE;
	t_valid_ram_value = (r_state != FLUSH_CACHE);
	t_valid_ram_idx = mem_rsp_valid ? r_mem_req_addr[IDX_STOP-1:IDX_START] : r_cache_idx;
	t_xor_pc_hist = {n_cache_pc[`GBL_HIST_LEN-7:2], 8'd0} ^ r_spec_gbl_hist;
	n_pht_idx = t_xor_pc_hist[`LG_PHT_SZ-1:0];
     end

   
   always_comb
     begin
	//t_xor_pc_hist = {n_cache_pc[`GBL_HIST_LEN-7:2], 8'd0} ^ r_spec_gbl_hist;	
	//n_pht_idx = t_xor_pc_hist[31:16] ^  t_xor_pc_hist[15:0];
	//n_pht_idx = t_xor_pc_hist[`LG_PHT_SZ-1:0];

	//n_pht_idx = r_spec_gbl_hist[15:0];
	
	//n_pht_idx = (n_cache_pc[15:0] ^ r_spec_gbl_hist[15:0]) ^
        //(n_cache_pc[31:16] ^ r_spec_gbl_hist[31:16]);
	
	t_pht_val = r_pht_update_out;
	t_do_pht_wr = r_pht_update;
	
	case(r_pht_update_out)
	  2'd0:
	    begin
	       if(r_take_br)
		 begin
		    t_pht_val =  2'd1;
		 end
	       else
		 begin
		    t_do_pht_wr = 1'b0;
		 end
	    end
	  2'd1:
	    begin
	       t_pht_val = r_take_br ? 2'd2 : 2'd0;
	    end
	  2'd2:
	    begin
	       t_pht_val = r_take_br ? 2'd3 : 2'd1;
	    end
	  2'd3:
	    begin
	       if(!r_take_br)
		 begin
		    t_pht_val = 2'd2;
		 end
	       else
		 begin
		    t_do_pht_wr = 1'b0;
		 end
	    end
	endcase // case (r_pht_update_out)
     end
   
   always_ff@(posedge clk)
     begin
	if(reset)
	  begin
	     r_pht_idx <= 'd0;
	     r_pht_update <= 1'b0;
	     r_pht_update_idx <= 'd0;
	     r_take_br <= 1'b0;
	  end
	else
	  begin
	     r_pht_idx <= n_pht_idx;
	     r_pht_update <= branch_pc_valid;
	     r_pht_update_idx <= branch_pht_idx;
	     r_take_br <= took_branch;
	  end
     end // always_ff@

`ifdef VERILATOR
   always_ff@(negedge clk)
     begin
	//$display("%b %b %b %b", t_push_insn, t_push_insn2, t_push_insn3, t_push_insn4);
	record_fetch(t_push_insn ? 32'd1 : 32'd0,
		     t_push_insn2 ? 32'd1 : 32'd0,
		     t_push_insn3 ? 32'd1 : 32'd0,
		     t_push_insn4 ? 32'd1 : 32'd0,
		     {32'd0, t_insn.pc},
		     {32'd0, t_insn2.pc},
		     {32'd0, t_insn3.pc},
		     {32'd0, t_insn4.pc},
		     r_resteer_bubble ? 32'd1 : 32'd0,
		     fq_full ? 32'd1 : 32'd0);
	
	
     end
`endif
	  

   ram2r1w #(.WIDTH(2), .LG_DEPTH(`LG_PHT_SZ) ) pht
     (
      .clk(clk),
      .rd_addr0(n_pht_idx),
      .rd_addr1(branch_pht_idx),
      .wr_addr(t_init_pht ? r_init_pht_idx : r_pht_update_idx),
      .wr_data(t_init_pht ? 2'd1 : t_pht_val),
      .wr_en(t_init_pht || t_do_pht_wr),
      .rd_data0(r_pht_out),
      .rd_data1(r_pht_update_out)
      );
         
   ram1r1w #(.WIDTH(1), .LG_DEPTH(`LG_L1D_NUM_SETS))
   valid_array (
	   .clk(clk),
	   .rd_addr(t_cache_idx),
	   .wr_addr(t_valid_ram_idx),
	   .wr_data(t_valid_ram_value),
	   .wr_en(t_wr_valid_ram_en),
	   .rd_data(r_valid_out)
	   );

   
   ram1r1w #(.WIDTH(N_TAG_BITS), .LG_DEPTH(`LG_L1D_NUM_SETS))
   tag_array (
	   .clk(clk),
	   .rd_addr(t_cache_idx),
	   .wr_addr(r_mem_req_addr[IDX_STOP-1:IDX_START]),
	   .wr_data(r_mem_req_addr[`M_WIDTH-1:IDX_STOP]),
	   .wr_en(mem_rsp_valid),
	   .rd_data(r_tag_out)
	   );
   
   ram1r1w #(.WIDTH(L1I_CL_LEN_BITS), .LG_DEPTH(`LG_L1D_NUM_SETS)) 
   insn_array (
	   .clk(clk),
	   .rd_addr(t_cache_idx),
	   .wr_addr(r_mem_req_addr[IDX_STOP-1:IDX_START]),
	   .wr_data({bswap32(mem_rsp_load_data[127:96]),
		     bswap32(mem_rsp_load_data[95:64]),
		     bswap32(mem_rsp_load_data[63:32]), 
		     bswap32(mem_rsp_load_data[31:0])}),
	   .wr_en(mem_rsp_valid),
	   .rd_data(r_array_out)
	   );

   wire [3:0] w_pd0, w_pd1, w_pd2, w_pd3;
   predecode pd0 (.insn_(mem_rsp_load_data[31:0]),   .pd(w_pd0));
   predecode pd1 (.insn_(mem_rsp_load_data[63:32]),  .pd(w_pd1));
   predecode pd2 (.insn_(mem_rsp_load_data[95:64]),  .pd(w_pd2));
   predecode pd3 (.insn_(mem_rsp_load_data[127:96]), .pd(w_pd3));   
   
   
   ram1r1w #(.WIDTH(4*WORDS_PER_CL), .LG_DEPTH(`LG_L1D_NUM_SETS))
   pd_data (
	    .clk(clk),
	    .rd_addr(t_cache_idx),
	    .wr_addr(r_mem_req_addr[IDX_STOP-1:IDX_START]),
	    .wr_data({w_pd3,w_pd2,w_pd1,w_pd0}),
	    .wr_en(mem_rsp_valid),
	    .rd_data(r_jump_out)
	    );
	    
	     
   always_comb
     begin
	n_spec_rs_tos = r_spec_rs_tos;
	if(n_restart_ack)
	  begin
	     n_spec_rs_tos = r_arch_rs_tos;
	  end
	else if(t_is_call)
	  begin
	     n_spec_rs_tos = r_spec_rs_tos - 'd1;
	  end
	else if(t_is_ret)
	  begin
	     n_spec_rs_tos = r_spec_rs_tos + 'd1;
	  end
     end

   always_ff@(posedge clk)
     begin
	if(t_is_call)
	  begin
	     r_spec_return_stack[r_spec_rs_tos] <= r_cache_pc + 'd8;
	  end
	else if(n_restart_ack)
	  begin
	     r_spec_return_stack <= r_arch_return_stack;
	  end
     end // always_ff@ (posedge clk)
   
   always_ff@(posedge clk)
     begin
	if(retire_reg_valid && retire_valid && retired_call)
	  begin
	     r_arch_return_stack[r_arch_rs_tos] <= retire_reg_data;
	  end
     end
   always_comb
     begin
	n_arch_rs_tos = r_arch_rs_tos;
	if(retire_valid && retired_call)
	  begin
	     n_arch_rs_tos = r_arch_rs_tos - 'd1;
	  end
	else if(retire_valid && retired_ret)
	  begin
	     n_arch_rs_tos = r_arch_rs_tos + 'd1;
	  end
     end

   always_comb
     begin
	n_spec_gbl_hist = r_spec_gbl_hist;
	if(n_restart_ack)
	  begin
	     n_spec_gbl_hist = r_arch_gbl_hist;
	  end
	else if(t_update_spec_hist)
	  begin
	     n_spec_gbl_hist = {r_spec_gbl_hist[`GBL_HIST_LEN-2:0], t_take_br};
	  end
     end

   always_comb
     begin
	n_arch_gbl_hist = r_arch_gbl_hist;
	if(branch_pc_valid)
	  begin
	     n_arch_gbl_hist = {r_arch_gbl_hist[`GBL_HIST_LEN-2:0], took_branch};
	  end
     end
   
   
   always_ff@(posedge clk)
     begin
	if(reset)
	  begin
	     r_state <= INITIALIZE;
	     r_init_pht_idx <= 'd0;
	     r_pc <= 'd0;
	     r_miss_pc <= 'd0;
	     r_cache_pc <= 'd0;
	     r_restart_ack <= 1'b0;
	     r_cache_idx <= 'd0;
	     r_cache_tag <= 'd0;
	     r_req <= 1'b0;
	     r_mem_req_valid <= 1'b0;
	     r_mem_req_addr <= 'd0;
	     r_fq_head_ptr <= 'd0;
	     r_fq_next_head_ptr <= 'd1;
	     r_fq_next_tail_ptr <= 'd1;
	     r_fq_next3_tail_ptr <= 'd1;
	     r_fq_next4_tail_ptr <= 'd1;
	     r_fq_tail_ptr <= 'd0;
	     r_restart_req <= 1'b0;
	     r_flush_req <= 1'b0;
	     r_flush_complete <= 1'b0;
	     r_delay_slot <= 1'b0;
	     r_spec_rs_tos <= RETURN_STACK_ENTRIES-1;
	     r_arch_rs_tos <= RETURN_STACK_ENTRIES-1;
	     r_arch_gbl_hist <= 'd0;
	     r_spec_gbl_hist <= 'd0;
	     r_cache_hits <= 'd0;
	     r_cache_accesses <= 'd0;
	     r_resteer_bubble <= 1'b0;
	  end
	else
	  begin
	     r_state <= n_state;
	     r_init_pht_idx <= n_init_pht_idx;
	     r_pc <= n_pc;
	     r_miss_pc <= n_miss_pc;
	     r_cache_pc <= n_cache_pc;
	     r_restart_ack <= n_restart_ack;
	     r_cache_idx <= t_cache_idx;
	     r_cache_tag <= t_cache_tag;	     
	     r_req <= n_req;
	     r_mem_req_valid <= n_mem_req_valid;
	     r_mem_req_addr <= n_mem_req_addr;
	     r_fq_head_ptr <= t_clear_fq ? 'd0 : n_fq_head_ptr;
	     r_fq_next_head_ptr <= t_clear_fq ? 'd1 : n_fq_next_head_ptr;
	     r_fq_next_tail_ptr <= t_clear_fq ? 'd1 : n_fq_next_tail_ptr;
	     r_fq_next3_tail_ptr <= t_clear_fq ? 'd2 : n_fq_next3_tail_ptr;
	     r_fq_next4_tail_ptr <= t_clear_fq ? 'd3 : n_fq_next4_tail_ptr;
	     r_fq_tail_ptr <= t_clear_fq ? 'd0 : n_fq_tail_ptr;
	     r_restart_req <= n_restart_req;
	     r_flush_req <= n_flush_req;
	     r_flush_complete <= n_flush_complete;
	     r_delay_slot <= n_delay_slot;
	     r_spec_rs_tos <= n_spec_rs_tos;
	     r_arch_rs_tos <= n_arch_rs_tos;
	     r_arch_gbl_hist <= n_arch_gbl_hist;
	     r_spec_gbl_hist <= n_spec_gbl_hist;
	     r_cache_hits <= n_cache_hits;
	     r_cache_accesses <= n_cache_accesses;
	     r_resteer_bubble <= n_resteer_bubble;	     
	  end
     end
   
endmodule
