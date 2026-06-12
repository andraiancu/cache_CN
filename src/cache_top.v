// Top-level wrapper pentru cache-ul 4-way set-associative
// Instanțiaza: cache_controller → fsm_controller + cache_memory + lru_tracker
//
// Parametri arhitectura:
//   - Cache size : 32 KB
//   - Block size : 64 bytes (512 biti)
//   - Sets       : 128
//   - Ways       : 4
//   - Adresa     : [31:13] tag | [12:6] index | [5:0] offset

module cache_top (
    input  wire        clk,
    input  wire        rst,

    // --- Interfata CPU ---
    input  wire [31:0] cpu_addr,    // adresa de accesat
    input  wire [31:0] cpu_wdata,   // data de scris (valida doar la write)
    input  wire        cpu_write,   // 1=scriere, 0=citire
    input  wire        cpu_valid,   // CPU prezinta un request valid
    output wire [31:0] cpu_rdata,   // data returnata catre CPU
    output wire        cpu_ready,   // 1=request servit, CPU poate continua

    // --- Interfata Memorie Principala ---
    output wire [31:0]  mem_addr,   // adresa bloc (aliniata la 64 bytes)
    output wire [511:0] mem_wdata,  // bloc trimis la memorie (evict)
    output wire         mem_write,  // initiaza scriere in memorie
    output wire         mem_read,   // initiaza citire din memorie
    input  wire [511:0] mem_rdata,  // bloc primit din memorie
    input  wire         mem_ready   // memoria a terminat operatia
);

    cache_controller u_cache_controller (
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

endmodule
