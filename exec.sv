`include "uop.vh"
`include "rob.vh"

`ifdef VERILATOR
import "DPI-C" function void report_exec(input int int_valid, 
					 input int int_blocked,
					 input int int2_valid, 
					 input int int2_blocked, 
					 input int mem_valid, 
					 input int mem_blocked,
					 input int fp_valid, 
					 input int fp_blocked,
					 input int iq_full,
					 input int mq_full,
					 input int fq_full,
					 input int blocked_by_store,
					 input int int_ready,
					 input int int_ready2
					 );
`endif

module exec(clk, 
	    reset,
	    retire,
	    retire_two,
`ifdef VERILATOR
	    clear_cnt,
`endif
	    divide_ready,
	    ds_done,
	    mem_dq_clr,
	    restart_complete,
	    uq_wait,
	    mq_wait,
	    uq_full,
	    uq_next_full,
	    uq_uop,
	    uq_uop_two,
	    uq_push,
	    uq_push_two,
	    complete_bundle_1,
	    complete_valid_1,
	    complete_bundle_2,
	    complete_valid_2,
	    exception_wr_cpr0_val,
	    exception_wr_cpr0_ptr,
	    exception_wr_cpr0_data,
	    mem_req, 
	    mem_req_valid, 
	    mem_req_ack,
	    core_store_data_valid,
	    core_store_data,
	    core_store_data_ack,
	    //tell rob store data has been read
	    core_store_data_ptr,
	    core_store_data_ptr_valid,
	    mem_rsp_dst_ptr,
	    mem_rsp_dst_valid,
	    mem_rsp_load_data,
	    branch_valid,
	    branch_fault);
   input logic clk;
   input logic reset;
   input logic retire;
   input logic retire_two;
   
