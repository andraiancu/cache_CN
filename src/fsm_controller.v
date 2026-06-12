// FSM controller pentru cache 4-way set-associative
// Stari: IDLE → CHECK_HIT → READ_HIT/WRITE_HIT/EVICT → ALLOCATE_FETCH → COMPLETE → IDLE
// Write policy: write-back + write-allocate

module fsm_controller (
    input  wire clk,
    input  wire rst,

    // Status inputs de la datapath
    input  wire cpu_valid,      // CPU are un request activ
    input  wire cpu_write,      // tipul requestului (1=write, 0=read)
    input  wire cache_hit,      // tag match + valid gasit
    input  wire is_dirty,       // way-ul LRU e dirty (necesita evict)
    input  wire mem_ready,      // memoria principala a terminat operatia

    // Semnale de control catre datapath
    output reg  latch_request,  // latchez addr/data de la CPU
    output reg  do_cache_write, // scrie un bloc in cache_memory
    output reg  do_mem_read,    // initiaza citire din memoria principala
    output reg  do_mem_write,   // initiaza scriere in memoria principala (evict)
    output reg  update_lru,     // actualizeaza LRU tracker dupa acces
    output reg  set_dirty,      // seteaza bitul dirty la scriere in cache
    output reg  cpu_ready,      // CPU poate avansa (stall release)

    output wire [2:0] state_out // starea curenta (pentru debug si datapath)
);

    // Encodarea starilor
    localparam IDLE           = 3'd0;
    localparam CHECK_HIT      = 3'd1;
    localparam READ_HIT       = 3'd2;
    localparam WRITE_HIT      = 3'd3;
    localparam EVICT          = 3'd4;
    localparam ALLOCATE_FETCH = 3'd5;
    localparam COMPLETE       = 3'd6;

    reg [2:0] state, next_state;
    reg       pending_write;    // tipul operatiei retinute (0=read, 1=write)

    assign state_out = state;

    // ---------- Registru de stare (secvential) ----------
    always @(posedge clk) begin
        if (rst) begin
            state         <= IDLE;
            pending_write <= 1'b0;
        end else begin
            state <= next_state;
            // retine tipul operatiei la prima tranzitie din IDLE
            if (state == IDLE && cpu_valid)
                pending_write <= cpu_write;
        end
    end

    // ---------- Logica next-state + semnale de control (combinational) ----------
    always @(*) begin
        // valori default: nimic activ, ramanem in starea curenta
        next_state     = state;
        latch_request  = 1'b0;
        do_cache_write = 1'b0;
        do_mem_read    = 1'b0;
        do_mem_write   = 1'b0;
        update_lru     = 1'b0;
        set_dirty      = 1'b0;
        cpu_ready      = 1'b0;

        case (state)

            // Asteptam request de la CPU
            IDLE: begin
                if (cpu_valid) begin
                    latch_request = 1'b1;  // latchez adresa si data
                    next_state    = CHECK_HIT;
                end
            end

            // Verificam daca blocul e in cache
            CHECK_HIT: begin
                if (cache_hit)
                    next_state = pending_write ? WRITE_HIT : READ_HIT;
                else
                    next_state = is_dirty ? EVICT : ALLOCATE_FETCH;
            end

            // Hit la citire: servim CPU direct din cache
            READ_HIT: begin
                update_lru = 1'b1;
                cpu_ready  = 1'b1;
                next_state = IDLE;
            end

            // Hit la scriere: modificam blocul in cache (write-back)
            WRITE_HIT: begin
                do_cache_write = 1'b1;
                set_dirty      = 1'b1;
                update_lru     = 1'b1;
                cpu_ready      = 1'b1;
                next_state     = IDLE;
            end

            // Miss + way LRU dirty: scriem blocul vechi in memoria principala
            EVICT: begin
                do_mem_write = 1'b1;
                if (mem_ready)
                    next_state = ALLOCATE_FETCH;
                // altfel asteptam (mem_ready = 0 => wait-state)
            end

            // Aducem blocul nou din memoria principala
            ALLOCATE_FETCH: begin
                do_mem_read = 1'b1;
                if (mem_ready)
                    next_state = COMPLETE;
            end

            // Blocul a ajuns din memorie; il scriem in cache si servim CPU
            COMPLETE: begin
                do_cache_write = 1'b1;
                // write-allocate: dirty doar daca operatia era o scriere
                set_dirty      = pending_write;
                update_lru     = 1'b1;
                cpu_ready      = 1'b1;
                next_state     = IDLE;
            end

            default: next_state = IDLE;

        endcase
    end

endmodule
