module top(
    input  logic clk, reset,
    output logic slti_sig
);
    logic [31:0] pc, instr;
    
    // --- New 128-bit Interconnect Wires ---
    logic         mem_valid;
    logic         mem_rw;
    logic [31:0]  mem_addr;
    logic [127:0] mem_writedata;
    logic [127:0] mem_readdata;
    logic         mem_ready;

    // Instantiate Processor
    mips mips(
        .clk(clk), .reset(reset), 
        .pc(pc), .instr(instr), 
        .mem_valid(mem_valid), .mem_rw(mem_rw), 
        .mem_addr(mem_addr), .mem_writedata(mem_writedata), 
        .mem_readdata(mem_readdata), .mem_ready(mem_ready), 
        .slti_sig(slti_sig)
    );
    
    // Instantiate Instruction Memory (Still Magic/0-cycle)
    imem imem(pc[9:2], instr);
    
    // Instantiate Data Memory (Now 128-bit with latency)
    dmem dmem(
        .clk(clk),
        .reset(reset),
        .mem_valid(mem_valid),
        .mem_rw(mem_rw),
        .mem_addr(mem_addr),
        .mem_writedata(mem_writedata),
        .mem_readdata(mem_readdata),
        .mem_ready(mem_ready)
    );
endmodule

module mips(
    input  logic         clk, reset,
    output logic [31:0]  pc,
    input  logic [31:0]  instr,
    
    // --- New 128-bit Memory Interface ---
    output logic         mem_valid,
    output logic         mem_rw,
    output logic [31:0]  mem_addr,
    output logic [127:0] mem_writedata,
    input  logic [127:0] mem_readdata,
    input  logic         mem_ready,
    
    output logic         slti_sig
);
    // (Internal controller wires remain the same)
    logic memtoreg, alusrc, regdst, regwrite, jump, pcsrc, zero;
    logic [2:0] alucontrol;
    
    datapath dp(
        .clk(clk), .reset(reset), 
        .pc_F(pc), .instr_F(instr), 
        
        // Connect Datapath ports to MIPS ports
        .mem_valid(mem_valid),
        .mem_rw(mem_rw),
        .mem_addr(mem_addr),
        .mem_writedata(mem_writedata),
        .mem_readdata(mem_readdata),
        .mem_ready(mem_ready)
        
        // slti_sig is missing from your dp instantiation in your code! 
        // Assuming it's still needed:
        // .slti_sig(slti_sig) 
    );
endmodule

module controller(input logic[5:0]op,funct,
        input logic zero,
        output logic memtoreg,memwrite,
        output logic pcsrc,alusrc,
        output logic regdst,regwrite,
        output logic jump, branch,
        output logic[2:0]alucontrol, output logic slti_sig,
        output logic vregwrite, vmemtoreg, v_req
        );
        logic[2:0]aluop;

        maindec md(op,memtoreg,memwrite,branch,
        alusrc,regdst,regwrite,jump,aluop, slti_sig, vregwrite, vmemtoreg, v_req);
        aludec ad(funct,aluop,alucontrol);
        assign pcsrc = branch&zero;
endmodule