`ifdef VERILATOR
   input logic [31:0] clear_cnt;
`endif
   output logic       divide_ready;
   input logic ds_done;
   input logic mem_dq_clr;
   input logic restart_complete;
   
   localparam N_ROB_ENTRIES = (1<<`LG_ROB_ENTRIES);   
   output logic [N_ROB_ENTRIES-1:0]  uq_wait;   
   output logic [N_ROB_ENTRIES-1:0]  mq_wait;
   
   output logic 			     uq_full;
   output logic 			     uq_next_full;
   
   input 				     uop_t uq_uop;
   input 				     uop_t uq_uop_two;
   
   input logic 				     uq_push;
   input logic 				     uq_push_two;
   
   output 	complete_t complete_bundle_1;
   output logic complete_valid_1;
   output 	complete_t complete_bundle_2;
   output logic complete_valid_2;   


   input logic 	exception_wr_cpr0_val;
   input logic [4:0] exception_wr_cpr0_ptr;
   input logic [`M_WIDTH-1:0] exception_wr_cpr0_data;
   
   output 	mem_req_t mem_req;
   output 	logic mem_req_valid;
   input logic 	      mem_req_ack;

   output logic 	      core_store_data_valid;
   output 		      mem_data_t core_store_data;
   input logic 		      core_store_data_ack;
   
   output logic [`LG_ROB_ENTRIES-1:0] core_store_data_ptr;
   output logic 		      core_store_data_ptr_valid;
   
   
   input logic [`LG_PRF_ENTRIES-1:0] mem_rsp_dst_ptr;
   input logic 			     mem_rsp_dst_valid;
   input logic [31:0] 		     mem_rsp_load_data;

   input logic 			     branch_valid;
   input logic 			     branch_fault;
   
   
   localparam N_INT_SCHED_ENTRIES = 1<<`LG_INT_SCHED_ENTRIES;
   
   localparam N_MQ_ENTRIES = (1<<`LG_MQ_ENTRIES);
   localparam N_INT_PRF_ENTRIES = (1<<`LG_PRF_ENTRIES);
   
   localparam N_UQ_ENTRIES = (1<<`LG_UQ_ENTRIES);
   localparam N_MEM_UQ_ENTRIES = (1<<`LG_MEM_UQ_ENTRIES);
   localparam N_MEM_DQ_ENTRIES = (1<<`LG_MEM_DQ_ENTRIES);
   
   logic [N_INT_PRF_ENTRIES-1:0]  r_prf_inflight, n_prf_inflight;
   
   logic 			  t_wr_int_prf, t_wr_int_prf2;
   
   logic 	t_take_br, t_take_br2;
   logic 	t_mispred_br, t_mispred_br2;
   logic 	t_alu_valid, t_alu_valid2;
   logic 	t_got_break;
   
   mem_req_t r_mem_q[N_MQ_ENTRIES-1:0];
   logic [`LG_MQ_ENTRIES:0] r_mq_head_ptr, n_mq_head_ptr;
   logic [`LG_MQ_ENTRIES:0] r_mq_tail_ptr, n_mq_tail_ptr;
   logic [`LG_MQ_ENTRIES:0] r_mq_next_tail_ptr, n_mq_next_tail_ptr;
   mem_req_t t_mem_tail, t_mem_head;
   logic 		    mem_q_full,mem_q_next_full, mem_q_empty;


   mem_data_t r_mdq[N_MQ_ENTRIES-1:0];
   mem_data_t t_mdq_tail, t_mdq_head;
   
   logic [`LG_MQ_ENTRIES:0] r_mdq_head_ptr, n_mdq_head_ptr;
   logic [`LG_MQ_ENTRIES:0] r_mdq_tail_ptr, n_mdq_tail_ptr;
   logic [`LG_MQ_ENTRIES:0] r_mdq_next_tail_ptr, n_mdq_next_tail_ptr;
   logic 		    mem_mdq_full,mem_mdq_next_full, mem_mdq_empty;
   
   wire [`LG_PRF_ENTRIES-1:0] w_mul_prf_ptr;
   logic [`LG_PRF_ENTRIES-1:0] r_mul_prf_ptr;
   logic 		       r_mul_complete;
   wire [`LG_PRF_ENTRIES-1:0] w_div_prf_ptr;
   logic [`LG_PRF_ENTRIES-1:0] r_div_prf_ptr;
   logic 		       r_div_complete;

   logic 	t_pop_uq,t_pop_mem_uq,t_pop_mem_dq,t_pop_uq2;
   
   logic 	r_mem_ready, r_dq_ready;
   
   
   localparam E_BITS = `M_WIDTH-16;
   localparam HI_EBITS = `M_WIDTH-32;
   
   logic [`M_WIDTH-1:0] t_result, t_result2;

   
   
   logic [`M_WIDTH-1:0] t_pc, t_pc_2;
   logic 	t_srcs_rdy;

   
   wire [31:0] w_srcA, w_srcB;
   logic [31:0] t_srcA_2, t_srcB_2;
   wire [31:0] 	w_srcA_2, w_srcB_2;
   
   wire [31:0] w_mem_srcA, w_mem_srcB;
   
   logic [31:0] r_mem_result, r_int_result, r_int_result2;
   
   logic 	r_fwd_int_srcA, r_fwd_int_srcB, r_fwd_int2_srcA, r_fwd_int2_srcB;
   logic 	r_fwd_int_srcA2, r_fwd_int_srcB2, r_fwd_int2_srcA2, r_fwd_int2_srcB2;
   
   logic 	r_fwd_mem_srcA, r_fwd_mem_srcB, r_fwd_mem_srcA2, r_fwd_mem_srcB2;

   logic t_fwd_int_mem_srcA,t_fwd_int_mem_srcB,t_fwd_int2_mem_srcA, t_fwd_int2_mem_srcB, 
	 t_fwd_mem_mem_srcA,t_fwd_mem_mem_srcB;
   logic r_fwd_int_mem_srcA,r_fwd_int_mem_srcB,r_fwd_int2_mem_srcA,r_fwd_int2_mem_srcB,
	 r_fwd_mem_mem_srcA,r_fwd_mem_mem_srcB;
   
      
   logic [31:0] t_srcA, t_srcB;
   logic [31:0] t_mem_srcA, t_mem_srcB;
   
   
   
   logic 	t_unimp_op;
   logic 	t_fault;
   
   logic 	t_signed_shift;
   logic 	t_left_shift;
   
   logic [4:0] 	t_shift_amt;
   
   wire [31:0] w_shifter_out;

   logic 	t_start_mul;
   logic 	t_mul_complete;
   logic [63:0] t_mul_result;
   
   logic [`LG_ROB_ENTRIES-1:0] t_rob_ptr_out;

   
   
   logic [`MAX_LAT:0] r_wb_bitvec, n_wb_bitvec;

   /* divider */
   logic 	t_div_ready, t_signed_div, t_is_rem, t_start_div32;
   logic [`LG_ROB_ENTRIES-1:0] t_div_rob_ptr;
   logic [63:0] 	       t_div_result;
   logic 			    t_div_complete;

   logic [N_ROB_ENTRIES-1:0] 	    r_uq_wait, r_mq_wait;
   /* non mem uop queue */
   uop_t r_uq[N_UQ_ENTRIES];
   uop_t uq, uq2, int_uop, int_uop2;
   logic 			    r_start_int2;
   logic 			    r_start_int;
   
   
   
   logic 			    t_uq_read, t_uq_empty, t_uq_full, t_uq_next_full, t_uq_next_empty;
   logic [`LG_UQ_ENTRIES:0] 	    r_uq_head_ptr, n_uq_head_ptr;
   logic [`LG_UQ_ENTRIES:0] 	    r_uq_tail_ptr, n_uq_tail_ptr;
   logic [`LG_UQ_ENTRIES:0] 	    r_uq_next_head_ptr, n_uq_next_head_ptr;
   logic [`LG_UQ_ENTRIES:0] 	    r_uq_next_tail_ptr, n_uq_next_tail_ptr;

   /* mem uop queue */
   uop_t r_mem_uq[N_MEM_UQ_ENTRIES];
   uop_t t_mem_uq, mem_uq;
   logic 	      t_mem_uq_read, t_mem_uq_empty, t_mem_uq_full,
		      t_mem_uq_next_full;
   
   logic [`LG_MEM_UQ_ENTRIES:0]  r_mem_uq_head_ptr, n_mem_uq_head_ptr;
   logic [`LG_MEM_UQ_ENTRIES:0]  r_mem_uq_tail_ptr, n_mem_uq_tail_ptr;
   logic [`LG_MEM_UQ_ENTRIES:0] r_mem_uq_next_head_ptr, n_mem_uq_next_head_ptr;
   logic [`LG_MEM_UQ_ENTRIES:0] r_mem_uq_next_tail_ptr, n_mem_uq_next_tail_ptr;

   /* mem data queue */
   dq_t r_mem_dq[N_MEM_DQ_ENTRIES];
   dq_t t_dq0, t_dq1, t_mem_dq, mem_dq;
   mem_data_t t_core_store_data;
   
   logic 	      t_mem_dq_read, t_mem_dq_empty, t_mem_dq_full,
		      t_mem_dq_next_full;
   
   logic [`LG_MEM_DQ_ENTRIES:0]  r_mem_dq_head_ptr, n_mem_dq_head_ptr;
   logic [`LG_MEM_DQ_ENTRIES:0]  r_mem_dq_tail_ptr, n_mem_dq_tail_ptr;
   logic [`LG_MEM_DQ_ENTRIES:0] r_mem_dq_next_head_ptr, n_mem_dq_next_head_ptr;
   logic [`LG_MEM_DQ_ENTRIES:0] r_mem_dq_next_tail_ptr, n_mem_dq_next_tail_ptr;


   
   logic             t_push_two_mem,  t_push_two_int;
   logic             t_push_one_mem,  t_push_one_int;
   logic 	     t_push_two_dq, t_push_one_dq;
   
   logic 			t_flash_clear;
   always_comb
     begin
	t_flash_clear = ds_done;
     end

   always_comb
     begin
	uq_full = t_uq_full || t_mem_uq_full || t_mem_dq_full;
	uq_next_full = t_uq_next_full || t_mem_uq_next_full || t_mem_dq_next_full;
     end
   
   always_ff@(posedge clk)
     begin
	if(reset || t_flash_clear)
	  begin
	     r_uq_head_ptr <= 'd0;
	     r_uq_tail_ptr <= 'd0;
	     r_uq_next_head_ptr <= 'd1;
	     r_uq_next_tail_ptr <= 'd1;	     
	  end
	else
	  begin
	     r_uq_head_ptr <=  n_uq_head_ptr;
	     r_uq_tail_ptr <=  n_uq_tail_ptr;
	     r_uq_next_head_ptr <= n_uq_next_head_ptr;
	     r_uq_next_tail_ptr <= n_uq_next_tail_ptr;	     
	  end
     end // always_ff@ (posedge clk)

   always_ff@(posedge clk)
     begin
	if(reset  || t_flash_clear)
	  begin
	     r_mem_uq_head_ptr <= 'd0;
	     r_mem_uq_tail_ptr <= 'd0;
	     r_mem_uq_next_head_ptr <= 'd1;
	     r_mem_uq_next_tail_ptr <= 'd1;
	  end
	else
	  begin
	     r_mem_uq_head_ptr <= n_mem_uq_head_ptr;
	     r_mem_uq_tail_ptr <= n_mem_uq_tail_ptr;
	     r_mem_uq_next_head_ptr <= n_mem_uq_next_head_ptr;
	     r_mem_uq_next_tail_ptr <= n_mem_uq_next_tail_ptr;
	  end
     end // always_ff@ (posedge clk// )
   
   always_ff@(posedge clk)
     begin
	if(reset  || mem_dq_clr)
	  begin
	     r_mem_dq_head_ptr <= 'd0;
	     r_mem_dq_tail_ptr <= 'd0;
	     r_mem_dq_next_head_ptr <= 'd1;
	     r_mem_dq_next_tail_ptr <= 'd1;
	  end
	else
	  begin
	     r_mem_dq_head_ptr <= n_mem_dq_head_ptr;
	     r_mem_dq_tail_ptr <= n_mem_dq_tail_ptr;
	     r_mem_dq_next_head_ptr <= n_mem_dq_next_head_ptr;
	     r_mem_dq_next_tail_ptr <= n_mem_dq_next_tail_ptr;
	  end
     end // always_ff@ (posedge clk// )
   
   

   always_comb
     begin
	n_mem_uq_head_ptr = r_mem_uq_head_ptr;
	n_mem_uq_tail_ptr = r_mem_uq_tail_ptr;
	n_mem_uq_next_head_ptr = r_mem_uq_next_head_ptr;
	n_mem_uq_next_tail_ptr = r_mem_uq_next_tail_ptr;
	
	n_mem_dq_head_ptr = r_mem_dq_head_ptr;
	n_mem_dq_tail_ptr = r_mem_dq_tail_ptr;
	n_mem_dq_next_head_ptr = r_mem_dq_next_head_ptr;
	n_mem_dq_next_tail_ptr = r_mem_dq_next_tail_ptr;


	
	t_mem_uq_empty = (r_mem_uq_head_ptr == r_mem_uq_tail_ptr);
	t_mem_uq_full = (r_mem_uq_head_ptr != r_mem_uq_tail_ptr) && (r_mem_uq_head_ptr[`LG_MEM_UQ_ENTRIES-1:0] == r_mem_uq_tail_ptr[`LG_MEM_UQ_ENTRIES-1:0]);

	t_mem_uq_next_full = (r_mem_uq_head_ptr != r_mem_uq_next_tail_ptr) && 
			     (r_mem_uq_head_ptr[`LG_MEM_UQ_ENTRIES-1:0] == r_mem_uq_next_tail_ptr[`LG_MEM_UQ_ENTRIES-1:0]);

	t_mem_dq_empty = (r_mem_dq_head_ptr == r_mem_dq_tail_ptr);
	t_mem_dq_full = (r_mem_dq_head_ptr != r_mem_dq_tail_ptr) && (r_mem_dq_head_ptr[`LG_MEM_DQ_ENTRIES-1:0] == r_mem_dq_tail_ptr[`LG_MEM_DQ_ENTRIES-1:0]);

	t_mem_dq_next_full = (r_mem_dq_head_ptr != r_mem_dq_next_tail_ptr) && 
			     (r_mem_dq_head_ptr[`LG_MEM_DQ_ENTRIES-1:0] == r_mem_dq_next_tail_ptr[`LG_MEM_DQ_ENTRIES-1:0]);
		
	t_mem_uq = r_mem_uq[r_mem_uq_head_ptr[`LG_MEM_UQ_ENTRIES-1:0]];

	t_mem_dq = r_mem_dq[r_mem_dq_head_ptr[`LG_MEM_DQ_ENTRIES-1:0]];

	t_push_two_mem = uq_push && uq_push_two && uq_uop.is_mem && uq_uop_two.is_mem;
	t_push_one_mem = ((uq_push && uq_uop.is_mem) || (uq_push_two && uq_uop_two.is_mem)) && !t_push_two_mem;

	t_push_two_dq = uq_push && uq_push_two && 
			uq_uop.is_mem && uq_uop.srcB_valid && 
			uq_uop_two.is_mem && uq_uop_two.srcB_valid;
	
	t_push_one_dq = (uq_push_two && uq_uop_two.is_mem && uq_uop_two.srcB_valid) || 
			(uq_push && uq_uop.is_mem && uq_uop.srcB_valid);
	
	
	if(t_push_two_dq)
	  begin
	     n_mem_dq_tail_ptr = r_mem_dq_tail_ptr + 'd2;
	     n_mem_dq_next_tail_ptr = r_mem_dq_next_tail_ptr + 'd2;	     
	  end
	else if(t_push_one_dq)
	  begin
	     n_mem_dq_tail_ptr = r_mem_dq_tail_ptr + 'd1;
	     n_mem_dq_next_tail_ptr = r_mem_dq_next_tail_ptr + 'd1;
	  end
	
	/* these need work */
	if(t_push_two_mem)
	  begin
	     n_mem_uq_tail_ptr = r_mem_uq_tail_ptr + 'd2;
	     n_mem_uq_next_tail_ptr = r_mem_uq_next_tail_ptr + 'd2;

	  end
	else if(uq_push_two && uq_uop_two.is_mem || uq_push && uq_uop.is_mem)
	  begin
	     n_mem_uq_tail_ptr = r_mem_uq_tail_ptr + 'd1;
	     n_mem_uq_next_tail_ptr = r_mem_uq_next_tail_ptr + 'd1;
	  end
	
	if(t_pop_mem_uq)
	  begin
	     n_mem_uq_head_ptr = r_mem_uq_head_ptr + 'd1;
	  end
	if(t_pop_mem_dq)
	  begin
	     n_mem_dq_head_ptr = r_mem_dq_head_ptr + 'd1;
	  end
     end // always_comb

   always_ff@(posedge clk)
     begin
	mem_uq <= t_mem_uq;
	mem_dq <= t_mem_dq;
     end

   always_ff@(posedge clk)
     begin
	if(reset)
	  begin
	     r_mq_wait <= 'd0;
	     r_uq_wait <= 'd0;
	  end
	else if(restart_complete)
	  begin
	     r_mq_wait <= 'd0;
	     r_uq_wait <= 'd0;
	  end
	else
	  begin
	     //mem port
	     if(t_push_two_mem)
	       begin
		  r_mq_wait[uq_uop_two.rob_ptr] <= 1'b1;
		  r_mq_wait[uq_uop.rob_ptr] <= 1'b1;
	       end
	     else if(t_push_one_mem)
	       begin
		  r_mq_wait[uq_uop.is_mem ? uq_uop.rob_ptr : uq_uop_two.rob_ptr] <= 1'b1; 
	       end
	     if(t_pop_mem_uq)
	       begin
		  r_mq_wait[t_mem_uq.rob_ptr] <= 1'b0;		  
	       end
	     
	     //int port
	     if(t_push_two_int)
	       begin
		  r_uq_wait[uq_uop.rob_ptr] <= 1'b1;
		  r_uq_wait[uq_uop_two.rob_ptr] <= 1'b1;
	       end
	     else if(t_push_one_int)
	       begin
		  r_uq_wait[uq_uop.is_int ? uq_uop.rob_ptr : uq_uop_two.rob_ptr] <= 1'b1; 
	       end
	     
	     if(r_start_int)
	       begin
		  r_uq_wait[int_uop.rob_ptr] <= 1'b0;
	       end

	  end // else: !if(reset)
     end // always_ff@ (posedge clk)

   
   always_ff@(posedge clk)
     begin
	if(t_push_two_mem)
	  begin
	     //$display("cycle %d : pushing mem ops for rob slots %d & %d", r_cycle, uq_uop_two.rob_ptr, uq_uop.rob_ptr);
	     r_mem_uq[r_mem_uq_next_tail_ptr[`LG_MEM_UQ_ENTRIES-1:0]] <= uq_uop_two;
	     r_mem_uq[r_mem_uq_tail_ptr[`LG_MEM_UQ_ENTRIES-1:0]] <= uq_uop;
	  end
	else if(t_push_one_mem)
	  begin
	     //$display("cycle %d : pushing mem ops for rob slots %d", r_cycle, uq_uop.rob_ptr);
	     r_mem_uq[r_mem_uq_tail_ptr[`LG_MEM_UQ_ENTRIES-1:0]] <= uq_uop.is_mem ? uq_uop : uq_uop_two;
	  end	
     end // always_ff@ (posedge clk)


   always_comb     
     begin
	t_dq0.rob_ptr = uq_uop.rob_ptr;	
	t_dq0.src_ptr = uq_uop.srcB;
	t_dq1.rob_ptr = uq_uop_two.rob_ptr;
	t_dq1.src_ptr = uq_uop_two.srcB;
     end

       

   
   always_ff@(posedge clk)
     begin
	if(t_push_two_dq)
	  begin
	     r_mem_dq[r_mem_dq_next_tail_ptr[`LG_MEM_DQ_ENTRIES-1:0]] <= t_dq1;
	     r_mem_dq[r_mem_dq_tail_ptr[`LG_MEM_DQ_ENTRIES-1:0]] <= t_dq0;
	  end
	else if(t_push_one_dq)
	  begin
	     r_mem_dq[r_mem_dq_tail_ptr[`LG_MEM_DQ_ENTRIES-1:0]] <= uq_uop.is_mem && uq_uop.srcB_valid ? t_dq0 : t_dq1;
	  end	
     end
   
   

   
   always_comb
     begin
	n_uq_head_ptr = r_uq_head_ptr;
	n_uq_tail_ptr = r_uq_tail_ptr;
	n_uq_next_head_ptr = r_uq_next_head_ptr;
	n_uq_next_tail_ptr = r_uq_next_tail_ptr;
	
	
	t_uq_empty = (r_uq_head_ptr == r_uq_tail_ptr);
	t_uq_next_empty = (r_uq_next_head_ptr == r_uq_tail_ptr);
	
	t_uq_full = (r_uq_head_ptr != r_uq_tail_ptr) && 
		    (r_uq_head_ptr[`LG_UQ_ENTRIES-1:0] == r_uq_tail_ptr[`LG_UQ_ENTRIES-1:0]);

	t_uq_next_full = (r_uq_head_ptr != r_uq_next_tail_ptr) && 
			 (r_uq_head_ptr[`LG_UQ_ENTRIES-1:0] == r_uq_next_tail_ptr[`LG_UQ_ENTRIES-1:0]);

	t_push_two_int = uq_push && uq_push_two && uq_uop.is_int && uq_uop_two.is_int;
	t_push_one_int = ((uq_push && uq_uop.is_int) || (uq_push_two && uq_uop_two.is_int)) && !t_push_two_int;
	
	uq = r_uq[r_uq_head_ptr[`LG_UQ_ENTRIES-1:0]];
	uq2 = r_uq[r_uq_next_head_ptr[`LG_UQ_ENTRIES-1:0]];

	
	if(t_push_two_int)
	  begin	     
	     n_uq_tail_ptr = r_uq_tail_ptr + 'd2;
	     n_uq_next_tail_ptr = r_uq_next_tail_ptr + 'd2;
	  end
	else if(uq_push_two && uq_uop_two.is_int || uq_push && uq_uop.is_int)
	  begin	     
	     n_uq_tail_ptr = r_uq_tail_ptr + 'd1;
	     n_uq_next_tail_ptr = r_uq_next_tail_ptr + 'd1;
	  end

	if(t_pop_uq2)
	  begin
	     n_uq_next_head_ptr = r_uq_next_head_ptr + 'd2;
	     n_uq_head_ptr = r_uq_head_ptr + 'd2;
	  end
	else if(t_pop_uq)
	  begin
	     n_uq_head_ptr = r_uq_head_ptr + 'd1;
	     n_uq_next_head_ptr = r_uq_next_head_ptr + 'd1;	     
	  end
     end // always_comb

   always_ff@(posedge clk)
     begin
	if(t_push_two_int)
	  begin
	     r_uq[r_uq_tail_ptr[`LG_UQ_ENTRIES-1:0]] <= uq_uop;
	     r_uq[r_uq_next_tail_ptr[`LG_UQ_ENTRIES-1:0]] <= uq_uop_two;	     
	  end
	else if(t_push_one_int)
	  begin
	     r_uq[r_uq_tail_ptr[`LG_UQ_ENTRIES-1:0]] <= uq_uop.is_int ? uq_uop : uq_uop_two;
	  end
	
     end // always_ff@ (posedge clk)
   
   logic [63:0]        r_cycle, r_retired_insns, r_branches, r_branch_faults;
   always_ff@(posedge clk)
     begin
	r_cycle <= reset ? 'd0 : r_cycle + 'd1;
	r_branches <= reset ? 'd0 : branch_valid ? (r_branches + 'd1) : r_branches;
	r_branch_faults <= reset ? 'd0 : branch_fault ? (r_branch_faults + 'd1) : r_branch_faults;
     end

   
   always_ff@(posedge clk)
     begin
	if(reset)
	  begin
	     r_retired_insns <= 'd0;
	  end
	else if(retire_two)
	  begin
	     r_retired_insns <= r_retired_insns + 'd2;
	  end
	else if(retire) 
	  begin
	     r_retired_insns <= r_retired_insns + 'd1;
	  end
     end // always_ff@ (posedge clk)


   always_ff@(posedge clk)
     begin
	if(reset)
	  begin
	     r_wb_bitvec <= 'd0;
	  end
	else
	  begin
	     r_wb_bitvec <= n_wb_bitvec;
	  end
     end // always_ff@ (posedge clk)

   always_comb
     begin
	for(integer i = (`MAX_LAT-1); i > -1; i = i-1)
	  begin
	     n_wb_bitvec[i] = r_wb_bitvec[i+1];	     
	  end
	n_wb_bitvec[`DIV32_LAT] = t_start_div32&r_start_int;
	
	if(t_start_mul&r_start_int)
	  begin
	     n_wb_bitvec[`MUL_LAT] = 1'b1;
	  end
     end // always_comb

   
   
   always_comb
     begin
	t_srcA = r_fwd_int_srcA ? r_int_result :
		 r_fwd_int2_srcA ? r_int_result2 :
		 r_fwd_mem_srcA ? r_mem_result :
		 w_srcA;
	
	t_srcB = r_fwd_int_srcB ? r_int_result :
		 r_fwd_int2_srcB ? r_int_result2 :		 
		 r_fwd_mem_srcB ? r_mem_result :
		 w_srcB;

	t_srcA_2 = r_fwd_int_srcA2 ? r_int_result :
		   r_fwd_int2_srcA2 ? r_int_result2 :
		   r_fwd_mem_srcA2 ? r_mem_result :
		   w_srcA_2;

	t_srcB_2 = r_fwd_int_srcB2 ? r_int_result :
		   r_fwd_int2_srcB2 ? r_int_result2 :
		   r_fwd_mem_srcB2 ? r_mem_result :
		   w_srcB_2;
	
	
	t_mem_srcA = r_fwd_int_mem_srcA ? r_int_result :
		     r_fwd_mem_mem_srcA ? r_mem_result :
		     r_fwd_int2_mem_srcA ? r_int_result2 :
		     w_mem_srcA;

	t_mem_srcB = r_fwd_int_mem_srcB ? r_int_result :
		     r_fwd_mem_mem_srcB ? r_mem_result :
		     r_fwd_int2_mem_srcB ? r_int_result2 :
		     w_mem_srcB;	
     end // always_comb




   //does this scheduler entry contain a valid uop?
   logic [N_INT_SCHED_ENTRIES-1:0] r_alu_sched_valid, r_alu_sched_valid2;
   logic [`LG_INT_SCHED_ENTRIES:0] t_alu_sched_alloc_ptr, t_alu_sched_alloc_ptr2;
   logic 			   t_alu_sched_full, t_alu_sched_full2;
   logic [N_INT_SCHED_ENTRIES-1:0] t_alu_alloc_entry, t_alu_select_entry, t_alu_alloc_entry2, t_alu_select_entry2;
   
   uop_t r_alu_sched_uops[N_INT_SCHED_ENTRIES-1:0], t_picked_uop;
   uop_t r_alu_sched_uops2[N_INT_SCHED_ENTRIES-1:0], t_picked_uop2;
   logic [N_INT_SCHED_ENTRIES-1:0] t_alu_entry_rdy, t_alu_entry_rdy2;
   logic [`LG_INT_SCHED_ENTRIES:0] t_alu_sched_select_ptr, t_alu_sched_select_ptr2;
   
	
   logic [N_INT_SCHED_ENTRIES-1:0] r_alu_srcA_rdy, r_alu_srcB_rdy, r_alu_srcA_rdy2, r_alu_srcB_rdy2;
   logic [N_INT_SCHED_ENTRIES-1:0] t_alu_srcA_match, t_alu_srcB_match, t_alu_srcA_match2, t_alu_srcB_match2;
   
   logic 			   t_alu_alloc_srcA_match, t_alu_alloc_srcB_match, t_alu_alloc_srcA_match2, t_alu_alloc_srcB_match2;
   
   
   wire [N_INT_SCHED_ENTRIES-1:0] w_alu_sched_oldest_ready, w_alu_sched_oldest_ready2;

   
   find_first_set#(`LG_INT_SCHED_ENTRIES) ffs_int_sched_alloc( .in(~r_alu_sched_valid),
							      .y(t_alu_sched_alloc_ptr));
   
   find_first_set#(`LG_INT_SCHED_ENTRIES) ffs_int_sched_select( .in(w_alu_sched_oldest_ready),
								.y(t_alu_sched_select_ptr));

   find_first_set#(`LG_INT_SCHED_ENTRIES) ffs_int_sched_alloc2( .in(~r_alu_sched_valid2),
								.y(t_alu_sched_alloc_ptr2));
   
   find_first_set#(`LG_INT_SCHED_ENTRIES) ffs_int_sched_select2( .in(w_alu_sched_oldest_ready2),
								 .y(t_alu_sched_select_ptr2));
     
   always_comb
     begin
	t_alu_alloc_entry = 'd0;
	t_alu_select_entry = 'd0;
	if(t_pop_uq)
	  begin
	     t_alu_alloc_entry[t_alu_sched_alloc_ptr[`LG_INT_SCHED_ENTRIES-1:0]] = 1'b1;
	  end
	if(t_alu_entry_rdy != 'd0)
	  begin
	     t_alu_select_entry[t_alu_sched_select_ptr[`LG_INT_SCHED_ENTRIES-1:0]] = 1'b1;
	  end
     end // always_comb

   always_comb
     begin
	t_alu_alloc_entry2 = 'd0;
	t_alu_select_entry2 = 'd0;
	if(t_pop_uq2)
	  begin
	     t_alu_alloc_entry2[t_alu_sched_alloc_ptr2[`LG_INT_SCHED_ENTRIES-1:0]] = 1'b1;
	  end
	if(t_alu_entry_rdy2 != 'd0)
	  begin
	     t_alu_select_entry2[t_alu_sched_select_ptr2[`LG_INT_SCHED_ENTRIES-1:0]] = 1'b1;
	  end
     end // always_comb


   always_comb
     begin
	t_picked_uop = r_alu_sched_uops[t_alu_sched_select_ptr[`LG_INT_SCHED_ENTRIES-1:0]];
     end

   always_comb
     begin
	t_picked_uop2 = r_alu_sched_uops2[t_alu_sched_select_ptr2[`LG_INT_SCHED_ENTRIES-1:0]];
     end
   
   
   always_ff@(posedge clk)
     begin
	int_uop <= t_picked_uop;
     end
   
   always_ff@(posedge clk)
     begin
	r_start_int <= reset ? 1'b0 : ((t_alu_entry_rdy != 'd0) & !ds_done);
     end // always_comb
   
   always_ff@(posedge clk)
     begin
	int_uop2 <= t_picked_uop2;
     end
   
   always_ff@(posedge clk)
     begin
	r_start_int2 <= reset ? 1'b0 : ((t_alu_entry_rdy2 != 'd0) & !ds_done);
     end

   // always@(negedge clk)
   //   begin
   // 	if(r_start_int)
   // 	  $display("cycle %d : starting %x on port 0, %x, %x -> %x", 
   // 		   r_cycle, int_uop.pc, t_srcA, t_srcB, t_result);
   // 	if(r_start_int2)
   // 	  begin
   // 	     $display("cycle %d : starting %x on port 1, %x, %x -> %x", 
   // 		      r_cycle, int_uop2.pc, t_srcA_2, t_srcB_2, t_result2);
   // 	     //if(int_uop2.pc == 'h80011b5c)
   // 	       //begin
   // 	     //$display("Src ptr A %d", int_uop2.srcA);
   // 	     //$stop();
   // 	     //end
   // 	  end
   //   end
   
   always_comb
     begin
	//allocation forwarding
	t_alu_alloc_srcA_match = uq.srcA_valid && (
						   (mem_rsp_dst_valid & (mem_rsp_dst_ptr == uq.srcA)) ||
						   (r_start_int2 && t_wr_int_prf2 && (int_uop2.dst == uq.srcA)) ||
						   (r_start_int && t_wr_int_prf & (int_uop.dst == uq.srcA))
						   );
	t_alu_alloc_srcB_match = uq.srcB_valid && (
						   (mem_rsp_dst_valid & (mem_rsp_dst_ptr == uq.srcB)) ||
						   (r_start_int2 && t_wr_int_prf2 && (int_uop2.dst == uq.srcB)) ||						   
						   (r_start_int && t_wr_int_prf & (int_uop.dst == uq.srcB))
						   );
	
	t_alu_alloc_srcA_match2 = uq2.srcA_valid && (
						     (mem_rsp_dst_valid & (mem_rsp_dst_ptr == uq2.srcA)) ||
						     (r_start_int2 && t_wr_int_prf2 && (int_uop2.dst == uq2.srcA)) ||
						     (r_start_int && t_wr_int_prf & (int_uop.dst == uq2.srcA))
						     );
	t_alu_alloc_srcB_match2 = uq2.srcB_valid && (
						     (mem_rsp_dst_valid & (mem_rsp_dst_ptr == uq2.srcB)) ||
						     (r_start_int2 && t_wr_int_prf2 && (int_uop2.dst == uq2.srcB)) ||						   
						     (r_start_int && t_wr_int_prf & (int_uop.dst == uq2.srcB))
						     );		
     end // always_comb
  

   logic [N_INT_SCHED_ENTRIES-1:0] t_alu_sched_mask_valid;
   logic [N_INT_SCHED_ENTRIES-1:0] r_alu_sched_matrix [N_INT_SCHED_ENTRIES-1:0];

   logic [N_INT_SCHED_ENTRIES-1:0] t_alu_sched_mask_valid2;
   logic [N_INT_SCHED_ENTRIES-1:0] r_alu_sched_matrix2 [N_INT_SCHED_ENTRIES-1:0];
   
   
   always_comb
     begin
	t_alu_sched_mask_valid = r_alu_sched_valid & (~t_alu_select_entry);
	t_alu_sched_mask_valid2 = r_alu_sched_valid2 & (~t_alu_select_entry2);	
     end

   generate
      for(genvar i = 0; i < N_INT_SCHED_ENTRIES; i=i+1)
	begin
	   assign w_alu_sched_oldest_ready[i] = t_alu_entry_rdy[i] & (~(|(t_alu_entry_rdy & r_alu_sched_matrix[i])));
	   always_ff@(posedge clk)
	     begin
		if(reset || t_flash_clear)
		  begin
		     r_alu_sched_matrix[i] <= 'd0;
		  end
		else if(t_alu_alloc_entry[i])
		  begin
		     r_alu_sched_matrix[i] <= t_alu_sched_mask_valid;
		     
		  end
		else if(t_alu_entry_rdy != 'd0)
		  begin
		     r_alu_sched_matrix[i] <= r_alu_sched_matrix[i] & (~t_alu_select_entry);
		  end
	     end
	end // for (genvar i = 0; i < N_INT_SCHED_ENTRIES; i=i+1)
   endgenerate

   generate
      for(genvar i = 0; i < N_INT_SCHED_ENTRIES; i=i+1)
	begin
	   assign w_alu_sched_oldest_ready2[i] = t_alu_entry_rdy2[i] & (~(|(t_alu_entry_rdy2 & r_alu_sched_matrix2[i])));
	   always_ff@(posedge clk)
	     begin
		if(reset || t_flash_clear)
		  begin
		     r_alu_sched_matrix2[i] <= 'd0;
		  end
		else if(t_alu_alloc_entry2[i])
		  begin
		     r_alu_sched_matrix2[i] <= t_alu_sched_mask_valid2;
		     
		  end
		else if(t_alu_entry_rdy2 != 'd0)
		  begin
		     r_alu_sched_matrix2[i] <= r_alu_sched_matrix2[i] & (~t_alu_select_entry2);
		  end
	     end
	end // for (genvar i = 0; i < N_INT_SCHED_ENTRIES; i=i+1)
   endgenerate
   

   
   // always_ff@(negedge clk)
   //   begin
   // 	for(integer i = 0; i < N_INT_SCHED_ENTRIES; i=i+1)
   // 	  begin
   // 	     if(r_alu_sched_valid[i])
   // 	       begin
   // 		  $display("entry for pc %x is %b ready, src A %b, src B %b", 
   // 			   r_alu_sched_uops[i].pc, t_alu_entry_rdy[i],
   // 			   r_alu_srcA_rdy[i],
   // 			   r_alu_srcB_rdy[i]);
   // 	       end
   // 	  end
   //   end
   
   
   generate
      for(genvar i = 0; i < N_INT_SCHED_ENTRIES; i=i+1)
	begin
	   always_comb
	     begin
		t_alu_srcA_match[i] = r_alu_sched_uops[i].srcA_valid && (
									 (mem_rsp_dst_valid & (mem_rsp_dst_ptr == r_alu_sched_uops[i].srcA)) ||
									 (r_mul_complete && (r_mul_prf_ptr == r_alu_sched_uops[i].srcA)) ||
									 (r_div_complete && (r_div_prf_ptr == r_alu_sched_uops[i].srcA)) ||
									 (r_start_int2 && t_wr_int_prf2 & (int_uop2.dst == r_alu_sched_uops[i].srcA)) ||			 
									 (r_start_int && t_wr_int_prf & (int_uop.dst == r_alu_sched_uops[i].srcA))
									 );
		t_alu_srcB_match[i] = r_alu_sched_uops[i].srcB_valid && (
									 (mem_rsp_dst_valid & (mem_rsp_dst_ptr == r_alu_sched_uops[i].srcB)) ||
									 (r_mul_complete && (r_mul_prf_ptr == r_alu_sched_uops[i].srcB)) ||
									 (r_div_complete && (r_div_prf_ptr == r_alu_sched_uops[i].srcB)) ||
									 (r_start_int2 && t_wr_int_prf2 & (int_uop2.dst == r_alu_sched_uops[i].srcB)) ||
									 (r_start_int && t_wr_int_prf & (int_uop.dst == r_alu_sched_uops[i].srcB))
									 );
		
		t_alu_entry_rdy[i] = r_alu_sched_valid[i] &&
				     (uses_div(r_alu_sched_uops[i].op) ?  t_div_ready :  
				      (uses_mul(r_alu_sched_uops[i].op) ?  !r_wb_bitvec[`MUL_LAT+2] : !r_wb_bitvec[1]))
				     ? (
					(t_alu_srcA_match[i] |r_alu_srcA_rdy[i]) & 
					(t_alu_srcB_match[i] |r_alu_srcB_rdy[i]) 
					 ) : 1'b0;
	     end // always_comb
	   
	   always_ff@(posedge clk)
	     begin
		if(reset)
		  begin
		     r_alu_srcA_rdy[i] <= 1'b0;
		     r_alu_srcB_rdy[i] <= 1'b0;
		  end
		else
		  begin
		     if(t_alu_alloc_entry[i])
		       begin //allocating to this entry
			  r_alu_srcA_rdy[i] <= uq.srcA_valid ? (!r_prf_inflight[uq.srcA] | t_alu_alloc_srcA_match) : 1'b1;
			  r_alu_srcB_rdy[i] <= uq.srcB_valid ? (!r_prf_inflight[uq.srcB] | t_alu_alloc_srcB_match) : 1'b1;
		       end
		     else if(t_alu_select_entry[i])
		       begin
			  r_alu_srcA_rdy[i] <= 1'b0;
			  r_alu_srcB_rdy[i] <= 1'b0;
		       end
		     else if(r_alu_sched_valid[i])
		       begin
			  r_alu_srcA_rdy[i] <= r_alu_srcA_rdy[i] | t_alu_srcA_match[i];
			  r_alu_srcB_rdy[i] <= r_alu_srcB_rdy[i] | t_alu_srcB_match[i];
		       end // else: !if(t_pop_uq&&(t_alu_sched_alloc_ptr == i))
		     
		  end // else: !if(reset)
	     end // always_ff@ (posedge clk)
	end // for (genvar i = 0; i < LG_INT_SCHED_ENTRIES; i=i+1)
   endgenerate


   generate
      for(genvar i = 0; i < N_INT_SCHED_ENTRIES; i=i+1)
	begin
	   always_comb
	     begin
		t_alu_srcA_match2[i] = r_alu_sched_uops2[i].srcA_valid && (
									   (mem_rsp_dst_valid & (mem_rsp_dst_ptr == r_alu_sched_uops2[i].srcA)) ||
									   (r_mul_complete && (r_mul_prf_ptr == r_alu_sched_uops2[i].srcA)) ||
									   (r_div_complete && (r_div_prf_ptr == r_alu_sched_uops2[i].srcA)) ||
									   (r_start_int2 && t_wr_int_prf2 & (int_uop2.dst == r_alu_sched_uops2[i].srcA)) ||			 
									   (r_start_int && t_wr_int_prf & (int_uop.dst == r_alu_sched_uops2[i].srcA))
									   );
		
		t_alu_srcB_match2[i] = r_alu_sched_uops2[i].srcB_valid && (
									   (mem_rsp_dst_valid & (mem_rsp_dst_ptr == r_alu_sched_uops2[i].srcB)) ||
									   (r_mul_complete && (r_mul_prf_ptr == r_alu_sched_uops2[i].srcB)) ||
									   (r_div_complete && (r_div_prf_ptr == r_alu_sched_uops2[i].srcB)) ||
									   (r_start_int2 && t_wr_int_prf2 & (int_uop2.dst == r_alu_sched_uops2[i].srcB)) ||
									   (r_start_int && t_wr_int_prf & (int_uop.dst == r_alu_sched_uops2[i].srcB))
									   );
		
		t_alu_entry_rdy2[i] = r_alu_sched_valid2[i] 
				      ? (
					 (t_alu_srcA_match2[i] |r_alu_srcA_rdy2[i]) & 
					 (t_alu_srcB_match2[i] |r_alu_srcB_rdy2[i]) 
					 ) : 1'b0;
	     end // always_comb
	   
	   always_ff@(posedge clk)
	     begin
		if(reset)
		  begin
		     r_alu_srcA_rdy2[i] <= 1'b0;
		     r_alu_srcB_rdy2[i] <= 1'b0;
		  end
		else
		  begin
		     if(t_alu_alloc_entry2[i])
		       begin //allocating to this entry
			  r_alu_srcA_rdy2[i] <= uq2.srcA_valid ? (!r_prf_inflight[uq2.srcA] | t_alu_alloc_srcA_match2) : 1'b1;
			  r_alu_srcB_rdy2[i] <= uq2.srcB_valid ? (!r_prf_inflight[uq2.srcB] | t_alu_alloc_srcB_match2) : 1'b1;
		       end
		     else if(t_alu_select_entry2[i])
		       begin
			  r_alu_srcA_rdy2[i] <= 1'b0;
			  r_alu_srcB_rdy2[i] <= 1'b0;
		       end
		     else if(r_alu_sched_valid2[i])
		       begin
			  r_alu_srcA_rdy2[i] <= r_alu_srcA_rdy2[i] | t_alu_srcA_match2[i];
			  r_alu_srcB_rdy2[i] <= r_alu_srcB_rdy2[i] | t_alu_srcB_match2[i];
		       end // else: !if(t_pop_uq&&(t_alu_sched_alloc_ptr == i))
		     
		  end // else: !if(reset)
	     end // always_ff@ (posedge clk)
	end // for (genvar i = 0; i < LG_INT_SCHED_ENTRIES; i=i+1)
   endgenerate
   
   
   always_comb
     begin
	t_pop_uq = 1'b0;
	t_pop_uq2 = 1'b0;
	t_alu_sched_full = (&r_alu_sched_valid);
	t_alu_sched_full2 = (&r_alu_sched_valid2);
	
	t_pop_uq = !(t_flash_clear | t_uq_empty | t_alu_sched_full);
	t_pop_uq2 = t_uq_next_empty ? 1'b0 : (t_pop_uq & uq2.is_cheap_int & (!t_alu_sched_full2));
     end // always_comb


   logic t_left_shift2, t_signed_shift2;
   wire [31:0] w_shifter_out2;
   logic [4:0] t_shift_amt2;   
   shift_right #(.LG_W(5)) s1(.is_left(t_left_shift2), 
			      .is_signed(t_signed_shift2), 
			      .data(t_srcA_2), 
			      .distance(t_shift_amt2), 
			      .y(w_shifter_out2));

   
   
   logic  t_sub2, t_addi_2;
   wire [31:0] w_pc2_4, w_add32_2;
   wire [31:0] w_s_sub32_2, w_c_sub32_2;   
   ppa32 npc_2 (.A(int_uop2.pc), .B(32'd4), .Y(w_pc2_4));

   csa #(.N(32)) csa2 (
		       .a(t_srcA_2), 
		       .b(t_addi_2 ? int_uop2.rvimm : (t_sub2 ? ~t_srcB_2 : t_srcB_2)), 
		       .cin(t_sub2 ? 32'd1 : 32'd0), 
		       .s(w_s_sub32_2), 
		       .cout(w_c_sub32_2) );

   
   ppa32 add32 (.A({w_c_sub32_2[30:0], 1'b0}), 
		.B(w_s_sub32_2), 
		.Y(w_add32_2));
   

   wire [31:0] w_indirect_target2;
   ppa32 itgt (.A(t_srcA_2), .B(int_uop2.rvimm), .Y(w_indirect_target2));
   
   wire        w_mispredicted_indirect2 = w_indirect_target2 != 
	       {int_uop2.jmp_imm,int_uop2.imm};   

   
   always_comb
     begin
	t_sub2 = 1'b0;
	t_addi_2 = 1'b0;
	t_take_br2 = 1'b0;
	t_mispred_br2= 1'b0;
	t_pc_2 = int_uop2.pc;
	t_left_shift2 = 1'b0;
	t_signed_shift2 = 1'b0;
	t_shift_amt2 = 5'd0;
	t_alu_valid2 = 1'b0;
	t_result2 = 'd0;
	t_wr_int_prf2 = 1'b0;
	case(int_uop2.op)
	  BNE:
	    begin
	       t_take_br2 = t_srcA_2 != t_srcB_2;
	       t_mispred_br2 = int_uop2.br_pred != t_take_br2;
	       t_pc_2 = t_take_br2 ? int_uop2.rvimm : w_pc2_4;
	       t_alu_valid2 = 1'b1;	       
	    end
	  BEQ:
	    begin
	       t_take_br2 = t_srcA_2 == t_srcB_2;
	       t_mispred_br2 = int_uop2.br_pred != t_take_br2;
	       t_pc_2 = t_take_br2 ? int_uop2.rvimm : w_pc2_4;
	       t_alu_valid2 = 1'b1;	       
	    end
	  BLT:
	    begin
	       t_take_br2 = $signed(t_srcA_2) < $signed(t_srcB_2);
	       t_mispred_br2 = int_uop2.br_pred != t_take_br2;
	       t_pc_2 = t_take_br2 ? int_uop2.rvimm : w_pc2_4;
	       t_alu_valid2 = 1'b1;	       	       
	    end
	  BGE:
	    begin
	       t_take_br2 = $signed(t_srcA_2) >= $signed(t_srcB_2);
	       t_mispred_br2 = int_uop2.br_pred != t_take_br2;
	       t_pc_2 = t_take_br2 ? int_uop2.rvimm : w_pc2_4;
	       t_alu_valid2 = 1'b1;	       	       
	    end
	  BLTU:
	    begin
	       t_take_br2 = t_srcA_2 < t_srcB_2;
	       t_mispred_br2 = int_uop2.br_pred != t_take_br2;
	       t_pc_2 = t_take_br2 ? int_uop2.rvimm : w_pc2_4;
	       t_alu_valid2 = 1'b1;	       	       
	    end
	  BGEU:
	    begin
	       t_take_br2 = t_srcA_2 >= t_srcB_2;
	       t_mispred_br2 = int_uop2.br_pred != t_take_br2;
	       t_pc_2 = t_take_br2 ? int_uop2.rvimm : w_pc2_4;
	       t_alu_valid2 = 1'b1;	       	       
	    end
	  JAL:
	    begin
	       t_take_br2 = 1'b1;
	       t_mispred_br2 = int_uop2.br_pred != 1'b1;
	       t_pc_2 = int_uop2.rvimm;
	       t_result2 = w_pc2_4;
	       t_alu_valid2 = 1'b1;
	       t_wr_int_prf2 = 1'b1;
	    end
	  JALR:
	    begin
	       t_take_br2 = 1'b1;
	       t_mispred_br2 = w_mispredicted_indirect2;	       
	       t_pc_2 = w_indirect_target2;
	       t_alu_valid2 = 1'b1;
	       t_result2 = w_pc2_4;
	       t_wr_int_prf2 = 1'b1;
	    end
	  JR:
	    begin
	       t_take_br2 = 1'b1;
	       t_mispred_br2 = w_mispredicted_indirect2;	       
	       t_pc_2 = w_indirect_target2;
	       t_alu_valid2 = 1'b1;
	    end
	  RET:
	    begin
	       t_take_br2 = 1'b1;
	       t_mispred_br2 = w_mispredicted_indirect2;	       
	       t_pc_2 = w_indirect_target2;
	       t_alu_valid2 = 1'b1;
	    end	  
	  ADDI:
	    begin
	       t_addi_2 = 1'b1;
	       t_result2 = w_add32_2;
	       t_alu_valid2 = 1'b1;
	       t_wr_int_prf2 = 1'b1;
	    end
	  ADDU:
	    begin
	       t_result2 = w_add32_2;
	       t_alu_valid2 = 1'b1;
	       t_wr_int_prf2 = 1'b1;
	    end
	  RDCYCLE:
	    begin
	       t_result2 = r_cycle[31:0];
	       t_alu_valid2 = 1'b1;
	       t_wr_int_prf2 = 1'b1;
	    end
	  RDCYCLEH:
	    begin
	       t_result2 = r_cycle[63:32];
	       t_alu_valid2 = 1'b1;
	       t_wr_int_prf2 = 1'b1;
	    end
	  SLT:
	    begin
	       t_result2 = {31'd0, $signed(t_srcA_2) < $signed(t_srcB_2)};
	       t_alu_valid2 = 1'b1;
	       t_wr_int_prf2 = 1'b1;
	    end
	  SLTU:
	    begin
	       t_result2 = {31'd0, t_srcA_2 < t_srcB_2};
	       t_alu_valid2 = 1'b1;
	       t_wr_int_prf2 = 1'b1;
	    end
	  SLTI:
	    begin
	       t_result2 = {31'd0, $signed(t_srcA_2) < $signed(int_uop2.rvimm)};
	       t_alu_valid2 = 1'b1;
	       t_wr_int_prf2 = 1'b1;
	    end
	  SLTIU:
	    begin
	       t_result2 = {31'd0, t_srcA_2 < int_uop2.rvimm};
	       t_alu_valid2 = 1'b1;
	       t_wr_int_prf2 = 1'b1;
	    end	       
	  SUBU:
	    begin
	       t_sub2 = 1'b1;
	       t_result2 = w_add32_2;
	       t_alu_valid2 = 1'b1;
	       t_wr_int_prf2 = 1'b1;
	    end
	  ANDI:
	    begin
	       t_result2 = int_uop2.rvimm & t_srcA_2;
	       t_alu_valid2 = 1'b1;
	       t_wr_int_prf2 = 1'b1;
	    end
	  ORI:
	    begin
	       t_result2 = int_uop2.rvimm | t_srcA_2;
	       t_alu_valid2 = 1'b1;
	       t_wr_int_prf2 = 1'b1;
	    end
	  XORI:
	    begin
	       t_result2 = int_uop2.rvimm ^ t_srcA_2;
	       t_alu_valid2 = 1'b1;
	       t_wr_int_prf2 = 1'b1;
	    end
	  AND:
	    begin
	       t_result2 = t_srcA_2 & t_srcB_2;	       
	       t_alu_valid2 = 1'b1;
	       t_wr_int_prf2 = 1'b1;
	    end
	  OR:
	    begin
	       t_result2 = t_srcA_2 | t_srcB_2;
	       t_alu_valid2 = 1'b1;
	       t_wr_int_prf2 = 1'b1;
	    end
	  XOR:
	    begin
	       t_result2 = t_srcA_2 ^ t_srcB_2;
	       t_alu_valid2 = 1'b1;
	       t_wr_int_prf2 = 1'b1;
	    end
	  SRL:
	    begin
	       t_shift_amt2 = t_srcB_2[4:0];
	       t_result2 = w_shifter_out2;
	       t_wr_int_prf2 = 1'b1;
	       t_alu_valid2 = 1'b1;
	    end
	  SRLI:
	    begin
		t_shift_amt2 = int_uop2.rvimm[4:0];
		t_result2 = w_shifter_out2;
		t_wr_int_prf2 = 1'b1;
		t_alu_valid2 = 1'b1;	       
	    end
	  SRA:
	    begin
	       t_signed_shift2 = 1'b1;
	       t_shift_amt2 = t_srcB_2[4:0];
	       t_result2 = w_shifter_out2;
	       t_wr_int_prf2 = 1'b1;
	       t_alu_valid2 = 1'b1;
	    end
	  SRAI:
	    begin
	       t_signed_shift2 = 1'b1;
	       t_shift_amt2 = int_uop2.rvimm[4:0];
	       t_result2 = w_shifter_out2;
	       t_wr_int_prf2 = 1'b1;
	       t_alu_valid2 = 1'b1;		
	    end	  
	  SLL:
	    begin
	       t_left_shift2 = 1'b1;
	       t_shift_amt2 = t_srcB_2[4:0];
	       t_result2 = w_shifter_out2;
	       t_wr_int_prf2 = 1'b1;
	       t_alu_valid2 = 1'b1;
	    end
	  SLLI:
	    begin
	       t_left_shift2 = 1'b1;	       
	       t_shift_amt2 = int_uop2.rvimm[4:0];
	       t_result2 = w_shifter_out2;
	       t_wr_int_prf2 = 1'b1;
	       t_alu_valid2 = 1'b1;		
	    end	  
	  AUIPC:
	    begin
	       t_result2 = int_uop2.rvimm;
	       t_alu_valid2 = 1'b1;
	       t_wr_int_prf2 = 1'b1;
	    end
	  LUI:
	    begin
	       t_result2 = int_uop2.rvimm;
	       t_alu_valid2 = 1'b1;
	       t_wr_int_prf2 = 1'b1;
	    end
	  default:
	    begin
	    end
	endcase
     end

   
   
   always_ff@(posedge clk)
     begin
	if(reset || t_flash_clear)
	  begin
	     r_alu_sched_valid <= 'd0;
	  end
	else
	  begin
	     if(t_pop_uq)
	       begin
		  r_alu_sched_valid[t_alu_sched_alloc_ptr[`LG_INT_SCHED_ENTRIES-1:0]] <= 1'b1;
		  r_alu_sched_uops[t_alu_sched_alloc_ptr[`LG_INT_SCHED_ENTRIES-1:0]] <= uq;
	       end
	     if(t_alu_entry_rdy != 'd0)
	       begin
		  r_alu_sched_valid[t_alu_sched_select_ptr[`LG_INT_SCHED_ENTRIES-1:0]] <= 1'b0;
	       end
	  end // else: !if(reset)
     end // always_ff@ (posedge clk)


   always_ff@(posedge clk)
     begin
	if(reset || t_flash_clear)
	  begin
	     r_alu_sched_valid2 <= 'd0;
	  end
	else
	  begin
	     if(t_pop_uq2)
	       begin
		  r_alu_sched_valid2[t_alu_sched_alloc_ptr2[`LG_INT_SCHED_ENTRIES-1:0]] <= 1'b1;
		  r_alu_sched_uops2[t_alu_sched_alloc_ptr2[`LG_INT_SCHED_ENTRIES-1:0]] <= uq2;
	       end
	     if(t_alu_entry_rdy2 != 'd0)
	       begin
		  r_alu_sched_valid2[t_alu_sched_select_ptr2[`LG_INT_SCHED_ENTRIES-1:0]] <= 1'b0;
	       end
	  end // else: !if(reset)
     end // always_ff@ (posedge clk)
   
   
   
   
   shift_right #(.LG_W(5)) s0(.is_left(t_left_shift), 
			      .is_signed(t_signed_shift), 
			      .data(t_srcA[31:0]), 
			      .distance(t_shift_amt), 
			      .y(w_shifter_out));


   
   always_ff@(posedge clk)
     begin
	r_mul_prf_ptr <= w_mul_prf_ptr;
	r_div_prf_ptr <= w_div_prf_ptr;
	r_mul_complete <= reset ? 1'b0 : t_mul_complete;
	r_div_complete <= reset ? 1'b0 : t_div_complete;
     end
   
   mul m(.clk(clk), 
	 .reset(reset), 
	 .is_signed(int_uop.op == MUL || int_uop.op == MULH),
	 .is_high(int_uop.op == MULHU || int_uop.op == MULH),
	 .go(t_start_mul&r_start_int),
	 .src_A(t_srcA[31:0]),
	 .src_B(t_srcB[31:0]),
	 .rob_ptr_in(int_uop.rob_ptr),
	 .prf_ptr_in(int_uop.dst),
	 .y(t_mul_result),
	 .complete(t_mul_complete),
	 .rob_ptr_out(t_rob_ptr_out),
	 .prf_ptr_val_out(),
	 .prf_ptr_out(w_mul_prf_ptr)
	 );

   always_ff@(negedge clk)
     begin
	// if(t_start_mul&r_start_int)
	//   begin
	//      $display("multiplier dest ptr entry %d", int_uop.dst);
	//   end
	// if(t_mul_complete)
	//   begin
	//      $display("r_start_int %b, t_wr_int_prf %b,ptr %d, result %x",
	// 	      r_start_int, t_wr_int_prf,w_mul_prf_ptr, t_mul_result);
	//      if(r_start_int & t_wr_int_prf)
	//        $stop();
	//   end

	// if(t_div_complete)
	//   begin
	//      $display("divider writes back to rob %d, prf %d, value %x at cycle %d",
	// 	      t_div_rob_ptr, w_div_prf_ptr, t_div_result[31:0], r_cycle);
	//   end
	
	
	if(t_mul_complete & t_div_complete)
	  $stop();
	
	if(t_mul_complete & r_start_int & t_wr_int_prf)
	  $stop();

	if(t_div_complete & r_start_int & t_wr_int_prf)
	  $stop();	
     end
   
   

   divider #(.LG_W(5)) d32 (
	   .clk(clk), 
	   .reset(reset),
	   .srcA(t_srcA[31:0]),
	   .srcB(t_srcB[31:0]),
	   .rob_ptr_in(int_uop.rob_ptr),
	   .prf_ptr_in(int_uop.dst),
	   .is_signed_div(t_signed_div),
           .is_rem(t_is_rem),
	   .start_div(t_start_div32),
	   .y(t_div_result),
	   .rob_ptr_out(t_div_rob_ptr),
	   .prf_ptr_out(w_div_prf_ptr),
	   .complete(t_div_complete),
	   .ready(t_div_ready)
	   );

   assign divide_ready = t_div_ready;




   
   always_comb
     begin
	n_mq_head_ptr = r_mq_head_ptr;
	n_mq_tail_ptr = r_mq_tail_ptr;
	n_mq_next_tail_ptr = r_mq_next_tail_ptr;
	
	if(r_mem_ready)
	  begin
	     n_mq_tail_ptr = r_mq_tail_ptr + 'd1;
	     n_mq_next_tail_ptr = r_mq_next_tail_ptr + 'd1;
	  end
	if(mem_req_ack)
	  begin
	     n_mq_head_ptr = r_mq_head_ptr + 'd1;
	  end
	
	t_mem_head = r_mem_q[r_mq_head_ptr[`LG_MQ_ENTRIES-1:0]];
	
	mem_q_empty = (r_mq_head_ptr == r_mq_tail_ptr);
	
	mem_q_full = (r_mq_head_ptr != r_mq_tail_ptr) &&
		     (r_mq_head_ptr[`LG_MQ_ENTRIES-1:0] == r_mq_tail_ptr[`LG_MQ_ENTRIES-1:0]);

	mem_q_next_full = (r_mq_head_ptr != r_mq_next_tail_ptr) &&
			  (r_mq_head_ptr[`LG_MQ_ENTRIES-1:0] == r_mq_next_tail_ptr[`LG_MQ_ENTRIES-1:0]);
	
     end // always_comb
   
   always_ff@(posedge clk)
     begin
	if(r_mem_ready)
	  begin
	     r_mem_q[r_mq_tail_ptr[`LG_MQ_ENTRIES-1:0]] <= t_mem_tail;
	  end
     end


   
   always_comb
     begin
	n_mdq_head_ptr = r_mdq_head_ptr;
	n_mdq_tail_ptr = r_mdq_tail_ptr;
	n_mdq_next_tail_ptr = r_mdq_next_tail_ptr;
	
	if(r_dq_ready)
	  begin
	     n_mdq_tail_ptr = r_mdq_tail_ptr + 'd1;
	     n_mdq_next_tail_ptr = r_mdq_next_tail_ptr + 'd1;
	  end
	
	if(core_store_data_ack)
	  begin
	     n_mdq_head_ptr = r_mdq_head_ptr + 'd1;
	  end

	core_store_data = r_mdq[r_mdq_head_ptr[`LG_MQ_ENTRIES-1:0]];
			       
	mem_mdq_empty = (r_mdq_head_ptr == r_mdq_tail_ptr);
	
	mem_mdq_full = (r_mdq_head_ptr != r_mdq_tail_ptr) &&
		     (r_mdq_head_ptr[`LG_MQ_ENTRIES-1:0] == r_mdq_tail_ptr[`LG_MQ_ENTRIES-1:0]);

	mem_mdq_next_full = (r_mdq_head_ptr != r_mdq_next_tail_ptr) &&
			    (r_mdq_head_ptr[`LG_MQ_ENTRIES-1:0] == r_mdq_next_tail_ptr[`LG_MQ_ENTRIES-1:0]);
     end // always_comb
   

   
   assign mem_req = t_mem_head;
   assign mem_req_valid = !mem_q_empty;
   assign uq_wait = r_uq_wait;
   assign mq_wait = r_mq_wait;
   assign core_store_data_valid = !mem_mdq_empty;
   
   
   always_ff@(posedge clk)
     begin
	r_mq_head_ptr <= reset ? 'd0 : n_mq_head_ptr;
	r_mq_tail_ptr <= reset ? 'd0 : n_mq_tail_ptr;
	r_mq_next_tail_ptr <= reset ? 'd1 : n_mq_next_tail_ptr;

	r_mdq_head_ptr <= (reset || mem_dq_clr) ? 'd0 : n_mdq_head_ptr;
	r_mdq_tail_ptr <= (reset || mem_dq_clr) ? 'd0 : n_mdq_tail_ptr;
	r_mdq_next_tail_ptr <= (reset || mem_dq_clr) ? 'd1 : n_mdq_next_tail_ptr;	
     end

   always_ff@(posedge clk)
     begin
	if(reset)
	  begin
	     r_prf_inflight <= 'd0;
	  end
	else
	  begin
	     r_prf_inflight <= ds_done ? 'd0 : n_prf_inflight;
	  end
     end // always_ff@ (posedge clk)

   
   always_comb
     begin
	n_prf_inflight = r_prf_inflight;

	
	if(uq_push && uq_uop.dst_valid)
	  begin
	     n_prf_inflight[uq_uop.dst] = 1'b1;
	  end
	if(uq_push_two && uq_uop_two.dst_valid)
	  begin
	     n_prf_inflight[uq_uop_two.dst] = 1'b1;
	  end
	
	
	if(mem_rsp_dst_valid)
	  begin
	     n_prf_inflight[mem_rsp_dst_ptr] = 1'b0;
	  end
	
	if(r_start_int && t_wr_int_prf)
	  begin
	     n_prf_inflight[int_uop.dst] = 1'b0;
	  end
	else if(t_mul_complete)
	  begin
	     n_prf_inflight[w_mul_prf_ptr] = 1'b0;
	  end
	else if(t_div_complete)
	  begin
	     n_prf_inflight[w_div_prf_ptr] = 1'b0;
	  end
	if(r_start_int2 && t_wr_int_prf2)
	  begin
	     n_prf_inflight[int_uop2.dst] = 1'b0;
	  end
	
     end // always_comb

   
`ifdef VERILATOR
   logic t_blocked_by_store;
   always_comb
     begin
	t_blocked_by_store = t_mem_uq_empty ? 1'b0 : !t_pop_mem_uq  & is_store(mem_uq.op) & 
			     !r_prf_inflight[mem_uq.srcA] &
			     !mem_q_full;
     end
   always_ff@(negedge clk)
     begin
	report_exec(t_uq_empty ? 32'd0 : 32'd1,
		    t_pop_uq ? 32'd1 : 32'd0,
		    !t_uq_next_empty & t_pop_uq & uq2.is_cheap_int ? 32'd1 : 32'd0,
		    t_pop_uq2 ? 32'd1 : 32'd0,
		    t_mem_uq_empty ? 32'd0 : 32'd1,
		    t_pop_mem_uq ? 32'd1 : 32'd0,
		    32'd1,
		    32'd0,
		    t_uq_full ? 32'd1 : 32'd0,
		    t_mem_uq_full ? 32'd1 : 32'd0,
		    32'd0,
		    t_blocked_by_store ? 32'd1 : 32'd0,
		    {{(32-N_INT_SCHED_ENTRIES){1'b0}}, t_alu_entry_rdy},
		    {{(32-N_INT_SCHED_ENTRIES){1'b0}}, t_alu_entry_rdy2}
		    );
     end
`endif //  `ifdef VERILATOR

   wire [31:0] w_add32;
   wire [63:0] w_add64;
   
   wire [31:0] w_s_sub32, w_c_sub32;
   wire [63:0] w_s_sub64, w_c_sub64;
   logic       t_sub, t_addi, t_slti, t_sltiu;

   csa #(.N(32)) csa0 (.a(t_srcA), 
		       .b(t_slti ? ~int_uop.rvimm  : (t_addi ? int_uop.rvimm : (t_sub ? ~t_srcB : t_srcB))), 
		       .cin(t_sub|t_slti ? 32'd1 : 32'd0), .s(w_s_sub32), .cout(w_c_sub32) );
   
   wire [31:0] w_add32_srcA = {w_c_sub32[30:0], 1'b0};
   wire [31:0] w_add32_srcB = w_s_sub32;
   
   ppa32 add0 (.A(w_add32_srcA), .B(w_add32_srcB), .Y(w_add32));


   csa #(.N(64)) csa1 (.a({32'd0, t_srcA}), 
		       .b(~{32'd0, t_sltiu ? int_uop.rvimm : t_srcB}), 
		       .cin(64'd1), 
		       .s(w_s_sub64), 
		       .cout(w_c_sub64) 
		       );

   wire [63:0] w_add64_srcA = {w_c_sub64[62:0], 1'b0};
   wire [63:0] w_add64_srcB = w_s_sub64;
   ppa64 add1 (.A(w_add64_srcA), .B(w_add64_srcB), .Y(w_add64));

   
   wire [31:0] w_pc4, w_pc_plus_imm;
   wire [31:0] w_indirect_target;
   ppa32 add2 (.A(t_srcA), .B(int_uop.rvimm), .Y(w_indirect_target));
   wire        w_mispredicted_indirect = w_indirect_target != {int_uop.jmp_imm,int_uop.imm};   
   ppa32 add3 (.A(int_uop.pc), .B(32'd4), .Y(w_pc4));

   wire        w_AeqB = t_srcA == t_srcB;
   wire w_AltB = (t_srcA[31] & (~t_srcB[31])) ? 1'b1 :
	((~t_srcA[31]) & t_srcB[31]) ? 1'b0 :
	w_add32[31];
   wire w_AltB_slti = (t_srcA[31] & (~int_uop.rvimm[31])) ? 1'b1 :
	((~t_srcA[31]) & int_uop.rvimm[31]) ? 1'b0 :
	w_add32[31];   
   

   // always_ff@(negedge clk)
   //   begin
   // 	if(int_uop.op == BGEU && r_start_int && t_alu_valid)
   // 	  begin
   // 	     $display("w_add64[32] = %b", 
   // 		      !w_add64[32]);
   // 	     $display("should be %b", 
   // 		      (t_srcA  > t_srcB) | (t_srcA == t_srcB));
   // 	     $display("t_srcA = %x, t_srcB = %x", t_srcA, t_srcB);
   // 	     $display("w_add64 = %x", w_add64);
   // 	     //$stop();
   // 	  end
   //   end
   
   always_comb
     begin
	t_sub = 1'b0;
	t_addi = 1'b0;
	t_sltiu = 1'b0;
	t_slti = 1'b0;
	t_pc = int_uop.pc;
	t_result = 32'd0;
	t_unimp_op = 1'b0;
	t_fault = 1'b0;
	t_wr_int_prf = 1'b0;
	t_take_br = 1'b0;
	t_mispred_br = 1'b0;
	t_alu_valid = 1'b0;
	t_got_break = 1'b0;
	t_signed_shift = 1'b0;
	t_left_shift = 1'b0;
	t_shift_amt = 5'd0;
	t_start_mul = 1'b0;
	t_signed_div = 1'b0;
	t_is_rem = 1'b0;
	t_start_div32 = 1'b0;	
	
	case(int_uop.op)
	  //riscv
	  DIV:
	    begin
	       t_signed_div = 1'b1;
	       t_start_div32 = r_start_int&!ds_done;	       
	    end
	  DIVU:
	    begin
	       t_start_div32 = r_start_int&!ds_done;
	    end
	  REM:
	    begin
	       t_signed_div = 1'b1;
	       t_is_rem = 1'b1;
	       t_start_div32 = r_start_int&!ds_done;	       
	    end
	  REMU:
	    begin
	       t_is_rem = 1'b1;
	       t_start_div32 = r_start_int&!ds_done;
	    end
	  
	  MUL:
	    begin
	       t_start_mul = r_start_int&!ds_done;
	    end
	  MULH:
	    begin
	       t_start_mul = r_start_int&!ds_done;
	    end
	  MULHU:
	    begin
	       t_start_mul = r_start_int&!ds_done;
	    end
	  ADDI:
	    begin
	       t_addi = 1'b1;
	       t_result = w_add32;
	       t_wr_int_prf = 1'b1;
	       t_alu_valid = 1'b1;
	    end
	  ADDU:
	    begin
	       t_result = w_add32;
	       t_wr_int_prf = 1'b1;
	       t_alu_valid = 1'b1;
	    end
	  RDCYCLE:
	    begin
	       t_result = r_cycle[31:0];
	       t_alu_valid = 1'b1;
	       t_wr_int_prf = 1'b1;
	    end
	  RDCYCLEH:
	    begin
	       t_result = r_cycle[63:32];
	       t_alu_valid = 1'b1;
	       t_wr_int_prf = 1'b1;
	    end
	  RDINSTRET:
	    begin
	       t_result = r_retired_insns[31:0];
	       t_alu_valid = 1'b1;
	       t_wr_int_prf = 1'b1;
	       t_pc = w_pc4;
	    end
	  RDINSTRETH:
	    begin
	       t_result = r_retired_insns[63:32];
	       t_alu_valid = 1'b1;
	       t_wr_int_prf = 1'b1;
	       t_pc = w_pc4;
	    end
	  RDBRANCH:
	    begin
	       t_result = r_branches[31:0];
	       t_alu_valid = 1'b1;
	       t_wr_int_prf = 1'b1;
	       t_pc = w_pc4;	       
	    end
	  RDFAULTEDBRANCH:
	    begin
	       t_result = r_branch_faults[31:0];
	       t_alu_valid = 1'b1;
	       t_wr_int_prf = 1'b1;
	       t_pc = w_pc4;
	    end
	  AND:
	    begin
	       t_result = t_srcA & t_srcB;
	       t_wr_int_prf = 1'b1;
	       t_alu_valid = 1'b1;	       
	    end
	  SUBU:
	    begin
	       t_sub = 1'b1;
	       t_result = w_add32;
	       t_wr_int_prf = 1'b1;
	       t_alu_valid = 1'b1;
	    end
	  ANDI:
	    begin
	       t_result = t_srcA & int_uop.rvimm;
	       t_wr_int_prf = 1'b1;
	       t_alu_valid = 1'b1;
	    end
	  AUIPC:
	    begin
	       t_result = int_uop.rvimm;
	       t_wr_int_prf = 1'b1;
	       t_alu_valid = 1'b1;
	    end
	  BEQ:
	    begin
	       t_take_br = w_AeqB;
	       t_mispred_br = int_uop.br_pred != t_take_br;
	       t_pc = t_take_br ? int_uop.rvimm : w_pc4;	       
	       t_alu_valid = 1'b1;
	    end
	  BGE:
	    begin
	       t_sub = 1'b1;
	       t_take_br = ((~t_srcA[31]) & t_srcB[31]) ? 1'b1 :
			   (t_srcA[31] & (~t_srcB[31])) ? 1'b0 :
			   (w_add32[31] == 1'b0);
	       t_mispred_br = int_uop.br_pred != t_take_br;
	       t_pc = t_take_br ? int_uop.rvimm : w_pc4;	       
	       t_alu_valid = 1'b1;
	    end
	  BGEU:
	    begin
	       t_take_br = !w_add64[32];
	       t_mispred_br = int_uop.br_pred != t_take_br;
	       t_pc = t_take_br ? int_uop.rvimm : w_pc4;
	       t_alu_valid = 1'b1;
	    end
	  BLT:
	    begin
	       t_sub = 1'b1;
	       t_take_br = w_AltB;
	       t_mispred_br = int_uop.br_pred != t_take_br;
	       t_pc = t_take_br ? int_uop.rvimm : w_pc4;
	       t_alu_valid = 1'b1;
	    end
	  BLTU:
	    begin
	       t_take_br = w_add64[32];
	       t_mispred_br = int_uop.br_pred != t_take_br;
	       t_pc = t_take_br ? int_uop.rvimm : w_pc4;
	       t_alu_valid = 1'b1;
	    end
	  
	  BNE:
	    begin
	       t_take_br = !w_AeqB;
	       t_mispred_br = int_uop.br_pred != t_take_br;
	       t_pc = t_take_br ? int_uop.rvimm : w_pc4;
	       t_alu_valid = 1'b1;
	    end
	  JAL:
	    begin
	       t_take_br = 1'b1;
	       t_mispred_br = int_uop.br_pred != t_take_br;
	       t_pc = int_uop.rvimm;
	       t_result = w_pc4;
	       t_alu_valid = 1'b1;
	       t_wr_int_prf = 1'b1;
	    end
	  JALR:
	    begin
	       t_take_br = 1'b1;
	       t_mispred_br = w_mispredicted_indirect;	       
	       t_pc = w_indirect_target;
	       t_alu_valid = 1'b1;
	       t_result = w_pc4;
	       t_wr_int_prf = 1'b1;
	    end
	  JR:
	     begin
		t_take_br = 1'b1;
		t_mispred_br = w_mispredicted_indirect;
		t_pc = w_indirect_target;
		t_alu_valid = 1'b1;
	     end
	  RET:
	    begin
	       t_take_br = 1'b1;
	       t_mispred_br = w_mispredicted_indirect;
	       t_pc = w_indirect_target;
	       t_alu_valid = 1'b1;
	    end
	  LUI:
	    begin
	       t_result = int_uop.rvimm;
	       t_wr_int_prf = 1'b1;
	       t_alu_valid = 1'b1;	       
	    end
	   OR:
	     begin
		t_result = t_srcA | t_srcB;	       
		t_wr_int_prf = 1'b1;
		t_alu_valid = 1'b1;
	     end
	   ORI:
	     begin
		t_result = t_srcA | int_uop.rvimm;	       
		t_wr_int_prf = 1'b1;
		t_alu_valid = 1'b1;
	     end
	  SLL:
	    begin
	       t_left_shift = 1'b1;
	       t_shift_amt = t_srcB[4:0];
	       t_result = w_shifter_out;
	       t_wr_int_prf = 1'b1;
	       t_alu_valid = 1'b1;
	    end
	  SLLI:
	    begin
	       t_left_shift = 1'b1;
	       t_shift_amt = int_uop.rvimm[4:0];
	       t_result = w_shifter_out;
	       t_wr_int_prf = 1'b1;
	       t_alu_valid = 1'b1;
	    end
	  SLT:
	    begin
	       t_sub = 1'b1;
	       t_result = {31'd0, w_AltB};
	       t_wr_int_prf = 1'b1;
	       t_alu_valid = 1'b1;
	    end
	  SLTU:
	    begin
	       t_result = {31'd0, w_add64[32]};
	       t_wr_int_prf = 1'b1;
	       t_alu_valid = 1'b1;
	    end
	  SLTI:
	    begin
	       t_slti = 1'b1;
	       t_result = {31'd0, w_AltB_slti};
	       t_wr_int_prf = 1'b1;
	       t_alu_valid = 1'b1;
	    end
	  SLTIU:
	    begin
	       t_sltiu = 1'b1;
	       t_result = {31'd0, w_add64[32]};
	       t_wr_int_prf = 1'b1;
	       t_alu_valid = 1'b1;
	    end
	  SRAI:
	    begin
	       t_signed_shift = 1'b1;
	       t_shift_amt = int_uop.rvimm[4:0];
	       t_result = {{HI_EBITS{w_shifter_out[31]}}, w_shifter_out};
	       t_wr_int_prf = 1'b1;
	       t_alu_valid = 1'b1;
	    end
	  SRA:
	    begin
	       t_signed_shift = 1'b1;
	       t_shift_amt = t_srcB[4:0];
	       t_result = {{HI_EBITS{w_shifter_out[31]}}, w_shifter_out};
	       t_wr_int_prf = 1'b1;
	       t_alu_valid = 1'b1;
	    end
	  SRL:
	    begin
	       t_shift_amt = t_srcB[4:0];
	       t_result = w_shifter_out;
	       t_wr_int_prf = 1'b1;
	       t_alu_valid = 1'b1;
	    end
	  SRLI:
	     begin
		t_shift_amt = int_uop.rvimm[4:0];
		t_result = w_shifter_out;
		t_wr_int_prf = 1'b1;
		t_alu_valid = 1'b1;
	     end
	  XORI:
	    begin
	       t_result = t_srcA ^ int_uop.rvimm;
	       t_wr_int_prf = 1'b1;
	       t_alu_valid = 1'b1;
	    end
	  XOR:
	    begin
	       t_result = t_srcA ^ t_srcB;
	       t_wr_int_prf = 1'b1;
	       t_alu_valid = 1'b1;
	    end

	  

	  // //old mips instructions
	  // BREAK:
	  //   begin
	  //      t_alu_valid = 1'b1;
	  //      t_got_break = 1'b1;
	  //      t_fault = 1'b1;
	  //      //t_unimp_op = 1'b1;
	  //   end
	  II:
	    begin
	       t_unimp_op = 1'b1;
	       t_alu_valid = 1'b1;
	    end
	  default:
	    begin
	       t_unimp_op = 1'b1;
	       t_alu_valid = 1'b1;
	    end
	endcase // case (int_uop.op)

	
     end // always_comb




   wire [31:0] w_agu32;
   ppa32 agu (.A(t_mem_srcA), .B(mem_uq.rvimm), .Y(w_agu32));

   wire w_mem_srcA_ready = t_mem_uq.srcA_valid ? (!r_prf_inflight[t_mem_uq.srcA] | t_fwd_int_mem_srcA | t_fwd_int2_mem_srcA | t_fwd_mem_mem_srcA) : 1'b1;


   wire w_dq_ready = !r_prf_inflight[t_mem_dq.src_ptr] | t_fwd_int_mem_srcB | t_fwd_mem_mem_srcB | t_fwd_int2_mem_srcB;
   	
   always_comb
     begin
	t_pop_mem_uq = (!t_mem_uq_empty) && (!(mem_q_next_full||mem_q_full)) && w_mem_srcA_ready && !t_flash_clear;

	t_pop_mem_dq = (!t_mem_dq_empty) && !mem_dq_clr && w_dq_ready
		       && (!(mem_mdq_next_full||mem_mdq_full)) ;
     end


   //need another queue to hold store data
   
   always_comb
     begin
	t_core_store_data.rob_ptr = mem_dq.rob_ptr;
	t_core_store_data.data = t_mem_srcB;
	core_store_data_ptr = mem_dq.rob_ptr;
	core_store_data_ptr_valid = r_dq_ready;
     end

   always_ff@(posedge clk)
     begin
	if(r_dq_ready)
	  begin
	     //$display("STORE DATA value %x for rob ptr %d", t_core_store_data.data, mem_dq.rob_ptr);
	     r_mdq[r_mdq_tail_ptr[`LG_MQ_ENTRIES-1:0]] <= t_core_store_data;
	  end
     end

   
   
   always_ff@(posedge clk)
     begin
	if(reset)
	  begin
	     r_mem_ready <= 1'b0;
	     r_dq_ready <= 1'b0;
	  end
	else
	  begin
	     r_mem_ready <= t_pop_mem_uq;
	     r_dq_ready <= t_pop_mem_dq;
	  end
     end // always_ff@ (posedge clk)

   
   //cases were address wraps the cacheline
   
   wire w_bad_16b_addr = &w_agu32[3:0];
   wire w_bad_32b_addr = (&w_agu32[3:2]) & (|w_agu32[1:0]);

   //wire w_bad_16b_addr = w_agu32[0];
   //wire w_bad_32b_addr = w_agu32[1:0] != 2'd0;   
   
   always_comb
     begin
	t_mem_tail.op = MEM_LW;
	t_mem_tail.addr = w_agu32;
	t_mem_tail.rob_ptr = mem_uq.rob_ptr;
	t_mem_tail.dst_valid = 1'b0;
	t_mem_tail.dst_ptr = mem_uq.dst;
	t_mem_tail.is_load = 1'b0;
	t_mem_tail.is_store = 1'b0;
	t_mem_tail.data = 32'd0;
	t_mem_tail.spans_cacheline = 1'b0;
	t_mem_tail.unaligned = 1'b0;
	t_mem_tail.pc = mem_uq.pc;
	case(mem_uq.op)
	  SB:
	    begin
	       t_mem_tail.op = MEM_SB;
	       t_mem_tail.is_store = 1'b1;
	       t_mem_tail.dst_valid = 1'b0;
	    end // case: SB
	  SH:
	    begin
	       t_mem_tail.op = w_bad_16b_addr ? MEM_NOP : MEM_SH;
	       t_mem_tail.is_store = ~w_bad_16b_addr;
	       t_mem_tail.dst_valid = 1'b0;
	       t_mem_tail.spans_cacheline = w_bad_16b_addr;
	       t_mem_tail.unaligned = w_agu32[0];
	    end // case: SW
	  SW:
	    begin
	       t_mem_tail.op = w_bad_32b_addr ? MEM_NOP : MEM_SW;
	       t_mem_tail.is_store = ~w_bad_32b_addr;
	       t_mem_tail.dst_valid = 1'b0;
	       t_mem_tail.spans_cacheline = w_bad_32b_addr;
	       t_mem_tail.unaligned = |w_agu32[1:0];
	    end // case: SW
	  SC:
	    begin
	       t_mem_tail.op = MEM_SC;
	       t_mem_tail.is_store = 1'b1;
	       t_mem_tail.dst_valid = 1'b1;
	       t_mem_tail.dst_ptr = mem_uq.dst;
	       t_mem_tail.spans_cacheline = (w_agu32[1:0] != 2'd0);
	       t_mem_tail.unaligned = |w_agu32[1:0];	       
	    end // case: SW
	  LW:
	    begin
	       t_mem_tail.is_load = 1'b1;
	       t_mem_tail.op = w_bad_32b_addr ? MEM_NOP : MEM_LW;
	       t_mem_tail.dst_valid = mem_uq.dst_valid;
	       t_mem_tail.spans_cacheline = w_bad_32b_addr;
	       t_mem_tail.unaligned = |w_agu32[1:0];
	    end // case: LW
	  LB:
	    begin
	       t_mem_tail.is_load = 1'b1;	       
	       t_mem_tail.op = MEM_LB;
	       t_mem_tail.dst_valid = mem_uq.dst_valid;
	    end
	  LBU:
	    begin
	       t_mem_tail.is_load = 1'b1;	       
	       t_mem_tail.op = MEM_LBU;
	       t_mem_tail.dst_valid = mem_uq.dst_valid;
	    end // case: LBU
	  LHU:
	    begin
	       t_mem_tail.is_load = 1'b1;
	       t_mem_tail.op = MEM_LHU;
	       t_mem_tail.dst_valid = mem_uq.dst_valid;
	       t_mem_tail.spans_cacheline = w_agu32[0];
	       t_mem_tail.unaligned = w_agu32[0];
	    end // case: LBU
	  LH:
	    begin
	       t_mem_tail.is_load = 1'b1;
	       t_mem_tail.op = w_bad_16b_addr ? MEM_NOP : MEM_LH;
	       t_mem_tail.dst_valid = mem_uq.dst_valid;
	       t_mem_tail.spans_cacheline = w_bad_16b_addr;
	       t_mem_tail.unaligned = w_agu32[0];
	    end // case: LH
	  default:
	    begin
	    end
	endcase // case (mem_uq.op)

     end // always_comb

   

   always_ff@(posedge clk)
     begin
	r_int_result <= t_result;
	r_int_result2 <= t_result2;
	r_mem_result <= mem_rsp_load_data[31:0];
     end

   always_comb
     begin
	t_fwd_int_mem_srcA = r_start_int && t_wr_int_prf &&(t_mem_uq.srcA == int_uop.dst);
	t_fwd_int_mem_srcB = r_start_int && t_wr_int_prf &&(t_mem_dq.src_ptr == int_uop.dst);
	t_fwd_int2_mem_srcA = r_start_int2 && t_wr_int_prf2 &&(t_mem_uq.srcA == int_uop2.dst);
	t_fwd_int2_mem_srcB = r_start_int2 && t_wr_int_prf2 &&(t_mem_dq.src_ptr == int_uop2.dst);
	
	t_fwd_mem_mem_srcA = mem_rsp_dst_valid && (t_mem_uq.srcA == mem_rsp_dst_ptr);
	t_fwd_mem_mem_srcB = mem_rsp_dst_valid && (t_mem_dq.src_ptr == mem_rsp_dst_ptr);
     end
   
   always_ff@(posedge clk)
     begin
	r_fwd_int_mem_srcA <= t_fwd_int_mem_srcA;
	r_fwd_int_mem_srcB <= t_fwd_int_mem_srcB;
	r_fwd_int2_mem_srcA <= t_fwd_int2_mem_srcA;
	r_fwd_int2_mem_srcB <= t_fwd_int2_mem_srcB;
	
	r_fwd_mem_mem_srcA <= t_fwd_mem_mem_srcA;
	r_fwd_mem_mem_srcB <= t_fwd_mem_mem_srcB;
	
	r_fwd_int_srcA <= r_start_int && t_wr_int_prf && (t_picked_uop.srcA == int_uop.dst);
	r_fwd_int_srcB <= r_start_int && t_wr_int_prf && (t_picked_uop.srcB == int_uop.dst);
	r_fwd_int2_srcA <= r_start_int2 && t_wr_int_prf2 && (t_picked_uop.srcA == int_uop2.dst);
	r_fwd_int2_srcB <= r_start_int2 && t_wr_int_prf2 && (t_picked_uop.srcB == int_uop2.dst);

	r_fwd_int_srcA2 <= r_start_int && t_wr_int_prf && (t_picked_uop2.srcA == int_uop.dst);
	r_fwd_int_srcB2 <= r_start_int && t_wr_int_prf && (t_picked_uop2.srcB == int_uop.dst);
	r_fwd_int2_srcA2 <= r_start_int2 && t_wr_int_prf2 && (t_picked_uop2.srcA == int_uop2.dst);
	r_fwd_int2_srcB2 <= r_start_int2 && t_wr_int_prf2 && (t_picked_uop2.srcB == int_uop2.dst);
	
	
	r_fwd_mem_srcA <= mem_rsp_dst_valid && (t_picked_uop.srcA == mem_rsp_dst_ptr);
	r_fwd_mem_srcB <= mem_rsp_dst_valid && (t_picked_uop.srcB == mem_rsp_dst_ptr);
	r_fwd_mem_srcA2 <= mem_rsp_dst_valid && (t_picked_uop2.srcA == mem_rsp_dst_ptr);
	r_fwd_mem_srcB2 <= mem_rsp_dst_valid && (t_picked_uop2.srcB == mem_rsp_dst_ptr);	
     end

   // always@(negedge clk)
   //   begin
   // 	if(r_fwd_int2_srcA | r_fwd_int2_srcB)
   // 	  begin
   // 	     $display("need forward (1->2) %b, %b, int_uop.pc %x",
   // 		      r_fwd_int2_srcA, r_fwd_int2_srcB, int_uop.pc);
   // 	     //$stop();
   // 	  end
	
   // 	if(r_fwd_int_srcA2 | r_fwd_int_srcB2)
   // 	  begin
   // 	     $display("need forward (1->2) %b, %b, %x, %x, %x, %x, int_uop2.pc %x",
   // 		      r_fwd_int_srcA2, r_fwd_int_srcB2,
   // 		      t_srcA_2, t_srcB_2,
   // 		      w_srcA_2, w_srcB_2,
   // 		      int_uop2.pc);
   // 	     //$stop();
   // 	  end
	
   // 	if(r_fwd_int2_srcA2 | r_fwd_int2_srcB2)
   // 	  begin
   // 	     $display("need forward (2->2) %b, %b, int_uop2.pc %x",
   // 		      r_fwd_int2_srcA2, r_fwd_int2_srcB2, int_uop2.pc);
	     
   // 	      //   $stop();
   // 	   end	
   //   end
   
   
   // always_ff@(negedge clk)
   //   begin
	
   // 	$display("at cycle %d, mul ptr = %d %b, div ptr = %d %b, int_uop.dst %d", 
   // 		 r_cycle, 
   // 		 w_mul_prf_ptr, t_mul_complete,
   // 		 w_div_prf_ptr, t_div_complete,
   // 		 int_uop.dst);
   //   end
   

   rf6r3w #(.WIDTH(32), .LG_DEPTH(`LG_PRF_ENTRIES)) 
   intprf (.clk(clk),
	   .rdptr0(t_picked_uop.srcA),
	   .rdptr1(t_picked_uop.srcB),
	   .rdptr2(t_mem_uq.srcA),
	   .rdptr3(t_mem_dq.src_ptr),
	   .rdptr4(t_picked_uop2.srcA),
	   .rdptr5(t_picked_uop2.srcB),
	   .wrptr0(t_mul_complete ? w_mul_prf_ptr :
		   t_div_complete ? w_div_prf_ptr :
		   int_uop.dst),
	   .wrptr1(mem_rsp_dst_ptr),
	   .wrptr2(int_uop2.dst),
	   .wen0(t_mul_complete | t_div_complete | (r_start_int & t_wr_int_prf)),
	   .wen1(mem_rsp_dst_valid),
	   .wen2(r_start_int2 & t_wr_int_prf2),
	   .wr0(t_mul_complete ? t_mul_result[31:0] :
		t_div_complete ? t_div_result[31:0] :
		t_result),
	   .wr1(mem_rsp_load_data[31:0]),
	   .wr2(t_result2),
	   .rd0(w_srcA),
	   .rd1(w_srcB),
	   .rd2(w_mem_srcA),
	   .rd3(w_mem_srcB),
	   .rd4(w_srcA_2),
	   .rd5(w_srcB_2)
	   
	   );
   
   

   
   always_ff@(posedge clk)
     begin
	if(reset)
	  begin
	     complete_valid_1 <= 1'b0;
	     complete_valid_2 <= 1'b0;
	  end
	else
	  begin
	     complete_valid_1 <= r_start_int && t_alu_valid || t_mul_complete || t_div_complete;
	     complete_valid_2 <= r_start_int2;
	  end
     end // always_ff@ (posedge clk)

   always_ff@(posedge clk)
     begin
	complete_bundle_2.rob_ptr <= int_uop2.rob_ptr;
	complete_bundle_2.complete <= t_alu_valid2;
	complete_bundle_2.faulted <= t_mispred_br2;
	complete_bundle_2.restart_pc <= t_pc_2;
	complete_bundle_2.is_ii <= 'd0;
	complete_bundle_2.take_br <= t_take_br2;
	complete_bundle_2.data <= t_result2;
     end
     

   
   always_ff@(posedge clk)
     begin
	if(t_mul_complete || t_div_complete)
	  begin
	     complete_bundle_1.rob_ptr <= t_mul_complete ? 
					  t_rob_ptr_out : 
					  t_div_rob_ptr;
	     complete_bundle_1.complete <= 1'b1;
	     complete_bundle_1.faulted <= 1'b0;
	     complete_bundle_1.restart_pc <= 'd0;
	     complete_bundle_1.is_ii <= 1'b0;
	     complete_bundle_1.take_br <= 1'b0;
	     complete_bundle_1.data <= t_mul_complete ? 
				       t_mul_result[31:0] :
				       t_div_result[31:0];
	  end
	else
	  begin
	     complete_bundle_1.rob_ptr <= int_uop.rob_ptr;
	     complete_bundle_1.complete <= t_alu_valid;
	     complete_bundle_1.faulted <= t_mispred_br || t_unimp_op || t_fault;
	     complete_bundle_1.restart_pc <= t_pc;
	     complete_bundle_1.is_ii <= t_unimp_op;
	     complete_bundle_1.take_br <= t_take_br;
	     complete_bundle_1.data <= t_result;
	  end
	//(uq.rob_ptr == 'd5) ? 1'b1 : 1'b0;
     end


endmodule
