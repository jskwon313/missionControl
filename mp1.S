
# mp1.S - missile-command version
# Good luck, and have fun!

.data
	
    # Constants for accessing the fields of a struct missile, 
    # struct missile is defined in rtc.h and mp1.h

	NEXT 	  = 0
	X	  = 4
	Y	  = 8
	VX	  = 12
	VY	  = 16
	DEST_X	  = 20
	DEST_Y	  = 24
	EXPLODED  = 28
	C	  = 32

    # Character to draw for an explosion - '@'

	EXPLOSION = 64
	EMPTY = 32
	CROSSHAIR = 120

# Data shared between this file and rtc.c helper functions

# This '.globl' directive makes these symbols visible externally
.globl mp1_missile_list, base_alive, mp1_score

mp1_missile_list:	.long 0x0	# Head of list pointer
base_alive:		.long 0x0	# Array of 3 bytes, plus a padding byte
mp1_score:		.long 0x0	# Player's current score


# Data private to this  file

base_pic:     	    .string "/^^^\\"	# Picture of a live base
dead_base_pic: 	    .string "xxxxx"	# Picture of a dead base
crosshairs_x:		.long 0x0	# X-position of the crosshairs
crosshairs_y:		.long 0x0	# Y-position of the crosshairs
base1_start: .long 3878 
base2_start: .long 3918
base3_start: .long 3958

.text

# void mp1_poke(void);
# You can use this function to write to video memory.
#
# Interface: Register-based arguments (not C-style)
#    Inputs: %cl  - The byte you wish to write
#            %eax - Offset from the start of video memory that you wish
#                   to write to
#   Outputs: Text-mode video screen is written to at location %eax with
#            the byte in %cl
# Registers: Clobbers EDX

mp1_poke:
		movl    vmem_base_addr(,1),%edx
		movb    %cl,(%edx,%eax,1)
		ret

#   ----------------- Exported functions ---------------------

# void mp1_rtc_tasklet(unsigned long garbage);
# Performs three tasks:
#	(1) updates the list of missiles (implement this in update_missiles,
#           below, and call it from here).
#	(2) Redraw the bases - they may have been overwritten with missiles
#	(3) Redraw the crosshairs - it may have been overwritten with missiles
# Inputs   : none
# Outputs  : none
# Registers: Standard C calling convention

.globl mp1_rtc_tasklet
mp1_rtc_tasklet:
# Saves caller saved registers
pushl %ebp
movl %esp, %ebp
pushl %eax
pushl %ecx
pushl %edx

# Calls update_missiles
call update_missiles

# Redraws cities and crosshair
call redraw_cities
pushl $CROSSHAIR
call redraw_crosshairs
addl $4, %esp

# Restores caller saved registers
popl %edx
popl %ecx
popl %eax
leave
ret

# int mp1_ioctl(unsigned long arg, unsigned int cmd)
# The dispatch function for the MP1 ioctls - should use the cmd argument
# and a jumptable to execute one of the specific ioctls implemented below.
# Inputs   : unsigned long arg - parameter to the mp1_ioctl_....
#          : unsigned int cmd  - specifies which mp1_ioctl_... function 
#          :                     to execute
# Outputs  : Returns an integer - depends on which ioctl() function is called
# Registers: Standard C calling convention

.globl mp1_ioctl
mp1_ioctl:
# Uses the jump table to jump to the right functions
cmpl $0, 8(%esp)
je mp1_ioctl_startgame
cmpl $1, 8(%esp)
je mp1_ioctl_addmissile
cmpl $2, 8(%esp)
je mp1_ioctl_movexhairs
cmpl $3, 8(%esp)
je mp1_ioctl_getstatus
cmpl $4, 8(%esp)
je mp1_ioctl_endgame

# Returns -1 if other argument 
movl $-1, %eax
ret


# Jump table used by mp1_ioctl
jump_table:
.long mp1_ioctl_startgame, mp1_ioctl_addmissile, mp1_ioctl_movexhairs, mp1_ioctl_getstatus, mp1_ioctl_endgame 

# ----------------- Functions private to this file -------------------

