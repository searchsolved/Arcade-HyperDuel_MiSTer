/*  This file is part of JT6295.
    JT6295 program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    JT6295 program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with JT6295.  If not, see <http://www.gnu.org/licenses/>.

    Author: Jose Tejada Gomez. Twitter: @topapate
    Version: 1.0
    Date: 6-1-2020 */

module jt6295_ctrl(
    input                  rst,
    input                  clk,
    input                  cen,     // master clock enable (the datasheet's "clock")
    input                  ss,      // sample-rate pin: n = 4 (H) or 5 (L)
    input                  cen4,
    input                  cen1,
    // CPU
    input                  wrn,
    input      [ 7:0]      din,
    // Channel address
    output reg [17:0]      start_addr,
    output reg [17:0]      stop_addr,
    // Attenuation
    output reg [ 3:0]      att,
    // ROM interface
    output     [ 9:0]      rom_addr,
    input      [ 7:0]      rom_data,
    input                  rom_ok,
    // flow control
    output reg [ 3:0]      start,
    output reg [ 3:0]      stop,
    input      [ 3:0]      busy,
    input      [ 3:0]      ack,
    input                  zero,
    // Patch 3 (PROVENANCE.md): BUSY as the datasheet times it
    output reg [ 3:0]      rdbusy
);

reg [3:0] status;          // MAME's per-voice "playing" (patch 3)

reg  last_wrn;
wire negedge_wrn  = !wrn && last_wrn;

// new request
reg [6:0] phrase;
reg       push, pull;
reg [3:0] ch, new_att;
reg       cmd;

always @(posedge clk) begin
    last_wrn <= wrn;
end

reg stop_clr;

`ifdef JT6295_DUMP
integer fdump;
integer ticks=0;
initial begin
    fdump=$fopen("jt6295.log");
end
always @(posedge zero) ticks<=ticks+1;
always @(posedge clk ) begin
    if( negedge_wrn ) begin
        if( !cmd && !din[7] ) begin
            $fwrite(fdump,"@%0d - Mute %1X\n", ticks, din[6:3]);
        end
        if( cmd ) begin
            $fwrite(fdump,"@%0d - Start %1X, phrase %X, Att %X\n",
                ticks, din[7:4], phrase, din[3:0] );
        end
    end
end
`endif


