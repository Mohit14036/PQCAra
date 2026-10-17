`timescale 1ns/1ps
// poly_basemul_montgomery.v -- matches ref/poly.c's
// poly_basemul_montgomery() EXACTLY (single polynomial pair, no
// accumulation, no reduce pass -- that's the K=3-specific behavior of
// polyvec_basemul_acc_montgomery, not this function):
//
//   for(i=0;i<KYBER_N/4;i++) {
//     basemul(&r[4*i],   &a[4*i],   &b[4*i],   zetas[64+i]);
//     basemul(&r[4*i+2], &a[4*i+2], &b[4*i+2], -zetas[64+i]);
//   }
// where basemul(r,a,b,zeta): r0=fqmul(a1,b1); r0=fqmul(r0,zeta); r0+=fqmul(a0,b0);
//                            r1=fqmul(a0,b1); r1+=fqmul(a1,b0);
//
// This is the same per-group datapath already verified inside
// polyvec_basemul_acc.v, extracted standalone (one polynomial pair
// instead of K=3 pairs, no accumulate, no barrett_reduce pass) so it can
// be chained directly after two ntt_fwd instances and before ntt_inv to
// build a full "multiply two polynomials via the NTT domain" pipeline
// -- the real-Kyber-parameter equivalent of the uploaded toy's
// negative-wrapped-convolution nwc_top.v pointwise-multiply stage.
// Reuses the single already-verified montgomery_reduce.v core.

module poly_basemul_montgomery (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start_i,
    input  wire [4095:0] a_in,
    input  wire [4095:0] b_in,
    output reg  [4095:0] r_out,
    output reg            done
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

  reg signed [15:0] a_mem [0:255];
  reg signed [15:0] b_mem [0:255];
  reg signed [15:0] r_mem [0:255];

  reg [6:0] i_r;   // 0..63 (KYBER_N/4)

  wire signed [15:0] a0v = a_mem[4*i_r+0];
  wire signed [15:0] a1v = a_mem[4*i_r+1];
  wire signed [15:0] a2v = a_mem[4*i_r+2];
  wire signed [15:0] a3v = a_mem[4*i_r+3];
  wire signed [15:0] b0v = b_mem[4*i_r+0];
  wire signed [15:0] b1v = b_mem[4*i_r+1];
  wire signed [15:0] b2v = b_mem[4*i_r+2];
  wire signed [15:0] b3v = b_mem[4*i_r+3];
  wire signed [15:0] zeta_pos = zetas[64+i_r];
  wire signed [15:0] zeta_neg = -zetas[64+i_r];

  // group 0 (a0,b0 / a1,b1), zeta = +zetas[64+i]
  wire signed [31:0] p_a1b1 = a1v * b1v;
  wire signed [15:0] fq_a1b1; montgomery_reduce m0 (.a(p_a1b1), .r(fq_a1b1));
  wire signed [31:0] p_a1b1_zp = fq_a1b1 * zeta_pos;
  wire signed [15:0] fq_a1b1_zp; montgomery_reduce m1 (.a(p_a1b1_zp), .r(fq_a1b1_zp));
  wire signed [31:0] p_a0b0 = a0v * b0v;
  wire signed [15:0] fq_a0b0; montgomery_reduce m2 (.a(p_a0b0), .r(fq_a0b0));
  wire signed [15:0] r0_new = fq_a1b1_zp + fq_a0b0;
  wire signed [31:0] p_a0b1 = a0v * b1v;
  wire signed [15:0] fq_a0b1; montgomery_reduce m3 (.a(p_a0b1), .r(fq_a0b1));
  wire signed [31:0] p_a1b0 = a1v * b0v;
  wire signed [15:0] fq_a1b0; montgomery_reduce m4 (.a(p_a1b0), .r(fq_a1b0));
  wire signed [15:0] r1_new = fq_a0b1 + fq_a1b0;

  // group 1 (a2,b2 / a3,b3), zeta = -zetas[64+i]
  wire signed [31:0] p_a3b3 = a3v * b3v;
  wire signed [15:0] fq_a3b3; montgomery_reduce m5 (.a(p_a3b3), .r(fq_a3b3));
  wire signed [31:0] p_a3b3_zn = fq_a3b3 * zeta_neg;
  wire signed [15:0] fq_a3b3_zn; montgomery_reduce m6 (.a(p_a3b3_zn), .r(fq_a3b3_zn));
  wire signed [31:0] p_a2b2 = a2v * b2v;
  wire signed [15:0] fq_a2b2; montgomery_reduce m7 (.a(p_a2b2), .r(fq_a2b2));
  wire signed [15:0] r2_new = fq_a3b3_zn + fq_a2b2;
  wire signed [31:0] p_a2b3 = a2v * b3v;
  wire signed [15:0] fq_a2b3; montgomery_reduce m8 (.a(p_a2b3), .r(fq_a2b3));
  wire signed [31:0] p_a3b2 = a3v * b2v;
  wire signed [15:0] fq_a3b2; montgomery_reduce m9 (.a(p_a3b2), .r(fq_a3b2));
  wire signed [15:0] r3_new = fq_a2b3 + fq_a3b2;

  typedef enum logic [1:0] {IDLE, LOAD, RUN, DONE} state_e;
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
            for (li = 0; li < 256; li = li + 1) begin
              a_mem[li] = a_in[16*li +: 16];
              b_mem[li] = b_in[16*li +: 16];
            end
            i_r <= 7'd0;
          end
        end
        RUN: begin
          r_mem[4*i_r+0] <= r0_new;
          r_mem[4*i_r+1] <= r1_new;
          r_mem[4*i_r+2] <= r2_new;
          r_mem[4*i_r+3] <= r3_new;
          if (i_r != 7'd63) i_r <= i_r + 1;
        end
        DONE: begin
          for (li = 0; li < 256; li = li + 1)
            r_out[16*li +: 16] <= r_mem[li];
          done <= 1'b1;
        end
        default: ;
      endcase
    end
  end

  always @(*) begin
    state_d = state_q;
    case (state_q)
      IDLE: if (start_i) state_d = LOAD;
      LOAD: state_d = RUN;
      RUN: if (i_r == 7'd63) state_d = DONE;
      DONE: state_d = IDLE;
      default: state_d = IDLE;
    endcase
  end

endmodule