# Updates the missile linked list
# Inputs: 		None
# Outputs: 		None
# Registers:	%ebx - Current missile
# 				%edi - Previous missile
#	     		%esi - Temp value
# 				%ecx - Temp value
update_missiles:
# Pushes callee saved registers
pushl %ebp
movl %esp, %ebp
pushl %ebx
pushl %edi
pushl %esi

# Moves the head of the linked list to EBX
movl mp1_missile_list, %ebx
movl $0, %edi

# Checks if EBX is NULL
cmpl $0, %ebx
je update_missiles_end

# Updates the missile linked list
update_missiles_loop:
# Moves the upper 16 bits of the X value into ESI
movl X(%ebx), %esi
addl VX(%ebx), %esi
shrl $16, %esi
# Checks if the missile has a X value between 0-79
cmpl $0, %esi
jl remove_missiles_prep
cmpl $79, %esi
jg remove_missiles_prep
# Moves the upper 16 bits of the Y value into ESI
movl Y(%ebx), %esi
addl VY(%ebx), %esi
shrl $16, %esi
# Checks to see if the missile has a Y value between 0-24
cmpl $0, %esi
jl remove_missiles_prep
cmpl $24, %esi
jg remove_missiles_prep

# Checks to see if the missile reached destination or exploded
destination_check:
movl DEST_X(%ebx), %esi
movl X(%ebx), %ecx
# Looks at the upper 16 bits to compare text-mode video locations
shrl $16, %ecx
cmpl %esi, %ecx
jne missile_explode_check
movl DEST_Y(%ebx), %esi
movl Y(%ebx), %ecx
# Looks at the upper 16 bits to compare text-mode video locations
shrl $16, %ecx
cmpl %esi, %ecx
jne missile_explode_check
jmp missile_explode_call

# Checks if currently exploding
missile_explode_check:
cmpl $0, EXPLODED(%ebx)
je update_missile_positions

# Calls missile_explode
missile_explode_call:
pushl %eax
pushl %ecx
pushl %edx
pushl %ebx
call missile_explode
cmpl $0, %eax
je missile_explode_pop
call mp1_notify_user
missile_explode_pop:
popl %ebx
popl %edx
popl %ecx
popl %eax
movl EXPLODED(%ebx), %esi

# Handles the explosion code
decl %esi
cmpl $0, %esi
jle remove_missiles_prep
movl %esi, EXPLODED(%ebx)

# Draws the explosion character
pushl %eax
pushl %ecx
pushl %edx
pushl %ebx
pushl $EXPLOSION
call mp1_poke_prep
addl $4, %esp
popl %ebx
popl %edx
popl %ecx
popl %eax
jmp next_missile

# Updates the missiles positions
update_missile_positions:
pushl %ebx
pushl $EMPTY
call mp1_poke_prep
addl $4, %esp
popl %ebx
# Moves Vx and Vy into ESI and updates values
movl X(%ebx), %esi
addl VX(%ebx), %esi
movl %esi, X(%ebx)
movl Y(%ebx), %esi
addl VY(%ebx), %esi
movl %esi, Y(%ebx)
shrl $16, %esi
cmpl $0, %esi
jl remove_missiles_prep
pushl %ebx
pushl C(%ebx)
call mp1_poke_prep
addl $4, %esp
popl %ebx

# Moves onto the next missile
next_missile:
movl %ebx, %edi 
cmpl $0, (%ebx)
je update_missiles_end
movl (%ebx), %ebx
jmp update_missiles_loop

# Pushes the appropriate values before removing missiles
remove_missiles_prep:
movl (%ebx), %esi
pushl %eax
pushl %ecx
pushl %edx
pushl %ebx
pushl %edi
call mp1_missile_remove
popl %edi
popl %ebx
popl %edx
popl %ecx
popl %eax
cmpl $0, %esi
je update_missiles_end
movl %esi, %ebx
jmp update_missiles_loop

# Returns saved register values before returning
update_missiles_end:
popl %esi
popl %edi
popl %ebx
leave
ret


# Function that redraws cities
# Inputs: 		None
# Outputs: 		None
# Registers: 	%eax - base offset
#	    		%ecx - character to draw basse
# 	     		%edx - checks if base is alive
# 	     		%esi - temp value
# 	     		%edi - counter value
redraw_cities:
# Saves callee saved registers
pushl %ebp
movl %esp, %ebp
pushl %ebx
pushl %edi
pushl %esi
pushl %edx

