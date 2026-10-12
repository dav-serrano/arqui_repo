/********************************************************************************
 * PROYECTO N° 16: Caché para Optimización de Simulación de Gráficos 3D
 * Asignatura: Arquitectura de Computadores
 * Lenguaje: C++ (Estándar C++17 recomendado, compatible con C++11 en adelante)
 *
 * DESCRIPCIÓN GENERAL
 *  Simulador de memoria caché L2/L3 enfocado en el canal de procesamiento
 *  gráfico 3D (Graphics Pipeline). Evalúa el comportamiento de la jerarquía de
 *  memoria ante diferentes arquitecturas de texturizado, recorrido de mallas 3D,
 *  políticas de escritura y mecanismos de pre-captura (prefetching).
 ********************************************************************************/

// ============================================================================
// LIBRERIAS USADAS
// ============================================================================

#include <iostream>      // Flujos de entrada y salida estándar (std::cout, std::cerr)
#include <vector>        // Contenedor dinámico de memoria contigua (std::vector)
#include <list>          // Lista doblemente enlazada para mantener el orden LRU en 
#include <unordered_map> // Tabla hash para búsqueda rápida de bloques por Tag en 
#include <cstdint>       // Definición de tipos de enteros con ancho fijo (uint64_t, uint32_t)
#include <iomanip>       // Manipulación de formato de salida (std::fixed, std::setprecision)
#include <string>        // Manejo de cadenas de texto (std::string)
#include <fstream>       // Flujos de archivos para la generación del informe CSV (std::ofstream)
#include <cmath>         // Funciones matemáticas estándar

// ============================================================================
// 1. ENUMERACIONES Y ESTRUCTURAS DE DATOS DE LA CACHÉ
// ============================================================================

/**
 * @brief Enum que define las políticas de escritura soportadas por la caché.
 */
enum class WritePolicy {
    WRITE_BACK,     // Los cambios se guardan solo en caché. Se escribe en VRAM al desalojar (Dirty Bit = true)
    WRITE_THROUGH   // Toda escritura actualiza de forma simultánea e inmediata la caché y la VRAM
};

/**
 * @brief Estructura que representa una línea o bloque dentro de la memoria caché.
 */
struct CacheBlock {
    uint64_t tag;   // Etiqueta identificadora que guarda la dirección superior de memoria
    bool dirty;     // Bit de modificación (Dirty Bit): true si el bloque cambió y no se ha escrito en VRAM

    // Constructor por defecto que inicializa el bloque en estado limpio/vacío
    CacheBlock() : tag(0), dirty(false) {}
};

// ============================================================================
// 2. CLASE PRINCIPAL: SIMULADOR DE CACHÉ DE GRÁFICOS 3D
// ============================================================================

class GraphicCache {
private:
    // Parámetros de configuración del Hardware
    size_t cacheSize;       // Capacidad total de la caché expresada en Bytes
    size_t blockSize;       // Tamaño de cada línea/bloque de datos en Bytes
    size_t associativity;   // Grado de asociatividad (Número de vías/líneas por conjunto)
    size_t numSets;         // Cantidad total de conjuntos (Sets) calculados en la memoria
    WritePolicy writePolicy;// Política de escritura activa (Write-Back o Write-Through)
    bool enablePrefetch;    // Interruptor del motor de Prefetching Secuencial (N+1)

    /**
     * @brief Estructura interna de un Conjunto (Set) dentro de la caché.
     * Utiliza una lista para mantener el orden LRU y una tabla Hash para búsquedas en tiempo constante.
     */
    struct Set {
        std::list<uint64_t> lruList; // Orden de uso: Cabeza = Most Recently Used (MRU), Cola = Least Recently Used (LRU)
        // Mapea la etiqueta (Tag) con el par: <Datos del Bloque, Iterador hacia la posición en lruList>
        std::unordered_map<uint64_t, std::pair<CacheBlock, std::list<uint64_t>::iterator>> blocks;
    };