module maindec(input logic[5:0]op,
    output logic memtoreg,memwrite,
    output logic branch,alusrc,
    output logic regdst,regwrite,
    output logic jump,
    output logic[2:0]aluop, output logic slti_sig,
    output logic vregwrite, vmemtoreg, v_req
    );
    logic[12:0] controls;
    assign{regwrite,regdst,alusrc,branch,memwrite,
    memtoreg,jump,aluop, vregwrite, vmemtoreg, v_req}=controls;

    assign slti_sig = (op == 6'b001010);
    always_comb
    case(op)
        6'b000000: controls = 13'b1100000010_000; // RTYPE 
        6'b100011: controls = 13'b1010010000_000; // LW    
        6'b101011: controls = 13'b0010100000_000; // SW    
        6'b000100: controls = 13'b0001000001_000; // BEQ   
        6'b001000: controls = 13'b1010000000_000; // ADDI  
        6'b000010: controls = 13'b0000001000_000; // J     
        6'b001010: controls = 13'b1010000011_000; // slti
        // --- SIMD INSTRUCTIONS ---
        6'b010000: controls = 13'b0100000010_100; // V-RTYPE (vadd/vsub)
        6'b110011: controls = 13'b0010000000_111; // VLW
        6'b111011: controls = 13'b0010100000_001; // VSW (Note: Scalar memwrite=1 to trigger cache, v_req=1)
        default:   controls = 13'b0000000000_000;

    endcase
endmodule

module alu(
    input  logic [31:0] a, b,
    input  logic [2:0]  alucontrol,
    output logic [31:0] result,
    output logic        zero
);
    always_comb begin
        case(alucontrol)
            3'b000: result = a & b;
            3'b001: result = a | b;
            3'b010: result = a + b;
            3'b110: result = a - b;
            3'b111: result = ($signed(a) < $signed(b)) ? 32'b1 : 32'b0; // slt/slti
            default: result = 32'b0;
        endcase
    end
    
    assign zero = (result == 32'b0);
endmodule

module valu(
    input logic [127:0] a, b,
    input logic [2:0] valucontrol,
    output logic [127:0] result
);

// --- 1. Slicing the 128-bit buses into 4 individual 32-bit lanes ---
    logic [31:0] a3, a2, a1, a0;
    logic [31:0] b3, b2, b1, b0;
    logic [31:0] res3, res2, res1, res0;

    // Unpack the 128-bit inputs
    assign {a3, a2, a1, a0} = a;
    assign {b3, b2, b1, b0} = b;
    
    // Pack the 128-bit output
    assign result = {res3, res2, res1, res0};
    
// --- 2. The Parallel Execution Engine ---
    always_comb begin
        case(valucontrol)
            3'b000: begin // Vector AND (vand)
                res0 = a0 & b0;
                res1 = a1 & b1;
                res2 = a2 & b2;
                res3 = a3 & b3;
            end
            3'b001: begin // Vector OR (vor)
                res0 = a0 | b0;
                res1 = a1 | b1;
                res2 = a2 | b2;
                res3 = a3 | b3;
            end
            3'b010: begin // Vector ADD (vadd)
                res0 = a0 + b0;
                res1 = a1 + b1;
                res2 = a2 + b2;
                res3 = a3 + b3;
            end
            3'b110: begin // Vector SUB (vsub)
                res0 = a0 - b0;
                res1 = a1 - b1;
                res2 = a2 - b2;
                res3 = a3 - b3;
            end
            default: begin // Default to 0 to prevent 'X' cascades
                res0 = 32'b0;
                res1 = 32'b0;
                res2 = 32'b0;
                res3 = 32'b0;
            end
        endcase
    end

endmodule

module aludec(input logic[5:0] funct,
              input logic[2:0] aluop,
              output logic[2:0] alucontrol);
    always_comb
    case(aluop)
        3'b000: alucontrol = 3'b010; // add (for lw/sw/addi)
        3'b001: alucontrol = 3'b110; // sub (for beq)
        3'b011: alucontrol = 3'b111; // slti[cite: 1]
        3'b010: case(funct)          // R-type instructions[cite: 1]
            6'b100000: alucontrol = 3'b010; // add[cite: 1]
            6'b100010: alucontrol = 3'b110; // sub[cite: 1]
            6'b100100: alucontrol = 3'b000; // and[cite: 1]
            6'b100101: alucontrol = 3'b001; // or[cite: 1]
            6'b101010: alucontrol = 3'b111; // slt[cite: 1]
            default:   alucontrol = 3'b010; 
        endcase
        default: alucontrol = 3'b010;
    endcase
endmodule

module datapath(
    input  logic        clk, reset,
    output logic [31:0] pc_F,
    input  logic [31:0] instr_F,
    // --- Main Memory Interface (from L1 Cache) ---
    output logic         mem_valid,
    output logic         mem_rw,
    output logic [31:0]  mem_addr,
    output logic [127:0] mem_writedata,
    input  logic [127:0] mem_readdata,
    input  logic         mem_ready
);

    logic regwrite_W;
    logic [31:0] result_W;
    logic [4:0]  writereg_W;
    // =========================================================================
    // VECTOR SIMD DATAPATH WIRES (Must declare before using in pipeline regs!)
    // =========================================================================
    // Decode Wires
    logic vregwrite_D, vmemtoreg_D, v_req_D;
    logic [127:0] vsrca_D, vsrcb_D;
    // Execute Wires
    logic vregwrite_E, vmemtoreg_E, v_req_E;
    logic [127:0] vsrca_E, vsrcb_E, valuout_E;
    // Memory Wires
    logic vregwrite_M, vmemtoreg_M, v_req_M;
    logic [127:0] valuout_M, vwritedata_M, vcpu_readdata_M;
    // Writeback Wires
    logic vregwrite_W, vmemtoreg_W;
    logic [127:0] valuout_W, vcpu_readdata_W, vresult_W;

//~~~~~~~~~~~Fetch Stage~~~~~~~~~~~~
    logic [31:0] pcplus4_F, pcnext_F, pcnextbr_F;

    //nextPC logic
    flopenrc #(32) pcreg (
        .clk(clk),         // The system clock
        .reset(reset),     // The system reset
        .en(~stall_F & ~cache_stall),         // Enable pin if stall is high don't enable
        .clear(1'b0),      // Clear pin (tied low for now)
        .d(pcnext_F),      // Data IN (the next address)
        .q(pc_F)           // Data OUT (the current address)
    );
    adder pcadd1(.a(pc_F), .b(32'h4), .y(pcplus4_F));   //takes pc, outputs pc+4

    mux2#(32) pcbrmux(
        .d0(pcplus4_F), 
        .d1(pcbranch_D), // Target calculated in Decode
        .s(pcsrc_D),     // Decision made in Decode
        .y(pcnextbr_F)
    );

    mux2#(32) pcmux(
        .d0(pcnextbr_F), 
        .d1({pcplus4_D[31:28], instr_D[25:0], 2'b00}), // Jump target from Decode
        .s(jump_D),      // Signal from Decode Controller
        .y(pcnext_F)
    );

    //IF/ID pipeline registers
    // This creates a physical 64-bit barrier separating Fetch from Decode
    flopenrc #(64) if_id_reg (
        .clk(clk), .reset(reset),
        .en(~stall_D & ~cache_stall),   // 
        .clear(flush_D & ~cache_stall), // For now, tie to 0.
        .d({instr_F, pcplus4_F}),
        .q({instr_D, pcplus4_D})
    );

//~~~~~~~~~~~~~Decode Stage~~~~~~~~~~~~
    //for ID stage
    logic [31:0] pcbranch_D, signimmsh_D, pcjump_D, signimm_D;
    logic [31:0] srca_D, srcb_D; 
    logic pcsrc_D;
    logic regwrite_D, memtoreg_D, memwrite_D, branch_D, alusrc_D, regdst_D, jump_D;
    logic [2:0] alucontrol_D;
    logic [31:0] instr_D, pcplus4_D;

    // Declarations for Execute stage (must be 32-bit for data!)
    logic [31:0] srca_E, srcb_E, signimm_E;
    logic [4:0]  rs_E, rt_E, rd_E;
    logic regwrite_E, memtoreg_E, memwrite_E, alusrc_E, regdst_E;
    logic [2:0]  alucontrol_E;


    controller c (
        .op(instr_D[31:26]), 
        .funct(instr_D[5:0]), 
        .zero(1'b0), // Tied to 0 for now, handled differently in pipeline
        .memtoreg(memtoreg_D), 
        .memwrite(memwrite_D), 
        .pcsrc(),    // We will generate branch logic later
        .alusrc(alusrc_D), 
        .regdst(regdst_D), 
        .regwrite(regwrite_D), 
        .jump(jump_D),
        .branch(branch_D),
        .alucontrol(alucontrol_D),
        .slti_sig(),  // Assuming you are keeping this custom signal
        .vregwrite(vregwrite_D), 
        .vmemtoreg(vmemtoreg_D), 
        .v_req(v_req_D)
    );

    //register file logic
    regfile rf(
        .clk(clk), .we3(regwrite_W), 
        .ra1(instr_D[25:21]), .ra2(instr_D[20:16]), 
        .wa3(writereg_W), .wd3(result_W), 
        .rd1(srca_D), .rd2(srcb_D)
    );

    // Vector Register File Logic
    vregfile vrf(
        .clk(clk), 
        .we3(vregwrite_W), 
        .ra1(instr_D[25:21]), // Uses same instruction fields as scalar
        .ra2(instr_D[20:16]), 
        .wa3(writereg_W), 
        .wd3(vresult_W), 
        .rd1(vsrca_D), 
        .rd2(vsrcb_D)
    );
    //mux2#(5) wrmux(instr_D[20:16],instr_D[15:11], regdst, writereg);
    // mux2#(32) resmux(aluout, readdata, memtoreg, result);
    signext se(instr_D[15:0],signimm_D);

    sl2 immsh_D(.a(signimm_D), .y(signimmsh_D));
    // Calculate Branch Target: PC+4 (from Decode) + Shifted Immediate
    adder pcadd2_D(.a(pcplus4_D), .b(signimmsh_D), .y(pcbranch_D));
    // Calculate Jump Target
    assign pcjump_D = {pcplus4_D[31:28], instr_D[25:0], 2'b00};
    logic [31:0] srca_forwarded_D, srcb_forwarded_D;
    
    assign srca_forwarded_D = forwarda_D ? aluout_M : srca_D;
    assign srcb_forwarded_D = forwardb_D ? aluout_M : srcb_D;

    assign pcsrc_D = branch_D & (srca_forwarded_D == srcb_forwarded_D);

    //ID/EX Register
    //Barrier between Decode and Execute
    flopenrc#(119) id_ex_reg(
        .clk(clk), 
        .reset(reset),
        .en(~cache_stall),     // 
        .clear(flush_E & ~cache_stall),  // 
        
        // Bundle all the Decode (D) wires together
        .d({ srca_D, srcb_D, signimm_D, instr_D[25:21], instr_D[20:16], instr_D[15:11],
             regwrite_D, memtoreg_D, memwrite_D, alusrc_D, regdst_D, alucontrol_D }),
             
        // Unbundle them into the Execute (E) wires
        .q({ srca_E, srcb_E, signimm_E, rs_E, rt_E, rd_E,
             regwrite_E, memtoreg_E, memwrite_E, alusrc_E, regdst_E, alucontrol_E })
    );
    //Vector register
    flopenrc#(259) id_ex_vreg(
        .clk(clk), 
        .reset(reset),
        .en(~cache_stall),
        .clear(flush_E & ~cache_stall),
        .d({vregwrite_D, vmemtoreg_D, v_req_D, vsrca_D, vsrcb_D}),
        .q({vregwrite_E, vmemtoreg_E, v_req_E, vsrca_E, vsrcb_E})
    );
    

//~~~~~~~~~~HAZARD UNIT~~~~~~~~~~~~~~~~
    // Hazard Unit Wires
    logic stall_F, stall_D, flush_E, flush_D;
    logic forwarda_D, forwardb_D;
    logic [1:0] forwarda_E, forwardb_E;

    hazard hu (
        .rs_D(instr_D[25:21]), .rt_D(instr_D[20:16]), .rs_E(rs_E), .rt_E(rt_E),
        .writereg_E(writereg_E), .writereg_M(writereg_M), .writereg_W(writereg_W),
        .regwrite_E(regwrite_E), .regwrite_M(regwrite_M), .regwrite_W(regwrite_W),
        .memtoreg_E(memtoreg_E), .memtoreg_M(memtoreg_M), .branch_D(branch_D),
        .pcsrc_D(pcsrc_D), .jump_D(jump_D),
        .stall_F(stall_F), .stall_D(stall_D), .flush_E(flush_E), .flush_D(flush_D),
        .forwarda_D(forwarda_D), .forwardb_D(forwardb_D),
        .forwarda_E(forwarda_E), .forwardb_E(forwardb_E)
    );

//~~~~~~~~~~~~Execute Stage~~~~~~~~~~

    //ALUlogic
    logic [31:0] srcb_alu_E; // Wire connecting Mux to ALU
    logic [31:0] aluout_E;
    logic zero_E;

    logic regwrite_M, memtoreg_M, memwrite_M;
    logic [31:0] aluout_M, writedata_M;
    logic [4:0] writereg_M;

    logic [31:0] srca_forwarded_E, srcb_forwarded_E;
    
    //Forwarding mux for source A
    always_comb begin
        case(forwarda_E)
            2'b00: srca_forwarded_E = srca_E;
            2'b01: srca_forwarded_E = result_W; // Forward from Writeback
            2'b10: srca_forwarded_E = aluout_M; // Forward from Memory
            default: srca_forwarded_E = 32'bx;
        endcase
    end

    // Forwarding Mux for Source B
    always_comb begin
        case(forwardb_E)
            2'b00: srcb_forwarded_E = srcb_E;
            2'b01: srcb_forwarded_E = result_W; // Forward from Writeback
            2'b10: srcb_forwarded_E = aluout_M; // Forward from Memory
            default: srcb_forwarded_E = 32'bx;
        endcase
    end

    mux2 #(32) srcbmux (
        .d0(srcb_forwarded_E), 
        .d1(signimm_E), 
        .s(alusrc_E), 
        .y(srcb_alu_E)
    );
    alu main_alu (
        .a(srca_forwarded_E),           //Solder datapath wire 'srca_E' to ALU pin 'a'
        .b(srcb_alu_E),           //Solder datapath wire 'srcb_E' to ALU pin 'b'
        .alucontrol(alucontrol_E), 
        .result(aluout_E),    
        .zero(zero_E)         
    );
    valu vector_alu (
        .a(vsrca_E),
        .b(vsrcb_E),
        .valucontrol(alucontrol_E), // Re-use the scalar control signals
        .result(valuout_E)
    );

    logic [4:0] writereg_E;
    mux2 #(5) wrmux (
        .d0(rt_E), 
        .d1(rd_E), 
        .s(regdst_E), 
        .y(writereg_E)
    );

    flopenrc#(72) ex_mem_reg(
        .clk(clk),
        .reset(reset),
        .en(~cache_stall),
        .clear(1'b0),

        .d({regwrite_E, memtoreg_E, memwrite_E, aluout_E, srcb_forwarded_E, writereg_E}),
        .q({regwrite_M, memtoreg_M, memwrite_M, aluout_M, writedata_M, writereg_M})
    );
    // Forward Vector Data and Controls to Memory
    flopenrc#(259) ex_mem_vreg(
        .clk(clk),
        .reset(reset),
        .en(~cache_stall),
        .clear(1'b0),
        .d({vregwrite_E, vmemtoreg_E, v_req_E, valuout_E, vsrcb_E}),
        .q({vregwrite_M, vmemtoreg_M, v_req_M, valuout_M, vwritedata_M})
    );


//~~~~~~~ --- Cache Control Wires ---~~~~~~
    logic cpu_valid;
    logic cpu_ready;
    logic cache_stall;
    
    // The CPU is requesting memory if it is executing a load (memtoreg) or store (memwrite)
    assign cpu_valid = memtoreg_M | memwrite_M | v_req_M; 
    // Only freeze the pipeline if a memory request is active AND the cache is busy
    assign cache_stall = cpu_valid & ~cpu_ready;

//~~~~~~~~~~~Memory Stage~~~~~~~~~~~~~~~~

    logic [31:0] cpu_readdata_M;    //write from cache to MEM/WB register
    // --- INTERCONNECT WIRES (L1 to L2 Bus) ---
    // These replace the direct connection to Main Memory
    logic         l2_valid;
    logic         l2_rw;
    logic [31:0]  l2_addr;
    logic [127:0] l2_writedata;
    logic [127:0] l2_readdata;
    logic         l2_ready;


    // 1. The L1 Cache (Talks to CPU and L2)
    l1_cache d_cache(
        .clk(clk),
        .reset(reset),
        
        // --- CPU Interface ---
        .cpu_valid(cpu_valid),
        .cpu_rw(memwrite_M),         // 1 if Store, 0 if Load
        .cpu_addr(aluout_M),         // Address calculated by ALU
        .cpu_writedata(writedata_M), // Data to store
        .cpu_readdata(cpu_readdata_M),// Fetched data going to Writeback
        .cpu_ready(cpu_ready),       // Controls the cache_stall signal

        // --- Vector Interface ---
        .v_req(v_req_M),
        .vcpu_writedata(vwritedata_M), // From Vector Register File via EX stage
        .vcpu_readdata(vcpu_readdata_M),// 128-bit data loaded from memory
        
        // --- Main Memory Interface (Routes out of Datapath) ---
        .mem_valid(l2_valid),
        .mem_rw(l2_rw),
        .mem_addr(l2_addr),
        .mem_writedata(l2_writedata),
        .mem_readdata(l2_readdata),
        .mem_ready(l2_ready)
    );

    // 2. The L2 Cache (Talks to L1 and Main Memory)
    l2_cache shared_l2(
        .clk(clk),
        .reset(reset),
        
        // --- L1 Interface (L2's "CPU") ---
        .l1_valid(l2_valid),
        .l1_rw(l2_rw),
        .l1_addr(l2_addr),
        .l1_writedata(l2_writedata),
        .l1_readdata(l2_readdata),
        .l1_ready(l2_ready),

        // --- Main Memory Interface (Routes out of Datapath) ---
        .mem_valid(mem_valid),
        .mem_rw(mem_rw),
        .mem_addr(mem_addr),
        .mem_writedata(mem_writedata),
        .mem_readdata(mem_readdata),
        .mem_ready(mem_ready)
    );


    flopenrc #(71) mem_wb_reg(
        .clk(clk),
        .reset(reset),
        .en(~cache_stall),
        .clear(1'b0),

        .d({regwrite_M, memtoreg_M, cpu_readdata_M, aluout_M, writereg_M}),
        .q({regwrite_W, memtoreg_W, readdata_W, aluout_W, writereg_W})
    );

    logic memtoreg_W;
    logic [31:0] aluout_W, readdata_W;
    
    // Forward Vector Data to Writeback
    flopenrc#(258) mem_wb_vreg(
        .clk(clk),
        .reset(reset),
        .en(~cache_stall),
        .clear(1'b0),
        .d({vregwrite_M, vmemtoreg_M, vcpu_readdata_M, valuout_M}),
        .q({vregwrite_W, vmemtoreg_W, vcpu_readdata_W, valuout_W})
    );

    // Vector Writeback Multiplexer (routes back to vregfile wd3)
    assign vresult_W = (vmemtoreg_W) ? vcpu_readdata_W : valuout_W;

//~~~~~~~~~~~Writeback Stage~~~~~~~~~~~~

    mux2 #(32) resmux (
        .d0(aluout_W), 
        .d1(readdata_W), 
        .s(memtoreg_W), 
        .y(result_W)
    );

