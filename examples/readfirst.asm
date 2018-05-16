
;<Program title>

jmp start

;data


;code
start: nop
check_for_data: in 0
adi 0
jnz check_for_data

handle_data: in 1
inr a
out 1
in 2
inr a
out 2
in 3
inr a
out 3
in 4
inr a
out 4
mvi a, 1
out 0
jmp check_for_data

hlt