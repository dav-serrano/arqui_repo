# practica 4 - ejercicio 1: buffer circular con filtro de mayusculas (interrupciones)

.data
    buffer:         .space 100                 # reservar 100 bytes para el buffer circular
    BUFFER_SIZE:    .word 100                  # tamano maximo del buffer
    head:           .word 0                    # indice de escritura (en memoria para la interrupcion)
    count:          .word 0                    # cantidad de elementos (en memoria para la interrupcion)
    
    # mensajes de interfaz
    msg_inicio:     .asciiz "\n--- Inicio de captura (20 segundos) ---\nIngrese caracteres: "
    msg_fin:        .asciiz "\n--- Tiempo agotado (20s). Contenido del Buffer: ---\n"
    msg_vacio:      .asciiz "(Buffer vacio)\n"
    msg_separador:  .asciiz "\n============================================\n"

.text
.globl main

main:
    # bucle infinito principal (repite el proceso indefinidamente)
bucle_principal:
    # 1. imprimir mensaje de inicio
    li $v0, 4
    la $a0, msg_inicio
    syscall

    # 2. inicializar punteros e indices en memoria
    sw $zero, head             # reiniciar indice de escritura
    sw $zero, count            # reiniciar contador de elementos

    # habilitar interrupciones de teclado (bit 1 del receiver control register)
    lui $t0, 0xffff
    li $t1, 2                  # bit 1 = 1 para habilitar interrupcion
    sw $t1, 0($t0)

    # habilitar interrupciones globales en el coprocesador 0 (status register)
    mfc0 $t0, $12              # leer registro status (12)
    ori $t0, $t0, 0x0101       # habilitar bit 0 (global) y bit 8 (mascara de teclado)
    mtc0 $t0, $12              # guardar registro status

    # 3. obtener el tiempo inicial del sistema (en milisegundos)
    li $v0, 30                 # syscall 30: time (devuelve tiempo en $a0:$a1)
    syscall
    move $s4, $a0              # $s4 = marca de tiempo inicial (lsb)

bucle_captura:
    # 4. verificar si han transcurrido 20,000 ms (20 segundos)
    li $v0, 30                 # obtener tiempo actual
    syscall
    subu $t0, $a0, $s4         # $t0 = tiempo actual - tiempo inicial
    bgeu $t0, 20000, fin_captura  # si transcurrieron >= 20000 ms, salir del bucle

    # 5. el procesador entra en espera activa solo por el tiempo, 
    # la lectura del teclado se maneja por interrupciones en segundo plano
    j bucle_captura

fin_captura:
    # deshabilitar interrupciones de teclado para no capturar mientras se imprime
    lui $t0, 0xffff
    sw $zero, 0($t0)

    # 6. transcurridos los 20 segundos, imprimir el contenido
    li $v0, 4
    la $a0, msg_fin
    syscall

    # cargar datos actualizados por la interrupcion
    lw $s2, count              # $s2 = elementos almacenados totales
    lw $s3, BUFFER_SIZE

    # si no se ingresaron caracteres validos
    beq $s2, $zero, imprimir_vacio

    # recorrer e imprimir los caracteres guardados
    li $t5, 0                  # contador de lectura
    la $s0, buffer             # direccion base del buffer
    move $t6, $zero            # $t6 = indice de lectura
    
imprimir_bucle:
    beq $t5, $s2, fin_impresion # terminar si leimos todos los elementos
    
    addu $t7, $s0, $t6         # direccion = base + indice lectura
    lbu $a0, 0($t7)            # cargar caracter
    
    li $v0, 11                 # syscall 11: print character
    syscall
    
    # imprimir espacio entre caracteres
    li $a0, ' '
    li $v0, 11
    syscall

    addi $t6, $t6, 1           # avanzar indice de lectura
    rem $t6, $t6, $s3          # aplicar modulo circular
    addi $t5, $t5, 1           # incrementar contador
    j imprimir_bucle

imprimir_vacio:
    li $v0, 4
    la $a0, msg_vacio
    syscall

fin_impresion:
    li $v0, 4
    la $a0, msg_separador
    syscall

    # repetir el ciclo indefinidamente
    j bucle_principal


# manejador de interrupciones (rutina de servicio de excepcion)
.kdata
    save_at: .word 0
    save_t0: .word 0
    save_t1: .word 0
    save_t2: .word 0
    save_t3: .word 0

.ktext 0x80000180
    # 1. guardar contexto de los registros a utilizar
    move $k0, $at              # proteger registro $at
    sw $k0, save_at
    sw $t0, save_t0
    sw $t1, save_t1
    sw $t2, save_t2
    sw $t3, save_t3

    # 2. verificar si la interrupcion es de teclado
    mfc0 $t0, $13              # leer registro cause (13)
    andi $t0, $t0, 0x0100      # aislar bit 8 (hardware interrupt 0)
    beq $t0, $zero, fin_interrupcion # si no fue teclado, ignorar

    # 3. leer el caracter (esto ademas limpia el flag de interrupcion del teclado)
    lui $t1, 0xffff
    lw $t2, 4($t1)             # $t2 = caracter leido en ascii

    # 4. filtrar unicamente letras mayusculas ('a' = 65 a 'z' = 90)
    blt $t2, 65, fin_interrupcion
    bgt $t2, 90, fin_interrupcion

    # 5. almacenar caracter en el buffer circular
    la $t0, buffer
    lw $t1, head
    addu $t3, $t0, $t1         # direccion destino = base + head(indice)
    sb $t2, 0($t3)             # guardar el byte

    # 6. actualizar indice circular y contador
    addi $t1, $t1, 1		# avanzamos al siguiente indice (avanzamos una casilla)
    lw $t3, BUFFER_SIZE
    rem $t1, $t1, $t3          # head = (head + 1) % buffer_size
    sw $t1, head               # guardar head actualizado en la ram

    lw $t1, count
    bge $t1, $t3, fin_interrupcion # tope maximo de elementos(100), si no se ha sobrepasado,
    addi $t1, $t1, 1			# entonces avanza a la siguiente casilla
    sw $t1, count              # guardar contador actualizado

fin_interrupcion:
    # 7. restaurar contexto original
    lw $t0, save_t0
    lw $t1, save_t1
    lw $t2, save_t2
    lw $t3, save_t3
    lw $k0, save_at
    move $at, $k0              # restaurar registro $at

    # 8. limpiar registro cause para prevenir falsas interrupciones
    mtc0 $zero, $13

    # 9. retornar a la instruccion interrumpida
    eret