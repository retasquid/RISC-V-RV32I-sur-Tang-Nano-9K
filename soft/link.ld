ENTRY(_start)

MEMORY
{
    IO     (rw)  : ORIGIN = 0x00000000, LENGTH = 32
    FLASH  (rx)  : ORIGIN = 0x40000000, LENGTH = 4M
    RAM    (rwx) : ORIGIN = 0x80000000, LENGTH = 8M
    VRAM   (rw)  : ORIGIN = 0xC0000000, LENGTH = 32K
}

/* Vector table at the very end of Flash */
VECTOR_ADDR = ORIGIN(FLASH) + LENGTH(FLASH) - 0x10;


SECTIONS
{
    /* -------------------------------------------------- */
    /* Code */
    /* -------------------------------------------------- */

    .text :
    {
        . = ALIGN(4);

        _text_start = .;

        KEEP(*(.text.startup))
        KEEP(*(.init))

        *(.text)
        *(.text.*)

        . = ALIGN(4);

        _text_end = .;
    } > FLASH


    /* -------------------------------------------------- */
    /* Read-only constants */
    /* -------------------------------------------------- */

    .rodata :
    {
        . = ALIGN(4);
        _rodata_start = .;

        *(.srodata .srodata.*)
        *(.rodata)
        *(.rodata.*)

        . = ALIGN(4);
        _rodata_end = .;
    } > FLASH


    /* -------------------------------------------------- */
    /* Initialized data */
    /*
     * Stored in Flash but copied to RAM at startup.
     * Destination is RAM1 here.
     */
    /* -------------------------------------------------- */

    .data :
    {
        . = ALIGN(4);
        _data_start = .;

        __global_pointer$ = . + 0x800;   /* portée gp-relative ±2KiB */

        *(.sdata .sdata.*)
        *(.data)
        *(.data.*)

        . = ALIGN(4);
        _data_end = .;

    } > RAM AT > FLASH

    _data_load = LOADADDR(.data);


    /* -------------------------------------------------- */
    /* Uninitialized data */
    /* -------------------------------------------------- */

    .bss :
    {
        . = ALIGN(4);
        _bss_start = .;

        *(.sbss .sbss.*)
        *(.bss)
        *(.bss.*)
        *(COMMON)

        . = ALIGN(4);
        _bss_end = .;
    } > RAM

    /* -------------------------------------------------- */
    /* Stack */
    /* -------------------------------------------------- */

    .stack (NOLOAD) :
    {
        . = ALIGN(16);

        _stack_bottom = .;

        . += 0x010000;       /* 1 MiB stack */

        . = ALIGN(16);
        _stack_top = .;

    } > RAM

    . = ALIGN(4);

    _heap_start = .;

    . = ORIGIN(RAM) + LENGTH(RAM) - 0x010000;

    _heap_end = .;

    /* -------------------------------------------------- */
    /* Vector table */
    /* -------------------------------------------------- */

    .vectors VECTOR_ADDR :
    {
        . = ALIGN(4);

        _vector_start = .;

        KEEP(*(.vectors))
        KEEP(*(.vector_table))

        . = ALIGN(4);

        _vector_end = .;

    } > FLASH


    /* -------------------------------------------------- */
    /* Discard unnecessary sections */
    /* -------------------------------------------------- */

    /DISCARD/ :
    {
        *(.comment)
        *(.note*)
        *(.eh_frame*)
    }
}