endmodule

module hazard(
    input  logic [4:0] rs_D, rt_D, rs_E, rt_E,
    input  logic [4:0] writereg_E, writereg_M, writereg_W,
    input  logic regwrite_E, regwrite_M, regwrite_W, 
    input  logic memtoreg_E, memtoreg_M, branch_D,
    input logic pcsrc_D, jump_D, 
    
    // 2. The Switches (Outputs)
    output logic stall_F, stall_D, forwarda_D, forwardb_D, flush_E, flush_D, 
    output logic [1:0] forwarda_E, forwardb_E
);
    logic lwstall, branchstall;

    always_comb begin
        // --- Forward A logic ---
        //Execute Stage
        // Condition 1: Forward from Memory Stage
        if ((rs_E != 0) && (rs_E == writereg_M) && regwrite_M)
            forwarda_E = 2'b10; 
            
        // Condition 2: Forward from Writeback Stage
        else if ((rs_E != 0) && (rs_E == writereg_W) && regwrite_W)
            forwarda_E = 2'b01; 
            
        // Condition 3: No Hazard
        else
            forwarda_E = 2'b00;

        //Decode Stage
        // Condition 1:
        if((rs_D != 0) && (rs_D == writereg_M) && regwrite_M)
            forwarda_D = 1'b1;
        else 
            forwarda_D = 1'b0;

        // --- Forward B logic ---
        //Execute Stage
        if ((rt_E != 0) && (rt_E == writereg_M) && regwrite_M)
            forwardb_E = 2'b10;
        else if ((rt_E != 0) && (rt_E == writereg_W) && regwrite_W)
            forwardb_E = 2'b01;
        else
            forwardb_E = 2'b00;

        //Decode Stage
        if((rt_D != 0) && (rt_D == writereg_M) && regwrite_M)
            forwardb_D = 1'b1;
        else 
            forwardb_D = 1'b0;

        //STALLING
        lwstall = (rs_D == writereg_E || rt_D == writereg_E) && memtoreg_E;
        branchstall = branch_D && regwrite_E && (writereg_E == rs_D || writereg_E == rt_D)
                ||
            (branch_D && memtoreg_M && (writereg_M == rs_D || writereg_M == rt_D));

        if(lwstall || branchstall) begin
            stall_F = 1'b1;
            stall_D = 1'b1;
            flush_E = 1'b1;
        end
        else begin
            stall_F = 1'b0;
            stall_D = 1'b0;
            flush_E = 1'b0;
        end

        //FLUSH LOGIC
        if ((pcsrc_D || jump_D) && !stall_D) begin
            flush_D = 1'b1;
        end else begin
            flush_D = 1'b0;
        end
    end

