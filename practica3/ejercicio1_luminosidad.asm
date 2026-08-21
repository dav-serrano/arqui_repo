.data
    # --------------------------------------------------------------------------
    # EJERCICIO1: SENSOR DE LUMINOSIDAD (MIPS32)
    # --------------------------------------------------------------------------
    LuzControl: .word 0     # Registro de control: Escribir 0x1 le indica al sensor que inicie
    LuzEstado:  .word 0     # Registro de estado: 0 = Buscando/Ocupado, 1 = Listo, -1 = Error
    LuzDatos:   .word 0     # Registro de datos: Guarda el valor leído del sensor (0 a 1023)

    # --------------------------------------------------------------------------
    # ESTRUCTURAS DE DATOS Y VARIABLES
    # --------------------------------------------------------------------------
    # Arreglo de 20 bytes (5 enteros de 4 bytes) para guardar la secuencia ingresada
    secuencia_estados: .space 20
    
    tamano_secuencia:  .word 0   # Almacena cuántos elementos ingresó el usuario (máximo 5)
    indice_estado:     .word 0   # Puntero/Índice para saber qué estado del vector estamos procesando

    # Buffer de 80 bytes (hasta 20 enteros) para almacenar los estados por los que transitó el sensor
    buffer_historial: .space 80
    conteo_historial: .word 0   # Cantidad de elementos guardados en el historial de pantalla

    # --------------------------------------------------------------------------
    # MENSAJES DE CONSOLA (CADENAS ASCIIZ)
    # --------------------------------------------------------------------------
    msg_in_cant:     .asciiz "Ingresa la cantidad de estados (1 a 5): "
    msg_in_elem:     .asciiz "Ingresa estado ["
    msg_in_elem_2:   .asciiz "] (0: Ocupado, 1: Listo, -1: Error): "
    msg_in_datos:    .asciiz "Ingresa la luminosidad (0 - 1023): "
    msg_separador:   .asciiz ", "
    msg_luz_ok:      .asciiz " exito. Valor de luminosidad: "
    msg_luz_err:     .asciiz " error de sensor."
    msg_timeout_err: .asciiz " error bucle infinito."

.text
.globl main

# ==============================================================================
# PROGRAMA PRINCIPAL
# ==============================================================================
main:
    # --------------------------------------------------------------------------
    # ETAPA 1: LECTURA Y VALIDACIÓN DE LA CANTIDAD DE ELEMENTOS
    # --------------------------------------------------------------------------
    li $v0, 4                   # Syscall 4: Imprimir cadena de texto
    la $a0, msg_in_cant         # Cargar dirección del mensaje
    syscall

    li $v0, 5                   # Syscall 5: Leer entero desde la consola
    syscall                     # El valor leído por el usuario queda almacenado en $v0
    
    # Validar que el usuario no ingrese un tamaño mayor a 5
    li $t0, 5                   # Cargar el tope máximo (5) en $t0
    ble $v0, $t0, cant_ok       # Si $v0 <= 5, salta a 'cant_ok' (es válido)
    move $v0, $t0               # Si $v0 > 5, forzamos/ajustamos el valor a 5

cant_ok:
    sw $v0, tamano_secuencia    # Guardar el tamaño final validado en la variable de memoria
    move $s2, $v0               # Guardar el tamaño en $s2 para usarlo como límite del bucle

    # --------------------------------------------------------------------------
    # ETAPA 2: LECTURA DEL VECTOR DE ESTADOS POR TECLADO
    # --------------------------------------------------------------------------
    li $s3, 0                   # $s3 funcionará como el índice del bucle (i = 0)
    la $s4, secuencia_estados   # $s4 contiene la dirección base del arreglo

loop_lectura_vec:
    bge $s3, $s2, fin_lectura_vec  # Si i >= cantidad_elementos, salimos del bucle

    # Imprimir la primera parte del mensaje: "Ingresa estado ["
    li $v0, 4
    la $a0, msg_in_elem
    syscall

    # Imprimir el índice actual (i)
    li $v0, 1                   # Syscall 1: Imprimir entero
    move $a0, $s3               # Pasar el valor de i ($s3) a $a0
    syscall

    # Imprimir la segunda parte: "] (0: Ocupado, 1: Listo, -1: Error): "
    li $v0, 4
    la $a0, msg_in_elem_2
    syscall

    # Leer el estado ingresado por el usuario (0, 1 o -1)
    li $v0, 5                   # Syscall 5: Leer entero
    syscall                     # El valor leído ingresa en $v0

    # Calcular la dirección de memoria donde se guardará: base + (i * 4)
    sll $t1, $s3, 2             # $t1 = i * 4 (multiplica por 4 desplazando 2 bits a la izq)
    add $t2, $s4, $t1           # $t2 = Dirección Base ($s4) + Desplazamiento ($t1)
    sw $v0, 0($t2)              # Guardar el estado leído en secuencia_estados[i]

    addi $s3, $s3, 1            # Incrementar índice: i = i + 1
    j loop_lectura_vec          # Repetir la iteración del bucle