// Bus interface
// Patch 3 (PROVENANCE.md, R17): the status register is a per-channel
// "playing" flag kept here, as MAME's okim6295 voice.m_playing:
//  - set when a start's second byte is accepted (channel not playing),
//  - cleared at once by a stop command,
//  - cleared when the channel's phrase ends in jt6295_serial (falling edge
//    of the committed busy flag) unless a start for it is still on its way.
// Starts to a playing channel are dropped here (patch 2). A start accepted
// for a channel clears that channel's pending stop (the new phrase replaces
// whatever is left of the old one), and a stop clears a start that has not
// reached jt6295_serial yet, so the two requests never meet in one slot and
// a later start can neither cancel a stop nor be lost to it. Upstream
// cleared every pending stop on any start's first byte and replaced the
// stop register on each stop command.
reg [3:0] spend;           // start accepted, not yet acknowledged by serial
reg [3:0] kill;            // stop written: cancel any queued start
reg [3:0] busy_l;          // busy, last clock
reg [3:0] ack_l;           // ack, last clock
reg [6:0] cmd_phrase;      // phrase of the start being written
wire [3:0] accept = din[7:4] & ~status;
// BUSY read by the CPU, timed as the MSM6295 datasheet (OKI data book
// p. 73, "Start and Stop of 1 Channel"): "H" 15 x n clocks after a start's
// second byte, "L" at the next sample after a stop (the stop takes effect
// in the channel's slot) or when the phrase ends. n = 4 (SS high) or 5.
// `status` above stays MAME's "playing" flag and decides whether a start
// is accepted: the datasheet does not cover a start to a playing channel
// or a restart within one sample of a stop (it says to wait a sample),
// and games do both (Ganbare Ginkun restarts 42 us after a stop), so the
// outcome follows MAME, where such a restart plays.
reg  [6:0] sdly0, sdly1, sdly2, sdly3;
reg  [3:0] sarm;
wire [6:0] sdly_n = ss ? 7'd60 : 7'd75;
wire [3:0] sdone  = sarm & { sdly3==7'd1, sdly2==7'd1, sdly1==7'd1, sdly0==7'd1 };
// a start whose phrase fetch has not finished is replaced by a newer one
// (as upstream); its channel must not stay marked as playing
// (only when the new command is accepted: an ignored start changes nothing)
wire [3:0] dropped = ((pull | push) && accept != 4'd0) ? ch & ~accept : 4'd0;
wire [3:0] ended  = busy_l & ~busy & ~spend & ~ack;
// pending stops: cleared once committed (upstream), and, when a start
// reaches the channel (ack rises), dropped: the start was written after the
// stop, so its phrase replaces the stopped one, as MAME's stop-then-start
wire [3:0] stop_base = (cen4 ? stop & busy : stop) & ~(ack & ~ack_l);
// a pending stop leaving the register other than by a start's acknowledge
// has taken effect at its channel's sample point
wire [3:0] stopped = stop & ~(cen4 ? stop & busy : stop) & ~(ack & ~ack_l);

always @(posedge clk) begin
    if( rst ) begin
        cmd      <= 1'b0;
        stop     <= 4'd0;
        ch       <= 4'd0;
        pull     <= 1'b1;
        phrase   <= 7'd0;
        new_att  <= 0;
        status   <= 4'd0;
        spend    <= 4'd0;
        kill     <= 4'd0;
        busy_l   <= 4'd0;
        ack_l    <= 4'd0;
        cmd_phrase <= 7'd0;
        rdbusy   <= 4'd0;
        sarm     <= 4'd0;
        { sdly0, sdly1, sdly2, sdly3 } <= 28'd0;
    end else begin
        busy_l <= busy;
        ack_l  <= ack;
        kill   <= 4'd0;
        spend  <= spend & ~ack;
        status <= status & ~ended;
        rdbusy <= (rdbusy & ~ended & ~stopped) | sdone;
        if( cen ) begin
            if( sarm[0] ) sdly0 <= sdly0 - 7'd1;
            if( sarm[1] ) sdly1 <= sdly1 - 7'd1;
            if( sarm[2] ) sdly2 <= sdly2 - 7'd1;
            if( sarm[3] ) sdly3 <= sdly3 - 7'd1;
            sarm <= sarm & ~sdone;
        end
        stop <= stop_base;
        if( push ) pull <= 1'b0;
        if( negedge_wrn  ) begin // new write
            if( cmd ) begin // 2nd byte
                cmd     <= 1'b0;
                if( accept != 4'd0 ) begin // patch 2: starts to playing channels are dropped
                    phrase  <= cmd_phrase;
                    ch      <= accept;
                    new_att <= din[3:0];
                    pull    <= 1'b1;
                end
                status  <= (status & ~ended & ~dropped) | accept;
                spend   <= (spend & ~ack & ~dropped) | accept;
                sarm    <= (sarm & ~dropped & ~(cen ? sdone : 4'd0)) | accept;
                if( accept[0] ) sdly0 <= sdly_n;
                if( accept[1] ) sdly1 <= sdly_n;
                if( accept[2] ) sdly2 <= sdly_n;
                if( accept[3] ) sdly3 <= sdly_n;
            end
            else if( din[7] ) begin // channel start
                cmd_phrase <= din[6:0]; // phrase is taken only if the start is accepted
                cmd    <= 1'b1; // wait for second byte
            end else begin // stop data
                stop   <= stop_base | din[6:3];
                status <= status & ~ended & ~din[6:3];
                spend  <= spend & ~ack & ~din[6:3];
                sarm   <= sarm & ~din[6:3];   // a start still in its 15 x n delay is cancelled
                kill   <= din[6:3];
            end
        end
    end
end

reg [17:0] new_start;
reg [17:8] new_stop;
reg [ 2:0] st, addr_lsb;
reg        wrom;

assign rom_addr = { phrase, addr_lsb };

// Request phrase address
always @(posedge clk) begin
    if( rst ) begin
        st         <= 7;
        att        <= 0;
        start_addr <= 0;
        stop_addr  <= 0;
        start      <= 0;
        push       <= 0;
        addr_lsb   <= 0;
    end else begin
        if( st!=7 ) begin
            wrom <= 0;
            if( !wrom && rom_ok ) begin
                st       <= st+3'd1;
                addr_lsb <= st;
                wrom     <= 1;
            end
        end
        case( st )
            7: begin
                start    <= start & ~ack & ~kill;
                addr_lsb <= 0;
                if(pull) begin
                    st       <= 0;
                    wrom     <= 1;
                    push     <= 1;
                end
            end
            0:;
            1: new_start[17:16] <= rom_data[1:0];
            2: new_start[15: 8] <= rom_data;
            3: new_start[ 7: 0] <= rom_data;
            4: new_stop [17:16] <= rom_data[1:0];
            5: new_stop [15: 8] <= rom_data;
            6: begin
                // patch 3: keep earlier unacknowledged starts (upstream
                // replaced them); a stop since the write drops the start
                start       <= (start & ~ack & ~kill) | (ch & spend & ~kill);
                start_addr  <= new_start;
                stop_addr   <= {new_stop[17:8], rom_data} ;
                att         <= new_att;
                push        <= 0;
            end
        endcase
    end
end

endmodule