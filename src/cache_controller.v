// Cache controller: integreaza FSM, cache_memory si lru_tracker
// Interfata CPU: 32-bit word access (read/write)
// Interfata memorie: 512-bit block transfer (64 bytes)
// Write policy: write-back + write-allocate
// Adresa: [31:13] tag | [12:6] index | [5:0] offset

module cache_controller (
    input  wire        clk,
    input  wire        rst,

    // --- Interfata CPU ---
    input  wire [31:0] cpu_addr,    // adresa ceruta
    input  wire [31:0] cpu_wdata,   // data de scris (doar la write)
    input  wire        cpu_write,   // 1=scriere, 0=citire
    input  wire        cpu_valid,   // CPU are un request activ
    output reg  [31:0] cpu_rdata,   // data returnata la citire
    output wire        cpu_ready,   // 1=request servit, CPU poate avansa

    // --- Interfata Memorie Principala ---
    output reg  [31:0]  mem_addr,   // adresa bloc (aliniata la 64 bytes)
    output reg  [511:0] mem_wdata,  // bloc de scris in memorie (evict)
    output reg          mem_write,  // initiaza scriere in memorie
    output reg          mem_read,   // initiaza citire din memorie
    input  wire [511:0] mem_rdata,  // bloc citit din memorie
    input  wire         mem_ready   // memoria a terminat operatia
);

    // =========================================================
    //  Decompunerea adresei latched
    // =========================================================
    reg [31:0] lat_addr;
    reg [31:0] lat_wdata;

    wire [18:0] lat_tag    = lat_addr[31:13];
    wire [6:0]  lat_index  = lat_addr[12:6];
    wire [5:0]  lat_offset = lat_addr[5:0];
    wire [3:0]  word_sel   = lat_offset[5:2]; // selectie cuvant 32b in blocul de 512b

    // =========================================================
    //  Instantiere cache_memory
    // =========================================================
    reg         cm_write_en;
    reg         cm_valid_in;
    reg         cm_dirty_in;
    reg  [1:0]  cm_way_sel;
    reg  [18:0] cm_tag_in;
    reg  [511:0] cm_data_in;

    wire [511:0] cm_data_out;
    wire [18:0]  cm_tag_out;
    wire         cm_valid_out;
    wire         cm_dirty_out;

    // Porturile paralele (toate 4 way-uri, combinational)
    wire [18:0]  cm_tag_w0,  cm_tag_w1,  cm_tag_w2,  cm_tag_w3;
    wire         cm_valid_w0, cm_valid_w1, cm_valid_w2, cm_valid_w3;
    wire         cm_dirty_w0, cm_dirty_w1, cm_dirty_w2, cm_dirty_w3;
    wire [511:0] cm_data_w0,  cm_data_w1,  cm_data_w2,  cm_data_w3;

    cache_memory u_cache_memory (
        .clk         (clk),
        .rst         (rst),
        .write_enable(cm_write_en),
        .valid_in    (cm_valid_in),
        .dirty_in    (cm_dirty_in),
        .set_index   (lat_index),
        .way_select  (cm_way_sel),
        .tag_in      (cm_tag_in),
        .data_in     (cm_data_in),
        .data_out    (cm_data_out),
        .tag_out     (cm_tag_out),
        .valid_out   (cm_valid_out),
        .dirty_out   (cm_dirty_out),
        .tag_w0      (cm_tag_w0),   .valid_w0 (cm_valid_w0),
        .dirty_w0    (cm_dirty_w0), .data_w0  (cm_data_w0),
        .tag_w1      (cm_tag_w1),   .valid_w1 (cm_valid_w1),
        .dirty_w1    (cm_dirty_w1), .data_w1  (cm_data_w1),
        .tag_w2      (cm_tag_w2),   .valid_w2 (cm_valid_w2),
        .dirty_w2    (cm_dirty_w2), .data_w2  (cm_data_w2),
        .tag_w3      (cm_tag_w3),   .valid_w3 (cm_valid_w3),
        .dirty_w3    (cm_dirty_w3), .data_w3  (cm_data_w3)
    );

    // =========================================================
    //  Instantiere lru_tracker
    // =========================================================
    reg  [1:0] lru_way_used;
    reg        lru_update_en;
    wire [1:0] lru_way;

    lru_tracker u_lru (
        .clk       (clk),
        .rst       (rst),
        .update_en (lru_update_en),
        .set_index (lat_index),
        .way_used  (lru_way_used),
        .lru_way   (lru_way)
    );

    // =========================================================
    //  Instantiere fsm_controller
    // =========================================================
    wire        fsm_latch_req;
    wire        fsm_do_cache_write;
    wire        fsm_do_mem_read;
    wire        fsm_do_mem_write;
    wire        fsm_update_lru;
    wire        fsm_set_dirty;
    wire [2:0]  fsm_state;

    // cache_hit si is_dirty sunt calculate mai jos (combinational)
    wire cache_hit;
    wire is_dirty;

    fsm_controller u_fsm (
        .clk           (clk),
        .rst           (rst),
        .cpu_valid     (cpu_valid),
        .cpu_write     (cpu_write),
        .cache_hit     (cache_hit),
        .is_dirty      (is_dirty),
        .mem_ready     (mem_ready),
        .latch_request (fsm_latch_req),
        .do_cache_write(fsm_do_cache_write),
        .do_mem_read   (fsm_do_mem_read),
        .do_mem_write  (fsm_do_mem_write),
        .update_lru    (fsm_update_lru),
        .set_dirty     (fsm_set_dirty),
        .cpu_ready     (cpu_ready),
        .state_out     (fsm_state)
    );

    // =========================================================
    //  Latch request CPU
    // =========================================================
    always @(posedge clk) begin
        if (fsm_latch_req) begin
            lat_addr  <= cpu_addr;
            lat_wdata <= cpu_wdata;
        end
    end

    // =========================================================
    //  Fill buffer: retine blocul adus din memorie
    //  Necesar deoarece mem_rdata poate disparea dupa mem_ready
    // =========================================================
    localparam ALLOCATE_FETCH_ST = 3'd5;

    reg [511:0] fill_buffer;
    always @(posedge clk) begin
        if (rst)
            fill_buffer <= 512'b0;
        else if (fsm_state == ALLOCATE_FETCH_ST && mem_ready)
            fill_buffer <= mem_rdata;
    end

    // =========================================================
    //  Hit detection (combinational, pe baza latched address)
    // =========================================================
    wire hit_w0 = cm_valid_w0 && (cm_tag_w0 == lat_tag);
    wire hit_w1 = cm_valid_w1 && (cm_tag_w1 == lat_tag);
    wire hit_w2 = cm_valid_w2 && (cm_tag_w2 == lat_tag);
    wire hit_w3 = cm_valid_w3 && (cm_tag_w3 == lat_tag);

    assign cache_hit = hit_w0 | hit_w1 | hit_w2 | hit_w3;

    // Way-ul care a dat hit
    reg [1:0] hit_way;
    always @(*) begin
        if      (hit_w0) hit_way = 2'd0;
        else if (hit_w1) hit_way = 2'd1;
        else if (hit_w2) hit_way = 2'd2;
        else             hit_way = 2'd3;
    end

    // Statusul dirty al way-ului LRU (candidat la evictiune)
    reg lru_dirty_mux;
    always @(*) begin
        case (lru_way)
            2'd0: lru_dirty_mux = cm_dirty_w0;
            2'd1: lru_dirty_mux = cm_dirty_w1;
            2'd2: lru_dirty_mux = cm_dirty_w2;
            2'd3: lru_dirty_mux = cm_dirty_w3;
        endcase
    end
    assign is_dirty = lru_dirty_mux;

    // Datele din way-ul care a dat hit
    reg [511:0] hit_data;
    always @(*) begin
        case (hit_way)
            2'd0: hit_data = cm_data_w0;
            2'd1: hit_data = cm_data_w1;
            2'd2: hit_data = cm_data_w2;
            2'd3: hit_data = cm_data_w3;
        endcase
    end

    // Datele si tag-ul din way-ul LRU (pentru evict)
    reg [511:0] lru_data;
    reg [18:0]  lru_tag;
    always @(*) begin
        case (lru_way)
            2'd0: begin lru_data = cm_data_w0; lru_tag = cm_tag_w0; end
            2'd1: begin lru_data = cm_data_w1; lru_tag = cm_tag_w1; end
            2'd2: begin lru_data = cm_data_w2; lru_tag = cm_tag_w2; end
            2'd3: begin lru_data = cm_data_w3; lru_tag = cm_tag_w3; end
        endcase
    end

    // =========================================================
    //  Blocul de date de scris in cache
    //  - WRITE_HIT:  pornim de la blocul din cache, modificam cuvantul
    //  - COMPLETE:   pornim de la blocul din memorie, eventual modificam
    // =========================================================
    reg [511:0] write_block;
    always @(*) begin
        // baza: blocul existent (hit) sau cel latched din memorie (miss)
        write_block = cache_hit ? hit_data : fill_buffer;
        // write-back sau write-allocate: suprascriem cuvantul tinta
        if (fsm_set_dirty)
            write_block[word_sel * 32 +: 32] = lat_wdata;
    end

    // =========================================================
    //  Control cache_memory
    // =========================================================
    always @(*) begin
        cm_write_en = fsm_do_cache_write;
        cm_valid_in = 1'b1;
        cm_dirty_in = fsm_set_dirty;
        cm_way_sel  = cache_hit ? hit_way : lru_way;
        cm_tag_in   = lat_tag;
        cm_data_in  = write_block;
    end

    // =========================================================
    //  Control lru_tracker
    // =========================================================
    always @(*) begin
        lru_update_en = fsm_update_lru;
        lru_way_used  = cache_hit ? hit_way : lru_way;
    end

    // =========================================================
    //  Interfata Memorie Principala
    // =========================================================
    always @(*) begin
        mem_write = 1'b0;
        mem_read  = 1'b0;
        mem_addr  = 32'b0;
        mem_wdata = lru_data;

        if (fsm_do_mem_write) begin
            // EVICT: adresa blocului dirty = {lru_tag, lat_index, 6'b0}
            mem_write = 1'b1;
            mem_addr  = {lru_tag, lat_index, 6'b0};
            mem_wdata = lru_data;
        end else if (fsm_do_mem_read) begin
            // ALLOCATE_FETCH: aducem blocul pentru tag-ul curent
            mem_read = 1'b1;
            mem_addr = {lat_tag, lat_index, 6'b0};
        end
    end

    // =========================================================
    //  Date catre CPU
    //  - hit: direct din cache (cuvantul selectat de offset)
    //  - miss/COMPLETE: din blocul adus din memorie
    // =========================================================
    always @(*) begin
        if (cache_hit)
            cpu_rdata = hit_data[word_sel * 32 +: 32];
        else
            cpu_rdata = fill_buffer[word_sel * 32 +: 32];
    end

endmodule
