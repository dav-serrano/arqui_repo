# algoritmo: quicksort iterativo en mips32

.data
    array:  .word 12, 3, 5, 7, 19, 1, 8, 2   # arreglo de prueba
    size:   .word 8                           # tamaño del arreglo
    
    msg_orig: .asciiz "Arreglo original:  "
    msg_sort: .asciiz "\nArreglo ordenado:  "
    space:    .asciiz " "

.text
.globl main

# funcion principal main
main:
    # 1. imprimir mensaje del arreglo original
    li   $v0, 4
    la   $a0, msg_orig
    syscall

    # 2. imprimir el arreglo original
    la   $a0, array
    lw   $a1, size
    jal  print_array

    # 3. llamar a la subrutina quicksort iterativo
    la   $a0, array
    li   $a1, 0
    lw   $t0, size
    subi $a2, $t0, 1
    jal  quicksort_iterative

    # 4. imprimir mensaje del arreglo ordenado
    li   $v0, 4
    la   $a0, msg_sort
    syscall

    # 5. imprimir el arreglo ordenado
    la   $a0, array
    lw   $a1, size
    jal  print_array

    # 6. salir del programa limpiamente
    li   $v0, 10
    syscall


# subrutina: print_array ($a0 = direccion base, $a1 = tamaño)
print_array:
    move $t0, $a0            # $t0 guarda la direccion actual del elemento
    li   $t1, 0              # $t1 es el contador i = 0

print_loop:
    bge  $t1, $a1, print_end # si i >= tamaño, terminar bucle

    lw   $a0, 0($t0)         # cargar el numero entero actual
    li   $v0, 1              # syscall para imprimir entero
    syscall

    li   $v0, 4              # syscall para imprimir cadena
    la   $a0, space          # imprimir espacio en blanco
    syscall

    addi $t0, $t0, 4         # avanzar a la siguiente direccion de memoria (4 bytes)
    addi $t1, $t1, 1         # i++
    j    print_loop

print_end:
    jr   $ra                 # retornar de la funcion


# subrutina: quicksort_iterative ($a0 = base, $a1 = inicio, $a2 = fin)
quicksort_iterative:
    addi $sp, $sp, -400      # reservar espacio en el stack para la pila auxiliar de limites (100 numeros)
    move $t8, $sp            # $t8 actua como puntero de nuestra pila auxiliar

    sw   $a1, 0($t8)         # guardar el limite inferior inicial (low)
    sw   $a2, 4($t8)         # guardar el limite superior inicial (high)
    addi $t8, $t8, 8         # avanzar el puntero de la pila auxiliar (2 palabras)

iter_loop:
    beq  $t8, $sp, end_qs    # si el puntero vuelve a la base del stack, la pila esta vacia

    addi $t8, $t8, -8        # desapilar: retroceder el puntero 8 bytes
    lw   $s0, 0($t8)         # extraer limite inferior ($s0 = low)
    lw   $s1, 4($t8)         # extraer limite superior ($s1 = high)

    bge  $s0, $s1, iter_loop # si low >= high, este sub-arreglo ya esta procesado

    # inicio de la particion
    sll  $t0, $s1, 2         # desplazamiento en bytes para high (high * 4)
    add  $t0, $a0, $t0       # direccion del pivote
    lw   $t1, 0($t0)         # $t1 = valor del pivote (ultimo elemento)

    subi $t2, $s0, 1         # $t2 = indice i = low - 1
    move $t3, $s0            # $t3 = indice j = low

part_loop:
    bge  $t3, $s1, part_end  # si j >= high, terminar bucle de particion

    sll  $t4, $t3, 2         # desplazamiento en bytes para j
    add  $t4, $a0, $t4       # direccion de array[j]
    lw   $t5, 0($t4)         # $t5 = array[j]

    bgt  $t5, $t1, next_j    # si array[j] > pivote, avanzar sin intercambiar

    # intercambio: array[i] y array[j]
    addi $t2, $t2, 1         # i++
    sll  $t6, $t2, 2         # desplazamiento para i
    add  $t6, $a0, $t6       # direccion de array[i]
    lw   $t7, 0($t6)         # $t7 = array[i]

    sw   $t5, 0($t6)         # array[i] = array[j]
    sw   $t7, 0($t4)         # array[j] = valor anterior de array[i]

next_j:
    addi $t3, $t3, 1         # j++
    j    part_loop

part_end:
    # colocar el pivote en su posicion correcta (i + 1)
    addi $t2, $t2, 1         # i + 1
    sll  $t6, $t2, 2         # desplazamiento para i + 1
    add  $t6, $a0, $t6       # direccion de array[i + 1]
    lw   $t7, 0($t6)         # $t7 = array[i + 1]

    sw   $t1, 0($t6)         # colocar el pivote en array[i + 1]
    sw   $t7, 0($t0)         # mover array[i + 1] a la posicion original del pivote

    move $s2, $t2            # $s2 guarda la posicion final del pivote
    # fin de la particion

    # verificar si hay sub-arreglo a la izquierda del pivote
    subi $t1, $s2, 1         # $t1 = pivote - 1
    blt  $s0, $t1, push_left # si low < pivote - 1, apilar sub-arreglo izquierdo
    j    check_right

push_left:
    sw   $s0, 0($t8)         # apilar limite inferior izquierdo
    sw   $t1, 4($t8)         # apilar limite superior izquierdo
    addi $t8, $t8, 8         # avanzar puntero de la pila auxiliar

check_right:
    # verificar si hay sub-arreglo a la derecha del pivote
    addi $t2, $s2, 1         # $t2 = pivote + 1
    blt  $t2, $s1, push_right# si pivote + 1 < high, apilar sub-arreglo derecho
    j    iter_loop

push_right:
    sw   $t2, 0($t8)         # apilar limite inferior derecho
    sw   $s1, 4($t8)         # apilar limite superior derecho
    addi $t8, $t8, 8         # avanzar puntero de la pila auxiliar
    j    iter_loop

end_qs:
    addi $sp, $sp, 400       # liberar el espacio reservado en el stack
    jr   $ra                 # retornar de la subrutina