    std::vector<Set> sets; // Vector dinámico que almacena todos los conjuntos de la caché

    // Contadores para el registro de métricas de rendimiento
    uint64_t hits;             // Conteo acumulado de aciertos en caché
    uint64_t misses;           // Conteo acumulado de fallos en caché
    uint64_t accesses;         // Conteo total de solicitudes recibidas (Lecturas + Escrituras)
    uint64_t bytesReadVRAM;    // Volumen total de Bytes leídos desde la VRAM hacia la caché
    uint64_t bytesWrittenVRAM; // Volumen total de Bytes escritos desde la caché hacia la VRAM
    uint64_t prefetchCount;    // Cantidad de bloques cargados preventivamente con éxito

    // Constantes de modelo temporal de Latencia (expresadas en Ciclos de Reloj)
    const uint64_t LATENCY_HIT = 1;     // Costo de un Acierto (1 ciclo de acceso a la caché L2/L3)
    const uint64_t LATENCY_VRAM = 100;  // Penalización por Fallo (100 ciclos por latencia de la VRAM)

    /**
     * @brief Calcula el índice del conjunto (Set) correspondiente a una dirección de memoria.
     * @param address Dirección de memoria solicitada de 64 bits.
     * @return Índice del conjunto dentro del vector 'sets'.
     */
    size_t getSetIndex(uint64_t address) const {
        // Se descartan los bits de desplazamiento interno de bloque (address / blockSize)
        // y se aplica la operación módulo sobre la cantidad de conjuntos.
        return (address / blockSize) % numSets;
    }

    /**
     * @brief Extrae la etiqueta (Tag) identificadora de una dirección de memoria.
     * @param address Dirección de memoria solicitada de 64 bits.
     * @return Valor de la etiqueta (Tag).
     */
    uint64_t getTag(uint64_t address) const {
        // Se eliminan los bits del offset de bloque y los bits asignados al índice del conjunto.
        return (address / blockSize) / numSets;
    }

    /**
     * @brief Carga un bloque de datos desde la VRAM hacia un conjunto específico de la caché.
     * Implementa la política de reemplazo LRU cuando el conjunto se encuentra lleno.
     * 
     * @param address Dirección base del bloque a cargar.
     * @param isWrite Indica si la carga fue detonada por una operación de escritura.
     */
    void loadBlock(uint64_t address, bool isWrite) {
        size_t setIdx = getSetIndex(address);
        uint64_t tag = getTag(address);
        Set& set = sets[setIdx];

        // Al traer un bloque de VRAM a la caché, se contabiliza la transferencia completa del bloque
        bytesReadVRAM += blockSize;

        // Verificar si el conjunto llegó a su capacidad máxima de vías (Asociatividad)
        if (set.blocks.size() >= associativity) {
            // El elemento candidato a expulsar es el que está al final de la lista LRU
            uint64_t lruTag = set.lruList.back();
            set.lruList.pop_back(); // Remover de la lista LRU

            // Si la política es Write-Back y el bloque saliente estaba modificado, se escribe en VRAM
            if (writePolicy == WritePolicy::WRITE_BACK && set.blocks[lruTag].first.dirty) {
                bytesWrittenVRAM += blockSize; // Transferencia de la línea completa a VRAM
            }

            // Liberar la entrada en la tabla hash
            set.blocks.erase(lruTag);
        }

        // Crear e inicializar la nueva línea de caché
        CacheBlock newBlock;
        newBlock.tag = tag;
        // Si es Write-Back y proviene de una escritura, se marca como modificado (dirty = true)
        newBlock.dirty = (writePolicy == WritePolicy::WRITE_BACK && isWrite);

        // Insertar en el frente de la lista LRU (se convierte en el Most Recently Used - MRU)
        set.lruList.push_front(tag);
        // Guardar en la tabla hash la estructura del bloque y su iterador de posición en la lista
        set.blocks[tag] = {newBlock, set.lruList.begin()};
    }

public:
    /**
     * @brief Constructor que configura los parámetros arquitectónicos del simulador.
     */
    GraphicCache(size_t totalSizeBytes, size_t blockSizeBytes, size_t ways, 
                WritePolicy policy = WritePolicy::WRITE_BACK, bool prefetch = false)
        : cacheSize(totalSizeBytes), blockSize(blockSizeBytes), associativity(ways),
        writePolicy(policy), enablePrefetch(prefetch),
        hits(0), misses(0), accesses(0), bytesReadVRAM(0), bytesWrittenVRAM(0), prefetchCount(0) {
        
        // El número de conjuntos se obtiene dividiendo el tamaño total entre (tamaño de bloque * vías)
        numSets = cacheSize / (blockSize * associativity);
        sets.resize(numSets);
    }

