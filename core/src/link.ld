ENTRY(_start)
OUTPUT_FORMAT(elf64-x86-64)

PHDRS
{
  boot PT_LOAD;                                /* one single loadable segment */
}
SECTIONS
{
    . = 0xffffffffffe00000;
	kernel_start = .;
    .text : {
        KEEP(*(.text.boot)) *(.text .text.*)   /* code */

        . = ALIGN(0x1000);
        start_of_kernel_rodata = .;
        *(.rodata .rodata.*)                   /* read-only data */
        end_of_kernel_rodata = .;

        . = ALIGN(0x1000);
        start_of_kernel_data = .;              /* data */
        *(.data .data.*)

    } :boot
    .bss (NOLOAD) : {                          /* bss */
        *(.bss .bss.*)
        *(COMMON)
    } :boot
    end_of_kernel_data = .;
	kernel_end = .;

    /DISCARD/ : { *(.eh_frame) *(.comment) }
}
