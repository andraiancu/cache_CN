// Testbench pentru fsm_controller
// Scenarii testate:
//   1. Read hit:  IDLE → CHECK_HIT → READ_HIT → IDLE
//   2. Write hit: IDLE → CHECK_HIT → WRITE_HIT → IDLE
//   3. Read miss (clean way): IDLE → CHECK_HIT → ALLOCATE_FETCH → COMPLETE → IDLE
//   4. Read miss (dirty way): IDLE → CHECK_HIT → EVICT → ALLOCATE_FETCH → COMPLETE → IDLE

`timescale 1ns/1ps

module tb_fsm_controller;

    // Ceas si reset
    reg clk, rst;

    // Inputs FSM
    reg cpu_valid, cpu_write;
    reg cache_hit, is_dirty, mem_ready;

    // Outputs FSM
    wire latch_request, do_cache_write, do_mem_read, do_mem_write;
    wire update_lru, set_dirty, cpu_ready;
    wire [2:0] state_out;

    // Instantiere DUT
    fsm_controller dut (
        .clk           (clk),
        .rst           (rst),
        .cpu_valid     (cpu_valid),
        .cpu_write     (cpu_write),
        .cache_hit     (cache_hit),
        .is_dirty      (is_dirty),
        .mem_ready     (mem_ready),
        .latch_request (latch_request),
        .do_cache_write(do_cache_write),
        .do_mem_read   (do_mem_read),
        .do_mem_write  (do_mem_write),
        .update_lru    (update_lru),
        .set_dirty     (set_dirty),
        .cpu_ready     (cpu_ready),
        .state_out     (state_out)
    );

    // Generare ceas: 10 ns perioada
    initial clk = 0;
    always #5 clk = ~clk;

    // Taskuri ajutatoare
    task tick;
        input integer n;
        integer k;
        begin
            for (k = 0; k < n; k = k + 1)
                @(posedge clk); #1;
        end
    endtask

    task show;
        input [127:0] label;
        begin
            $display("[%0t] %s | state=%0d | cpu_ready=%b latch=%b cache_wr=%b mem_rd=%b mem_wr=%b upd_lru=%b dirty=%b",
                $time, label, state_out, cpu_ready, latch_request,
                do_cache_write, do_mem_read, do_mem_write, update_lru, set_dirty);
        end
    endtask

    initial begin
        $dumpfile("waves/tb_fsm.vcd");
        $dumpvars(0, tb_fsm_controller);

        // ---------- Reset ----------
        rst = 1; cpu_valid = 0; cpu_write = 0;
        cache_hit = 0; is_dirty = 0; mem_ready = 0;
        tick(2);
        rst = 0;
        $display("--- RESET done ---");

        // ========================================================
        // Scenariu 1: READ HIT
        // ========================================================
        $display("\n--- Scenariu 1: READ HIT ---");
        cpu_valid = 1; cpu_write = 0;
        cache_hit = 1; is_dirty = 0;
        show("IDLE+req ");
        tick(1); show("CHECK_HIT");  // trebuie sa fim in CHECK_HIT
        tick(1); show("READ_HIT ");  // servire + cpu_ready=1
        tick(1); show("IDLE     ");  // inapoi in IDLE
        cpu_valid = 0;
        tick(1);

        // ========================================================
        // Scenariu 2: WRITE HIT
        // ========================================================
        $display("\n--- Scenariu 2: WRITE HIT ---");
        cpu_valid = 1; cpu_write = 1;
        cache_hit = 1; is_dirty = 0;
        tick(1); show("CHECK_HIT");
        tick(1); show("WRITE_HIT");  // do_cache_write=1, set_dirty=1, cpu_ready=1
        tick(1); show("IDLE     ");
        cpu_valid = 0; cpu_write = 0;
        tick(1);

        // ========================================================
        // Scenariu 3: READ MISS, way curat
        // ========================================================
        $display("\n--- Scenariu 3: READ MISS (clean way) ---");
        cpu_valid = 1; cpu_write = 0;
        cache_hit = 0; is_dirty = 0;
        tick(1); show("CHECK_HIT    ");
        tick(1); show("ALLOC_FETCH  ");  // do_mem_read=1
        // simulam 2 wait-state de la memorie
        tick(1); show("wait mem     ");
        mem_ready = 1;
        tick(1); show("COMPLETE     ");  // do_cache_write=1, cpu_ready=1
        mem_ready = 0;
        tick(1); show("IDLE         ");
        cpu_valid = 0;
        tick(1);

        // ========================================================
        // Scenariu 4: READ MISS, way dirty (evict + fetch)
        // ========================================================
        $display("\n--- Scenariu 4: READ MISS (dirty way → EVICT) ---");
        cpu_valid = 1; cpu_write = 0;
        cache_hit = 0; is_dirty = 1;
        tick(1); show("CHECK_HIT    ");
        tick(1); show("EVICT        ");  // do_mem_write=1
        tick(1); show("wait evict   ");
        mem_ready = 1;
        tick(1); show("ALLOC_FETCH  ");  // do_mem_read=1
        mem_ready = 0;
        tick(1); show("wait fetch   ");
        mem_ready = 1;
        tick(1); show("COMPLETE     ");  // do_cache_write=1, cpu_ready=1
        mem_ready = 0; is_dirty = 0;
        tick(1); show("IDLE         ");
        cpu_valid = 0;
        tick(2);

        $display("\n--- Toate scenariile terminate ---");
        $finish;
    end

endmodule
