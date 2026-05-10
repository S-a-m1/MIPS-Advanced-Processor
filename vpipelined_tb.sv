module testbench();
    logic        clk;
    logic        reset;
    logic [31:0] dataadr;
    logic        memwrite;
    logic        slti_sig;
    logic        cache_stall; 

    // --- NEW: 128-bit Spy Wires ---
    logic [127:0] vwritedata;
    logic         v_req;

    top dut(clk, reset, slti_sig);

    // Hierarchical Assignments
    assign memwrite    = dut.mips.dp.memwrite_M;
    assign dataadr     = dut.mips.dp.aluout_M;
    assign cache_stall = dut.mips.dp.cache_stall;
    
    // Tap directly into the vector memory stage
    assign vwritedata  = dut.mips.dp.vwritedata_M;
    assign v_req       = dut.mips.dp.v_req_M;

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, testbench);
        reset <= 1; #22; 
        reset <= 0;
        
        #5000; 
        $display("Simulation timed out. Check GTKWave for hazards!");
        $finish;
    end

    always begin
        clk <= 1; #5; 
        clk <= 0; #5;
    end

    always @(negedge clk) begin
        /*
        // Check for Vector Store (vsw)
        if (memwrite && v_req && ~cache_stall) begin
            if (dataadr === 160) begin
                // The expected vector result is [44, 33, 22, 11] in hex
                if (vwritedata === 128'h0000002c_00000021_00000016_0000000b) begin
                    $display("SIMD SUCCESS! 4 lanes of math executed in 1 cycle!");
                    $finish;
                end else begin
                    $display("SIMD FAILED! Wrote %h", vwritedata);
                    $finish;
                end
            end
        end
        */
        if (memwrite && v_req && ~cache_stall) begin
            // Spy on the final chunk of the array (Address 304)
            if (dataadr === 304) begin
                // Expected final math: [16+160, 15+150, 14+140, 13+130] 
                // In Hex: [b0, a5, 9a, 8f]
                if (vwritedata === 128'h000000b0_000000a5_0000009a_0000008f) begin
                    $display("SIMD LOOP SUCCESS! Processed 16 elements across 4 vector iterations!");
                    $finish;
                end else begin
                    $display("SIMD LOOP FAILED! Wrote %h", vwritedata);
                    $finish;
                end
            end
        end
    end
endmodule