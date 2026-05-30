
// tine evidența ordinii de acces pentru politica LRU
// pt fiecare set o sa stie care way n a mai fost folost de mult
// fiecare way primeste un nr/varsta de la 1 la 3 cu 0 = cel mai recent folosit, 3 = cel mai demult folosit -la asta se verif dirty si s ar putea sa fie evacuat. basically candideaza

// cand accesăm un way, el devine 0 și restul îmbătrânesc :))

module lru_tracker (
    input  wire       clk,
    input  wire       rst,

    // date de la fsm
    input  wire       update_en,    // 1 - actualiz dupa acces un way
    input  wire [6:0] set_index,    // care set actualizăm
    input  wire [1:0] way_used,     // care way tocmai a fost accesat

    // spre fsm
  output reg  [1:0] lru_way       // way-ul cel mai batran din setul cerut
);

    
    // age[set][way] = cât de "bătrân" e way-ul
    reg [1:0] age [0:127][0:3];

    integer i, j;

  // gasim way ul LRU (cel mai batran)
    // FSM-ul vede mereu care e candidatul pentru evacuare
    always @(*) begin
        // Pornim cu way 0 ca și candidat
        lru_way = 2'd0;

        // Comparăm cu celelalte way-uri
        if (age[set_index][1] > age[set_index][lru_way])
            lru_way = 2'd1;
        if (age[set_index][2] > age[set_index][lru_way])
            lru_way = 2'd2;
        if (age[set_index][3] > age[set_index][lru_way])
            lru_way = 2'd3;
    end

    // actualizam varste cum am zis
    always @(posedge clk) begin
        if (rst) begin
            // La reset, dăm vârste inițiale diferite
            // way 0 = cel mai recent, way 3 = cel mai old
            for (i = 0; i < 128; i = i + 1)
                for (j = 0; j < 4; j = j + 1)
                    age[i][j] <= j[1:0];  // 0, 1, 2, 3
        end

        else if (update_en) begin
            // way_used devine cel mai recent (vârsta 0)
            // orice way mai tânăr decât way_used îmbătrânește cu 1
            

            age[set_index][way_used] <= 2'd0;

            if (way_used != 2'd0 && age[set_index][0] < age[set_index][way_used])
                age[set_index][0] <= age[set_index][0] + 1;

            if (way_used != 2'd1 && age[set_index][1] < age[set_index][way_used])
                age[set_index][1] <= age[set_index][1] + 1;

            if (way_used != 2'd2 && age[set_index][2] < age[set_index][way_used])
                age[set_index][2] <= age[set_index][2] + 1;

            if (way_used != 2'd3 && age[set_index][3] < age[set_index][way_used])
                age[set_index][3] <= age[set_index][3] + 1;
        end
    end

endmodule
