/*
 * Copyright (C) <2018> Intel Corporation
 * SPDX-License-Identifier: BSD-3-Clause
 */
#include <vcpu.h>
#include <spinlock.h>

/* NOTE:
 *
 * MISRA C requires that all unsigned constants should have the suffix 'U'
 * (e.g. 0xffU), but the assembler may not accept such C-style constants. For
 * example, binutils 2.26 fails to compile assembly in that case. To work this
 * around, all unsigned constants must be explicitly spells out in assembly
 * with a comment tracking the original expression from which the magic
 * number is calculated. As an example:
 *
 *    /* 0x00000668 =
 *     *    (CR4_DE | CR4_PAE | CR4_MCE | CR4_OSFXSR | CR4_OSXMMEXCPT) *\/
 *    movl    $0x00000668, %eax
 *
 * Make sure that these numbers are updated accordingly if the definition of
 * the macros involved are changed.
 */
   .text
   .align   8
   .code64
   .extern    restore_msrs
   .extern    cpu_ctx
   .extern    load_gdtr_and_tr
   .extern    do_acpi_s3
   .extern    trampoline_spinlock

   .global    __enter_s3
__enter_s3:
	/*
	 * 0U=0x0=CPU_CONTEXT_OFFSET_RAX
	 * 8U=0x8=CPU_CONTEXT_OFFSET_RCX
	 * 16U=0x10=CPU_CONTEXT_OFFSET_RDX
	 * 24U=0x18=CPU_CONTEXT_OFFSET_RBX
	 * 32U=0x20=CPU_CONTEXT_OFFSET_RSP
	 * 40U=0x28=CPU_CONTEXT_OFFSET_RBP
	 * 48U=0x30=CPU_CONTEXT_OFFSET_RSI
	 * 56U=0x38=CPU_CONTEXT_OFFSET_RDI
	 * 64U=0x40=CPU_CONTEXT_OFFSET_R8
	 * 72U=0x48=CPU_CONTEXT_OFFSET_R9
	 * 80U=0x50=CPU_CONTEXT_OFFSET_R10
	 * 88U=0x58=CPU_CONTEXT_OFFSET_R11
	 * 96U=0x60=CPU_CONTEXT_OFFSET_R12
	 * 104U=0x68=CPU_CONTEXT_OFFSET_R13
	 * 112U=0x70=CPU_CONTEXT_OFFSET_R14
	 * 120U=0x78=CPU_CONTEXT_OFFSET_R15
	 */
	movq %rax, 0x0 + cpu_ctx(%rip)
	movq %rcx, 0x8 + cpu_ctx(%rip)
	movq %rdx, 0x10 + cpu_ctx(%rip)
	movq %rbx, 0x18 + cpu_ctx(%rip)
	movq %rsp, 0x20 + cpu_ctx(%rip)
	movq %rbp, 0x28 + cpu_ctx(%rip)
	movq %rsi, 0x30 + cpu_ctx(%rip)
	movq %rdi, 0x38 + cpu_ctx(%rip)
	movq %r8,  0x40 + cpu_ctx(%rip)
	movq %r9,  0x48 + cpu_ctx(%rip)
	movq %r10, 0x50 + cpu_ctx(%rip)
	movq %r11, 0x58 + cpu_ctx(%rip)
	movq %r12, 0x60 + cpu_ctx(%rip)
	movq %r13, 0x68 + cpu_ctx(%rip)
	movq %r14, 0x70 + cpu_ctx(%rip)
	movq %r15, 0x78 + cpu_ctx(%rip)

	pushfq
	/*168U=0xa8=CPU_CONTEXT_OFFSET_RFLAGS*/
	popq 0xa8 + cpu_ctx(%rip)

	/*504U=0x1f8=CPU_CONTEXT_OFFSET_IDTR*/
	sidt 0x1f8 + cpu_ctx(%rip)
	/*536U=0x218=CPU_CONTEXT_OFFSET_LDTR*/
	sldt 0x218 + cpu_ctx(%rip)

	mov %cr0, %rax
	/*128U=0x80=CPU_CONTEXT_OFFSET_CR0*/
	mov %rax, 0x80 + cpu_ctx(%rip)

	mov %cr3, %rax
	/*144U=0x90=CPU_CONTEXT_OFFSET_CR3*/
	mov %rax, 0x90 + cpu_ctx(%rip)

	mov %cr4, %rax
	/*152U=0x98=CPU_CONTEXT_OFFSET_CR4*/
	mov %rax, 0x98 + cpu_ctx(%rip)

	wbinvd

	/*16U=0x10=CPU_CONTEXT_OFFSET_RDX*/
	movq 0x10 + cpu_ctx(%rip), %rdx  /* pm1b_cnt_val */
	/*56U=0x38=CPU_CONTEXT_OFFSET_RDI*/
	movq 0x38 + cpu_ctx(%rip), %rdi  /* *vm */
	/*48U=0x30=CPU_CONTEXT_OFFSET_RSI*/
	movq 0x30 + cpu_ctx(%rip), %rsi  /* pm1a_cnt_val */

	call do_acpi_s3

	/* if do_acpi_s3 returns, which means ACRN can't enter S3 state.
	 * Then trampoline will not be executed and we need to acquire
	 * trampoline_spinlock here to match release in enter_sleep
	 */
	mov $trampoline_spinlock, %rdi
	spinlock_obtain(%rdi)


