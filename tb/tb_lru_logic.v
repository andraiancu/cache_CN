// Testbench izolat pentru lru_tracker
// Verifica explicit ca ordinea de evacuare LRU este corecta dupa secvente de acces
//
// Logica lru_tracker:
//   - age[set][way] = 0 → cel mai recent accesat
//   - age[set][way] = 3 → cel mai vechi (candidat LRU)
//   - La acces way X: age[X]=0, way-urile mai tinere (age < age_vechi[X]) imbatranesc cu 1

`timescale 1ns/1ps

module tb_lru_logic;

    reg        clk, rst;
    reg        update_en;
    reg  [6:0] set_index;
    reg  [1:0] way_used;
    wire [1:0] lru_way;

    lru_tracker dut (
        .clk       (clk),
        .rst       (rst),
        .update_en (update_en),
        .set_index (set_index),
        .way_used  (way_used),
        .lru_way   (lru_way)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // Acceseaza un way si asteapta un ciclu
    task access;
        input [1:0] w;
        begin
            @(negedge clk);
            update_en = 1;
            way_used  = w;
            @(posedge clk); #1;
            update_en = 0;
        end
    endtask

    // Verifica LRU si afiseaza rezultatul
    task check_lru;
        input [1:0] expected;
        input [63:0] label;
        begin
            @(negedge clk); #1;
            if (lru_way === expected)
                $display("PASS  %s | lru_way=%0d (expected %0d)", label, lru_way, expected);
            else
                $display("FAIL  %s | lru_way=%0d (expected %0d) !!!", label, lru_way, expected);
        end
    endtask

    integer i;

    initial begin
        $dumpfile("waves/tb_lru.vcd");
        $dumpvars(0, tb_lru_logic);

        // Reset
        rst = 1; update_en = 0; set_index = 0; way_used = 0;
        @(posedge clk); #1;
        @(posedge clk); #1;
        rst = 0;

        // Dupa reset: age = [0,1,2,3] → way 3 e LRU
        $display("\n--- Dupa reset (set 0) ---");
        check_lru(2'd3, "initial LRU");

        // ============================================================
        // Test 1: Acces secvential 0→1→2→3
        // Dupa acces way 0: ages=[0,2,3,1]? Sa vedem
        // ============================================================
        $display("\n--- Test 1: acces secvential way 0,1,2,3 ---");
        set_index = 0;

        access(2'd0); // accesat: 0  → age[0]=0, restul imbatranesc cei cu age<age_vechi[0]=0 → nimeni
                      // ages: [0,1,2,3]→ [0,1,2,3] (way 0 era deja cel mai tanar)
        check_lru(2'd3, "dupa access(0)   ");

        access(2'd1); // age[1] era 1 → age[1]=0, way 0 (age=0 < 1) → age[0]++
                      // ages: [1,0,2,3]
        check_lru(2'd3, "dupa access(1)   ");

        access(2'd2); // age[2] era 2 → age[2]=0, way 0 (1<2)→+1, way 1 (0<2)→+1
                      // ages: [2,1,0,3]
        check_lru(2'd3, "dupa access(2)   ");

        access(2'd3); // age[3] era 3 → age[3]=0, way 0(2<3)→+1, way 1(1<3)→+1, way 2(0<3)→+1
                      // ages: [3,2,1,0]
        check_lru(2'd0, "dupa access(3)   "); // way 0 e acum LRU

        // ============================================================
        // Test 2: Re-acces way 0 → way 0 devine cel mai tanar
        // ============================================================
        $display("\n--- Test 2: re-acces way 0 (trebuie sa nu mai fie LRU) ---");
        access(2'd0); // age[0] era 3 → age[0]=0, restul (age<3) imbatranesc
                      // ages: [0,3,2,1]
        check_lru(2'd1, "dupa re-access(0)"); // way 1 (age=3) e acum LRU

        // ============================================================
        // Test 3: Acces repetat pe acelasi way → LRU nu se schimba
        // ============================================================
        $display("\n--- Test 3: acces repetat way 0 (LRU ramane acelasi) ---");
        access(2'd0);
        access(2'd0);
        access(2'd0);
        check_lru(2'd1, "dupa 3x access(0)"); // way 1 ramane LRU

        // ============================================================
        // Test 4: Set diferit (set 5) — nu afecteaza set 0
        // ============================================================
        $display("\n--- Test 4: acces pe set 5, verificam ca set 0 e neafectat ---");
        set_index = 5;
        access(2'd2);
        access(2'd3);
        set_index = 0;
        check_lru(2'd1, "set0 neafectat   "); // set 0 pastrat din test 3

        // ============================================================
        // Test 5: Rotatie completa — fiecare way devine LRU pe rand
        // ============================================================
        $display("\n--- Test 5: rotatie 3,2,1,0 → LRU in ordine inversa ---");
        set_index = 7;
        // reset indirect: acces in ordine 0,1,2,3 → ages=[3,2,1,0]
        access(2'd0); access(2'd1); access(2'd2); access(2'd3);
        check_lru(2'd0, "lru dupa 0123    "); // way 0 e LRU

        access(2'd0); // accesam LRU-ul
        check_lru(2'd1, "lru dupa +acc(0) "); // way 1 devine LRU

        access(2'd1);
        check_lru(2'd2, "lru dupa +acc(1) ");

        access(2'd2);
        check_lru(2'd3, "lru dupa +acc(2) ");

        access(2'd3);
        check_lru(2'd0, "lru dupa +acc(3) ");

        #20;
        $display("\n--- Testbench LRU finalizat ---");
        $finish;
    end

endmodule
