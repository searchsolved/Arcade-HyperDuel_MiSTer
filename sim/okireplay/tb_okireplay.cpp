// jt6295 alone, driven by MAME's OKI command stream (sim/mame/tap_oki.lua,
// W lines with emulated time), to measure what the two jt6295 patches
// change for this game's sound (docs/ACCURACY.md 3.7). The chip runs at
// MAME's clock (4 MHz / 16 / 16 * 132 = 2.0625 MHz, hyprduel.cpp L443) so
// busy windows line up with MAME's; command bytes are written at their
// MAME timestamps.
// Usage: tb_okireplay <oki rom .bin> <tap .csv> <out prefix>
// Writes <prefix>_pcm.raw (s16le, one value per chip sample) and prints:
//   starts, starts that found their voice busy (a restart in the original
//   jt6295, ignored with patch 2), total busy enables per voice, sum of
//   squares of the output.
#include "Vjt6295.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cmath>
#include <cstring>
#include <fstream>
#include <string>
#include <vector>

struct Cmd { double t; int b; };

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    std::ifstream rf(argv[1], std::ios::binary);
    std::vector<uint8_t> rom((std::istreambuf_iterator<char>(rf)), {});
    std::vector<Cmd> cmds;
    {
        std::ifstream cf(argv[2]);
        std::string line;
        while (std::getline(cf, line)) {
            if (line.size() < 2 || line[0] != 'W') continue;
            int fr = 0; unsigned b = 0; double t = 0;
            if (sscanf(line.c_str(), "W,%d,%x,%lf", &fr, &b, &t) == 3) cmds.push_back({t, (int)b});
        }
    }
    std::string pre = argv[3];
    FILE *pcm = fopen((pre + "_pcm.raw").c_str(), "wb");
    Vjt6295 t;
    const int DIV = 4;                       // clk / 4 = cen (3 idle clocks settle the ROM read)
    const double CEN_HZ = 4000000.0 / 16 / 16 * 132;
    uint64_t cen_n = 0;
    auto tick = [&]() {
        static uint64_t clk = 0;
        t.cen = (clk % DIV) == 0;
        t.rom_data = rom[t.rom_addr % rom.size()];
        t.rom_ok = 1;
        t.clk = 0; t.eval(); t.clk = 1; t.eval();
        if (t.cen) cen_n++;
        if (t.sample) { int16_t v = t.sound; fwrite(&v, 2, 1, pcm); }
        clk++;
    };
    t.rst = 1; t.ss = 1; t.wrn = 1; t.din = 0;
    for (int i = 0; i < 1000; i++) tick();
    t.rst = 0;
    uint64_t starts = 0, busy_starts = 0, busy_en[4] = {0, 0, 0, 0};
    double sumsq = 0; uint64_t nsamp = 0;
    int pend = -1;
    size_t ci = 0;
    double t_end = cmds.empty() ? 0 : cmds.back().t + 5.0;
    const char *tw = getenv("TRACE_T0"); double tr0 = tw ? atof(tw) : 1e9;
    const char *tw1 = getenv("TRACE_T1"); double tr1 = tw1 ? atof(tw1) : 0;
    int last_dout = -1;
    while ((double)cen_n / CEN_HZ < t_end) {
        double now = (double)cen_n / CEN_HZ;
        if (now >= tr0 && now <= tr1 && t.dout != last_dout) {
            printf("t=%.6f dout=%02x\n", now, t.dout); last_dout = t.dout;
        }
        if (ci < cmds.size() && now >= cmds[ci].t) {
            int b = cmds[ci].b;
            if (pend >= 0) {
                starts++;
                int sel = (b >> 4) & 0xf;
                if (t.dout & sel) busy_starts++;
                pend = -1;
            } else if (b & 0x80) pend = b & 0x7f;
            if (now >= tr0 && now <= tr1) printf("t=%.6f write %02x dout=%02x\n", now, b, t.dout);
            t.din = b; t.wrn = 0; tick(); t.wrn = 1;
            ci++;
            continue;
        }
        uint64_t c0 = cen_n;
        tick();
        if (cen_n != c0) for (int v = 0; v < 4; v++) if (t.dout & (1 << v)) busy_en[v]++;
        if (t.sample) { sumsq += (double)t.sound * t.sound; nsamp++; }
    }
    fclose(pcm);
    printf("commands %zu starts %llu busy_starts %llu busy_enables %llu %llu %llu %llu samples %llu rms %.3f\n",
           cmds.size(), (unsigned long long)starts, (unsigned long long)busy_starts,
           (unsigned long long)busy_en[0], (unsigned long long)busy_en[1],
           (unsigned long long)busy_en[2], (unsigned long long)busy_en[3],
           (unsigned long long)nsamp, nsamp ? std::sqrt(sumsq / nsamp) : 0.0);
    return 0;
}
