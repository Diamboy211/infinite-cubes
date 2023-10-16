[bits 16]
[org 0x7C00]

CODE_SEG equ code_desc - gdt_start
DATA_SEG equ data_desc - gdt_start

section boot1

start:
	xor ax, ax
	mov ds, ax
	mov bx, ax
	mov ax, 0x07E0
	mov es, ax
	mov ax, 0x0202
	mov cx, 0x0002
	xor dh, dh
	int 0x13

	mov si, err
	jc print_err
	cmp al, 2
	jne print_err

	mov eax, 1
	cpuid
	test edx, 1 << 25
	jz print_err
	test edx, 1 << 26
	jz print_err
	mov eax, cr0
	and ax, 0xFFFB
	or ax, 0x0002
	mov cr0, eax
	mov eax, cr4
	or eax, (3 << 9)
	mov cr4, eax

	mov ax, 0x0013
	int 0x10
	mov ax, 0xA000
	mov es, ax

	mov dx, 0x3C8
	xor ax, ax
	out dx, al
	inc dx
start0:
	out dx, al
	out dx, al
	out dx, al
	inc ah
	mov al, ah
	shr al, 2
	test ah, ah
	jnz start0
	cli
	lgdt [gdt_desc]
	mov eax, cr0
	or eax, 1
	mov cr0, eax
	jmp CODE_SEG:start1

print_err:
	mov ax, 0x0003
	int 0x10
	mov ax, 0xB800
	mov es, ax
	mov ah, 0x07
	xor di, di

print_err0:
	mov al, [si]
	test al, al
	jz done
	mov [es:di], ax
	inc di
	inc di
	inc si
	jmp print_err0

done:
	hlt
	jmp done

; copied from some other code i made
gdt_start:
	dd 0
	dd 0
code_desc:
	dw 0xFFFF ; first 2 bytes of limit
	dw 0      ;
	db 0      ; first 24 bits of base
	db 0b10011010
	db 0b11001111 ; other flags + last 4 bits of limit
	db 0      ; last 8 bits of base
data_desc:
	dw 0xFFFF ; first 2 bytes of limit
	dw 0      ;
	db 0      ; first 24 bits of base
	db 0b10010010
	db 0b11001111 ; other flags + last 4 bits of limit
	db 0      ; last 8 bits of base
	; what a fucking mess
gdt_end:

gdt_desc:
	dw gdt_end - gdt_start - 1
	dd gdt_start

err:
db "a", 0

[bits 32]

T equ 0x00200000  ; remember, A20 is NOT enabled
PX equ 0x0023E800
PY equ 0x0027D000
PZ equ 0x002BB800
AXX equ 0x002FA000 ; the matrix
AXY equ 0x002FA010 ; the increment is 0x10 so a
AXZ equ 0x002FA020 ; movaps can load it all
AYX equ 0x002FA030
AYY equ 0x002FA040
AYZ equ 0x002FA050
AZX equ 0x002FA060
AZY equ 0x002FA070
AZZ equ 0x002FA080
OX equ 0x002FA090
OY equ 0x002FA0A0
OZ equ 0x002FA0B0
RR equ 0x002FA0C0
RI equ 0x002FA0D0

f_0_01:	dd 0.01
f_0_1:	dd 0.1
f_1:	dd 1.0
f_111:	dd 111.0
; (x + 25165824.0f) - 25165824.0f ≈ roundf(x / 2.0f) * 2.0f
f_25165824:	dd 25165824.0
f_sqrt1_2:	dd 0.7071067811865476
f_m0_032:	dd -0.032
f_0_01024:	dd 0.01024
f_1_024:	dd 1.024
f_0_3:	dd 0.3
f_m0:	dd -0.0
f_nan: dd 0x7FFFFFFF

start1:
	mov esp, 0x7C00
	call setup_dither
	; fill in PX and PY
	; first with ints
	mov ebx, PX
	xor esi, esi
	mov eax, -100
start2:
	mov ecx, -160
start3:
	mov [ebx+esi*4], ecx
	mov [ebx+esi*4+(PY-PX)], eax
	inc esi
	inc ecx
	cmp ecx, 160
	jl start3
	inc eax
	cmp eax, 100
	jl start2

	; convert to floats
	movss xmm0, [f_0_01]
	shufps xmm0, xmm0, 0b00000000
	xor esi, esi