/*
 * When system resume from S3, trampoline_start64 will
 * jump to restore_s3_context after setup temporary stack.
 */
.global restore_s3_context
restore_s3_context:
	/*152U=0x98=CPU_CONTEXT_OFFSET_CR4*/
	mov 0x98 + cpu_ctx(%rip), %rax
	mov %rax, %cr4

	/*144U=0x90=CPU_CONTEXT_OFFSET_CR3*/
	mov 0x90 + cpu_ctx(%rip), %rax
	mov %rax, %cr3

	/*128U=0x80=CPU_CONTEXT_OFFSET_CR0*/
	mov 0x80 + cpu_ctx(%rip), %rax
	mov %rax, %cr0

	/*504U=0x1f8=CPU_CONTEXT_OFFSET_IDTR*/
	lidt 0x1f8 + cpu_ctx(%rip)
	/*536U=0x218=CPU_CONTEXT_OFFSET_LDTR*/
	lldt 0x218 + cpu_ctx(%rip)

	/*
	 *312U=0x138=CPU_CONTEXT_OFFSET_SS
	 *32=0x20=CPU_CONTEXT_OFFSET_RSP
	 */
	mov 0x138 + cpu_ctx(%rip), %ss
	movq 0x20 + cpu_ctx(%rip), %rsp

	/*168U=0xa8=CPU_CONTEXT_OFFSET_RFLAGS*/
	pushq 0xa8 + cpu_ctx(%rip)
	popfq

	call load_gdtr_and_tr
	call restore_msrs

	/*
	 * 0U=0x0=CPU_CONTEXT_OFFSET_RAX
	 * 8U=0x8=CPU_CONTEXT_OFFSET_RCX
	 * 16U=0x10=CPU_CONTEXT_OFFSET_RDX
	 * 24U=0x18=CPU_CONTEXT_OFFSET_RBX
	 * 40U=0x28=CPU_CONTEXT_OFFSET_RBP
	 * 48U=0x30=CPU_CONTEXT_OFFSET_RSI
	 * 56U=0x38=CPU_CONTEXT_OFFSET_RDI
	 * 64U=0x40=CPU_CONTEXT_OFFSET_R8
	 * 72U=0x48=CPU_CONTEXT_OFFSET_R9
	 * 80U=0x50=CPU_CONTEXT_OFFSET_R10
	 * 88U=0x58=CPU_CONTEXT_OFFSET_R11
	 * 96U=0x60=CPU_CONTEXT_OFFSET_R12
	 * 104U=0x68=CPU_CONTEXT_OFFSET_R13
	 * 112U=0x70=CPU_CONTEXT_OFFSET_R14
	 * 120U=0x79=CPU_CONTEXT_OFFSET_R15
	 */
	movq 0x0 + cpu_ctx(%rip), %rax
	movq 0x8 + cpu_ctx(%rip), %rcx
	movq 0x10 + cpu_ctx(%rip), %rdx
	movq 0x18 + cpu_ctx(%rip), %rbx
	movq 0x28 + cpu_ctx(%rip), %rbp
	movq 0x30 + cpu_ctx(%rip), %rsi
	movq 0x38 + cpu_ctx(%rip), %rdi
	movq 0x40 + cpu_ctx(%rip), %r8
	movq 0x48 + cpu_ctx(%rip), %r9
	movq 0x50 + cpu_ctx(%rip), %r10
	movq 0x58 + cpu_ctx(%rip), %r11
	movq 0x60 + cpu_ctx(%rip), %r12
	movq 0x68 + cpu_ctx(%rip), %r13
	movq 0x70 + cpu_ctx(%rip), %r14
	movq 0x78 + cpu_ctx(%rip), %r15

	retq