endmodule

module regfile(input logic clk,
    input logic we3,
    input logic[4:0] ra1,ra2,wa3,
    input logic[31:0]wd3,
    output logic[31:0]rd1,rd2);
    logic[31:0]rf[31:0];
    integer i;
    initial begin
        for(i=0; i<32; i++) rf[i] = 32'b0;
    end
    //three ported register file
    //read two ports combinationally
    //write third port on rising edge of clk
    //register 0 hardwired to 0
    //note: for pipelined processor, write third port
    //on falling edge of clk
    always_ff@(negedge clk)
    if(we3)rf[wa3]<=wd3;
    assign rd1=(ra1!=0)?rf[ra1]:0;
    assign rd2=(ra2!=0)?rf[ra2]:0;
endmodule

module vregfile(
    input  logic         clk,
    input  logic         we3,           // Write Enable
    input  logic [4:0]   ra1, ra2, wa3, // 5-bit addresses for 32 registers
    input  logic [127:0] wd3,           // 128-bit write data (Four 32-bit lanes)
    output logic [127:0] rd1, rd2       // 128-bit read data
);
    logic [127:0] vrf[31:0];
    integer i;
    initial begin
        for(i=0; i<32; i++) vrf[i] = 128'b0;
    end
    //three ported register file
    //read two ports combinationally
    //write third port
    //on falling edge of clk
    always_ff @(posedge clk) begin
        if (we3) begin
            vrf[wa3] <= wd3;
        end
    end
    assign rd1 = vrf[ra1];
    assign rd2 = vrf[ra2];
