`timescale 1ns/1ps
// ntt_inv.v -- Kyber's inverse NTT (Gentleman-Sande, decimation-in-
// frequency) plus the final Montgomery-factor scaling pass, matching
// ref/ntt.c's invntt() EXACTLY:
//
//   k = 127;
//   for(len = 2; len <= 128; len <<= 1)
//     for(start = 0; start < 256; start = j + len) {
//       zeta = zetas[k--];
//       for(j = start; j < start + len; j++) {
//         t = r[j];
//         r[j] = barrett_reduce(t + r[j + len]);
//         r[j + len] = r[j + len] - t;
//         r[j + len] = fqmul(zeta, r[j + len]);
//       }
//     }
//   for(j = 0; j < 256; j++)
//     r[j] = fqmul(r[j], f);   // f = 1441 = mont^2/128
//
// Reuses the single already-verified montgomery_reduce.v and
// barrett_fixed.v cores, one butterfly (or one final-scale multiply)
// per cycle, same real zetas[128] ROM as ntt_fwd.v.

module ntt_inv (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start_i,
    input  wire [4095:0] coeffs_in,
    output reg  [4095:0] coeffs_out,
    output reg           done
);

  reg signed [15:0] zetas [0:127];
  initial begin
    zetas[0]=-1044;  zetas[1]=-758;   zetas[2]=-359;   zetas[3]=-1517;
    zetas[4]=1493;   zetas[5]=1422;   zetas[6]=287;    zetas[7]=202;
    zetas[8]=-171;   zetas[9]=622;    zetas[10]=1577;  zetas[11]=182;
    zetas[12]=962;   zetas[13]=-1202; zetas[14]=-1474; zetas[15]=1468;
    zetas[16]=573;   zetas[17]=-1325; zetas[18]=264;   zetas[19]=383;
    zetas[20]=-829;  zetas[21]=1458;  zetas[22]=-1602; zetas[23]=-130;
    zetas[24]=-681;  zetas[25]=1017;  zetas[26]=732;   zetas[27]=608;
    zetas[28]=-1542; zetas[29]=411;   zetas[30]=-205;  zetas[31]=-1571;
    zetas[32]=1223;  zetas[33]=652;   zetas[34]=-552;  zetas[35]=1015;
    zetas[36]=-1293; zetas[37]=1491;  zetas[38]=-282;  zetas[39]=-1544;
    zetas[40]=516;   zetas[41]=-8;    zetas[42]=-320;  zetas[43]=-666;
    zetas[44]=-1618; zetas[45]=-1162; zetas[46]=126;   zetas[47]=1469;
    zetas[48]=-853;  zetas[49]=-90;   zetas[50]=-271;  zetas[51]=830;
    zetas[52]=107;   zetas[53]=-1421; zetas[54]=-247;  zetas[55]=-951;
    zetas[56]=-398;  zetas[57]=961;   zetas[58]=-1508; zetas[59]=-725;
    zetas[60]=448;   zetas[61]=-1065; zetas[62]=677;   zetas[63]=-1275;
    zetas[64]=-1103; zetas[65]=430;   zetas[66]=555;   zetas[67]=843;
    zetas[68]=-1251; zetas[69]=871;   zetas[70]=1550;  zetas[71]=105;
    zetas[72]=422;   zetas[73]=587;   zetas[74]=177;   zetas[75]=-235;
    zetas[76]=-291;  zetas[77]=-460;  zetas[78]=1574;  zetas[79]=1653;
    zetas[80]=-246;  zetas[81]=778;   zetas[82]=1159;  zetas[83]=-147;
    zetas[84]=-777;  zetas[85]=1483;  zetas[86]=-602;  zetas[87]=1119;
    zetas[88]=-1590; zetas[89]=644;   zetas[90]=-872;  zetas[91]=349;
    zetas[92]=418;   zetas[93]=329;   zetas[94]=-156;  zetas[95]=-75;
    zetas[96]=817;   zetas[97]=1097;  zetas[98]=603;   zetas[99]=610;
    zetas[100]=1322; zetas[101]=-1285;zetas[102]=-1465;zetas[103]=384;
    zetas[104]=-1215;zetas[105]=-136; zetas[106]=1218; zetas[107]=-1335;
    zetas[108]=-874; zetas[109]=220;  zetas[110]=-1187;zetas[111]=-1659;
    zetas[112]=-1185;zetas[113]=-1530;zetas[114]=-1278;zetas[115]=794;
    zetas[116]=-1510;zetas[117]=-854; zetas[118]=-870; zetas[119]=478;
    zetas[120]=-108; zetas[121]=-308; zetas[122]=996;  zetas[123]=991;
    zetas[124]=958;  zetas[125]=-1460;zetas[126]=1522; zetas[127]=1628;
  end

  reg signed [15:0] mem [0:255];
  localparam signed [15:0] F = 16'sd1441;

  reg [8:0] len_r;
  reg [8:0] start_r;
  reg [8:0] j_r;
  reg [7:0] k_r;         // 127 downto 1
  reg [8:0] scale_j;     // final-pass index 0..255

  // butterfly datapath
  wire signed [15:0] rj    = mem[j_r];
  wire signed [15:0] rjl   = mem[j_r + len_r];
  wire signed [15:0] zeta_cur = zetas[k_r];
  wire signed [16:0] sum_ext   = rj + rjl;          // barrett_reduce(t + r[j+len])
  wire signed [15:0] barrett_in = sum_ext[15:0];    // fits: both operands < q in magnitude
  wire signed [15:0] barrett_out;
  barrett i_barrett (.a(barrett_in), .r(barrett_out));

  wire signed [15:0] diff = rjl - rj;               // r[j+len] - t
  wire signed [31:0] prod_bf = zeta_cur * diff;
  wire signed [15:0] fqmul_bf;
  montgomery_reduce i_fqmul_bf (.a(prod_bf), .r(fqmul_bf));

  // final-scale datapath (separate fqmul instance, only active in SCALE state)
  wire signed [15:0] scale_in = mem[scale_j];
  wire signed [31:0] prod_sc  = scale_in * F;
  wire signed [15:0] fqmul_sc;
  montgomery_reduce i_fqmul_sc (.a(prod_sc), .r(fqmul_sc));

  typedef enum logic [1:0] {IDLE, RUN, SCALE, DONE} state_e;
  state_e state_q, state_d;
  integer li;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= IDLE;
      done    <= 1'b0;
    end else begin
      state_q <= state_d;
      case (state_q)
        IDLE: begin
          done <= 1'b0;
          if (start_i) begin
            for (li = 0; li < 256; li = li + 1)
              mem[li] = coeffs_in[16*li +: 16];
            len_r   <= 9'd2;
            start_r <= 9'd0;
            j_r     <= 9'd0;
            k_r     <= 8'd127;
          end
        end
        RUN: begin
          mem[j_r]       <= barrett_out;
          mem[j_r+len_r] <= fqmul_bf;

          if (j_r == start_r + len_r - 1) begin
            if (start_r + (len_r << 1) >= 9'd256) begin
              if (len_r == 9'd128) begin
                scale_j <= 9'd0; // move to final scaling pass
              end else begin
                len_r   <= len_r << 1;
                start_r <= 9'd0;
                j_r     <= 9'd0;
                k_r     <= k_r - 1;
              end
            end else begin
              start_r <= start_r + (len_r << 1);
              j_r     <= start_r + (len_r << 1);
              k_r     <= k_r - 1;
            end
          end else begin
            j_r <= j_r + 1;
          end
        end
        SCALE: begin
          mem[scale_j] <= fqmul_sc;
          scale_j <= scale_j + 1;
        end
        DONE: begin
          for (li = 0; li < 256; li = li + 1)
            coeffs_out[16*li +: 16] <= mem[li];
          done <= 1'b1;
        end
        default: ;
      endcase
    end
  end

  always @(*) begin
    state_d = state_q;
    case (state_q)
      IDLE: if (start_i) state_d = RUN;
      RUN: begin
        if (j_r == start_r + len_r - 1 &&
            start_r + (len_r << 1) >= 9'd256 &&
            len_r == 9'd128)
          state_d = SCALE;
      end
      SCALE: if (scale_j == 9'd255) state_d = DONE;
      DONE: state_d = IDLE;
      default: state_d = IDLE;
    endcase
  end

endmodule