# Checks if the bases are alive
movl $3, %edi
# Computes the value to use to check if the base is alive
city:
cmpl $3, %edi
je city1
cmpl $2, %edi
je city2
cmpl $1, %edi
je city3
cmpl $0, %edi
je redraw_cities_end
# Checks if the base is alive
is_base_alive:
movl base_alive, %edx
andl %esi, %edx
cmpl $0, %edx
je dead_city
# Draws an alive city
movl $base_pic, %esi
movb (%esi), %cl
call mp1_poke
mov 1(%esi), %cl
addl $2, %eax
call mp1_poke
mov 2(%esi), %cl
addl $2, %eax
call mp1_poke
mov 3(%esi), %cl
addl $2, %eax
call mp1_poke
mov 4(%esi), %cl
addl $2, %eax
call mp1_poke
jmp city
# Draws a dead city
dead_city:
# Moves the character for a dead city into CL
movb $120, %cl
call mp1_poke
addl $2, %eax
call mp1_poke
addl $2, %eax
call mp1_poke
addl $2, %eax
call mp1_poke
addl $2, %eax
call mp1_poke
jmp city

# Values to check a certain byte in base_alive array
city1:
movl $0x000000FF, %esi
movl base1_start, %eax
decl %edi
jmp is_base_alive
city2:
movl $0x0000FF00, %esi
movl base2_start, %eax
decl %edi
jmp is_base_alive
city3:
movl $0x00FF0000, %esi
movl base3_start, %eax
decl %edi
jmp is_base_alive

# Restores call save registers
redraw_cities_end:
popl %edx
popl %esi
popl %edi
popl %ebx
leave
ret


# Function to draw the crosshair
# Inputs: 		None
# Outputs 		None
# Registers: 	%eax - offset value
# 	     		%ecx - crosshair character
# 	     		%ebx - x position
#	     		%edi - y position
redraw_crosshairs:
# Saves callee saved registers
pushl %ebp
movl %esp, %ebp
pushl %ebx
pushl %edi
pushl %esi
pushl %edx

# Draws the crosshair
movl crosshairs_x, %ebx
movl crosshairs_y, %edi
shll $1, %ebx
shll $1, %edi
imull $80, %edi
addl %ebx, %edi
movl %edi, %eax
movb 8(%ebp), %cl
call mp1_poke

# Returns callee saved registers
popl %edx
popl %esi
popl %edi
popl %ebx
leave
ret


# Function that prepares the values to be drawn
# Inputs: 		character - character to be printed out
# 	  			current - pointer to the current missile
# Outputs: 		None
# Registers: 	%edx - current missile pointer
# 	     		%ecx - character to be printed
# 	     		%eax - screen offset
#				%esi - temp value
mp1_poke_prep:
# Pushes the callee saved registers
pushl %ebp
movl %esp, %ebp
pushl %ebx
pushl %edi
pushl %esi
pushl %ecx
pushl %edx

# Moves current into EDX and calculates offset
movl 12(%ebp), %edx
movl 8(%edx), %ecx
andl $0xFFFF0000, %ecx
shrl $16, %ecx
shll $1, %ecx
imull $80, %ecx
movl %ecx, %eax
movl 4(%edx), %ecx
andl $0xFFFF0000, %ecx
shrl $16, %ecx
shll $1, %ecx
addl %ecx, %eax

# Moves the character into ECX and calls mp1_poke
poke_prep_call:
mov 8(%ebp), %ecx
call mp1_poke
jmp poke_prep_end

# Restores registers and returns
poke_prep_end:
popl %edx
popl %ecx
popl %esi
popl %edi
popl %ebx
leave
ret


# Function to remove the missiles from the list
# Inputs: 		prev - pointer to the previous missile
#	  			current - pointer to the current missile
# Outputs: 		None
# Registers: 	%ebx - current missile
#	     		%edi - previous missile
#	     		%esi - next missile
mp1_missile_remove:
# Pushes callee saved registers
pushl %ebp
movl %esp, %ebp
pushl %ebx
pushl %edi
pushl %esi

