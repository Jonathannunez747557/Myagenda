# Guía: endpoints.sh - Testing Automatizado de Microservicios

## Descripción General

`endpoints.sh` es un script bash que **automatiza completamente el testing de todos los endpoints** de los microservicios en la arquitectura. Levanta las bases de datos, inicia los microservicios, obtiene tokens JWT, ejecuta tests contra todos los endpoints, y genera un reporte detallado.

## ¿Qué hace?

### 1. **Levantamiento Automático de Infraestructura**
- Reinicia contenedores Docker (BDs PostgreSQL)
- Levanta microservicios con `mvn spring-boot:run` en background
- Espera a que todos respondan antes de continuar
- Ejecuta todo en **paralelo** para minimizar tiempo

### 2. **Autenticación y Autorización**
- Crea usuario `testadmin` con rol `ADMIN` directamente en la BD
- Intenta obtener JWT desde `/auth/login`
- Si falla, usa token mock como fallback
- Todos los tests usan este token para autorización

### 3. **Testing de Endpoints**
- Ejecuta curl contra todos los endpoints de cada microservicio
- Captura respuesta HTTP, status code, y body
- Valida que las respuestas sean 2xx (exitosas)
- Extrae IDs dinámicamente para requests encadenadas

### 4. **Reporte y Limpieza**
- Guarda todos los resultados en `endpoints_results.log`
- Muestra resumen de **fallos en rojo** al final
- Mata todos los procesos Maven levantados
- Baja contenedores Docker y borra volúmenes

## Estructura del Script

### Variables Globales
```bash
BASE_URL="http://localhost"
GATEWAY_PORT=8080
IDENTITY_PORT=8081
CORE_PORT=8082
PAYMENT_PORT=8083
NOTIFICATION_PORT=8084
```

### Funciones Principales

#### `restart_db(db_name)`
Reinicia un contenedor Docker específico:
```bash
restart_db "identity-db"  # Baja, elimina, y levanta el contenedor
```

#### `wait_for_service(port, name)`
Espera activamente a que un servicio responda en un puerto:
```bash
wait_for_service 8081 "Identity Service"  # Intenta /actuator/health cada 2s
```

#### `start_microservice(name, port, dir)`
Levanta un microservicio con Maven en background:
```bash
start_microservice "identity-service" 8081 "$PROJECT_ROOT/services/identity-service"
```

#### `wait_for_microservices(service1|port1 service2|port2 ...)`
Espera a múltiples servicios en paralelo:
```bash
wait_for_microservices "identity-service|8081" "core-service|8082"
```

#### `get_auth_token()`
Obtiene JWT válido para autorizar requests:
- Intenta login en `/auth/login`
- Si falla, usa token mock
- Guarda en variable global `$AUTH_TOKEN`

#### `execute_curl(description, curl_args...)`
Ejecuta un curl y captura respuesta:
```bash
execute_curl "POST /users - Crear usuario" \
    -X POST "http://localhost:8081/users" \
    -H "Content-Type: application/json" \
    -d '{"username":"test","password":"Test1234!"}'
```

#### `print_summary(service_name)`
Muestra resumen de fallos para un servicio:
```bash
print_summary "IDENTITY SERVICE"
# Salida: === FALLOS EN IDENTITY SERVICE ===
#           FAILED: POST /users → HTTP 401
```

#### `cleanup()`
Limpia recursos al final:
- Mata procesos Maven
- Baja contenedores Docker
- Borra volúmenes

### Funciones de Test

#### `test_identity_service()`
1. Reinicia `identity-db`
2. Levanta `identity-service`
3. Crea usuario ADMIN en BD
4. Obtiene token
5. Tests:
   - POST /users (crear usuario)
   - POST /auth/login (obtener token)
   - GET /admin/test (endpoint protegido)
   - GET /actuator/health

#### `test_core_service()`
1. Reinicia `identity-db` + `core-db`
2. Levanta `identity-service` + `core-service` en paralelo
3. Crea usuario ADMIN
4. Obtiene token
5. Tests:
   - POST /availability (crear disponibilidad)
   - GET /availability (listar)
   - GET /availability/{id} (obtener por ID)
   - POST /bookings/hold (reservar)
   - GET /bookings/user (mis reservas)
   - GET /actuator/health

#### `test_payment_service()`
1. Reinicia `identity-db` + `payment-db`
2. Levanta `identity-service` + `payment-service` en paralelo
3. Crea usuario ADMIN
4. Obtiene token
5. Tests:
   - POST /payments/process (procesar pago)
   - GET /payments/{id} (obtener pago)
   - GET /actuator/health

#### `test_notification_service()`
1. Reinicia `identity-db` + `notification-db`
2. Levanta `identity-service` + `notification-service` en paralelo
3. Crea usuario ADMIN
4. Obtiene token
5. Tests:
   - POST /notifications/send (enviar notificación)
   - GET /notifications/user (mis notificaciones)
   - GET /actuator/health