start4:
	movdqa xmm1, [ebx+esi*8]
	cvtdq2ps xmm1, xmm1
	mulps xmm1, xmm0
	movaps [ebx+esi*8], xmm1
	inc esi
	inc esi
	cmp esi, 64000
	jb start4

	; add (0,0,1) to the vectors and normalize
	movss xmm4, [f_1]
	shufps xmm4, xmm4, 0b00000000
	xor esi, esi
start5:
	movaps xmm0, [ebx+esi*8]
	movaps xmm1, [ebx+esi*8+(PY-PX)]
	movaps xmm2, xmm0
	movaps xmm3, xmm1
	mulps xmm2, xmm0
	mulps xmm3, xmm1
	addps xmm2, xmm3
	addps xmm2, xmm4
	rsqrtps xmm2, xmm2 ; fuck precision
	mulps xmm0, xmm2
	mulps xmm1, xmm2
	movaps [ebx+esi*8], xmm0
	movaps [ebx+esi*8+(PY-PX)], xmm1
	movaps [ebx+esi*8+(PZ-PX)], xmm2
	inc esi
	inc esi
	cmp esi, 32000
	jb start5

	call setup_mat
start6:
	xor esi, esi
start7:
	movaps xmm0, [esi+T]
	xorps xmm0, xmm0
	movaps [esi+T], xmm0
	add esi, 16
	cmp esi, 256000
	jb start7

	mov ecx, 64
start8:
	call update_t
	dec ecx
	jnz start8

	mov ebx, T
	call disp
	call update_mat
	jmp start6


times (510 - ($ - $$)) db 0
dw 0xAA55



section boot2

; display routine
; converts floats in [ebx] to u8's and paste into 0xA0000
disp:
	xor esi, esi
	movss xmm4, [f_111]
	shufps xmm4, xmm4, 0b00000000
disp0:
	rsqrtps xmm0, [ebx+esi*4]
	rsqrtps xmm1, [ebx+esi*4+16]
	rsqrtps xmm2, [ebx+esi*4+32]
	rsqrtps xmm3, [ebx+esi*4+48]

	mulps xmm0, xmm4
	mulps xmm1, xmm4
	mulps xmm2, xmm4
	mulps xmm3, xmm4
	cvtps2dq xmm0, xmm0
	cvtps2dq xmm1, xmm1
	cvtps2dq xmm2, xmm2
	cvtps2dq xmm3, xmm3
	packssdw xmm0, xmm1
	packssdw xmm2, xmm3
	packuswb xmm0, xmm2
	movdqa xmm1, [esi+0x10000]
	paddb xmm0, xmm1
	movaps [esi+0xA0000], xmm0

	add esi, 16
	cmp si, 64000
	jb disp0
	ret

update_t:
	xor esi, esi
	movss xmm7, [f_25165824]
	shufps xmm7, xmm7, 0b00000000
update_t1:
	movaps xmm0, [esi+PX]
	movaps xmm1, [esi+PY]
	movaps xmm2, [esi+PZ]
	movaps xmm3, [esi+T]
	movaps xmm4, [OX]
	movaps xmm5, [OY]
	movaps xmm6, [OZ]
	mulps xmm0, xmm3
	mulps xmm1, xmm3
	mulps xmm2, xmm3
	addps xmm0, xmm4
	addps xmm1, xmm5
	addps xmm2, xmm6
	movaps xmm4, xmm0
	movaps xmm5, xmm1
	movaps xmm6, xmm2
	addps xmm4, xmm7
	addps xmm5, xmm7
	addps xmm6, xmm7
	subps xmm4, xmm7
	subps xmm5, xmm7
	subps xmm6, xmm7
	subps xmm0, xmm4
	subps xmm1, xmm5
	subps xmm2, xmm6

	movaps xmm4, xmm0
	movaps xmm5, xmm1
	movaps xmm6, xmm2
	mulps xmm4, [AXX]
	mulps xmm5, [AXY]
	mulps xmm6, [AXZ]
	addps xmm4, xmm5
	addps xmm4, xmm6
	movaps [0x2FA0E0], xmm4
	movaps xmm4, xmm0
	movaps xmm5, xmm1
	movaps xmm6, xmm2
	mulps xmm4, [AYX]
	mulps xmm5, [AYY]
	mulps xmm6, [AYZ]
	addps xmm4, xmm5
	addps xmm4, xmm6
	movaps [0x2FA0F0], xmm4
	mulps xmm0, [AZX]
	mulps xmm1, [AZY]
	mulps xmm2, [AZZ]
	addps xmm0, xmm1
	addps xmm2, xmm0
	movaps xmm1, [0x2FA0F0]
	movaps xmm0, [0x2FA0E0]

	movss xmm4, [f_nan]
	shufps xmm4, xmm4, 0b00000000
	andps xmm0, xmm4
	andps xmm1, xmm4
	andps xmm2, xmm4
	maxps xmm0, xmm1
	maxps xmm0, xmm2
	movss xmm4, [f_0_3]
	shufps xmm4, xmm4, 0b00000000
	subps xmm0, xmm4
	addps xmm3, xmm0
	movaps [esi+T], xmm3
	add esi, 16
	cmp esi, 256000
	jb update_t1
	ret