endmodule

module l1_cache (
    input  logic        clk, reset,
    
    // --- CPU to Cache Interface ---
    input  logic        cpu_valid,    // 1 = CPU is requesting memory
    input  logic        cpu_rw,       // 0 = Read, 1 = Write
    input  logic [31:0] cpu_addr,     // Address from CPU
    input  logic [31:0] cpu_writedata,// 32-bit data to store
    output logic [31:0] cpu_readdata, // 32-bit data to CPU
    output logic        cpu_ready,    // 1 = Cache is done (Inverts your pipeline stall!)

    // --- VECTOR CPU Interface ---
    input  logic         v_req,         // 1 = This is a vector load/store
    input  logic [127:0] vcpu_writedata,
    output logic [127:0] vcpu_readdata,

    // --- L1 Cache to L2 Cache Interface ---
    output logic        mem_valid,    // 1 = Cache is asking RAM for data
    output logic        mem_rw,       // 0 = Read, 1 = Write to RAM
    output logic [31:0] mem_addr,     // Address to RAM
    output logic [127:0] mem_writedata,// 128-bit block to RAM (Eviction)
    input  logic [127:0] mem_readdata, // 128-bit block from RAM
    input  logic        mem_ready     // 1 = RAM is done
);

    // Cache parameters (e.g., 64 blocks)
    parameter SETS = 64; 

    // The Three Cache Arrays
    logic        valid_array [SETS-1:0];
    logic        dirty_array [SETS-1:0];
    logic [21:0] tag_array   [SETS-1:0]; // Top bits of address
    logic [127:0] data_array  [SETS-1:0]; // The actual data

    // Break the 32-bit CPU address into its components
    // Assuming 32-bit words, byte addressable:
    // Offset = bits [1:0] (Byte offset, usually ignored for word-aligned accesses)
    // Index  = bits [7:2] (6 bits to index 64 sets)
    // Tag    = bits [31:8] (The remaining 24 bits)
    
    logic [5:0]  index;
    logic [21:0] tag;
    logic [3:0] offset;
    logic [1:0] word_offset;

    assign offset = cpu_addr[3:0];
    //assign byte_offset = offset[1:0];
    assign word_offset = offset[3:2];
    assign index = cpu_addr[9:4];
    assign tag   = cpu_addr[31:10];

    logic cache_hit;
    // It's a hit ONLY IF the valid bit is 1 AND the tags match exactly
    assign cache_hit = valid_array[index] && (tag_array[index] == tag);
    
    //assign cpu_readdata = data_array[index][word_offset * 32 +: 32];
    // Safe 4-to-1 Multiplexer (Bypasses the Icarus 'X' index hang)
    assign vcpu_readdata = data_array[index];
    assign cpu_readdata = (word_offset == 2'b00) ? data_array[index][31:0]   :
                          (word_offset == 2'b01) ? data_array[index][63:32]  :
                          (word_offset == 2'b10) ? data_array[index][95:64]  :
                          (word_offset == 2'b11) ? data_array[index][127:96] : 32'b0;

    typedef enum logic [2:0] {IDLE, COMPARE, ALLOCATE, WRITE_BACK, REFILL} statetype;
    statetype state, next_state;

    // =========================================================================
    // SEQUENTIAL BLOCK (Memory Updates & State Flips)
    // =========================================================================
    integer i;
    always_ff @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            for (i = 0; i < SETS; i = i + 1) begin
                valid_array[i] <= 0; // Clear cache on boot
                dirty_array[i] <= 0;
                tag_array[i] <= 0;
                data_array[i] <= 0;
            end
        end else begin
            state <= next_state;

            // Update Arrays on a WRITE HIT
            if (state == COMPARE && cache_hit && cpu_valid && cpu_rw) begin
                dirty_array[index] <= 1;
                if (v_req) begin
                    // Vector Store (vsw): Overwrite the entire 128-bit block
                    data_array[index] <= vcpu_writedata;
                end else begin
                    // Only overwrite the specific 32-bit word!
                    case(word_offset)
                        2'b00: data_array[index][31:0]   <= cpu_writedata;
                        2'b01: data_array[index][63:32]  <= cpu_writedata;
                        2'b10: data_array[index][95:64]  <= cpu_writedata;
                        2'b11: data_array[index][127:96] <= cpu_writedata;
                    endcase
                end
            end
            
            // Update Arrays when ALLOCATE finishes fetching from RAM
            if (state == ALLOCATE && mem_ready) begin
                data_array[index]  <= mem_readdata;
                tag_array[index]   <= tag;
                valid_array[index] <= 1;
                dirty_array[index] <= 0; // New block from RAM is clean!
            end

            // Write-back after refill: if the original request was a store,
            // update the newly-filled line immediately in REFILL
            if (state == REFILL && cpu_rw) begin
                dirty_array[index] <= 1;
                if (v_req) begin
                    data_array[index] <= vcpu_writedata; // FIXED: Handle Vector Stores here too!
                end else begin
                    case (word_offset)
                        2'b00: data_array[index][31:0]   <= cpu_writedata;
                        2'b01: data_array[index][63:32]  <= cpu_writedata;
                        2'b10: data_array[index][95:64]  <= cpu_writedata;
                        2'b11: data_array[index][127:96] <= cpu_writedata;
                    endcase
                end
            end
        end
    end

    // FSM Combinational Logic
    always_comb begin
        // Default values
        cpu_ready = 0;
        mem_rw = 0;
        mem_valid = 0;
        next_state = state;
        mem_addr = 32'b0;
        mem_writedata = 128'b0;

        case (state)
            IDLE: begin
                if(cpu_valid==1) 
                    next_state = COMPARE;
            end

            COMPARE: begin
                if (cache_hit && cpu_valid) begin
                    cpu_ready  = 1;
                    next_state = IDLE;
                end else if (!cache_hit && cpu_valid) begin
                    if (valid_array[index] && dirty_array[index])
                        next_state = WRITE_BACK;
                    else
                        next_state = ALLOCATE;
                end
                // cpu_valid=0 in COMPARE: stay (shouldn't happen with cache_stall)
            end

            WRITE_BACK: begin
                mem_valid = 1;
                mem_rw = 1; // Write to RAM
                // Reconstruct the old memory address using the stored tag + index
                mem_addr = {tag_array[index], index, 4'b0000}; 
                mem_writedata = data_array[index];
                
                if (mem_ready) next_state = ALLOCATE; // Done saving, now go fetch!
            end

            ALLOCATE: begin
                mem_addr  = {tag, index, 4'b0000};
                if (!mem_ready) begin   // ← this is the entire fix
                    mem_valid = 1;
                    mem_rw    = 0;
                end
                
                if (mem_ready) next_state = REFILL; // Fetched! Go back to register the Hit.
            end

            REFILL: begin
                // Arrays were written on the posedge that brought us here.
                // Now assert cpu_ready for one cycle and go back to IDLE.
                cpu_ready  = 1;
                next_state = IDLE;
            end
        endcase
    end
    
endmodule


module l2_cache (
    input  logic         clk, reset,
    
    // --- L1 Cache Interface (L1 is the "CPU" here) ---
    input  logic         l1_valid,     // 1 = L1 is requesting a block
    input  logic         l1_rw,        // 0 = Read, 1 = Write (Eviction from L1)
    input  logic [31:0]  l1_addr,      // Address from L1
    input  logic [127:0] l1_writedata, // 128-bit block evicted FROM L1
    output logic [127:0] l1_readdata,  // 128-bit block going TO L1
    output logic         l1_ready,     // 1 = L2 is done

    // --- Main Memory Interface ---
    output logic         mem_valid,    
    output logic         mem_rw,       
    output logic [31:0]  mem_addr,     
    output logic [127:0] mem_writedata,
    input  logic [127:0] mem_readdata, 
    input  logic         mem_ready     
);

    // L2 is larger: 128 sets
    parameter SETS = 128; 

    // --- Way 0 Arrays ---
    logic         valid_0 [SETS-1:0];
    logic         dirty_0 [SETS-1:0];
    logic [20:0]  tag_0   [SETS-1:0]; // 21 bits
    logic [127:0] data_0  [SETS-1:0]; 

    // --- Way 1 Arrays ---
    logic         valid_1 [SETS-1:0];
    logic         dirty_1 [SETS-1:0];
    logic [20:0]  tag_1   [SETS-1:0]; 
    logic [127:0] data_1  [SETS-1:0]; 

    // --- LRU Array ---
    logic         lru     [SETS-1:0]; // 0 = Way 0 is LRU, 1 = Way 1 is LRU

    // Address Breakdown
    // Block offset [3:0] (ignored, we deal in full 128-bit blocks)
    // Index [10:4] (7 bits for 128 sets)
    // Tag [31:11] (Remaining 21 bits)
    logic [6:0]  index;
    logic [20:0] tag;

    assign index = l1_addr[10:4];
    assign tag   = l1_addr[31:11];

    // --- Parallel Hit Detection ---
    logic hit_0, hit_1, cache_hit;
    assign hit_0 = valid_0[index] && (tag_0[index] == tag);
    assign hit_1 = valid_1[index] && (tag_1[index] == tag);
    assign cache_hit = hit_0 | hit_1;

    // Route the correct data back to L1
    assign l1_readdata = hit_0 ? data_0[index] : 
                         hit_1 ? data_1[index] : 128'b0;

    // --- Eviction Logic Helpers ---
    // These wires automatically look at the LRU bit to figure out what we are evicting
    logic        evict_way;
    logic        evict_valid;
    logic        evict_dirty;
    logic [20:0] evict_tag;

    assign evict_way   = lru[index];
    assign evict_valid = evict_way ? valid_1[index] : valid_0[index];
    assign evict_dirty = evict_way ? dirty_1[index] : dirty_0[index];
    assign evict_tag   = evict_way ? tag_1[index]   : tag_0[index];

    typedef enum logic [2:0] {IDLE, COMPARE, ALLOCATE, WRITE_BACK, REFILL} statetype;
    statetype state, next_state;

    // =========================================================================
    // SEQUENTIAL BLOCK (Memory Updates & State Flips)
    // =========================================================================
    integer i;
    always_ff @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            for (i = 0; i < SETS; i = i + 1) begin
                valid_0[i] <= 0; dirty_0[i] <= 0;
                valid_1[i] <= 0; dirty_1[i] <= 0;
                lru[i]     <= 0; // Default LRU is Way 0
                tag_0[i] <= 0;
                tag_1[i] <= 0;
            end
        end else begin
            state <= next_state;

            // Update Arrays on an L2 HIT
            if (state == COMPARE && cache_hit && l1_valid) begin
                if (hit_0) begin
                    lru[index] <= 1; // Way 0 was used, so Way 1 is now LRU
                    if (l1_rw) begin
                        data_0[index]  <= l1_writedata;
                        dirty_0[index] <= 1;
                    end
                end else if (hit_1) begin
                    lru[index] <= 0; // Way 1 was used, so Way 0 is now LRU
                    if (l1_rw) begin
                        data_1[index]  <= l1_writedata;
                        dirty_1[index] <= 1;
                    end
                end
            end
            
            // Update Arrays when ALLOCATE finishes fetching from RAM
            if (state == ALLOCATE && mem_ready) begin
                if (evict_way == 0) begin
                    data_0[index]  <= mem_readdata;
                    tag_0[index]   <= tag;
                    valid_0[index] <= 1;
                    dirty_0[index] <= 0;
                end else begin
                    data_1[index]  <= mem_readdata;
                    tag_1[index]   <= tag;
                    valid_1[index] <= 1;
                    dirty_1[index] <= 0;
                end
                // The way we just filled is now the MRU, flip the LRU bit!
                lru[index] <= ~evict_way; 
            end
        end
    end

    // =========================================================================
    // COMBINATIONAL BLOCK (The FSM Brain)
    // =========================================================================
    always_comb begin
        // Defaults
        next_state    = state;
        l1_ready      = 0;
        mem_valid     = 0;
        mem_rw        = 0;
        mem_addr      = 32'b0;
        mem_writedata = 128'b0;

        case (state)
            IDLE: begin
                if (l1_valid) next_state = COMPARE;
            end

            COMPARE: begin
                if (cache_hit && l1_valid) begin
                    l1_ready   = 1;
                    next_state = IDLE;
                end else if (!cache_hit && l1_valid) begin
                    if (evict_valid && evict_dirty)
                        next_state = WRITE_BACK;
                    else
                        next_state = ALLOCATE;
                end
            end

            WRITE_BACK: begin
                mem_valid = 1;
                mem_rw = 1; 
                // Reconstruct the memory address of the old block
                mem_addr = {evict_tag, index, 4'b0000}; 
                mem_writedata = evict_way ? data_1[index] : data_0[index];
                
                if (mem_ready) next_state = ALLOCATE; 
            end

            ALLOCATE: begin
                mem_addr  = {tag, index, 4'b0000};
                if (!mem_ready) begin   // ← this is the entire fix
                    mem_valid = 1;
                    mem_rw    = 0;
                end
                if (mem_ready) next_state = REFILL; 
            end

            REFILL: begin
                // Arrays are now updated (written on the posedge entering this state).
                // Signal l1_ready for one clean cycle.
                l1_ready   = 1;
                if(!l1_valid) next_state = IDLE;  
            end
        endcase
    end

endmodule


module adder(input logic[31:0]a, b, output logic[31:0]y);
    assign y=a+b;
endmodule

module sl2(input logic[31:0]a, output logic[31:0]y);
    //shiftleftby2
    assign y={a[29:0],2'b00};
endmodule

module signext(input logic[15:0]a,
    output logic[31:0]y);
    assign y={{16{a[15]}},a};
endmodule

module flopenrc#(parameter WIDTH=8) //flip flop with enable, clear(stall+flushing), reset
    (input logic clk, reset, en, clear, input logic[WIDTH-1:0]d, output logic[WIDTH-1:0]q);
    always_ff @(posedge clk, posedge reset)
        if (reset) 
            q <= 0;                    // Asynchronous reset
        else if (clear) 
            q <= 0;                    // Synchronous clear (Flush)
        else if (en) 
            q <= d;                    // Only update if enabled (Stall logic)
endmodule

module mux2#(parameter WIDTH=8) 
    (input logic[WIDTH-1:0] d0, d1, input logic s, output logic[WIDTH-1:0]y);
    assign y=s?d1:d0;
endmodule

module dmem(
    input  logic         clk, reset,
    
    // --- Cache to Memory Interface ---
    input  logic         mem_valid,
    input  logic         mem_rw,       // 0 = Read, 1 = Write
    input  logic [31:0]  mem_addr,
    input  logic [127:0] mem_writedata,
    output logic [127:0] mem_readdata,
    output logic         mem_ready
);

    logic [31:0] RAM [255:0];
    integer i;

    // 1. Initialize to 0 BEFORE loading the file to kill all X states!
    initial begin
        for(i=0; i<256; i=i+1) begin
            RAM[i] = 32'b0;
        end
        $readmemh("vmemfile.dat", RAM);
    end

    logic [29:0] block_base_word;
    assign block_base_word = {mem_addr[31:4], 2'b00}; 

    logic [2:0] delay_count;
    parameter LATENCY = 3'd4; 

    always_ff @(posedge clk) begin
        if (reset) begin
            delay_count <= 0;
            mem_ready   <= 0;
        end else if (mem_valid && !mem_ready) begin
            if (delay_count == LATENCY - 1) begin
                
                // 2. RESTORED: Actually write the data to RAM!
                if (mem_rw == 1) begin
                    RAM[block_base_word]     <= mem_writedata[31:0];
                    RAM[block_base_word + 1] <= mem_writedata[63:32];
                    RAM[block_base_word + 2] <= mem_writedata[95:64];
                    RAM[block_base_word + 3] <= mem_writedata[127:96];
                end
                
                mem_ready   <= 1;
                delay_count <= 0;
            end else begin
                delay_count <= delay_count + 1;
            end
        end else if (!mem_valid) begin
            mem_ready   <= 0;
            delay_count <= 0;
        end
    end

    assign mem_readdata = { RAM[block_base_word + 3], 
                            RAM[block_base_word + 2], 
                            RAM[block_base_word + 1], 
                            RAM[block_base_word] };

endmodule

module imem(input logic[7:0] a,
    output logic[31:0]rd);
    
    logic[31:0] RAM [255:0];
    integer i;
    
    // 3. Initialize to 0 to prevent fetching X instructions at the end of the program
    initial begin
        for(i=0; i<256; i=i+1) begin
            RAM[i] = 32'b0;
        end
        $readmemh("vmemfile.dat", RAM);
    end
    
    assign rd = RAM[a]; 
endmodule