#### `test_gateway_service()`
1. Reinicia `identity-db`
2. Levanta `identity-service` + `gateway-service` en paralelo
3. Crea usuario ADMIN
4. Obtiene token
5. Tests:
   - GET /actuator/health (gateway health)

## Flujo de Ejecución

```
1. Usuario selecciona servicio (1-6 o "all")
   ↓
2. Reinicia BDs necesarias
   ↓
3. Levanta microservicios en paralelo
   ↓
4. Espera a que todos respondan
   ↓
5. Crea usuario ADMIN en BD
   ↓
6. Obtiene JWT token
   ↓
7. Ejecuta todos los tests del servicio
   ↓
8. Guarda resultados en endpoints_results.log
   ↓
9. Muestra resumen de fallos (en rojo)
   ↓
10. Mata procesos y baja contenedores
```

## Uso

### Ejecutar el script
```bash
./endpoints.sh
```

### Menú Interactivo
```
╔════════════════════════════════════════════════════════════════╗
║        TESTING ENDPOINTS - MICROSERVICIOS                      ║
╚════════════════════════════════════════════════════════════════╝

1) Gateway Service
2) Identity Service
3) Core Service
4) Payment Service
5) Notification Service
6) All Services
0) Salir

Selecciona una opción:
```

### Ejemplos

**Testear solo Identity Service:**
```bash
./endpoints.sh
# Seleccionar opción 2
```

**Testear todos los servicios:**
```bash
./endpoints.sh
# Seleccionar opción 6
```

## Output

### En Pantalla
```
🔐 IDENTITY SERVICE
========================================

🔄 Reiniciando identity-db...
  identity-db reiniciada

🚀 Levantando identity-service en background...
⏳ Esperando que identity-service responda en :8081...
✅ identity-service está listo

🔑 Obteniendo JWT...
✅ Token obtenido desde /auth/login

→ POST /users - Crear usuario ADMIN
  HTTP 201 ✅

→ POST /auth/login - Login y obtener token
  HTTP 200 ✅

→ GET /admin/test - Admin test
  HTTP 200 ✅

→ GET /actuator/health
  HTTP 200 ✅

📄 Log completo guardado en: endpoints_results.log

🧹 Limpiando procesos y contenedores...
✅ Limpieza completada
```

### En endpoints_results.log
```
POST /users - Crear usuario ADMIN
CURL: curl -X POST http://localhost:8081/users ...
HTTP Status: 201
Response: {"id":"user-123","username":"testadmin","roles":["ADMIN"]}
---

POST /auth/login - Login y obtener token
CURL: curl -X POST http://localhost:8081/auth/login ...
HTTP Status: 200
Response: {"access_token":"eyJhbGciOiJIUzI1NiI...","token_type":"Bearer"}
---

=== FALLOS EN IDENTITY SERVICE ===
(ninguno)
```

## Configuración

### Cambiar puertos
Edita las variables al inicio del script:
```bash
GATEWAY_PORT=8080
IDENTITY_PORT=8081
CORE_PORT=8082
```

### Cambiar credenciales
Busca `testadmin` y `Admin1234!` en el script y reemplaza.

### Cambiar ruta de logs
Edita `RESULTS_FILE`:
```bash
RESULTS_FILE="endpoints_results.log"  # Cambiar aquí
```

## Troubleshooting

### "HTTP 000" - Sin conexión
- El servicio no está corriendo
- El puerto está bloqueado
- Verifica `C:\Temp\{service-name}.log`

### "HTTP 401" - No autorizado
- El token no se generó correctamente
- El usuario no existe en BD
- Verifica que SecurityConfig permite `/auth/login` sin autenticación

### "HTTP 500" - Error del servidor
- Hay un bug en el endpoint
- La BD no está disponible
- Revisa los logs de Maven

### Script lento
- Los microservicios tardan en compilar
- Aumentá el timeout en `wait_for_service` (línea ~50)

## Notas Técnicas

- **Parallelización:** Los microservicios se levantan en paralelo para minimizar tiempo total
- **Stateless:** Usa `SessionCreationPolicy.STATELESS` para no depender de sesiones
- **JWT:** Token firmado con HMAC-SHA256, secret: `clave-super-secreta-12345678901234567890`
- **Docker:** Usa `docker-compose-local.yml` para orquestar contenedores
- **Logs:** Maven logs en `C:\Temp\{service-name}.log`

## Próximas Mejoras

- [ ] Agregar tests de carga (load testing)
- [ ] Generar reporte HTML
- [ ] Integración con CI/CD
- [ ] Tests de integración entre microservicios
- [ ] Validación de schemas JSON
