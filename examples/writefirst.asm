
;<Program title>

jmp start

;data


;code
; set counter to 0, set sum to 10, output a 1 to attempt to send data
start: nop
mvi c, 0
mvi b, 10

send_data: mvi a, 1
out 0

; if 10 cycles have past read data
; if a zero is read, we are free to write data
; otherwise, loop
check_for_ok: nop
inr c
mov a, c
sbi 250
jz read_data_1
in 0
adi 0
jz write_data
jmp check_for_ok

; send our sum and increment
; output a 1 to confirm data is ready
write_data: nop
mov a, b
out 1
inr b
jmp send_data

; clear our counter
; output a 0, to allow data to be recieved
; when 1 is recieved, read the data
; then set 0 to attempt to write again
read_data_1: mvi c, 0
read_data: inr c
mov a, c
sbi 250
jz send_data
mvi a, 0
out 0
in 0
jz read_data
in 1
add b
mov b, a
jmp send_data



donea: hlt
doneb: hlt
