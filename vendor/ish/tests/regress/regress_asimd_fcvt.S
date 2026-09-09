#ifdef __APPLE__
#define NAME(x) _##x
#else
#define NAME(x) x
#endif
.text
// Each helper is a standalone function so the compiler cannot interleave code
// between the load, the instruction under test and the store.
.global NAME(do_fcvtn)
.align 4
NAME(do_fcvtn):            // 2xdouble -> 2xfloat, low half; x0=in x1=out
    ldr q0, [x0]
    movi v1.4s, #0
    fcvtn v1.2s, v0.2d
    str q1, [x1]
    ret
.global NAME(do_fcvtn2)
.align 4
NAME(do_fcvtn2):           // narrow into high half; x2 seeds the low half
    ldr q0, [x0]
    ldr q1, [x2]
    fcvtn2 v1.4s, v0.2d
    str q1, [x1]
    ret
.global NAME(do_fcvtl)
.align 4
NAME(do_fcvtl):            // 2xfloat -> 2xdouble
    ldr q0, [x0]
    movi v1.4s, #0
    fcvtl v1.2d, v0.2s
    str q1, [x1]
    ret
.global NAME(do_fcvtl2)
.align 4
NAME(do_fcvtl2):           // widen the HIGH two floats
    ldr q0, [x0]
    movi v1.4s, #0
    fcvtl2 v1.2d, v0.4s
    str q1, [x1]
    ret
.global NAME(do_fcvtxn)
.align 4
NAME(do_fcvtxn):           // narrow with round-to-odd
    ldr q0, [x0]
    movi v1.4s, #0
    fcvtxn v1.2s, v0.2d
    str q1, [x1]
    ret
.global NAME(do_fcvtxn2)
.align 4
NAME(do_fcvtxn2):
    ldr q0, [x0]
    ldr q1, [x2]
    fcvtxn2 v1.4s, v0.2d
    str q1, [x1]
    ret
.global NAME(do_fcvtn_h)
.align 4
NAME(do_fcvtn_h):          // 4xsingle -> 4xhalf (sz=0 form)
    ldr q0, [x0]
    movi v1.4s, #0
    fcvtn v1.4h, v0.4s
    str q1, [x1]
    ret
.global NAME(do_fcvtl_h)
.align 4
NAME(do_fcvtl_h):          // 4xhalf -> 4xsingle (sz=0 form)
    ldr q0, [x0]
    movi v1.4s, #0
    fcvtl v1.4s, v0.4h
    str q1, [x1]
    ret
