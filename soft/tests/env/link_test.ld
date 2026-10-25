/* Script d'edition de liens des tests assembleur (riscv-tests et tests/custom).
 * Code en flash, donnees en PSRAM chargees depuis la flash par RVTEST_CODE_BEGIN. */
OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    FLASH (rx)  : ORIGIN = 0x40000000, LENGTH = 4M
    RAM   (rwx) : ORIGIN = 0x80000000, LENGTH = 8M
}

SECTIONS
{
    .text :
    {
        *(.text.init)
        *(.text .text.*)
        *(.rodata .rodata.* .srodata .srodata.*)
        . = ALIGN(4);
    } > FLASH

    .data :
    {
        . = ALIGN(4);
        _data_start = .;
        *(.data .data.* .sdata .sdata.*)
        . = ALIGN(4);
        _data_end = .;
    } > RAM AT > FLASH

    _data_load = LOADADDR(.data);

    .bss (NOLOAD) :
    {
        *(.bss .bss.* .sbss .sbss.* COMMON)
    } > RAM

    /DISCARD/ : { *(.comment) *(.note*) *(.eh_frame*) *(.riscv.attributes) }
}