    /**
     * @brief Simula una solicitud de acceso a la memoria caché (Lectura o Escritura).
     * 
     * @param address Dirección de memoria a solicitar (64 bits).
     * @param isWrite 'false' para operaciones de lectura, 'true' para operaciones de escritura.
     * @return 'true' si ocurrió un Acierto (Hit), 'false' si ocurrió un Fallo (Miss).
     */
    bool access(uint64_t address, bool isWrite = false) {
        accesses++; // Incremento del contador global de solicitudes
        size_t setIdx = getSetIndex(address);
        uint64_t tag = getTag(address);
        Set& set = sets[setIdx];

        // Búsqueda del Tag dentro del conjunto
        auto it = set.blocks.find(tag);

        if (it != set.blocks.end()) {
            // -----------------------------------------------------------------
            // CASO 1: ACIERTO EN CACHÉ (HIT)
            // -----------------------------------------------------------------
            hits++;
            
            // Actualizar la política LRU: mover la etiqueta al frente (MRU)
            set.lruList.erase(it->second.second);
            set.lruList.push_front(tag);
            it->second.second = set.lruList.begin(); // Actualizar el iterador en la tabla hash

            // Manejo de la política de escritura en caso de ser una operación de escritura
            if (isWrite) {
                if (writePolicy == WritePolicy::WRITE_BACK) {
                    it->second.first.dirty = true; // Marcar el bloque como modificado en caché
                } else { // Write-Through
                    bytesWrittenVRAM += 4; // Transferencia inmediata del dato modificado (4 Bytes)
                }
            }
            return true;
        }

        // ---------------------------------------------------------------------
        // CASO 2: FALLO EN CACHÉ (MISS)
        // ---------------------------------------------------------------------
        misses++;

        // En Write-Through, si falla la escritura, también se actualiza la memoria externa
        if (isWrite && writePolicy == WritePolicy::WRITE_THROUGH) {
            bytesWrittenVRAM += 4;
        }

        // Cargar el bloque faltante desde VRAM
        loadBlock(address, isWrite);

        // ---------------------------------------------------------------------
        // MECANISMO DE PREFETCHING SECUENCIAL (STREAM PREFETCHER N+1)
        // ---------------------------------------------------------------------
        if (enablePrefetch) {
            uint64_t nextBlockAddress = address + blockSize; // Dirección del siguiente bloque adyacente
            size_t nextSetIdx = getSetIndex(nextBlockAddress);
            uint64_t nextTag = getTag(nextBlockAddress);

            // Verificar si el bloque contiguo N+1 ya existe en la caché
            if (sets[nextSetIdx].blocks.find(nextTag) == sets[nextSetIdx].blocks.end()) {
                loadBlock(nextBlockAddress, false); // Traer el bloque N+1 preventivamente
                prefetchCount++;
            }
        }

        return false;
    }

    /**
     * @brief Retorna la estimación total de ciclos de reloj consumidos.
     */
    uint64_t getTotalCycles() const {
        return (hits * LATENCY_HIT) + (misses * LATENCY_VRAM);
    }

