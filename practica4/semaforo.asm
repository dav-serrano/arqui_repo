# ===================================================================
# PRÁCTICA 4 - EJERCICIO 2: Semáforo con Pulsador 's'
# ===================================================================

.data
    msg_verde_esp: .asciiz "\n[VERDE] Semaforo en verde, esperando pulsador ('s')...\n"
    msg_pulsado:   .asciiz "\n[ACTIVADO] Pulsador activado: en 20 segundos, el semaforo cambiara a amarillo.\n"
    msg_amarillo:  .asciiz "\n[AMARILLO] Semaforo en amarillo, en 10 segundos, semaforo en rojo.\n"
    msg_rojo:      .asciiz "\n[ROJO] Semaforo en rojo, en 30 segundos, semaforo en verde.\n"

.text
.globl main

main:
    # Bucle infinito que maneja el ciclo de estados del semáforo
ciclo_semaforo:

    # ---------------------------------------------------------------
    # ESTADO 1: VERDE - Esperando la tecla 's'
    # ---------------------------------------------------------------
    li $v0, 4
    la $a0, msg_verde_esp
    syscall

esperar_pulsador:
    # Direcciones MMIO para el teclado en MARS:
    # 0xffff0000: Receiver Control (bit 0 indica si hay tecla lista)
    # 0xffff0004: Receiver Data (contiene el código ASCII de la tecla)
    
    lui $t0, 0xffff            # $t0 = 0xffff0000
    lw $t1, 0($t0)             # Leer Receiver Control
    andi $t1, $t1, 0x0001      # Enmascarar el bit 0 (Ready bit)
    beq $t1, $zero, esperar_pulsador # Si es 0, sigue esperando (espera activa)

    # Leer el carácter recibido cuando el bit ready pasa a 1
    lw $t2, 4($t0)             # Leer Receiver Data
    
    # Comprobar si la tecla ingresada es 's' (ASCII 115) o 'S' (ASCII 83)
    beq $t2, 115, pulsador_ok
    beq $t2, 83, pulsador_ok
    j esperar_pulsador         # Descarta cualquier otra tecla e insiste

pulsador_ok:
    # ---------------------------------------------------------------
    # ESTADO 2: VERDE ACTIVADO (Cuenta regresiva de 20 segundos)
    # ---------------------------------------------------------------
    li $v0, 4
    la $a0, msg_pulsado
    syscall

    # Esperar 20 segundos (20,000 ms)
    li $a0, 20000
    jal temporizador_delay

    # ---------------------------------------------------------------
    # ESTADO 3: AMARILLO (Cuenta regresiva de 10 segundos)
    # ---------------------------------------------------------------
    li $v0, 4
    la $a0, msg_amarillo
    syscall

    # Esperar 10 segundos (10,000 ms)
    li $a0, 10000
    jal temporizador_delay

    # ---------------------------------------------------------------
    # ESTADO 4: ROJO (Cuenta regresiva de 30 segundos)
    # ---------------------------------------------------------------
    li $v0, 4
    la $a0, msg_rojo
    syscall

    # Esperar 30 segundos (30,000 ms)
    li $a0, 30000
    jal temporizador_delay

    # Reiniciar el ciclo
    j ciclo_semaforo

# ===================================================================
# SUBRUTINA: temporizador_delay
# Entrada: $a0 = Milisegundos a esperar
# Utiliza la Syscall 32 (Sleep) nativa de MARS
# ===================================================================
temporizador_delay:
    # Guardar la dirección de retorno ($ra) en la pila por buenas prácticas
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    # Syscall 32: Sleep (recibe el tiempo en ms dentro de $a0)
    li $v0, 32
    syscall

    # Restaurar la pila y retornar
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra
