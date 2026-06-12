
//stocheaza date taguri si biti de control
//128 seturi si 64 bytes pe bloc

module cache_memory (
    input  wire        clk,
    input  wire        rst,

    // de la fsm
    input  wire        write_enable,   // daca e 1, se scrie in cache
  input  wire        valid_in,       // valoarea lui valid ( de scris)
    input  wire        dirty_in,       // valoarea lui dirty 

    // descompunem adresa
  input  wire [6:0]  set_index,      // care set  de la 0 la 127
  input  wire [1:0]  way_select,     // care way de la 0 la 3
    input  wire [18:0] tag_in,         // tag-ul de scris

    // date
  input  wire [511:0] data_in,       // blocul de scris -64 bytes
    output reg  [511:0] data_out,      // blocul citit

    //iesirile fsm ului
    output reg  [18:0] tag_out,        // tag-ul din way-ul sel
    output reg         valid_out,      // valid din way-ul sel
    output reg         dirty_out,      // dirty din way-ul sel

    // Citire paralela toate 4 way-uri (pentru hit detection in controller)
    output wire [18:0]  tag_w0,   tag_w1,   tag_w2,   tag_w3,
    output wire         valid_w0, valid_w1, valid_w2, valid_w3,
    output wire         dirty_w0, dirty_w1, dirty_w2, dirty_w3,
    output wire [511:0] data_w0,  data_w1,  data_w2,  data_w3
);

    // memoria
    // 128 seturi, 4 way-uri, fiecare cu valid/dirty/tag/data
    reg         valid [0:127][0:3];
    reg         dirty [0:127][0:3];
    reg [18:0]  tag   [0:127][0:3];
    reg [511:0] data  [0:127][0:3];

    integer i, j;

    // Assign-uri combinationale pentru citirea paralela a tuturor way-urilor
    assign tag_w0   = tag  [set_index][0];
    assign tag_w1   = tag  [set_index][1];
    assign tag_w2   = tag  [set_index][2];
    assign tag_w3   = tag  [set_index][3];
    assign valid_w0 = valid[set_index][0];
    assign valid_w1 = valid[set_index][1];
    assign valid_w2 = valid[set_index][2];
    assign valid_w3 = valid[set_index][3];
    assign dirty_w0 = dirty[set_index][0];
    assign dirty_w1 = dirty[set_index][1];
    assign dirty_w2 = dirty[set_index][2];
    assign dirty_w3 = dirty[set_index][3];
    assign data_w0  = data [set_index][0];
    assign data_w1  = data [set_index][1];
    assign data_w2  = data [set_index][2];
    assign data_w3  = data [set_index][3];

    // reset- totul devine invalid si nu dirty
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 128; i = i + 1)
                for (j = 0; j < 4; j = j + 1) begin
                    valid[i][j] <= 1'b0;   // nimic valid
                    dirty[i][j] <= 1'b0;   // nimic dirty
                    tag  [i][j] <= 19'b0;
                    data [i][j] <= 512'b0;
                end
        end

      //la write (fsm decide)
        else if (write_enable) begin
            valid[set_index][way_select] <= valid_in;
            dirty[set_index][way_select] <= dirty_in;
            tag  [set_index][way_select] <= tag_in;
            data [set_index][way_select] <= data_in;
        end
    end

    // citire
  //  de fiecare dată când se schimbă set_index sau way_select (combinational ?)
    // nu asteapta clock
    always @(*) begin
        tag_out   = tag  [set_index][way_select];
        valid_out = valid[set_index][way_select];
        dirty_out = dirty[set_index][way_select];
        data_out  = data [set_index][way_select];
    end

endmodule
