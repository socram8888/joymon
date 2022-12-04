/* Based on https://github.com/grumpycoders/pcsx-redux/blob/ff45bf832fa78073eabe78a2b11586cdb87ba951/src/mips/ps-exe.ld */

OUTPUT_FORMAT("binary")

EXEC_START  = 0x801FF000;
STACK_START = 0x801FFF00;

MEMORY {
	header   : ORIGIN = (EXEC_START - 0x800), LENGTH = 2048
	ram(wrx) : ORIGIN = EXEC_START, LENGTH = STACK_START - EXEC_START
}
SECTIONS {
	. = EXEC_START - 0x800;

	.header : {
		/* 0x0000 - 0x0007 : "PS-X EXE" */
		BYTE(80); BYTE(83); BYTE(45); BYTE(88); BYTE(32); BYTE(69); BYTE(88); BYTE(69);

		/* 0x0008 - 0x000F : skip text_off and data_off since they're not supported by the PS1 BIOS */
		LONG(0); LONG(0);

		/* 0x0010 - 0x0013 : entry point */
		LONG(EXEC_START);

		/* 0x0014 - 0x0017 : initial value of $gp */
		LONG(0);

		/* 0x0018 - 0x001B : Memory address to load "text" section to. */
		LONG(EXEC_START);

		/* 0x001C - 0x001F :  size, in bytes, of the "text" section. */
		LONG(EXEC_END - EXEC_START);

		/* 0x0020 - 0x002F :
			Skip "data_addr", "data_size", "bss_addr" and "bss_size".
			None of these are supported by retail PS1 BIOS.
		*/
		LONG(0); LONG(0);
		LONG(0); LONG(0);

		/* 0x0030 - 0x0033 :  Initial stack address. */
		LONG(STACK_START);

		/* 0x0034 - 0x0037 : Initial stack size, set it to 0. */
		LONG(0);

		/* Skip the remaining fields as they're not supported by the BIOS */
		/* e.g. 2048 header bytes minus whatever we've actually used */
		. = . + 1992;
	} >header

	.text : {
		*(.text)
		. = ALIGN(2048);
	} >ram

	EXEC_END = .;

	/DISCARD/ : {
		*(*)
	}
}
ENTRY (__start)