fin_lectura_vec:
    # --------------------------------------------------------------------------
    # ETAPA 3: LECTURA DE LA LUMINOSIDAD SIMULADA
    # --------------------------------------------------------------------------
    li $v0, 4
    la $a0, msg_in_datos        # Pedir el valor de la luz
    syscall

    li $v0, 5                   # Leer valor entero (0 a 1023)
    syscall
    sw $v0, LuzDatos            # Escribir directamente en el registro mapeado LuzDatos

    # --------------------------------------------------------------------------
    # ETAPA 4: CONFIGURACIÓN INICIAL DEL ESTADO Y HISTORIAL
    # --------------------------------------------------------------------------
    la $t0, secuencia_estados   # Cargar dirección base del vector
    lw $t1, 0($t0)              # Leer el primer estado guardado (secuencia_estados[0])
    sw $t1, LuzEstado           # Asignarlo como estado inicial del sensor en memoria

    # Guardar este primer estado en el historial de pantalla
    move $a0, $t1               # Pasar el estado inicial en $a0 como argumento
    jal GuardarEnHistorial      # Salta a la función GuardarEnHistorial

    # --------------------------------------------------------------------------
    # ETAPA 5: EJECUCIÓN DE LA INICIALIZACIÓN DEL SENSOR (POLLING)
    # --------------------------------------------------------------------------
    jal InicializarSensorLuz    # Llama a la rutina de encendido/espera del sensor

    move $s1, $v1               # Guardar en $s1 el código devuelto por la función ($v1)

    # Verificar si ocurrió un desbordamiento o bucle infinito (Timeout = -2)
    li $t0, -2
    beq $s1, $t0, imprimir_resultado  # Si hubo Timeout, ir directo a mostrar el historial

    # --------------------------------------------------------------------------
    # ETAPA 6: LECTURA DE DATOS FINAL (SI NO HUBO TIMEOUT)
    # --------------------------------------------------------------------------
    jal LeerLuminosidad         # Llamar a la función que valida el estado final
    move $s0, $v0               # Guardar en $s0 el valor de luminosidad devuelto
    move $s1, $v1               # Guardar en $s1 el código de éxito (0) o error (-1)

imprimir_resultado:
    # --------------------------------------------------------------------------
    # ETAPA 7: IMPRESIÓN DEL HISTORIAL Y MENSAJE DE SALIDA
    # --------------------------------------------------------------------------
    jal ImprimirHistorial       # Muestra en consola la secuencia de estados (ej: 0, 0, 1)

    # Evaluar el código de retorno almacenado en $s1 para decidir qué mensaje imprimir
    li $t0, -2
    beq $s1, $t0, res_timeout   # Si es -2, imprimir error de bucle infinito

    li $t0, -1
    beq $s1, $t0, res_error     # Si es -1, imprimir error del sensor

    # --- CASO DE ÉXITO (Código 0) ---
    li $v0, 4
    la $a0, msg_luz_ok         # Imprimir " exito. Valor de luminosidad: "
    syscall

    li $v0, 1
    move $a0, $s0               # Imprimir el valor leido almacenado en $s0
    syscall
    j fin_programa              # Saltar al final para evitar ejecutar las otras ramas

res_timeout:
    li $v0, 4
    la $a0, msg_timeout_err     # Imprimir " error bucle infinito."
    syscall
    j fin_programa

res_error:
    li $v0, 4
    la $a0, msg_luz_err         # Imprimir " error de sensor."
    syscall

fin_programa:
    li $v0, 10                  # Syscall 10: Finalizar la ejecución del programa
    syscall


# ==============================================================================
# PROCEDIMIENTO: InicializarSensorLuz
# Descripción: Envía la orden de encendido y espera a que el hardware cambie de estado.
# ==============================================================================
InicializarSensorLuz:
    # Guardar en la pila ($sp) la dirección de retorno ($ra) porque se harán subllamadas (jal)
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    # Escribir 0x1 en el registro LuzControl para iniciar el dispositivo
    la $t0, LuzControl
    li $t1, 0x1
    sw $t1, 0($t0)

esperar_sensor_luz:
    # Bucle de consulta constante (Polling)
    la $t2, LuzEstado
    lw $t3, 0($t2)              # Leer el estado actual de la memoria

    # Si LuzEstado ya no es 0 (cambió a 1 o -1), finaliza la espera
    bne $t3, $zero, fin_espera_luz 

    # Si sigue en 0 (ocupado), llamamos a la función auxiliar para avanzar en el vector
    jal SimularAvanceHardware
    
    # Comprobar si la simulación devolvió Timeout ($v1 == -2)
    li $t4, -2
    beq $v1, $t4, fin_espera_luz  # Romper el bucle de espera si excedió el vector

    j esperar_sensor_luz        # Volver a verificar el estado

fin_espera_luz:
    # Restaurar la dirección de retorno ($ra) desde la pila y liberar espacio
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra                      # Regresar al punto de llamada original