setup_mat:
	xorps xmm0, xmm0
	mov esi, AZY
	movaps [esi], xmm0
	movaps [esi+(AXY-AZY)], xmm0
	movaps [esi+(AYX-AZY)], xmm0
	movaps [esi+(AYZ-AZY)], xmm0
	movaps [esi+(OX-AZY)], xmm0
	movaps [esi+(OY-AZY)], xmm0
	movss xmm0, [f_sqrt1_2]
	shufps xmm0, xmm0, 0b00000000
	movaps [esi+(AZX-AZY)], xmm0
	movaps [esi+(AZZ-AZY)], xmm0
	movaps [esi+(AXX-AZY)], xmm0
	movss xmm1, [f_m0]
	shufps xmm1, xmm1, 0b00000000
	xorps xmm0, xmm1
	movaps [esi+(AXZ-AZY)], xmm0
	movss xmm0, [f_1]
	shufps xmm0, xmm0, 0b00000000
	movaps [esi+(AYY-AZY)], xmm0
	movss xmm1, [f_1_024]
	shufps xmm1, xmm1, 0b00000000
	movaps [esi+(OZ-AZY)], xmm1
	movss xmm1, [f_0_1]
	shufps xmm1, xmm1, 0b00000000
	movaps [esi+(RI-AZY)], xmm1
	mulps xmm1, xmm1
	subps xmm0, xmm1
	sqrtps xmm0, xmm0
	movaps [esi+(RR-AZY)], xmm0
	ret

update_mat:
	movss xmm0, [f_m0_032]
	movss xmm1, [f_0_01024]
	shufps xmm0, xmm0, 0b00000000
	shufps xmm1, xmm1, 0b00000000
	addps xmm0, [OX]
	addps xmm1, [OY]
	movaps [OX], xmm0
	movaps [OY], xmm1

	movaps xmm4, [RR]
	movaps xmm5, [RI]
	mov esi, 0x2FA000
update_mat0:
	movaps xmm0, [esi]
	movaps xmm1, [esi+0x10]
	movaps xmm2, xmm0
	movaps xmm3, xmm1

	mulps xmm0, xmm4
	mulps xmm1, xmm5
	mulps xmm2, xmm5
	mulps xmm3, xmm4

	subps xmm0, xmm1
	addps xmm2, xmm3

	movaps [esi], xmm0
	movaps [esi+0x10], xmm2

	add esi, 0x30
	cmp si, 0xA090
	jb update_mat0
	ret
setup_dither:
	xor ecx, ecx
setup_dither0:
	xor edx, edx
setup_dither1:
	mov edi, ecx
	mov esi, ecx
	shl edi, 8
	shl esi, 6
	add esi, edi
	add esi, edx
	mov byte [esi+0x10000], 0
	mov byte [esi+0x10001], 2
	mov byte [esi+0x10000 + 320], 3
	mov byte [esi+0x10000 + 321], 1
	add edx, 2
	cmp edx, 320
	jb setup_dither1
	add ecx, 2
	cmp ecx, 200
	jb setup_dither0
	ret
times (512*2 - ($ - $$)) db 0
