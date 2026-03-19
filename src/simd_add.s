# x86_64 SIMD add — 4x i32 at once using SSE
# void add_arrays_asm(const int32_t* a, const int32_t* b, int32_t* c, size_t len);
# rdi = a, rsi = b, rdx = c, rcx = len

.text
.globl add_arrays_asm
.type add_arrays_asm, @function

add_arrays_asm:
    xor %r8, %r8                  # i = 0
.loop:
    cmp %r8, %rcx
    jge .done

    movdqu (%rdi,%r8,4), %xmm0   # load 4 i32s from a[i]
    movdqu (%rsi,%r8,4), %xmm1   # load 4 i32s from b[i]
    paddd %xmm1, %xmm0           # xmm0 = a[0..3] + b[0..3]
    movdqu %xmm0, (%rdx,%r8,4)   # store to c[i]

    add $4, %r8                  # i += 4
    jmp .loop
.done:
    ret