# Checks to see if the next missile is NULL after moving the appropriate values in
movl 12(%ebp), %ebx
movl 8(%ebp), %edi
cmpl $0, (%ebx)
je last_missile
 
# Removes the missile from the linked list
movl (%ebx), %esi
cmpl $0, %edi
je mp1_remove_missile_prevhead
movl %esi, (%edi)

# Removes the missile from memory and erases it from the screen
mp1_missile_remove_memory:
pushl %eax
pushl %ecx
pushl %edx
pushl %ebx
pushl $EMPTY
call mp1_poke_prep
addl $4, %esp
call mp1_free
popl %ebx
popl %edx
popl %ecx
popl %eax
jmp mp1_missile_remove_end

# Removes the last missile from the list
last_missile:
cmpl $0, %edi
je mp1_remove_missile_onemissile
movl $0, (%edi)
jmp mp1_missile_remove_memory

# Removes the missile if it is the only one
mp1_remove_missile_onemissile:
movl $0, mp1_missile_list
jmp mp1_missile_remove_memory

# Removes the only missile
mp1_remove_missile_prevhead:
movl (%ebx), %esi
movl %esi, mp1_missile_list
jmp mp1_missile_remove_memory

# Restores the necessary steps before returning
mp1_missile_remove_end:
popl %esi
popl %edi
popl %ebx
leave
ret


#  Function to start the game by drawing necessary items
# Inputs: 		None
# Outputs: 		None
# Registers: 	None
mp1_ioctl_startgame:
# Saves callee saved registers
pushl %ebp
movl %esp, %ebp
pushl %ebx
pushl %edi
pushl %esi

# Sets score to 0
movl $0, mp1_score
# Sets all bases to alive
movl $0x00FFFFFF, base_alive
# Sets the crosshair start values to (40, 12)
movl $40, crosshairs_x
movl $12, crosshairs_y

# Restores callee saved registers
movl $0, %eax
popl %esi
popl %edi
popl %ebx
leave
ret
	

# Function to add a missile
# Inputs: 		struct missile* user_missile - pointer to the new missile
# Outputs: 		int - returns whether a missile was successfully added
# Registers: 	%eax - return value
# 	     		%ebx - missile pointer in user space
#	     		%ecx - missile pointer in linked list
mp1_ioctl_addmissile:
# Saves callee saved registers		
pushl %ebp
movl %esp, %ebp
pushl %ebx
pushl %edi
pushl %esi

# Moves the pointer into EBX
movl 8(%ebp), %ebx

# Allocates 34 bytes in the memory space for the new missile
pushl $34
call mp1_malloc
addl $4, %esp
cmpl $0, %eax
je memory_fail
movl %eax, %ecx

# Transfers 34 bytes of data to the new missile pointer from user space
missile_data_transfer:
pushl $34
pushl %ebx
pushl %ecx
call mp1_copy_from_user
popl %ecx
popl %ebx
addl $4, %esp
cmpl $0, %eax
jne memory_move_fail

# Adds the missile to the linked list
movl mp1_missile_list, %ebx
movl %ebx, (%ecx)
movl %ecx, mp1_missile_list
pushl %ecx
pushl C(%ecx)
call mp1_poke_prep
addl $8, %esp
jmp add_missile_end

# Handles when allocating memory or data transfer fails
memory_move_fail:
pushl %ecx
call mp1_free
addl $4, %esp
memory_fail:
movl $-1, %eax

# Restores callee saved registers
add_missile_end:
popl %esi
popl %edi
popl %ebx
leave
ret


# Function that moves the crosshairs
# Inputs: 		unsigned long xhair_delta_packed
# Outputs: 		int - always returns 0
# Registers: 	%eax - Return value
# 	     		%ebx - value that the crosshair has to move by
# 	     		%ecx - temp value used in calculations 
mp1_ioctl_movexhairs:
# Saves callee saved registers
pushl %ebp
movl %esp, %ebp
pushl %ebx
pushl %edi
pushl %esi

# Erases old crosshair
pushl $EMPTY
call redraw_crosshairs
addl $4, %esp

# Moves the input into EBX
movl 8(%ebp), %ebx