    /**
     * @brief Calcula la tasa de aciertos (Hit Ratio) en porcentaje.
     */
    double getHitRatio() const {
        return accesses > 0 ? (static_cast<double>(hits) / accesses) * 100.0 : 0.0;
    }

    // Métodos Getters para obtener métricas clave
    uint64_t getHits() const { return hits; }
    uint64_t getMisses() const { return misses; }
    uint64_t getAccesses() const { return accesses; }
    uint64_t getBytesReadVRAM() const { return bytesReadVRAM; }
    uint64_t getBytesWrittenVRAM() const { return bytesWrittenVRAM; }

    /**
     * @brief Imprime en la consola un informe formateado con los resultados del experimento.
     * @param scenarioName Nombre descriptivo de la prueba.
     */
    void printStats(const std::string& scenarioName) const {
        double hitRatio = getHitRatio();
        double missRatio = 100.0 - hitRatio;

        std::cout << "========================================================\n";
        std::cout << " ESCENARIO: " << scenarioName << "\n";
        std::cout << "--------------------------------------------------------\n";
        std::cout << " Configuración Hardware:\n";
        std::cout << "  - Tamaño Caché   : " << cacheSize / 1024 << " KB\n";
        std::cout << "  - Tamaño Bloque  : " << blockSize << " Bytes\n";
        std::cout << "  - Asociatividad  : " << associativity << " Vía(s)\n";
        std::cout << "  - Política Esc.  : " << (writePolicy == WritePolicy::WRITE_BACK ? "Write-Back" : "Write-Through") << "\n";
        std::cout << "  - Prefetching    : " << (enablePrefetch ? "ACTIVADO (N+1)" : "DESACTIVADO") << "\n";
        std::cout << "--------------------------------------------------------\n";
        std::cout << " Métricas de Rendimiento:\n";
        std::cout << "  - Solicitudes    : " << accesses << "\n";
        std::cout << "  - Hits / Misses  : " << hits << " / " << misses << "\n";
        std::cout << std::fixed << std::setprecision(2);
        std::cout << "  - Hit Ratio      : " << hitRatio << " %\n";
        std::cout << "  - Miss Ratio     : " << missRatio << " %\n";
        std::cout << "  - Tráfico VRAM R : " << bytesReadVRAM / 1024.0 << " KB leídos\n";
        std::cout << "  - Tráfico VRAM W : " << bytesWrittenVRAM / 1024.0 << " KB escritos\n";
        std::cout << "  - Ciclos Totales : " << getTotalCycles() << " ciclos de reloj\n";
        if (enablePrefetch) {
            std::cout << "  - Prefetches     : " << prefetchCount << " bloques cargados anticipadamente\n";
        }
        std::cout << "========================================================\n\n";
    }

    /**
     * @brief Restablece todos los contadores y limpia el contenido de la caché.
     */
    void resetStats() {
        hits = 0;
        misses = 0;
        accesses = 0;
        bytesReadVRAM = 0;
        bytesWrittenVRAM = 0;
        prefetchCount = 0;
        for (auto& set : sets) {
            set.lruList.clear();
            set.blocks.clear();
        }
    }
};

// ============================================================================
// 3. MODELADO DE ALGORITMOS Y ESCENARIOS GRÁFICOS 3D
// ============================================================================

/**
 * @brief Estructura que representa las propiedades físicas de un vértice 3D.
 */
struct Vertex {
    float x, y, z;    // Posición espacial 3D (3 * 4 B = 12 Bytes)
    float nx, ny, nz; // Vector Normal para iluminación (3 * 4 B = 12 Bytes)
    float u, v;       // Coordenadas UV de texturizado (2 * 4 B = 8 Bytes)
};                    // Tamaño Total de la Estructura: 32 Bytes por Vértice

/**
 * @brief Simula la lectura de geometría indexada (Index Buffer / glDrawElements).
 * Permite evaluar la reutilización de vértices compartidos en la Caché de Vértices.
 * 
 * @param cache Referencia a la instancia del simulador de caché.
 * @param triangleCount Cantidad total de triángulos a procesar.
 */
