# ===================================================================
# PRÁCTICA 4 - EJERCICIO 2: Semáforo con Pulsador 's' (Interrupciones)
# Plataforma: MARS (MIPS32)
# ===================================================================

.data
    msg_verde_esp: .asciiz "\n[VERDE] Semaforo en verde, esperando pulsador ('s')...\n"
    msg_pulsado:   .asciiz "\n[ACTIVADO] Pulsador activado: en 20 segundos, el semaforo cambiara a amarillo.\n"
    msg_amarillo:  .asciiz "\n[AMARILLO] Semaforo en amarillo, en 10 segundos, semaforo en rojo.\n"
    msg_rojo:      .asciiz "\n[ROJO] Semaforo en rojo, en 30 segundos, semaforo en verde.\n"
    
    # Novedad: Variable en RAM para que la interrupción le avise al programa principal
    flag_pulsador: .word 0 

.text
.globl main

main:
    # ---------------------------------------------------------------
    # CONFIGURACIÓN INICIAL DE INTERRUPCIONES
    # ---------------------------------------------------------------
    # 1. Habilitar interrupciones de teclado (bit 1 del Receiver Control Register)
    lui $t0, 0xffff
    li $t1, 2                  # Bit 1 = 1 para habilitar la interrupción hardware del teclado
    sw $t1, 0($t0)

    # 2. Habilitar interrupciones globales en el Coprocesador 0 (Registro Status)
    mfc0 $t0, $12              # Leer registro Status (12)
    ori $t0, $t0, 0x0101       # Habilitar bit 0 (Permiso Global) y bit 8 (Máscara del teclado)
    mtc0 $t0, $12              # Guardar configuración en el registro Status

    # Bucle infinito que maneja el ciclo de estados del semáforo
ciclo_semaforo:

    # ---------------------------------------------------------------
    # ESTADO 1: VERDE - Esperando la tecla 's'
    # ---------------------------------------------------------------
    li $v0, 4
    la $a0, msg_verde_esp
    syscall

    # Asegurarnos de que la bandera esté en 0 al iniciar el ciclo
    sw $zero, flag_pulsador

esperar_pulsador:
    # Leemos la variable en RAM. El procesador es libre de hacer otras tareas aquí.
    lw $t1, flag_pulsador
    beq $t1, $zero, esperar_pulsador # Esperar hasta que el manejador de interrupción cambie el 0 por un 1

pulsador_ok:
    # ---------------------------------------------------------------
    # ESTADO 2: VERDE ACTIVADO (Cuenta regresiva de 20 segundos)
    # ---------------------------------------------------------------
    li $v0, 4
    la $a0, msg_pulsado
    syscall

    li $a0, 20000              # Tiempo en ms
    jal temporizador_delay

    # ---------------------------------------------------------------
    # ESTADO 3: AMARILLO (Cuenta regresiva de 10 segundos)
    # ---------------------------------------------------------------
    li $v0, 4
    la $a0, msg_amarillo
    syscall

    li $a0, 10000              # Tiempo en ms
    jal temporizador_delay

    # ---------------------------------------------------------------
    # ESTADO 4: ROJO (Cuenta regresiva de 30 segundos)
    # ---------------------------------------------------------------
    li $v0, 4
    la $a0, msg_rojo
    syscall

    li $a0, 30000              # Tiempo en ms
    jal temporizador_delay

    # Volver a repetir el ciclo completo
    j ciclo_semaforo

# ===================================================================
# SUBRUTINA: temporizador_delay
# Utiliza la syscall 32 (Sleep) para suspender la ejecución
# ===================================================================
temporizador_delay:
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    li $v0, 32
    syscall
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra


# ===================================================================
# MANEJADOR DE INTERRUPCIONES (Rutina de Servicio de Excepción)
# Se ubica obligatoriamente en la dirección 0x80000180
# ===================================================================
.kdata
    # Espacio para guardar el contexto (los registros que la interrupción va a usar)
    save_at: .word 0
    save_t0: .word 0
    save_t1: .word 0
    save_t2: .word 0

.ktext 0x80000180
    # 1. Salvar el contexto del procesador antes de procesar la interrupción
    move $k0, $at              # Proteger registro $at
    sw $k0, save_at
    sw $t0, save_t0
    sw $t1, save_t1
    sw $t2, save_t2

    # 2. Verificar en el registro Cause si la interrupción proviene del teclado
    mfc0 $t0, $13              # Leer registro Cause
    andi $t0, $t0, 0x0100      # Aislar bit 8 (Hardware Interrupt 0 / Teclado)
    beq $t0, $zero, fin_interrupcion # Si fue otra interrupción, ignorarla

    # 3. Leer el carácter del teclado. (Esto automáticamente limpia la señal de interrupción en MARS)
    lui $t1, 0xffff
    lw $t2, 4($t1)             # $t2 = Carácter leído en ASCII

    # 4. Comprobar si la tecla es 's' (115) o 'S' (83)
    beq $t2, 115, activar_flag
    beq $t2, 83, activar_flag
    j fin_interrupcion         # Si es otra tecla, ignorar y terminar

activar_flag:
    # 5. La tecla es correcta: Modificamos la variable en RAM para avisar al programa principal
    li $t0, 1
    sw $t0, flag_pulsador

fin_interrupcion:
    # 6. Restaurar el contexto (devolver los registros a sus valores originales)
    lw $t0, save_t0
    lw $t1, save_t1
    lw $t2, save_t2
    lw $k0, save_at
    move $at, $k0              # Restaurar registro $at

    # 7. Limpiar el registro Cause para evitar un bucle de interrupciones fantasma[cite: 1]
    mtc0 $zero, $13

    # 8. Instrucción ERET (Exception Return): Regresa al programa principal (PC restaurado desde EPC)
    eret