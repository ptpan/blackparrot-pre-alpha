
module bp_fe_mem
 import bp_common_pkg::*;
 import bp_common_aviary_pkg::*;
 import bp_fe_pkg::*;
 import bp_common_rv64_pkg::*;
 #(parameter bp_params_e bp_params_p = e_bp_inv_cfg
   `declare_bp_proc_params(bp_params_p)
   `declare_bp_lce_cce_if_widths(cce_id_width_p, lce_id_width_p, paddr_width_p, lce_assoc_p, dword_width_p, cce_block_width_p)

   , localparam mem_cmd_width_lp  = `bp_fe_mem_cmd_width(vaddr_width_p, vtag_width_p, ptag_width_p)
   , localparam mem_resp_width_lp = `bp_fe_mem_resp_width

   , localparam cfg_bus_width_lp = `bp_cfg_bus_width(vaddr_width_p, core_id_width_p, cce_id_width_p, lce_id_width_p, cce_pc_width_p, cce_instr_width_p)
   )
  (input                                              clk_i
   , input                                            reset_i

   , input [cfg_bus_width_lp-1:0]                     cfg_bus_i

   , input [mem_cmd_width_lp-1:0]                     mem_cmd_i
   , input                                            mem_cmd_v_i
   , output                                           mem_cmd_yumi_o

   , input [rv64_priv_width_gp-1:0]                   mem_priv_i
   , input                                            mem_translation_en_i
   , input                                            mem_poison_i

   , output [mem_resp_width_lp-1:0]                   mem_resp_o
   , output                                           mem_resp_v_o
   , input                                            mem_resp_ready_i

   , output [lce_cce_req_width_lp-1:0]                lce_req_o
   , output                                           lce_req_v_o
   , input                                            lce_req_ready_i

   , input [lce_cmd_width_lp-1:0]                     lce_cmd_i
   , input                                            lce_cmd_v_i
   , output                                           lce_cmd_yumi_o

   , output [lce_cmd_width_lp-1:0]                    lce_cmd_o
   , output                                           lce_cmd_v_o
   , input                                            lce_cmd_ready_i

   , output [lce_cce_resp_width_lp-1:0]               lce_resp_o
   , output                                           lce_resp_v_o
   , input                                            lce_resp_ready_i
   );

`declare_bp_cfg_bus_s(vaddr_width_p, core_id_width_p, cce_id_width_p, lce_id_width_p, cce_pc_width_p, cce_instr_width_p);
`declare_bp_fe_mem_structs(vaddr_width_p, lce_sets_p, cce_block_width_p, vtag_width_p, ptag_width_p)

bp_cfg_bus_s cfg_bus_cast_i;
bp_fe_mem_cmd_s  mem_cmd_cast_i;
bp_fe_mem_resp_s mem_resp_cast_o;

assign cfg_bus_cast_i = cfg_bus_i;
assign mem_cmd_cast_i = mem_cmd_i;
assign mem_resp_o     = mem_resp_cast_o;

logic instr_page_fault_lo, instr_access_fault_lo, icache_miss_lo, itlb_miss_lo;
logic icache_ready_lo;

wire itlb_fence_v = mem_cmd_v_i & (mem_cmd_cast_i.op == e_fe_op_tlb_fence);
wire itlb_fill_v  = mem_cmd_v_i & (mem_cmd_cast_i.op == e_fe_op_tlb_fill);
wire fetch_v      = mem_cmd_v_i & (mem_cmd_cast_i.op == e_fe_op_fetch) & icache_ready_lo;

bp_fe_tlb_entry_s itlb_r_entry;
logic itlb_r_v_lo;
bp_tlb
 #(.bp_params_p(bp_params_p), .tlb_els_p(itlb_els_p))
 itlb
  (.clk_i(clk_i)
   ,.reset_i(reset_i)
   ,.flush_i(itlb_fence_v)
   ,.translation_en_i(mem_translation_en_i)
         
   ,.v_i(fetch_v | itlb_fill_v)
   ,.w_i(itlb_fill_v)
   ,.vtag_i(itlb_fill_v ? mem_cmd_cast_i.operands.fill.vtag : mem_cmd_cast_i.operands.fetch.vaddr.tag)
   ,.entry_i(mem_cmd_cast_i.operands.fill.entry)
     
   ,.v_o(itlb_r_v_lo)
   ,.entry_o(itlb_r_entry)

   ,.miss_v_o(itlb_miss_lo)
   ,.miss_vtag_o()
   );

wire [ptag_width_p-1:0] ptag_li     = itlb_r_entry.ptag;
wire                    ptag_v_li   = itlb_r_v_lo;

logic uncached_li;
bp_pma
 #(.bp_params_p(bp_params_p))
 pma
  (.ptag_v_i(ptag_v_li)
   ,.ptag_i(ptag_li)

   ,.uncached_o(uncached_li)
   );

logic [instr_width_p-1:0] icache_data_lo;
logic                     icache_data_v_lo;
bp_fe_icache 
 #(.bp_params_p(bp_params_p)) 
 icache
  (.clk_i(clk_i)
   ,.reset_i(reset_i)

   ,.cfg_bus_i(cfg_bus_i)

   ,.vaddr_i(mem_cmd_cast_i.operands.fetch.vaddr)
   ,.vaddr_v_i(fetch_v)
   ,.vaddr_ready_o(icache_ready_lo)

   ,.uncached_i(uncached_li)
   ,.ptag_i(ptag_li)
   ,.ptag_v_i(ptag_v_li)
   ,.poison_i(mem_poison_i)

   ,.data_o(icache_data_lo)
   ,.data_v_o(icache_data_v_lo)
   ,.cache_miss_o(icache_miss_lo)
  
   ,.lce_req_o(lce_req_o)
   ,.lce_req_v_o(lce_req_v_o)
   ,.lce_req_ready_i(lce_req_ready_i)
         
   ,.lce_cmd_i(lce_cmd_i)
   ,.lce_cmd_v_i(lce_cmd_v_i)
   ,.lce_cmd_yumi_o(lce_cmd_yumi_o)
         
   ,.lce_cmd_o(lce_cmd_o)
   ,.lce_cmd_v_o(lce_cmd_v_o)
   ,.lce_cmd_ready_i(lce_cmd_ready_i)

   ,.lce_resp_o(lce_resp_o)
   ,.lce_resp_v_o(lce_resp_v_o)
   ,.lce_resp_ready_i(lce_resp_ready_i)
   );

assign mem_cmd_yumi_o = itlb_fence_v | itlb_fill_v | fetch_v;

logic fetch_v_r, fetch_v_rr;
logic itlb_miss_r;
logic instr_access_fault_v, instr_access_fault_r, instr_access_err_v, instr_page_fault_r;
always_ff @(posedge clk_i)
  begin
    if(reset_i) begin
      itlb_miss_r <= '0;
      fetch_v_r   <= '0;
      fetch_v_rr  <= '0;

      instr_access_fault_r <= '0;
      instr_page_fault_r   <= '0;
    end
    else begin
      fetch_v_r   <= fetch_v;
      fetch_v_rr  <= fetch_v_r & ~mem_poison_i;
      itlb_miss_r <= itlb_miss_lo & ~mem_poison_i;

      instr_access_fault_r <= instr_access_fault_v & ~mem_poison_i;
      instr_page_fault_r   <= instr_access_err_v & ~mem_poison_i;
    end
  end

wire instr_priv_access_fault = ((mem_priv_i == `PRIV_MODE_S) & itlb_r_entry.u)
                               | ((mem_priv_i == `PRIV_MODE_U) & ~itlb_r_entry.u);
wire instr_exe_access_fault = ~itlb_r_entry.x;

wire is_uncached_mode = (cfg_bus_cast_i.icache_mode == e_lce_mode_uncached);
assign instr_access_fault_v = is_uncached_mode & ~uncached_li;
assign instr_access_err_v  = fetch_v_r & itlb_r_v_lo & mem_translation_en_i & (instr_priv_access_fault | instr_exe_access_fault);

wire unused = &{mem_resp_ready_i};

assign mem_resp_v_o    = fetch_v_rr;
assign mem_resp_cast_o = '{instr_access_fault: instr_access_fault_r
                           ,instr_page_fault : instr_page_fault_r
                           ,itlb_miss        : itlb_miss_r
                           ,icache_miss      : fetch_v_rr & ~icache_data_v_lo
                           ,data             : icache_data_lo
                           };

endmodule