void simulateIndexedMeshProcessing(GraphicCache& cache, size_t triangleCount) {
    uint64_t vertexBufferBase = 0x100000; // Dirección base ficticia en VRAM
    size_t vertexSize = sizeof(Vertex);   // 32 Bytes por vértice

    for (size_t t = 0; t < triangleCount; ++t) {
        // En mallas continuas, los triángulos adyacentes reutilizan vértices anteriores
        uint32_t indices[3];
        indices[0] = static_cast<uint32_t>(t * 2);
        indices[1] = static_cast<uint32_t>(t * 2 + 1);
        indices[2] = static_cast<uint32_t>(t * 2 + 2); // Vértice compartido con el siguiente triángulo

        // Consultar cada uno de los 3 vértices del triángulo en la caché
        for (int i = 0; i < 3; ++i) {
            uint64_t addr = vertexBufferBase + (indices[i] * vertexSize);
            cache.access(addr, false); // Lectura por el Vertex Shader
        }
    }
}

/**
 * @brief Simula la lectura de una textura almacenada en bloques 2D (Tiled / Tiling Layout).
 * Utilizado ampliamente en arquitecturas modernas de GPUs (NVIDIA/AMD) para mejorar la localidad espacial.
 * 
 * @param cache Referencia al simulador de caché.
 * @param width Ancho de la textura en texeles.
 * @param height Alto de la textura en texeles.
 * @param tileSize Dimensión del bloque (ej. 8 para bloques de 8x8 texeles).
 */
void simulateTextureTiled(GraphicCache& cache, size_t width, size_t height, size_t tileSize) {
    uint64_t baseAddress = 0x800000; // Dirección base de la textura
    size_t texelSizeBytes = 4;        // Formato RGBA de 32 bits (4 Bytes por texel)

    // Recorrer la textura bloque por bloque (Tile por Tile)
    for (size_t ty = 0; ty < height; ty += tileSize) {
        for (size_t tx = 0; tx < width; tx += tileSize) {
            
            // Recorrer los texeles individuales contenidos dentro del bloque actual
            for (size_t y = 0; y < tileSize; ++y) {
                for (size_t x = 0; x < tileSize; ++x) {
                    
                    // Cálculo del índice único del Tile y la posición del texel dentro del mismo
                    uint64_t tileIndex = (ty / tileSize) * (width / tileSize) + (tx / tileSize);
                    uint64_t pixelInTile = y * tileSize + x;
                    uint64_t linearIdx = tileIndex * (tileSize * tileSize) + pixelInTile;

                    uint64_t addr = baseAddress + (linearIdx * texelSizeBytes);
                    cache.access(addr, false); // Lectura por el Texture Mapping Unit (TMU)
                }
            }
        }
    }
}

/**
 * @brief Simula la lectura tradicional de una textura en orden por filas (Scanline / Row-Major).
 */
void simulateTextureScanline(GraphicCache& cache, size_t width, size_t height) {
    uint64_t baseAddress = 0x800000;
    size_t texelSizeBytes = 4;

    for (size_t y = 0; y < height; ++y) {
        for (size_t x = 0; x < width; ++x) {
            // Mapeo lineal simple: (y * ancho + x)
            uint64_t addr = baseAddress + (y * width + x) * texelSizeBytes;
            cache.access(addr, false);
        }
    }
}

/**
 * @brief Algoritmo de intercalado de bits para generar el Código de Morton (Curva Z / Z-Order Curve).
 * Mapea coordenadas 2D (x, y) a un espacio unidimensional manteniendo la localidad espacial multidimensional.
 */
uint64_t mortonEncode2D(uint32_t x, uint32_t y) {
    uint64_t answer = 0;
    for (uint32_t i = 0; i < 16; ++i) {
        // Intercala el i-ésimo bit de X y el i-ésimo bit de Y en posiciones alternas
        answer |= ((static_cast<uint64_t>(x) & (1U << i)) << i) |
                ((static_cast<uint64_t>(y) & (1U << i)) << (i + 1));
    }
    return answer;
}

