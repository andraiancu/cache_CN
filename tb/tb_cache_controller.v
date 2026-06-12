// Testbench integrare cache_controller
// Simuleaza un CPU care face request-uri + un model simplu de memorie principala
// Scenarii:
//   1. Read miss → fetch → read hit (aceeasi adresa)
//   2. Write hit (dupa read miss)
//   3. Evict: scriem in mai multe seturi din acelasi way LRU pana provocam un evict

`timescale 1ns/1ps

module tb_cache_controller;

    // =========================================================
    //  Semnale
    // =========================================================
    reg         clk, rst;

    // CPU side
    reg  [31:0] cpu_addr;
    reg  [31:0] cpu_wdata;
    reg         cpu_write;
    reg         cpu_valid;
    wire [31:0] cpu_rdata;
    wire        cpu_ready;

    // Memory side (conectate la modelul de memorie de mai jos)
    wire [31:0]  mem_addr;
    wire [511:0] mem_wdata;
    wire         mem_write;
    wire         mem_read;
    reg  [511:0] mem_rdata;
    reg          mem_ready;

    // =========================================================
    //  DUT
    // =========================================================
    cache_controller dut (
        .clk       (clk),
        .rst       (rst),
        .cpu_addr  (cpu_addr),
        .cpu_wdata (cpu_wdata),
        .cpu_write (cpu_write),
        .cpu_valid (cpu_valid),
        .cpu_rdata (cpu_rdata),
        .cpu_ready (cpu_ready),
        .mem_addr  (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_write (mem_write),
        .mem_read  (mem_read),
        .mem_rdata (mem_rdata),
        .mem_ready (mem_ready)
    );

    // =========================================================
    //  Model simplu de memorie principala (2 cicluri latenta)
    // =========================================================
    reg [511:0] main_mem [0:255]; // 256 × 64B = 16KB
    reg [1:0]   mem_wait_cnt;

    always @(posedge clk) begin
        mem_rdata <= 512'b0;
        mem_ready <= 1'b0;

        if (mem_read || mem_write) begin
            if (mem_wait_cnt == 2'd0) begin
                mem_wait_cnt <= 2'd1;
            end else if (mem_wait_cnt == 2'd1) begin
                // raspuns dupa 2 cicli
                if (mem_read)
                    mem_rdata <= main_mem[mem_addr[13:6]]; // indexare pe blocuri de 64B
                if (mem_write)
                    main_mem[mem_addr[13:6]] <= mem_wdata;
                mem_ready    <= 1'b1;
                mem_wait_cnt <= 2'd0;
            end
        end else begin
            mem_wait_cnt <= 2'd0;
        end
    end

    // =========================================================
    //  Ceas
    // =========================================================
    initial clk = 0;
    always #5 clk = ~clk;

    // =========================================================
    //  Task: trimite request CPU si asteapta cpu_ready
    // =========================================================
    task cpu_request;
        input [31:0] addr;
        input [31:0] wdata;
        input        wr;
        begin
            @(negedge clk);
            cpu_addr  = addr;
            cpu_wdata = wdata;
            cpu_write = wr;
            cpu_valid = 1;
            // asteaptam cpu_ready
            @(posedge cpu_ready);
            @(negedge clk);
            cpu_valid = 0;
            if (!wr)
                $display("[%0t] READ  addr=%08h → rdata=%08h", $time, addr, cpu_rdata);
            else
                $display("[%0t] WRITE addr=%08h  data=%08h → done", $time, addr, wdata);
        end
    endtask

    // =========================================================
    //  Secventa de test
    // =========================================================
    integer i;

    initial begin
        $dumpfile("waves/tb_cache.vcd");
        $dumpvars(0, tb_cache_controller);

        // initializare memorie cu valori cunoscute
        for (i = 0; i < 256; i = i + 1)
            main_mem[i] = {16{32'hDEAD_0000 | i[7:0]}};

        // ---------- Reset ----------
        rst = 1; cpu_valid = 0; cpu_write = 0;
        cpu_addr = 0; cpu_wdata = 0;
        mem_wait_cnt = 0;
        #20; rst = 0;

        // ========================================================
        // Test 1: Read miss → blocul e adus din memorie
        // ========================================================
        $display("\n=== Test 1: Read miss (set 0, tag 0) ===");
        cpu_request(32'h0000_0000, 32'h0, 1'b0);

        // ========================================================
        // Test 2: Read hit (aceeasi adresa → blocul e in cache)
        // ========================================================
        $display("\n=== Test 2: Read hit (aceeasi adresa) ===");
        cpu_request(32'h0000_0000, 32'h0, 1'b0);

        // ========================================================
        // Test 3: Write hit (scriem cuvantul 1 din acelasi bloc)
        // ========================================================
        $display("\n=== Test 3: Write hit (acelasi set, offset diferit) ===");
        cpu_request(32'h0000_0004, 32'hCAFE_BABE, 1'b1);

        // ========================================================
        // Test 4: Read inapoi cuvantul scris (verificam write-back in cache)
        // ========================================================
        $display("\n=== Test 4: Read hit la adresa scrisa ===");
        cpu_request(32'h0000_0004, 32'h0, 1'b0);

        // ========================================================
        // Test 5: Read miss pe o alta adresa (set diferit)
        // ========================================================
        $display("\n=== Test 5: Read miss (set 1) ===");
        cpu_request(32'h0000_0040, 32'h0, 1'b0);  // set_index=1

        // ========================================================
        // Test 6: Write miss (write-allocate): fetch + modify
        // ========================================================
        $display("\n=== Test 6: Write miss → write-allocate ===");
        cpu_request(32'h0000_2000, 32'hBEEF_1234, 1'b1);  // tag diferit
        // verificam ca data a fost scrisa
        cpu_request(32'h0000_2000, 32'h0, 1'b0);

        #50;
        $display("\n--- Testbench finalizat ---");
        $finish;
    end

    // Timeout de siguranta
    initial begin
        #50000;
        $display("TIMEOUT!");
        $finish;
    end

endmodule
