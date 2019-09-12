/////////////////////////////////
// Filename    : xlr8_rc_input.v
// Author      : 
// Description : A collection of pwm_recv channels (up to 32) and the
//                AVR IO registers to access them.
//                Each PR Separately enabled/disabled).
//                3 Registers
//                  ControlRegister : 
//                        [7]   = enable channel  (write, read returns enable with/of selected channel)
//                        [6]   = disable channel (write, always read as zero)
//                        [5]   = update channel zero width (always read as zero)
//                        [4:0] = pwm_recv channel to enable/disable/update
//
//                  PWL:  [7:0] = lower        8 bits of pwm_recv width
//                  PWH:  [7:0] = upper        8 bits of pwm_recv width
//
//                   To start a channel the channel is reset first,
//                    then write the control register with the desired channel and
//                    both the enable and update bits set
//
// Copyright 2017, Superion Technology Group. All Rights Reserved
/////////////////////////////////

module xlr8_rc_input
 #(parameter NUM_PWM_RECVS       = 4,
   parameter PRCR_ADDR           = 6'h0, // pwm_recv control register
   parameter PRPULSE_WIDTH1_ADDR = 6'h0, // pwm_recv width high
   parameter PRPULSE_WIDTH0_ADDR = 6'h0) // pwm_recv width low
  (input logic clk,
  input logic                   en1mhz, // clock enable at 1MHz rate
  input logic                   rstn,
  // Register access for registers in first 64
  input [5:0]                   adr,
  input [7:0]                   dbus_in,
  output [7:0]                  dbus_out,
  input                         iore,
  input                         iowe,
  output wire                   io_out_en,
  // Register access for registers not in first 64
  input wire [7:0]              ramadr,
  input wire                    ramre,
  input wire                    ramwe,
  input wire                    dm_sel,
  // External inputs/outputs from Arduino perimeter
  output logic [NUM_PWM_RECVS-1:0]  pwm_recvs_en,
  input  logic [NUM_PWM_RECVS-1:0]  pw_in
  );

  /////////////////////////////////
  // Local Parameters
  /////////////////////////////////
  // Registers in I/O address range x0-x3F (memory addresses -x20-0x5F)
  //  use the adr/iore/iowe inputs. Registers in the extended address
  //  range (memory address 0x60 and above) use ramadr/ramre/ramwe
  localparam  PRCR_DM_LOC             = (PRCR_ADDR >= 16'h60) ? 1 : 0;
  localparam  PRPULSE_WIDTH1_DM_LOC   = (PRPULSE_WIDTH1_ADDR >= 16'h60) ? 1 : 0;
  localparam  PRPULSE_WIDTH0_DM_LOC   = (PRPULSE_WIDTH0_ADDR >= 16'h60) ? 1 : 0;

  // Control register definitions
  localparam PREN_BIT   = 7; // Enable channel
  localparam PRDIS_BIT  = 6; // Disable Channel
  localparam PRUP_BIT   = 5; // Update Channel
  localparam PRCHAN_LSB = 0;    

  /////////////////////////////////
  // Signals
  /////////////////////////////////
  /*AUTOREG*/
  /*AUTOWIRE*/ 
  // Address decoding, control, & data declarations
  logic prcr_sel;
  logic pr_pulse_width1_sel;
  logic pr_pulse_width0_sel;
  logic prcr_we ;
  logic prcr_re ;
  logic pr_pulse_width1_re ;
  logic pr_pulse_width0_re ;
  logic [7:0] prcr_rdata;
  logic [7:0] pr_pulse_width1_rdata;
  logic [7:0] pr_pulse_width0_rdata;
  //
  logic       PREN;                          // Current Channel enable state
  logic [4:0] PRCHAN;                        // Current Channel
  logic [4:0] chan_in;
  logic [15:0] pw_count [NUM_PWM_RECVS-1:0]; // Used to measure PWM pulse width
  logic [15:0] chan_pw [NUM_PWM_RECVS-1:0];  // pwm_recv pulse width per channel
  logic [NUM_PWM_RECVS-1:0] pw_sync_in_1;    // rc input synchronizer 1
  logic [NUM_PWM_RECVS-1:0] pw_sync_in_2;    // rc input synchronizer 2
  logic state;                               // state to determine if the host is reading
  logic hold_pwm;                            // Don't allow pwm update if host is reading
  logic [9:0] timer_1ms;                           // 1ms timer
  logic en1ms;                                     // 1ms tick
  logic [5:0] watchdog_timer [NUM_PWM_RECVS-1:0];  // RC inactivity detections
  logic [NUM_PWM_RECVS-1:0] watchdog_expired;      // Channel watchdog alert

  localparam IDLE = 1'b0;
  localparam ONE_READ = 1'b1;


  /////////////////////////////////
  // Functions and Tasks
  /////////////////////////////////

  /////////////////////////////////
  // Main Code
  /////////////////////////////////

  // Address decode and write read control
  assign prcr_sel            = PRCR_DM_LOC           ?  (dm_sel && ramadr == PRCR_ADDR )   : (adr[5:0] == PRCR_ADDR[5:0] ); 
  assign pr_pulse_width1_sel = PRPULSE_WIDTH1_DM_LOC ?  (dm_sel && ramadr == PRPULSE_WIDTH1_ADDR ) : (adr[5:0] == PRPULSE_WIDTH1_ADDR[5:0] );
  assign pr_pulse_width0_sel = PRPULSE_WIDTH0_DM_LOC ?  (dm_sel && ramadr == PRPULSE_WIDTH0_ADDR ) : (adr[5:0] == PRPULSE_WIDTH0_ADDR[5:0] );
  assign prcr_we             = prcr_sel            && (PRCR_DM_LOC           ?  ramwe : iowe); 
  assign prcr_re             = prcr_sel            && (PRCR_DM_LOC           ?  ramre : iore); 
  assign pr_pulse_width1_re  = pr_pulse_width1_sel && (PRPULSE_WIDTH1_DM_LOC ?  ramre : iore);
  assign pr_pulse_width0_re  = pr_pulse_width0_sel && (PRPULSE_WIDTH0_DM_LOC ?  ramre : iore); 
  // Host Read Pulsewidth
  assign dbus_out  = ({8{prcr_sel}}            & prcr_rdata)            |
                     ({8{pr_pulse_width1_sel}} & pr_pulse_width1_rdata) | 
                     ({8{pr_pulse_width0_sel}} & pr_pulse_width0_rdata); 
  assign io_out_en = prcr_re            || 
                     pr_pulse_width1_re ||
                     pr_pulse_width0_re; 

   // Control Register write logic
  assign chan_in = dbus_in[PRCHAN_LSB +: 5];
  always @(posedge clk or negedge rstn)
    begin
      if (!rstn)
        begin
          PREN             <= 1'b0;
          PRCHAN           <= 5'h0;
          pwm_recvs_en     <= {NUM_PWM_RECVS{1'b0}};
        end
      else if (prcr_we)
        begin
          // Or in the enable bit from the host if the disable is not set
          PREN   <= dbus_in[PREN_BIT]       ||   (pwm_recvs_en[chan_in] && ~dbus_in[PRDIS_BIT]);
          // Select the PR to be enables or disabled
          PRCHAN                <= chan_in;
          pwm_recvs_en[chan_in] <= dbus_in[PREN_BIT] | (pwm_recvs_en[chan_in] && ~dbus_in[PRDIS_BIT]);
        end
      else
        begin
          PREN     <= pwm_recvs_en[PRCHAN];
        end
    end // always @ (posedge clk or negedge rstn)


  // Control Register read logic
  assign prcr_rdata = ({7'h0,PREN}     << PREN_BIT) |
                      ({5'h0,PRCHAN}   << PRCHAN_LSB);

  // Pulsewidth register read data for selected channel
  assign pr_pulse_width1_rdata = chan_pw[PRCHAN][15:8];
  assign pr_pulse_width0_rdata = chan_pw[PRCHAN][7:0];

  // 1 millisecond timer = (1000 x 1us)
  always@(posedge clk or negedge rstn) begin
    if (!rstn)
      begin
        timer_1ms <= 10'b0;
        en1ms     <= 1'b0;
      end
    else
      begin
        if (en1mhz)
          begin
            if (timer_1ms <= 1000)
              begin
                timer_1ms <= timer_1ms + 1'b1;
                en1ms <= 1'b0;
              end
            else
              begin
                timer_1ms <= 10'b0;
                en1ms     <= 1'b1;
              end
          end
        else
          begin
            timer_1ms <= timer_1ms;
            en1ms <= en1ms;
          end
      end
  end // always

  // RC input synchronizers (1us sampling)
  genvar i;
  generate
  for (i=0;i<NUM_PWM_RECVS;i++) begin : gen_sync
    always @(posedge clk or negedge rstn) begin
      if (!rstn)
        begin
          pw_sync_in_1[i] <= 1'b0;
          pw_sync_in_2[i] <= 1'b0;
        end
      else
        begin
          if (en1mhz)
            begin
              pw_sync_in_1[i] <= pw_in[i];        // Stage 1
              pw_sync_in_2[i] <= pw_sync_in_1[i]; // Stage 2
            end
          else
            begin
              pw_sync_in_1[i] <= pw_sync_in_1[i]; // keep between samples
              pw_sync_in_2[i] <= pw_sync_in_2[i]; // keep between samples
            end
        end
    end // always
  end // for
  endgenerate

  // The channel based watchdog timers
  generate
  for (i=0;i<NUM_PWM_RECVS;i++) begin : gen_watchdog
    always @(posedge clk or negedge rstn) begin
      if (!rstn)
        begin
          watchdog_timer[i] <= 6'b0;
          watchdog_expired[i] <= 1'b0;
        end
      else
        begin
          if (en1mhz)
            begin
              if (pw_sync_in_1[i] && !pw_sync_in_2[i]) // positive pulse
                begin
                  watchdog_timer[i] <= 6'b0;          // we saw rc input activity, zero the watchdog
                  watchdog_expired[i] <= 1'b0;        // keep watchdog quiet
                end
              else if (en1ms)
                begin
                  if (watchdog_timer[i] < 6'd50)      // if the watchdog is less than 50ms, count
                    begin
                      watchdog_timer[i] <= watchdog_timer[i] + 1'b1;
                      watchdog_expired[i] <= 1'b0;    // keep watchdog quiet
                    end
                  else
                    begin
                      watchdog_timer[i] <= watchdog_timer[i];
                      watchdog_expired[i] <= 1'b1;    // watchdog barks
                    end
                end
              else
                begin // no activity not on 1ms interval
                  watchdog_timer[i] <= watchdog_timer[i];        // hold
                  watchdog_expired[i] <= watchdog_expired[i];    // hold
                end
            end
          else // not 1mhz
            begin
              watchdog_timer[i] <= watchdog_timer[i];            // hold
              watchdog_expired[i] <= watchdog_expired[i];        // hold
            end
        end
    end // always
  end // for
  endgenerate

  // The following determines the leading and trailing edges of the rc_inputs.
  // On the leading edge, we begin counting.
  // While between Leading and Trailing edges, we continue counting.
  // On the trailing edge we we stop counting and transfer the accumulated
  //   count to the host pulsewidth register.
  //   If the host happens to be reading at this time, we defer this transfer
  //   until the host is finished reading.
  generate
  for (i=0;i<NUM_PWM_RECVS;i++) begin : gen_tim
    always @(posedge clk or negedge rstn) begin
      if (!rstn)
        begin
          pw_count[i] <= 16'h0;
          chan_pw[i] <= 16'b0;
        end
      else if (pwm_recvs_en[i])                           // Process only enabled channels
        begin
          if(en1mhz)
            begin
              if (watchdog_expired[i])
                begin
                  pw_count[i] <= 16'h0;
                  chan_pw[i] <= 16'b0;
                end
              else if (pw_sync_in_1[i] == 1'b1 && pw_sync_in_2[i] == 1'b0) // BEGINNING OF PULSE
                begin
                  pw_count[i] <= 16'd1;                   // start counting
                  chan_pw[i] <= chan_pw[i];               // hold reporting register
                end
              else if (pw_sync_in_1[i] == 1'b1 && pw_sync_in_2[i] == 1'b1) // MIDDLE OF PULSE
                begin
                  chan_pw[i] <= chan_pw[i];               // hold reporting register
                  if (pw_count[i] < 16'hfffe)             // don't let count rollover
                    pw_count[i] <= (pw_count[i] + 16'd1); // continue counting
                  else
                    pw_count[i] <= pw_count[i];
                end
              else if (pw_sync_in_1[i] == 1'b0 && pw_sync_in_2[i] == 1'b1) // END OF PULSE
                begin
                  pw_count[i] <= pw_count[i];             // hold the count
                  if (!hold_pwm)
                    begin
                      chan_pw[i] <= pw_count[i];          // transfer width to reporting register
                    end
                  else
                    begin
                      chan_pw[i] <= chan_pw[i];           // hold reporting register
                    end
                end
              else                                                         // BETWEEN PULSES
                begin
                  pw_count[i] <= pw_count[i];             // no counting, hold count
                  if (!hold_pwm)
                    begin
                      chan_pw[i] <= pw_count[i];          // transfer width to reporting register
                    end
                  else
                    begin
                      chan_pw[i] <= chan_pw[i];           // hold reported pulse width
                    end
                end
            end
          else // not 16MHz
            begin
              pw_count[i] <= pw_count[i]; // hold values
              chan_pw[i] <= chan_pw[i];
            end
        end
      else // Disabled
        begin
          pw_count[i] <= 16'h0;
          chan_pw[i] <= 16'b0;
        end

    end //always
  end // for
  endgenerate
  

  // State machine to detect a 2 byte host read of the pulsewidth.
  // We set the signal "hold_pwm" if the first byte has been read but the
  // second has not, thus blocking updates to the pulse width register.
  always @(posedge clk or negedge rstn)
    begin
      if (!rstn)
        begin
          state <= IDLE;
          hold_pwm <= 1'b0;
        end
      else
        begin
          case (state)
            IDLE:
              begin
                if (pr_pulse_width0_re || pr_pulse_width1_re) // First byte read
                  begin
                    state <= ONE_READ;
                    hold_pwm <= 1'b1;                         // Block PWM transfer
                  end
                else
                  begin
                    state <= IDLE;                            // No host read process
                    hold_pwm <= 1'b0;
                  end
              end
            ONE_READ:                                         // The host has read one byte of 2
              begin
                if (prcr_we)                                  // Reset the state machine if the control register is written
                  begin
                    state <= IDLE;
                    hold_pwm <= 1'b0;
                  end
                else if (pr_pulse_width0_re || pr_pulse_width1_re)
                  begin                                       // The second byte has been read
                    state <= IDLE;
                    hold_pwm <= 1'b0;                         // Enable pulsewidth updates
                  end
                else
                  begin                                       // Waiting for second byte read
                    state <= ONE_READ;
                    hold_pwm <= 1'b1;
                  end
              end
          endcase
        end
    end


   /////////////////////////////////
   // Assertions
   /////////////////////////////////


   /////////////////////////////////
   // Cover Points
   /////////////////////////////////

`ifdef SUP_COVER_ON
`endif

endmodule