/**
 * @brief Simula la lectura de una textura con organización de memoria basada en Curva de Morton (Z-Order).
 */
void simulateTextureMorton(GraphicCache& cache, size_t width, size_t height) {
    uint64_t baseAddress = 0x800000;
    size_t texelSizeBytes = 4;

    for (size_t y = 0; y < height; ++y) {
        for (size_t x = 0; x < width; ++x) {
            uint64_t mortonIdx = mortonEncode2D(static_cast<uint32_t>(x), static_cast<uint32_t>(y));
            uint64_t addr = baseAddress + (mortonIdx * texelSizeBytes);
            cache.access(addr, false);
        }
    }
}

/**
 * @brief Simula la escritura de fotogramas en el Búfer de Color y Profundidad (Framebuffer / Render Target).
 */
void simulateFramebufferWriting(GraphicCache& cache, size_t width, size_t height) {
    uint64_t baseAddress = 0xC00000; // Dirección base del Framebuffer
    size_t pixelSize = 4;             // 32 bits por píxel (RGBA)

    for (size_t y = 0; y < height; ++y) {
        for (size_t x = 0; x < width; ++x) {
            uint64_t addr = baseAddress + (y * width + x) * pixelSize;
            cache.access(addr, true); // Operación de ESCRITURA por el Raster Operations Pipeline (ROP)
        }
    }
}

// ============================================================================
// 4. EXPORTADOR AUTOMÁTICO DE RESULTADOS A FORMATO CSV
// ============================================================================

/**
 * @brief Guarda en un archivo .csv los datos consolidados de la batería de pruebas.
 * Permite importar la información directamente en Python (Matplotlib) o Excel para generar gráficos.
 */
void exportResultsToCSV(const std::string& filename, 
                        const std::vector<std::pair<std::string, GraphicCache>>& experiments) {
    std::ofstream file(filename);
    if (!file.is_open()) {
        std::cerr << "Error crítico: No se pudo crear el archivo CSV '" << filename << "'\n";
        return;
    }

    // Cabecera estructurada del CSV
    file << "Escenario,Accesos,Hits,Misses,HitRatio_Porcentaje,BytesRead_VRAM,BytesWritten_VRAM,CiclosTotales\n";

    // Escribir fila por fila con formato numérico
    for (const auto& exp : experiments) {
        const std::string& name = exp.first;
        const GraphicCache& c = exp.second;

        file << "\"" << name << "\","
            << c.getAccesses() << ","
            << c.getHits() << ","
            << c.getMisses() << ","
            << std::fixed << std::setprecision(2) << c.getHitRatio() << ","
            << c.getBytesReadVRAM() << ","
            << c.getBytesWrittenVRAM() << ","
            << c.getTotalCycles() << "\n";
    }

    file.close();
    std::cout << ">>> Se ha generado el archivo '" << filename << "' con los datos formateados. <<<\n\n";
}

// ============================================================================
// 5. PROGRAMA PRINCIPAL (MAIN) Y BATERÍA DE EXPERIMENTOS
// ============================================================================

