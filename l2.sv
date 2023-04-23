module l2(clk,
	  reset,
	  flush_req,
	  flush_complete,

	  //l1 -> l2
	  l1_mem_req_valid,
	  l1_mem_req_ack,
	  l1_mem_req_addr,
	  l1_mem_req_store_data,
	  l1_mem_req_opcode,

	  //l2 -> l1
	  l1_mem_rsp_valid,
	  l1_mem_load_data,

	  //l2 -> mem
	  mem_req_ack,
	  mem_req_valid, 
	  mem_req_addr, 
	  mem_req_store_data, 
	  mem_req_opcode,
	  
	  //mem -> l2
	  mem_rsp_valid,
	  mem_rsp_load_data
	  
	  );

   input logic clk;
   input logic reset;
   input logic flush_req;
   output logic flush_complete;

   input logic 	l1_mem_req_valid;
   output logic l1_mem_req_ack;
   input logic [31:0] l1_mem_req_addr;
   input logic [127:0] l1_mem_req_store_data;
   input logic [3:0]   l1_mem_req_opcode;

   output logic        l1_mem_rsp_valid;
   output logic [127:0] l1_mem_load_data;
   
   input logic 	mem_req_ack;
   output logic mem_req_valid;
   output logic [31:0] mem_req_addr;
   output logic [511:0] mem_req_store_data;
   output logic [3:0] 	mem_req_opcode;
   
   input logic 		mem_rsp_valid;
   input logic [511:0] 	mem_rsp_load_data;

   localparam LG_L2_LINES = 9;
   localparam L2_LINES = 1<<LG_L2_LINES;
   
   localparam TAG_BITS = 32 - (LG_L2_LINES + 6);

   logic 		t_wr_dirty, t_wr_valid;
   logic 		t_wr_d0, t_wr_d1, t_wr_d2, t_wr_d3, t_wr_tag;
   
   logic 		t_valid, t_dirty;
   logic [LG_L2_LINES-1:0] t_idx, r_idx;
   logic [TAG_BITS-1:0]    n_tag, r_tag;
   logic [1:0] 		 n_bank, r_bank;
   logic [31:0] 	 n_addr, r_addr;
   
   logic [3:0] 		   n_opcode, r_opcode;

   logic 		   r_mem_req, n_mem_req;
   logic [3:0] 		   r_mem_opcode, n_mem_opcode;
   logic 		   r_req_ack, n_req_ack;
   
   logic 		   r_rsp_valid, n_rsp_valid;
   logic [127:0] 	   r_rsp_data, n_rsp_data;
   logic [127:0] 	   r_store_data, n_store_data;
   
   logic 		   r_reload, n_reload;
   
   
   typedef enum 	logic [2:0] {
				     INITIALIZE,
				     IDLE,
				     WAIT_FOR_RAM,
				     CHECK_VALID_AND_TAG,
				     CLEAN_RELOAD,
				     WAIT_CLEAN_RELOAD,
				     WAIT_STORE_IDLE
				     } state_t;

   state_t n_state, r_state;
   logic 		n_flush_complete, r_flush_complete;
   logic 		r_flush_req, n_flush_req;
      

   assign flush_complete = r_flush_complete;
   assign mem_req_addr = r_addr;
   assign mem_req_valid = r_mem_req;
   assign mem_req_opcode = r_mem_opcode;
   assign l1_mem_rsp_valid = r_rsp_valid;
   assign l1_mem_load_data = r_rsp_data;
   assign l1_mem_req_ack = r_req_ack;
        
   logic [127:0] 	t_d0, t_d1, t_d2, t_d3;
      
   wire [127:0] 	w_d0, w_d1, w_d2, w_d3;
   wire [TAG_BITS-1:0] 	w_tag;
   wire 		w_valid, w_dirty;

   
   reg_ram1rw #(.WIDTH(128), .LG_DEPTH(LG_L2_LINES)) data_ram0
     (.clk(clk), .addr(t_idx), .wr_data(t_d0), .wr_en(t_wr_d0), .rd_data(w_d0));

   reg_ram1rw #(.WIDTH(128), .LG_DEPTH(LG_L2_LINES)) data_ram1
     (.clk(clk), .addr(t_idx), .wr_data(t_d1), .wr_en(t_wr_d1), .rd_data(w_d1));

   reg_ram1rw #(.WIDTH(128), .LG_DEPTH(LG_L2_LINES)) data_ram2
     (.clk(clk), .addr(t_idx), .wr_data(t_d2), .wr_en(t_wr_d2), .rd_data(w_d2));

   reg_ram1rw #(.WIDTH(128), .LG_DEPTH(LG_L2_LINES)) data_ram3
     (.clk(clk), .addr(t_idx), .wr_data(t_d3), .wr_en(t_wr_d3), .rd_data(w_d3));
      
   reg_ram1rw #(.WIDTH(TAG_BITS), .LG_DEPTH(LG_L2_LINES)) tag_ram
     (.clk(clk), .addr(t_idx), .wr_data(r_tag), .wr_en(t_wr_tag), .rd_data(w_tag));   
   
   reg_ram1rw #(.WIDTH(1), .LG_DEPTH(LG_L2_LINES)) valid_ram
     (.clk(clk), .addr(t_idx), .wr_data(t_valid), .wr_en(t_wr_valid), .rd_data(w_valid));   

   reg_ram1rw #(.WIDTH(1), .LG_DEPTH(LG_L2_LINES)) dirty_ram
     (.clk(clk), .addr(t_idx), .wr_data(t_dirty), .wr_en(t_wr_dirty), .rd_data(w_dirty));   

   wire 		w_hit = w_valid ? (r_tag == w_tag) : 1'b0;

   
   always_ff@(posedge clk)
     begin
	if(reset)
	  begin
	     r_state <= INITIALIZE;
	     r_flush_complete <= 1'b0;
	     r_idx <= 'd0;
	     r_tag <= 'd0;
	     r_bank <= 2'd0;
	     r_opcode <= 4'd0;
	     r_addr <= 'd0;
	     r_mem_req <= 1'b0;
	     r_mem_opcode <= 4'd0;
	     r_rsp_data <= 'd0;
	     r_rsp_valid <= 1'b0;
	     r_reload <= 1'b0;
	     r_req_ack <= 1'b0;
	     r_store_data <= 'd0;
	     r_flush_req <= 1'b0;
	  end
	else
	  begin
	     r_state <= n_state;
	     r_flush_complete <= n_flush_complete;
	     r_idx <= t_idx;
	     r_tag <= n_tag;
	     r_bank <= n_bank;
	     r_opcode <= n_opcode;
	     r_addr <= n_addr;
	     r_mem_req <= n_mem_req;
	     r_mem_opcode <= n_mem_opcode;
	     r_rsp_data <= n_rsp_data;
	     r_rsp_valid <= n_rsp_valid;
	     r_reload <= n_reload;
	     r_req_ack <= n_req_ack;
	     r_store_data <= n_store_data;
	     r_flush_req <= n_flush_req;
	  end
     end


   logic [31:0] r_cycle;
   always_ff@(posedge clk)
     begin
	r_cycle <= reset ? 'd0 : (r_cycle + 'd1);
     end

   always_ff@(negedge clk)
     begin
	if(r_state == IDLE && l1_mem_req_valid)
	  begin
	     $display("cycle %d : request for address %x", r_cycle, l1_mem_req_addr);
	     $display("tag = %x, index = %d, bank = %d", n_tag, t_idx, n_bank);
	  end
	if(r_state == CLEAN_RELOAD && mem_rsp_valid)
	  begin
	     $display("cycle %d : clean reload for address %x", r_cycle, r_addr);
	     $display("load data %x%x", 
		      mem_rsp_load_data[511:256],
		      mem_rsp_load_data[255:0]
		      );
	  end
	if(r_rsp_valid)
	  begin
	     $display("cycle %d : reply data : %x", r_cycle, r_rsp_data);
	  end
     end

   always_comb
     begin
	n_state = r_state;
	n_flush_complete = 1'b0;
	t_wr_valid = 1'b0;
	t_wr_dirty = 1'b0;
	t_wr_d0 = 1'b0;
	t_wr_d1 = 1'b0;
	t_wr_d2 = 1'b0;
	t_wr_d3 = 1'b0;
	t_wr_tag = 1'b0;
	
	t_idx = r_idx;
	n_tag = r_tag;
	n_bank = r_bank;
	n_opcode = r_opcode;
	n_addr = r_addr;

	n_req_ack = 1'b0;
	n_mem_req = r_mem_req;
	n_mem_opcode = r_mem_opcode;
		
	t_valid = 1'b0;
	t_dirty = 1'b0;

	t_d0 = mem_rsp_load_data[127:0];
	t_d1 = mem_rsp_load_data[255:128];
	t_d2 = mem_rsp_load_data[383:256];
	t_d3 = mem_rsp_load_data[511:384];

	n_rsp_data = r_rsp_data;
	n_rsp_valid = 1'b0;

	n_reload = r_reload;
	n_store_data = r_store_data;
	n_flush_req = flush_req | r_flush_req;
	
	case(r_state)
	  INITIALIZE:
	    begin
	       t_valid = 1'b0;
	       t_dirty = 1'b0;
	       
	       t_wr_valid = 1'b1;
	       t_wr_dirty = 1'b1;
	       
	       t_idx = r_idx + 'd1;
	       if(r_idx == (L2_LINES-1))
		 begin
		    n_state = IDLE;
		 end
	    end // case: INITIALIZE
	  IDLE:
	    begin
	       t_idx = l1_mem_req_addr[LG_L2_LINES+5:6];
	       n_tag = l1_mem_req_addr[31:LG_L2_LINES+6];
	       n_bank = l1_mem_req_addr[5:4];
	       n_addr = {l1_mem_req_addr[31:6], 6'd0};
	       n_opcode = l1_mem_req_opcode;
	       n_store_data = l1_mem_req_store_data;
	       
	       if(n_flush_req)
		 begin
		    $stop();
		 end
	       else if(l1_mem_req_valid)
		 begin
		    n_req_ack = 1'b1;
		    n_state = WAIT_FOR_RAM;
		 end
	    end
	  WAIT_FOR_RAM:
	    begin
	       n_state = CHECK_VALID_AND_TAG;
	    end
	
	  CHECK_VALID_AND_TAG:
	    begin
	       //load hit
	       if(w_hit)
		 begin
		    n_reload = 1'b0;
		    if(r_opcode == 4'd4)
		      begin
			 n_rsp_valid = 1'b1;
			 n_rsp_data = r_bank == 'd0 ? w_d0 :
				      r_bank == 'd1 ? w_d1 :
				      r_bank == 'd2 ? w_d2 :
				      w_d3;
			 n_state = IDLE;

		      end
		    else if(r_opcode == 4'd7)
		      begin
			 t_wr_dirty = 1'b1;
			 t_dirty = 1'b1;
			 n_state = WAIT_STORE_IDLE;			 
			 if(r_bank == 'd0)
			   begin
			      t_d0 = r_store_data;
			      t_wr_d0 = 1'b1;
			   end
			 else if(r_bank == 'd1)
			   begin
			      t_d1 = r_store_data;
			      t_wr_d1 = 1'b1;
			   end
			 else if(r_bank == 'd2)
			   begin
			      t_d2 = r_store_data;			      
			      t_wr_d2 = 1'b1;
			   end
			 else
			   begin
			      t_d3 = r_store_data;			      
			      t_wr_d3 = 1'b1;
			   end
		      end
		 end
	       else
		 begin
		    if(w_dirty)
		      begin
			 $stop();
		      end
		    else //invalid or clean
		      begin
			 if(r_reload)
			   $stop();
			 n_reload = 1'b1;
			 n_state = CLEAN_RELOAD;
			 n_mem_opcode = 4'd4; //load
			 n_mem_req = 1'b1;
		      end
		 end
	    end // case: CHECK_VALID_AND_TAG
	  CLEAN_RELOAD:
	    begin
	       if(mem_rsp_valid)
		 begin
		    n_mem_req = 1'b0;
		    t_valid = 1'b1;
		    t_wr_valid = 1'b1;
		    t_wr_tag = 1'b1;
		    t_wr_d0 = 1'b1;
		    t_wr_d1 = 1'b1;
		    t_wr_d2 = 1'b1;
		    t_wr_d3 = 1'b1;
		    n_state = WAIT_CLEAN_RELOAD;
		 end
	    end // case: CLEAN_RELOAD
	  WAIT_CLEAN_RELOAD: /* need a cycle to turn around */
	    begin
	       n_state = WAIT_FOR_RAM;
	    end
	  WAIT_STORE_IDLE:
	    begin
	       n_state = IDLE;
	    end
	  default:
	    begin
	    end
	endcase
     end
   
endmodule