// Regression test for #22: the ASIMD vector FP lane narrow/widen instructions
// FCVTN/FCVTN2, FCVTL/FCVTL2 and FCVTXN/FCVTXN2 had no gadget in the
// guest-arm64 Asbestos backend, so any guest executing one was killed outright
// (numpy's float64<->float32 .astype() hits them). These are mandatory
// ARMv8.0-A Advanced SIMD instructions and iSH advertises `asimd`.
//
// Every expected value here was taken from running the same helpers natively
// on an Apple Silicon host, so this checks the emulated result bit-for-bit
// against real hardware rather than against a re-derivation of the spec.
//
// Build:  aarch64-linux-musl-gcc -static -O0 -o regress_asimd_fcvt
//             regress_asimd_fcvt.c regress_asimd_fcvt.S
// Run:    ish -r <rootfs> /tmp/regress_asimd_fcvt
// Exit status is 0 when every case passes.
//
// The instructions live in a separate .S file on purpose: with inline asm the
// compiler is free to insert code between the load, the instruction under test
// and the store, which silently invalidates the result.

#include <stdio.h>
#include <stdint.h>
#include <string.h>
void do_fcvtn(const void*,void*); void do_fcvtn2(const void*,void*,const void*);
void do_fcvtl(const void*,void*); void do_fcvtl2(const void*,void*);
void do_fcvtxn(const void*,void*); void do_fcvtxn2(const void*,void*,const void*);
void do_fcvtn_h(const void*,void*); void do_fcvtl_h(const void*,void*);
static int pass,fail;
static void eq(const char*n,uint64_t*got,uint64_t e0,uint64_t e1){
  if(got[0]==e0&&got[1]==e1){pass++;printf("  PASS  %-8s %016llx %016llx\n",n,
     (unsigned long long)got[0],(unsigned long long)got[1]);}
  else{fail++;printf("  FAIL  %-8s got %016llx %016llx want %016llx %016llx\n",n,
     (unsigned long long)got[0],(unsigned long long)got[1],
     (unsigned long long)e0,(unsigned long long)e1);}
}
#define A __attribute__((aligned(16)))
int main(void){
  A uint64_t d2[2]={0x3FF8000000000000ULL,0xC002000000000000ULL};   // 1.5, -2.25
  A uint64_t s2[2]={((uint64_t)0xC0980000u<<32)|0x40600000u,0};      // 3.5f, -4.75f
  A uint64_t s4[2]={((uint64_t)0xC0980000u<<32)|0x40600000u,
                    ((uint64_t)0x41100000u<<32)|0x41000000u};        // +8.0f,9.0f high
  A uint64_t seed[2]={((uint64_t)0x41000000u<<32)|0x41100000u,0};    // 9.0f,8.0f
  A uint64_t o[2];
  printf("=== FCVTN / FCVTN2 / FCVTL / FCVTL2 / FCVTXN / FCVTXN2 ===\n");
  o[0]=o[1]=0; do_fcvtn(d2,o);
    eq("FCVTN",o, ((uint64_t)0xC0100000u<<32)|0x3FC00000u, 0);
  o[0]=o[1]=0; do_fcvtn2(d2,o,seed);
    eq("FCVTN2",o, seed[0], ((uint64_t)0xC0100000u<<32)|0x3FC00000u);
  o[0]=o[1]=0; do_fcvtl(s2,o);
    eq("FCVTL",o, 0x400C000000000000ULL, 0xC013000000000000ULL);   // 3.5, -4.75
  o[0]=o[1]=0; do_fcvtl2(s4,o);
    eq("FCVTL2",o, 0x4020000000000000ULL, 0x4022000000000000ULL);  // 8.0, 9.0
  o[0]=o[1]=0; do_fcvtxn(d2,o);
    eq("FCVTXN",o, ((uint64_t)0xC0100000u<<32)|0x3FC00000u, 0);
  o[0]=o[1]=0; do_fcvtxn2(d2,o,seed);
    eq("FCVTXN2",o, seed[0], ((uint64_t)0xC0100000u<<32)|0x3FC00000u);

  printf("=== sz=0 forms (single<->half) ===\n");
  A uint64_t f4[2]={((uint64_t)0xC0980000u<<32)|0x40600000u,
                    ((uint64_t)0x41100000u<<32)|0x41000000u};
  o[0]=o[1]=0; do_fcvtn_h(f4,o);
    // 3.5->0x4300, -4.75->0xC4C0, 8.0->0x4800, 9.0->0x4880
    eq("FCVTN.4h",o, ((uint64_t)0x4880ULL<<48)|((uint64_t)0x4800ULL<<32)|((uint64_t)0xC4C0ULL<<16)|0x4300ULL, 0);
  A uint64_t h4[2]={((uint64_t)0x4880ULL<<48)|((uint64_t)0x4800ULL<<32)|((uint64_t)0xC4C0ULL<<16)|0x4300ULL,0};
  o[0]=o[1]=0; do_fcvtl_h(h4,o);
    eq("FCVTL.4s",o, ((uint64_t)0xC0980000u<<32)|0x40600000u, ((uint64_t)0x41100000u<<32)|0x41000000u);

  printf("=== FCVTXN round-to-odd semantics ===\n");
  // A double just above 1.0 that is NOT representable in single: round-to-odd
  // must give the odd-mantissa neighbour 0x3F800001, whereas FCVTN (round to
  // nearest even) gives exactly 1.0 (0x3F800000).
  A uint64_t tiny[2]={0x3FF0000000000001ULL,0x3FF0000000000001ULL};
  o[0]=o[1]=0; do_fcvtxn(tiny,o);
  uint32_t lo=(uint32_t)(o[0]&0xffffffffu);
  if(lo==0x3F800001u){pass++;printf("  PASS  FCVTXN round-to-odd -> 0x%08x (odd mantissa)\n",lo);}
  else{fail++;printf("  FAIL  FCVTXN round-to-odd got 0x%08x want 0x3F800001\n",lo);}
  o[0]=o[1]=0; do_fcvtn(tiny,o);
  lo=(uint32_t)(o[0]&0xffffffffu);
  if(lo==0x3F800000u){pass++;printf("  PASS  FCVTN  nearest-even -> 0x%08x (contrast)\n",lo);}
  else{fail++;printf("  FAIL  FCVTN nearest-even got 0x%08x want 0x3F800000\n",lo);}

  printf("\n  PASS=%d FAIL=%d\n",pass,fail);
  return fail?1:0;}
