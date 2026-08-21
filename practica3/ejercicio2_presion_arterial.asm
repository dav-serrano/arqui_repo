# EJERCICIO 2: MEDIDOR DE TENSIÓN ARTERIAL

.data
    # registros del dispositivo mapeados en memoria
    TensionControl: .word 0 # escribir 1 inicia la medición
    TensionEstado:  .word 0, 0, 0, 0, 1 # 0: midiendo, 1: resultados listos (ARREGLO SIMULANDO EL INFLADO)
    TensionSistol:  .word 0 # resultado de tensión sistólica (maxima presion)
    TensionDiastol: .word 0 # resultado de tensión diastólica (minima presion)

    # mensajes para la consola
    msg_tension:    .asciiz "\n[Medicion finalizada]\nPresion Sistolica: "
    msg_diastol:    .asciiz "\nPresion Diastolica: "

.text
.globl main


# PROGRAMA PRINCIPAL
main:
    # INICIO SIMULACIÓN DE PRECARGA
    # para que la espera activa no se quede en bucle infinito en el
    # simulador, precargamos los datos y marcamos el estado como listo (1)
    li $t0, 120             # valor simulado para sistólica
    sw $t0, TensionSistol   # lo guardamos en memoria
    li $t0, 80              # valor simulado para diastólica
    sw $t0, TensionDiastol  # lo guardamos en memoria
    # FIN SIMULACIÓN DE PRECARGA

    # 1. llamar al controlador para iniciar y leer la tensión
    jal controlador_tension
    
    # 2. respaldar los resultados devueltos por la subrutina
    move $s0, $v0           # guardamos la presión sistólica ($v0) en $s0
    move $s1, $v1           # guardamos la presión diastólica ($v1) en $s1

    # 3. mostrar presión sistólica (maxima presion)
    li $v0, 4               # código 4 para imprimir texto
    la $a0, msg_tension     # dirección del mensaje sistólico
    syscall
    
    li $v0, 1               # código 1 para imprimir entero
    move $a0, $s0           # cargamos el valor sistólico guardado
    syscall
    
    # 4. mostrar presión diastólica (minima presion)
    li $v0, 4               # código 4 para imprimir texto
    la $a0, msg_diastol     # dirección del mensaje diastólico
    syscall
    
    li $v0, 1               # código 1 para imprimir entero
    move $a0, $s1           # cargamos el valor diastólico guardado
    syscall

    # 5. finalizar el programa
    li $v0, 10              # código 10 para terminar la ejecución limpiamente
    syscall                 # cierra el programa


# PROCEDIMIENTO: controlador_tension
controlador_tension:
    # 1. iniciar la medición
    la $t0, TensionControl  # cargamos la dirección de TensionControl
    li $t1, 1               # cargamos el comando de inicio (1 = activar brazalete)
    sw $t1, 0($t0)          # escribimos 1 en TensionControl

    # 2. bucle de espera (espera activa)
    la $t2, TensionEstado   # cargamos la dirección de TensionEstado
    
esperar_medicion_tension:
    lw $t3, 0($t2)          # leemos el estado actual del dispositivo
    addi $t2, $t2, 4        # SUMAMOS 4 BYTES: Avanza por el arreglo de 0s para simular el paso del tiempo
    beq $t3, $zero, esperar_medicion_tension # Si es 0 (midiendo), repite el bucle

    # 3. leer los datos cuando el estado es 1 (ya terminado)
    la $t4, TensionSistol   # cargamos dirección de Sistólica
    lw $v0, 0($t4)          # guardamos el valor sistólico en $v0 (salida 1)

    la $t5, TensionDiastol  # cargamos dirección de diastólica
    lw $v1, 0($t5)          # guardamos el valor diastólico en $v1 (salida 2)

    jr $ra                  # retornamos al main con los datos en $v0 y $v1
