.data
    msg_input:  .asciiz "Ingrese un numero entero positivo (n): "
    msg_output: .asciiz "La paridad es: "
    msg_error:  .asciiz "Error: El numero debe ser positivo o cero.\n\n"

.text
.globl main

main:
    li $v0, 4		# imprimir mensaje para pedir n
    la $a0, msg_input
    syscall

    # leer el entero ingresado por el usuario
    li $v0, 5
    syscall
    move $s0, $v0           # guardar n en $s0

    # validar que n >= 0 (Si es negativo, mostrar error)
    bltz $s0, error_input

    # llamar a la funcion paridad_recursiva
    move $a0, $s0           # pasar n como argumento
    jal paridad_recursiva
    move $s1, $v0           # guardar el resultado devuelto en $s1

    # imprimir el mensaje de salida
    li $v0, 4
    la $a0, msg_output
    syscall

    # imprimir el resultado (paridad)
    li $v0, 1
    move $a0, $s1
    syscall

    # terminar ejecucion del programa limpiamente
    li $v0, 10
    syscall

error_input:
    # mostrar mensaje de error y volver a pedir el numero
    li $v0, 4
    la $a0, msg_error
    syscall
    j main

# ==========================================
# funcion: paridad_recursiva
# entrada: $a0 = n
# salida:  $v0 = paridad(n)
# ==========================================
paridad_recursiva:
    addi $sp, $sp, -8       # Reservar 8 bytes en la pila
    sw $ra, 4($sp)          # Guardar direccion de retorno
    sw $a0, 0($sp)          # Guardar argumento n actual

    # caso base
    # si n == 0, retornar 0
    bgtz $a0, paso_recursivo
    li $v0, 0               # resultado = 0
    j restauro

paso_recursivo:
    # llamada recursiva
    addi $a0, $a0, -1       # n = n - 1
    jal paridad_recursiva   # llamar paridad(n-1)

    # calcular 1 - paridad(n-1)
    li $t0, 1
    sub $v0, $t0, $v0       # $v0 = 1 - $v0

restauro:
    # restauracion
    lw $a0, 0($sp)          # restaurar argumento n original
    lw $ra, 4($sp)          # restaurar direccion de retorno
    addi $sp, $sp, 8        # liberar el espacio de la pila

    jr $ra                  # retornar a la instruccion llamadora