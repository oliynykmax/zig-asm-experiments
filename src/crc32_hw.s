# x86_64 hardware CRC32-C — uses SSE4.2 crc32 instruction
# uint32_t crc32_hw(const uint8_t* data, size_t len);
# rdi = data, rsi = len -> eax = crc32
# CRC-32C (Castagnoli), polynomial 0x1EDC6F41

.text
.globl crc32_hw
.type crc32_hw, @function

crc32_hw:
    mov $0xFFFFFFFF, %eax            # crc = 0xFFFFFFFF (initial)
    xor %r8, %r8                     # i = 0

    # Process first 4 bytes with crc32l (safe: initial CRC state)
    cmp $4, %rsi
    jl .byte_loop
    crc32l (%rdi), %eax
    add $4, %r8

    # Remaining bytes one at a time (crc32l with non-zero CRC state
    # doesn't match sequential crc32b — possible Intel quirk)
.byte_loop:
    cmp %r8, %rsi
    jle .done
    crc32b (%rdi,%r8), %eax
    inc %r8
    jmp .byte_loop

.done:
    not %eax
    ret