# ==============================================================================
# PROCEDIMIENTO: SimularAvanceHardware
# Descripción: Avanza la posición en el vector de estados simular el paso del tiempo.
# Devuelve: $v1 = 0 (Normal) o $v1 = -2 (Timeout si se pasa del tamaño del vector)
# ==============================================================================
SimularAvanceHardware:
    addi $sp, $sp, -4
    sw $ra, 0($sp)              # Guardar $ra en la pila

    lw $t5, indice_estado       # Cargar el índice de estado actual
    lw $t6, tamano_secuencia    # Cargar el límite ingresado por el usuario

    addi $t5, $t5, 1            # Incrementar índice: indice = indice + 1
    sw $t5, indice_estado       # Guardar el nuevo índice actualizado

    # Si el nuevo índice alcanzó o superó el tamaño definido -> Ocurre un Timeout
    bge $t5, $t6, retorno_timeout

    # Cargar el estado del siguiente elemento del vector: secuencia_estados[indice]
    la $t7, secuencia_estados
    sll $t8, $t5, 2             # Desplazamiento en bytes = indice * 4
    add $t7, $t7, $t8           # Dirección exacta del siguiente elemento
    lw $t9, 0($t7)              # Cargar valor del estado ($t9)

    # Actualizar la variable mapeada LuzEstado con el nuevo valor extraído del vector
    la $t0, LuzEstado
    sw $t9, 0($t0)              

    # Registrar este nuevo estado en el historial para mostrarlo al final
    move $a0, $t9
    jal GuardarEnHistorial

    li $v1, 0                   # Indicar que la simulación continuó correctamente ($v1 = 0)
    lw $ra, 0($sp)              # Restaurar $ra
    addi $sp, $sp, 4
    jr $ra                      # Retornar

retorno_timeout:
    li $v1, -2                  # Indicar código de error Timeout ($v1 = -2)
    lw $ra, 0($sp)              # Restaurar $ra
    addi $sp, $sp, 4
    jr $ra                      # Retornar


# ==============================================================================
# PROCEDIMIENTO: GuardarEnHistorial
# Parámetros: $a0 = Valor del estado a insertar en el historial
# ==============================================================================
GuardarEnHistorial:
    lw $t0, conteo_historial    # Cargar la cantidad de elementos guardados hasta ahora
    la $t1, buffer_historial    # Dirección base del buffer

    sll $t2, $t0, 2             # Desplazamiento = conteo * 4 bytes
    add $t1, $t1, $t2           # Dirección de la casilla libre actual
    sw $a0, 0($t1)              # Almacenar el estado ($a0) en esa posición

    addi $t0, $t0, 1            # Incrementar el número de elementos en el historial
    sw $t0, conteo_historial    # Actualizar la variable en memoria
    jr $ra                      # Retornar a la función que lo llamó


# ==============================================================================
# PROCEDIMIENTO AUXILIAR: ImprimirHistorial
# Descripción: Recorre e imprime los valores guardados en buffer_historial
#              separándolos con comas.
# ==============================================================================
ImprimirHistorial:
    lw $t0, conteo_historial    # Cargar el total de datos a imprimir
    li $t1, 0                   # Índice del bucle i = 0
    la $t2, buffer_historial    # Dirección base del buffer

loop_imp:
    bge $t1, $t0, fin_imp       # Si i >= total_elementos, terminar impresión

    # Leer buffer_historial[i]
    sll $t3, $t1, 2             # Desplazamiento = i * 4
    add $t3, $t2, $t3           # Dirección del elemento
    lw $a0, 0($t3)              # Cargar el número
    li $v0, 1                   # Syscall 1: Imprimir entero
    syscall

    # Comprobar si es el último número de la lista para evitar imprimir una coma final sobrante
    addi $t4, $t0, -1
    beq $t1, $t4, salto_coma    # Si es el último elemento, salta la impresión de la coma

    # Imprimir la coma de separación ", "
    li $v0, 4
    la $a0, msg_separador
    syscall

salto_coma:
    addi $t1, $t1, 1            # Incrementar contador i = i + 1
    j loop_imp

fin_imp:
    jr $ra                      # Retornar al programa principal


# ==============================================================================
# PROCEDIMIENTO: LeerLuminosidad
# Descripción: Consulta el valor del registro LuzEstado para verificar si la
#              lectura fue exitosa o si finalizó en error.
# Devuelve: $v0 = Valor leído (si fue exitoso), $v1 = Estado de salida (0 éxito, -1 error)
# ==============================================================================
LeerLuminosidad:
    la $t0, LuzEstado
    lw $t1, 0($t0)              # Cargar el estado final almacenado

    li $t2, -1
    beq $t1, $t2, retorno_error_luz  # Si el estado es -1, ir a manejo de error

    li $t2, 1
    beq $t1, $t2, retorno_exito_luz  # Si el estado es 1, lectura correcta

    j retorno_error_luz         # Si terminó en cualquier otro valor diferido, reportar error

retorno_exito_luz:
    la $t3, LuzDatos
    lw $v0, 0($t3)              # Colocar en $v0 el dato de luminosidad
    li $v1, 0                   # Retornar código de éxito ($v1 = 0)
    jr $ra                  

retorno_error_luz:
    li $v0, 0                   # Dato en 0 (inválido)
    li $v1, -1                  # Retornar código de error ($v1 = -1)
    jr $ra