# Calculates the new Y position by looking at the upper 16 bits of EBX
movl %ebx, %ecx
andl $0xFFFF0000, %ecx
shrl $16, %ecx
addw crosshairs_y, %cx
# Checks if the Y position is between 0-24 and fixes it if it is not
cmpw $0, %cx
jl y_pos_lower
cmpw $24, %cx
jg y_pos_greater
movl %ecx, crosshairs_y
jmp x_position_update

# Handles the edge cases in the Y direction
y_pos_lower:
movl $0, crosshairs_y
jmp x_position_update
y_pos_greater:
movl $24, crosshairs_y
jmp x_position_update

# Calculates the new X position by looking at the lower 16 bits of EBX
x_position_update:
movl %ebx, %ecx
andl $0x0000FFFF, %ecx
addw crosshairs_x, %cx
# Checks if the X position is between 0-79 and fixes it if it is not
cmpw $0, %cx
jl x_pos_lower
cmpw $79, %cx
jg x_pos_greater
movl %ecx, crosshairs_x
jmp redraw_new_crosshair

# Handles the edge cases in the X direction
x_pos_lower:
movl $0, crosshairs_x
jmp redraw_new_crosshair
x_pos_greater:
movl $79, crosshairs_x
jmp redraw_new_crosshair

# Redraws the new crosshair
redraw_new_crosshair:
pushl $CROSSHAIR
call redraw_crosshairs
addl $4, %esp

# Restores callee saved registers and loads 0 into EAX
movl $0, %eax
popl %esi
popl %edi
popl %ebx
leave
ret


# Function that gets the status of the game
# Inputs: 		unsigned long* user_status
# Outputs: 		int - returns whether data transfer succeeds or not
# Registers: 	%eax - return value
# 	     		%ebx - pointer from the user space
# 	     		%ecx - data to move into user space
# 	     		%edx - temp value used in calculations
mp1_ioctl_getstatus:
# Saves callee saved registers
pushl %ebp
movl %esp, %ebp
pushl %ebx
pushl %edi
pushl %esi

# Moves the input value into EBX and clears ECX
movl 8(%ebp), %ebx
xorl %ecx, %ecx

# Calculates if the cities are alive and stores the result in ECX
movl base_alive, %edx
andl $0x000000FF, %edx
cmpl $0, %edx
jne add_city1
city2_status_check:
movl base_alive, %edx
andl $0x0000FF00, %edx
cmpl $0, %edx
jne add_city2
city3_status_check:
movl base_alive, %edx
andl $0x00FF0000, %edx
cmpl $0, %edx
jne add_city3
jmp add_game_score

# Adds the value of the alive cities into ECX into bits 1,2, and 3
add_city1:
addl $1, %ecx
jmp city2_status_check
add_city2:
addl $2, %ecx
jmp city3_status_check
add_city3:
addl $4, %ecx

# Shifts the bits in 1-3 to bits 16-18 and adds the score
add_game_score:
shll $16, %ecx
addw mp1_score, %cx

# Updates user space
pushl %ecx
movl %esp, %eax
pushl $4
pushl %eax
pushl %ebx
call mp1_copy_to_user
addl $16, %esp
cmpl $0, %eax
je update_score_pop
movl $-1, %eax

# Restores callee saved registers
update_score_end:
movl $0, %eax
update_score_pop:
popl %esi
popl %edi
popl %ebx
leave
ret


# Function that ends the game
# Inputs: 		None
# Outputs: 		int - returns success
# Registers: 	%ebx - current missile pointer
# 	     		%edi - next missile pointer
mp1_ioctl_endgame:
# Saves callee saved registers
pushl %ebp
movl %esp, %ebp
pushl %ebx
pushl %edi
pushl %esi

# Set up values in order to remove missiles
movl mp1_missile_list, %ebx
# Checks if EBX is NULL
cmpl $0, %ebx
je endgame_end

# Loops to remove missiles in the linked list and frees memory
endgame_loop:
# Moves next missile into EDI
movl (%ebx), %edi
# Frees current missile from memory
pushl %ebx
call mp1_free
addl $4, %esp
movl %edi, %ebx
# Checks if next missile is NULL
cmpl $0, %ebx
je endgame_end
jmp endgame_loop

# Restores callee saved registers
endgame_end:
movl $0, %eax
popl %esi
popl %edi
popl %ebx
leave
ret