int main() {
    std::cout << "========================================================\n";
    std::cout << " SIMULADOR AVANZADO DE CACHÉ EN GRÁFICOS 3D (PROYECTO N16)\n";
    std::cout << "========================================================\n\n";

    // Vector para acumular los resultados de cada prueba y posteriormente exportarlos
    std::vector<std::pair<std::string, GraphicCache>> experimentLog;

    // Configuración base del hardware a simular
    size_t cacheSize = 32 * 1024; // Caché L2/L3 de 32 KB
    size_t blockSize = 64;        // Tamaño de bloque estándar de 64 Bytes
    size_t defaultWays = 4;       // Asociatividad de 4 vías (4-Way Set Associative)

    // ------------------------------------------------------------------------
    // EXPERIMENTO 1: Procesamiento de Geometría con Búfer de Índices
    // ------------------------------------------------------------------------
    GraphicCache cache1(cacheSize, blockSize, defaultWays);
    simulateIndexedMeshProcessing(cache1, 15000); // Malla 3D con 15,000 triángulos
    cache1.printStats("1. Renderizado de Malla 3D Indexada (Index Buffer)");
    experimentLog.push_back({"1. Malla 3D Indexada", cache1});

    // ------------------------------------------------------------------------
    // EXPERIMENTO 2: Comparativa de Disposición de Texturas 2D (512x512)
    // ------------------------------------------------------------------------
    GraphicCache cacheScanline(cacheSize, blockSize, defaultWays);
    simulateTextureScanline(cacheScanline, 512, 512);
    cacheScanline.printStats("2A. Textura 2D - Orden Scanline");
    experimentLog.push_back({"2A. Textura Scanline", cacheScanline});

    GraphicCache cacheTiled(cacheSize, blockSize, defaultWays);
    simulateTextureTiled(cacheTiled, 512, 512, 8); // Organización en bloques/tiles de 8x8
    cacheTiled.printStats("2B. Textura 2D - Disposición Tiled (8x8)");
    experimentLog.push_back({"2B. Textura Tiled 8x8", cacheTiled});

    GraphicCache cacheMorton(cacheSize, blockSize, defaultWays);
    simulateTextureMorton(cacheMorton, 512, 512);
    cacheMorton.printStats("2C. Textura 2D - Curva Z (Morton Code)");
    experimentLog.push_back({"2C. Textura Morton Z-Order", cacheMorton});

    // ------------------------------------------------------------------------
    // EXPERIMENTO 3: Evaluación de la Técnica de Prefetching Secuencial (N+1)
    // ------------------------------------------------------------------------
    GraphicCache cacheNoPrefetch(cacheSize, blockSize, defaultWays, WritePolicy::WRITE_BACK, false);
    simulateTextureScanline(cacheNoPrefetch, 512, 512);
    
    GraphicCache cacheWithPrefetch(cacheSize, blockSize, defaultWays, WritePolicy::WRITE_BACK, true);
    simulateTextureScanline(cacheWithPrefetch, 512, 512);

    cacheNoPrefetch.printStats("3A. Textura Scanline (Sin Prefetch)");
    cacheWithPrefetch.printStats("3B. Textura Scanline (Con Prefetch Secuencial N+1)");
    experimentLog.push_back({"3A. Scanline Sin Prefetch", cacheNoPrefetch});
    experimentLog.push_back({"3B. Scanline Con Prefetch", cacheWithPrefetch});

    // ------------------------------------------------------------------------
    // EXPERIMENTO 4: Comparativa de Políticas de Escritura en Framebuffer
    // ------------------------------------------------------------------------
    GraphicCache cacheWriteBack(cacheSize, blockSize, defaultWays, WritePolicy::WRITE_BACK);
    simulateFramebufferWriting(cacheWriteBack, 256, 256);

    GraphicCache cacheWriteThrough(cacheSize, blockSize, defaultWays, WritePolicy::WRITE_THROUGH);
    simulateFramebufferWriting(cacheWriteThrough, 256, 256);

    cacheWriteBack.printStats("4A. Escritura en Framebuffer (Write-Back)");
    cacheWriteThrough.printStats("4B. Escritura en Framebuffer (Write-Through)");
    experimentLog.push_back({"4A. Framebuffer Write-Back", cacheWriteBack});
    experimentLog.push_back({"4B. Framebuffer Write-Through", cacheWriteThrough});

    // ------------------------------------------------------------------------
    // EXPORTACIÓN FINAL A CSV
    // ------------------------------------------------------------------------
    exportResultsToCSV("resultados_simulacion.csv", experimentLog);

    return 0;
}