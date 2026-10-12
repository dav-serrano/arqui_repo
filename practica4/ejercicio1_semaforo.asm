# practica 4 - ejercicio 2: semaforo con pulsador 's' (interrupciones)

.data
    msg_verde_esp: .asciiz "\n[VERDE] Semaforo en verde, esperando pulsador ('s')...\n"
    msg_pulsado:   .asciiz "\n[ACTIVADO] Pulsador activado: en 20 segundos, el semaforo cambiara a amarillo.\n"
    msg_amarillo:  .asciiz "\n[AMARILLO] Semaforo en amarillo, en 10 segundos, semaforo en rojo.\n"
    msg_rojo:      .asciiz "\n[ROJO] Semaforo en rojo, en 30 segundos, semaforo en verde.\n"
    
    # novedad: variable en ram para que la interrupcion le avise al programa principal
    flag_pulsador: .word 0 

.text
.globl main

main:
    # configuracion inicial de interrupciones

    # 1. habilitar interrupciones de teclado (bit 1 del receiver control register)
    lui $t0, 0xffff
    li $t1, 2                  # bit 1 = 1 para habilitar la interrupcion hardware del teclado
    sw $t1, 0($t0)

    # 2. habilitar interrupciones globales en el coprocesador 0 (registro status)
    mfc0 $t0, $12              # leer registro status (12)
    ori $t0, $t0, 0x0101       # habilitar bit 0 (permiso global) y bit 8 (mascara del teclado)
    mtc0 $t0, $12              # guardar configuracion en el registro status

    # bucle infinito que maneja el ciclo de estados del semaforo
ciclo_semaforo:

    # estado 1: verde - esperando la tecla 's'
    li $v0, 4
    la $a0, msg_verde_esp
    syscall

    # asegurarnos de que la bandera este en 0 al iniciar el ciclo
    sw $zero, flag_pulsador

esperar_pulsador:
    # nuevo comportamiento: ya no hacemos polling al hardware (0xffff0000).
    # leemos la variable en ram. el procesador es libre de hacer otras tareas aqui.
    lw $t1, flag_pulsador
    beq $t1, $zero, esperar_pulsador # esperar hasta que el manejador de interrupcion cambie el 0 por un 1

pulsador_ok:
    # estado 2: verde activado (cuenta regresiva de 20 segundos)
    li $v0, 4
    la $a0, msg_pulsado
    syscall

    li $a0, 20000              # tiempo en ms
    jal temporizador_delay

    # estado 3: amarillo (cuenta regresiva de 10 segundos)
    li $v0, 4
    la $a0, msg_amarillo
    syscall

    li $a0, 10000              # tiempo en ms
    jal temporizador_delay

    # estado 4: rojo (cuenta regresiva de 30 segundos)
    li $v0, 4
    la $a0, msg_rojo
    syscall

    li $a0, 30000              # tiempo en ms
    jal temporizador_delay

    # volver a repetir el ciclo completo
    j ciclo_semaforo

# subrutina: temporizador_delay
# utiliza la syscall 32 (sleep) para suspender la ejecucion
temporizador_delay:
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    li $v0, 32
    syscall
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra


# manejador de interrupciones (rutina de servicio de excepcion)
# se ubica obligatoriamente en la direccion 0x80000180
.kdata
    # espacio para guardar el contexto (los registros que la interrupcion va a usar)
    save_at: .word 0
    save_t0: .word 0
    save_t1: .word 0
    save_t2: .word 0

.ktext 0x80000180
    # 1. salvar el contexto del procesador antes de procesar la interrupcion
    move $k0, $at              # proteger registro $at
    sw $k0, save_at
    sw $t0, save_t0
    sw $t1, save_t1
    sw $t2, save_t2

    # 2. verificar en el registro cause si la interrupcion proviene del teclado
    mfc0 $t0, $13              # leer registro cause
    andi $t0, $t0, 0x0100      # aislar bit 8 (hardware interrupt 0 / teclado)
    beq $t0, $zero, fin_interrupcion # si fue otra interrupcion, ignorarla

    # 3. leer el caracter del teclado. (esto automaticamente limpia la senal de interrupcion en mars)
    lui $t1, 0xffff
    lw $t2, 4($t1)             # $t2 = caracter leido en ascii

    # 4. comprobar si la tecla es 's' (115) o 's' (83)
    beq $t2, 115, activar_flag
    beq $t2, 83, activar_flag
    j fin_interrupcion         # si es otra tecla, ignorar y terminar

activar_flag:
    # 5. la tecla es correcta: modificamos la variable en ram para avisar al programa principal
    li $t0, 1
    sw $t0, flag_pulsador

fin_interrupcion:
    # 6. restaurar el contexto (devolver los registros a sus valores originales)
    lw $t0, save_t0
    lw $t1, save_t1
    lw $t2, save_t2
    lw $k0, save_at
    move $at, $k0              # restaurar registro $at

    # 7. limpiar el registro cause para evitar un bucle de interrupciones fantasma
    mtc0 $zero, $13

    # 8. instruccion eret (exception return): regresa al programa principal (pc restaurado desde epc)
    eret