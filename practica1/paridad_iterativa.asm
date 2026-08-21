.data
	prompt: .asciiz "Ingrese un numero entero positivo n:"
	msg_result: .asciiz "\nLa paridad del numero es: "

.text
	# pido n
	li $v0, 4		#syscall para imprimir
	la $a0, prompt		# cargar la direccion del mensaje
	syscall
	
	# leo n
	li $v0, 5			# syscall para leer un entero
	syscall
	move $t0, $v0			# guardo el numero n ingresado en $t0
	
	# validacion de la entrada (valor absoluto al valor ingresado, la paridad es la misma)
	# si el numero es negativo, lo convertimos a positivo
	bgez $t0, continuar_flujo	# si n >= 0, saltar a continuar_flujo
	sub $t0, $zero, $t0		# si n < 0, hacemos n = 0 - n
	
continuar_flujo:
	li $t1, 0			# $t1 sera la variable paridad, inicia en 0
	li $t2, 1 			# constante 1 guardada en $t2 para la resta
	
loop_paridad:
	blez $t0, end_loop		# si n <= 0, terminamos, fin
	
	#aplico la formula: 	paridad = 1 - paridad
	sub $t1,$t2,$t1
	
	#decremento n (n = n-1)
	addi $t0, $t0, -1
	
	j loop_paridad		# salto al inicio
	
end_loop:
	# imprimir el mensaje de resultado
	li $v0, 4		# syscall para imprimir tetxo
	la $a0, msg_result		
	syscall
	
	li $v0, 1		# syscall para imprimir entyero
	move $a0, $t1		# mover el resultado calculado a $a0
	syscall
	
	li $v0, 10		#syscall para salir del programa
	syscall
