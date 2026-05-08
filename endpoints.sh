#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

BASE_URL="http://localhost"
GATEWAY_PORT=8080
IDENTITY_PORT=8081
CORE_PORT=8082
PAYMENT_PORT=8083
NOTIFICATION_PORT=8084
RESULTS_FILE="endpoints_results.log"
DOCKER_COMPOSE_FILE="$(dirname "$0")/infra/docker/docker-compose-local.yml"
PROJECT_ROOT="$(dirname "$0")"

AUTH_TOKEN=""
FAILED_TESTS=()
SELECTED_SERVICE=""
PIDS_TO_KILL=()
RUNNING_ALL=false
IDENTITY_STARTED=false

print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

check_prerequisites() {
    echo -e "${CYAN}🔍 Verificando requisitos...${NC}"
    
    if ! command -v mvn &> /dev/null; then
        echo -e "${RED}  ❌ Maven no está en el PATH${NC}"
        echo -e "${YELLOW}  Intenta: mvn --version${NC}"
        return 1
    fi
    echo -e "${GREEN}  ✅ Maven disponible${NC}"
    
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}  ❌ Docker no está en el PATH${NC}"
        return 1
    fi
    echo -e "${GREEN}  ✅ Docker disponible${NC}"
    
    return 0
}

restart_db() {
    local db_name="$1"
    echo -e "${CYAN}🔄 Reiniciando $db_name...${NC}"
    docker-compose -f "$DOCKER_COMPOSE_FILE" stop "$db_name" 2>/dev/null || true
    docker-compose -f "$DOCKER_COMPOSE_FILE" rm -f "$db_name" 2>/dev/null || true
    docker-compose -f "$DOCKER_COMPOSE_FILE" up -d "$db_name"
    echo -e "${GREEN}✅ $db_name reiniciada${NC}"
    echo -e "${YELLOW}⏳ Esperando 5s para que la BD levante...${NC}"
    sleep 5
}

wait_for_service() {
    local port="$1"
    local name="$2"
    local max=20
    local i=1
    echo -e "${YELLOW}⏳ Esperando que $name responda en :$port...${NC}"
    while [ $i -le $max ]; do
        local status
        status=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$port/actuator/health" 2>/dev/null)
        if [ "$status" = "200" ]; then
            echo -e "${GREEN}✅ $name está listo!${NC}"
            return 0
        fi
        sleep 3
        i=$((i + 1))
    done
    echo -e "${RED}❌ $name no respondió en el tiempo esperado. ¿Está corriendo desde IntelliJ?${NC}"
    return 1
}

execute_curl() {
    local description="$1"
    shift
    echo -e "\n${YELLOW}→ $description${NC}"

    local tmp_body
    tmp_body=$(mktemp 2>/dev/null || echo "C:\\Temp\\curl_tmp_$$.txt")

    local http_code
    http_code=$(curl -s -o "$tmp_body" -w '%{http_code}' "$@" 2>/dev/null)

    local response
    response=$(cat "$tmp_body" 2>/dev/null)
    rm -f "$tmp_body" 2>/dev/null

    if [[ "$http_code" =~ ^2 ]]; then
        echo -e "${GREEN}  HTTP $http_code ✅${NC}"
        echo "  $response" | head -3
    else
        echo -e "${RED}  HTTP $http_code ❌${NC}"
        FAILED_TESTS+=("$description → HTTP $http_code")
        if [ -z "$response" ]; then
            echo -e "${RED}  ⚠️  Sin body en la respuesta${NC}"
        else
            echo -e "${RED}  Error: $(echo "$response" | head -2)${NC}"
        fi
    fi

    {
        echo "$description"
        printf "CURL: curl"
        for arg in "$@"; do
            printf " '%s'" "$arg"
        done
        printf "\n"
        echo "HTTP Status: $http_code"
        echo "Response: $response"
        echo "---"
    } >> "$RESULTS_FILE"
}

print_summary() {
    local service_name="$1"
    echo ""
    echo -e "${BLUE}----------------------------------------${NC}"
    echo -e "${BLUE}  RESUMEN: $service_name${NC}"
    echo -e "${BLUE}----------------------------------------${NC}"
    if [ ${#FAILED_TESTS[@]} -eq 0 ]; then
        echo -e "${GREEN}  ✅ Todos los endpoints respondieron OK${NC}"
    else
        echo -e "${RED}  ❌ Endpoints fallidos:${NC}"
        for t in "${FAILED_TESTS[@]}"; do
            echo -e "${RED}    • $t${NC}"
        done
        {
            echo ""
            echo "=== FALLOS EN $service_name ==="
            for t in "${FAILED_TESTS[@]}"; do
                echo "  FAILED: $t"
            done
        } >> "$RESULTS_FILE"
    fi
    FAILED_TESTS=()
}

ensure_identity_running() {
    echo -e "${CYAN}🔐 Verificando identity-service...${NC}"
    if ! wait_for_service $IDENTITY_PORT "Identity Service"; then
        echo -e "${RED}❌ Identity-service no está disponible. Abortando.${NC}"
        cleanup
        exit 1
    fi
}

create_test_user() {
    echo -e "${CYAN}👤 Creando usuario de prueba...${NC}"

    docker exec identity-db psql -U myagenda -d identity_db -c "
    DELETE FROM user_roles WHERE user_id IN (SELECT id FROM users WHERE username = 'testadmin');
    DELETE FROM users WHERE username = 'testadmin';
    " 2>/dev/null || true

    local create_resp
    create_resp=$(curl -s -X POST "${BASE_URL}:${IDENTITY_PORT}/users" \
        -H "Content-Type: application/json" \
        -d '{"username":"testadmin","password":"Admin1234!","roles":["ADMIN"]}')

    if echo "$create_resp" | grep -q '"id"'; then
        echo -e "${GREEN}  ✅ Usuario creado${NC}"
    else
        echo -e "${YELLOW}  ⚠️  Usuario ya existe o error al crear${NC}"
    fi
}

get_auth_token() {
    echo -e "${CYAN}🔑 Obteniendo JWT...${NC}"

    local login_resp
    login_resp=$(curl -s -X POST "${BASE_URL}:${IDENTITY_PORT}/auth/login" \
        -H "Content-Type: application/json" \
        -d '{"username":"testadmin","password":"Admin1234!"}')

    AUTH_TOKEN=$(echo "$login_resp" | grep -o '"access_token":"[^"]*' | sed 's/"access_token":"//')

    if [ -n "$AUTH_TOKEN" ]; then
        echo -e "${GREEN}  ✅ Token obtenido: ${AUTH_TOKEN:0:20}...${NC}"
    else
        echo -e "${RED}  ❌ No se pudo obtener token${NC}"
        echo "  Respuesta: $login_resp"
        return 1
    fi
}

start_microservice() {
    local service_name="$1"
    local service_port="$2"
    local service_dir="$3"

    echo -e "${CYAN}🚀 Levantando $service_name en background...${NC}"

    if [ ! -d "$service_dir" ]; then
        echo -e "${RED}  ❌ Directorio no existe: $service_dir${NC}"
        return 1
    fi

    local existing_pid
    existing_pid=$(netstat -ano 2>/dev/null | grep ":${service_port}.*LISTENING" | awk '{print $5}' | head -1)
    if [ -n "$existing_pid" ] && [ "$existing_pid" != "0" ]; then
        echo -e "${YELLOW}  ⚠️  Puerto $service_port ocupado (PID $existing_pid), matando...${NC}"
        taskkill //PID "$existing_pid" //F > /dev/null 2>&1 || true
        sleep 2
    fi

    mkdir -p "C:\\Temp" 2>/dev/null || true
    cd "$service_dir" || return 1
    
    echo -e "${YELLOW}  Ejecutando: mvn spring-boot:run -Dspring-boot.run.arguments=\"--spring.profiles.active=local\"${NC}"
    mvn spring-boot:run -Dspring-boot.run.arguments="--spring.profiles.active=local" > "C:\\Temp\\$service_name.log" 2>&1 &
    local pid=$!
    PIDS_TO_KILL+=($pid)
    
    echo -e "${YELLOW}  PID: $pid${NC}"
    cd - > /dev/null || return 1
}

wait_for_microservices() {
    local -a services=("$@")
    
    for service_info in "${services[@]}"; do
        IFS='|' read -r service_name service_port <<< "$service_info"
        echo -e "${YELLOW}⏳ Esperando que $service_name responda en :$service_port...${NC}"
        wait_for_service "$service_port" "$service_name"
    done
    
    echo -e "${YELLOW}⏳ Esperando 3s para que los servicios se estabilicen...${NC}"
    sleep 3
}

cleanup() {
    echo -e "\n${CYAN}🧹 Limpiando procesos y contenedores...${NC}"

    for pid in "${PIDS_TO_KILL[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "${YELLOW}  Matando proceso $pid...${NC}"
            kill -9 "$pid" 2>/dev/null || true
        fi
    done

    echo -e "${CYAN}  Esperando a que se liberen los puertos...${NC}"
    for port in 8080 8081 8082 8083 8084; do
        local count=0
        while netstat -ano 2>/dev/null | grep -q ":${port}.*LISTENING"; do
            if [ $count -eq 0 ]; then
                echo -e "${YELLOW}    Puerto $port aún en uso, esperando...${NC}"
            fi
            sleep 1
            count=$((count + 1))
            if [ $count -gt 30 ]; then
                echo -e "${YELLOW}    ⚠️  Puerto $port no se liberó en 30s${NC}"
                break
            fi
        done
        if [ $count -gt 0 ] && [ $count -le 30 ]; then
            echo -e "${GREEN}    ✅ Puerto $port liberado${NC}"
        fi
    done

    echo -e "${CYAN}  Bajando contenedores y volúmenes...${NC}"
    docker-compose -f "$DOCKER_COMPOSE_FILE" down -v 2>/dev/null || true
    echo -e "${GREEN}✅ Limpieza completada${NC}"
}

# ==========================================
# TEST FUNCTIONS
# ==========================================

setup_identity_once() {
    if [ "$IDENTITY_STARTED" = true ]; then
        return
    fi
    
    restart_db "identity-db"
    start_microservice "identity-service" $IDENTITY_PORT "$PROJECT_ROOT/services/identity-service"
    wait_for_microservices "identity-service|$IDENTITY_PORT"
    create_test_user
    get_auth_token
    
    IDENTITY_STARTED=true
}

test_identity_service() {
    print_header "🔐 IDENTITY SERVICE"
    
    if [ "$RUNNING_ALL" = true ]; then
        setup_identity_once
    else
        restart_db "identity-db"
        start_microservice "identity-service" $IDENTITY_PORT "$PROJECT_ROOT/services/identity-service"
        wait_for_microservices "identity-service|$IDENTITY_PORT"
        create_test_user
    fi

    execute_curl "POST /users - Crear usuario ADMIN" \
        -X POST "${BASE_URL}:${IDENTITY_PORT}/users" \
        -H "Content-Type: application/json" \
        -d '{"username":"testuser2","password":"Test1234!","roles":["ADMIN"]}'

    if [ "$RUNNING_ALL" = false ]; then
        get_auth_token
    fi

    execute_curl "GET /admin/test - Admin test" \
        -X GET "${BASE_URL}:${IDENTITY_PORT}/admin/test" \
        -H "Authorization: Bearer $AUTH_TOKEN"

    execute_curl "GET /actuator/health" \
        -X GET "${BASE_URL}:${IDENTITY_PORT}/actuator/health"

    print_summary "IDENTITY SERVICE"
}

test_core_service() {
    print_header "📅 CORE SERVICE"
    
    if [ "$RUNNING_ALL" = true ]; then
        setup_identity_once
        restart_db "core-db"
        start_microservice "core-service" $CORE_PORT "$PROJECT_ROOT/services/myagenda-core-service"
        wait_for_microservices "core-service|$CORE_PORT"
    else
        restart_db "identity-db"
        restart_db "core-db"
        start_microservice "identity-service" $IDENTITY_PORT "$PROJECT_ROOT/services/identity-service"
        start_microservice "core-service" $CORE_PORT "$PROJECT_ROOT/services/myagenda-core-service"
        wait_for_microservices "identity-service|$IDENTITY_PORT" "core-service|$CORE_PORT"
        create_test_user
        get_auth_token
    fi

    local avail_resp
    avail_resp=$(curl -s -X POST "${BASE_URL}:${CORE_PORT}/availability" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $AUTH_TOKEN" \
        -d '{"startTime":"2026-06-01T10:00:00","endTime":"2026-06-01T11:00:00","capacity":5}')
    local avail_id
    avail_id=$(echo "$avail_resp" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

    execute_curl "POST /availability - Crear disponibilidad" \
        -X POST "${BASE_URL}:${CORE_PORT}/availability" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $AUTH_TOKEN" \
        -d '{"startTime":"2026-06-01T10:00:00","endTime":"2026-06-01T11:00:00","capacity":5}'

    execute_curl "GET /availability - Listar disponibilidades" \
        -X GET "${BASE_URL}:${CORE_PORT}/availability"

    execute_curl "GET /availability/$avail_id - Obtener por ID" \
        -X GET "${BASE_URL}:${CORE_PORT}/availability/$avail_id" \
        -H "Authorization: Bearer $AUTH_TOKEN"

    local booking_resp
    booking_resp=$(curl -s -X POST "${BASE_URL}:${CORE_PORT}/bookings/hold" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $AUTH_TOKEN" \
        -d "{\"availabilityId\":\"$avail_id\"}")
    local booking_id
    booking_id=$(echo "$booking_resp" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

    execute_curl "POST /bookings/hold - Crear reserva" \
        -X POST "${BASE_URL}:${CORE_PORT}/bookings/hold" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $AUTH_TOKEN" \
        -d "{\"availabilityId\":\"$avail_id\"}"

    execute_curl "POST /bookings/$booking_id/confirm - Confirmar reserva" \
        -X POST "${BASE_URL}:${CORE_PORT}/bookings/$booking_id/confirm" \
        -H "Authorization: Bearer $AUTH_TOKEN"

    execute_curl "GET /bookings - Listar reservas del usuario" \
        -X GET "${BASE_URL}:${CORE_PORT}/bookings" \
        -H "Authorization: Bearer $AUTH_TOKEN"

    execute_curl "GET /bookings/$booking_id - Obtener reserva por ID" \
        -X GET "${BASE_URL}:${CORE_PORT}/bookings/$booking_id" \
        -H "Authorization: Bearer $AUTH_TOKEN"

    execute_curl "GET /actuator/health" \
        -X GET "${BASE_URL}:${CORE_PORT}/actuator/health"

    print_summary "CORE SERVICE"
}

test_payment_service() {
    print_header "💳 PAYMENT SERVICE"
    
    if [ "$RUNNING_ALL" = true ]; then
        setup_identity_once
        restart_db "payment-db"
        start_microservice "payment-service" $PAYMENT_PORT "$PROJECT_ROOT/services/payment-service"
        wait_for_microservices "payment-service|$PAYMENT_PORT"
    else
        restart_db "identity-db"
        restart_db "payment-db"
        start_microservice "identity-service" $IDENTITY_PORT "$PROJECT_ROOT/services/identity-service"
        start_microservice "payment-service" $PAYMENT_PORT "$PROJECT_ROOT/services/payment-service"
        wait_for_microservices "identity-service|$IDENTITY_PORT" "payment-service|$PAYMENT_PORT"
        create_test_user
        get_auth_token
    fi

    local payment_resp
    payment_resp=$(curl -s -X POST "${BASE_URL}:${PAYMENT_PORT}/payments/process" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $AUTH_TOKEN" \
        -d '{"bookingId":"booking-test-001","amount":100.00}')
    local payment_id
    payment_id=$(echo "$payment_resp" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

    execute_curl "POST /payments/process - Procesar pago" \
        -X POST "${BASE_URL}:${PAYMENT_PORT}/payments/process" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $AUTH_TOKEN" \
        -d '{"bookingId":"booking-test-001","amount":100.00}'

    execute_curl "GET /payments/$payment_id - Obtener pago por ID" \
        -X GET "${BASE_URL}:${PAYMENT_PORT}/payments/$payment_id" \
        -H "Authorization: Bearer $AUTH_TOKEN"

    execute_curl "GET /actuator/health" \
        -X GET "${BASE_URL}:${PAYMENT_PORT}/actuator/health"

    print_summary "PAYMENT SERVICE"
}

test_notification_service() {
    print_header "🔔 NOTIFICATION SERVICE"
    
    if [ "$RUNNING_ALL" = true ]; then
        setup_identity_once
        restart_db "notification-db"
        start_microservice "notification-service" $NOTIFICATION_PORT "$PROJECT_ROOT/services/notification-service"
        wait_for_microservices "notification-service|$NOTIFICATION_PORT"
    else
        restart_db "identity-db"
        restart_db "notification-db"
        start_microservice "identity-service" $IDENTITY_PORT "$PROJECT_ROOT/services/identity-service"
        start_microservice "notification-service" $NOTIFICATION_PORT "$PROJECT_ROOT/services/notification-service"
        wait_for_microservices "identity-service|$IDENTITY_PORT" "notification-service|$NOTIFICATION_PORT"
        create_test_user
        get_auth_token
    fi

    local notif_resp
    notif_resp=$(curl -s -X POST "${BASE_URL}:${NOTIFICATION_PORT}/notifications/send" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $AUTH_TOKEN" \
        -d '{"message":"Tu reserva fue confirmada","type":"EMAIL"}')
    local notif_id
    notif_id=$(echo "$notif_resp" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

    execute_curl "POST /notifications/send - Enviar notificación" \
        -X POST "${BASE_URL}:${NOTIFICATION_PORT}/notifications/send" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $AUTH_TOKEN" \
        -d '{"message":"Tu reserva fue confirmada","type":"EMAIL"}'

    execute_curl "GET /notifications - Listar notificaciones" \
        -X GET "${BASE_URL}:${NOTIFICATION_PORT}/notifications" \
        -H "Authorization: Bearer $AUTH_TOKEN"

    execute_curl "GET /notifications/$notif_id - Obtener notificación por ID" \
        -X GET "${BASE_URL}:${NOTIFICATION_PORT}/notifications/$notif_id" \
        -H "Authorization: Bearer $AUTH_TOKEN"

    execute_curl "GET /actuator/health" \
        -X GET "${BASE_URL}:${NOTIFICATION_PORT}/actuator/health"

    print_summary "NOTIFICATION SERVICE"
}

test_gateway_service() {
    print_header "🌐 GATEWAY SERVICE"
    restart_db "identity-db"
    start_microservice "identity-service" $IDENTITY_PORT "$PROJECT_ROOT/services/identity-service"
    start_microservice "gateway-service" $GATEWAY_PORT "$PROJECT_ROOT/services/gateway-service"
    wait_for_microservices "identity-service|$IDENTITY_PORT" "gateway-service|$GATEWAY_PORT"

    create_test_user
    get_auth_token

    execute_curl "GET /actuator/health" \
        -X GET "${BASE_URL}:${GATEWAY_PORT}/actuator/health"

    print_summary "GATEWAY SERVICE"
}

show_menu() {
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║       MyAgenda Microservices Endpoints Test Script             ║"
    echo "║                                                                ║"
    echo "║  ¿Qué microservicio quieres testear?                          ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo "  1) Gateway Service"
    echo "  2) Identity Service"
    echo "  3) Core Service"
    echo "  4) Payment Service"
    echo "  5) Notification Service"
    echo "  6) Todos"
    echo ""
    read -rp "Selecciona: " choice
    case $choice in
        1) SELECTED_SERVICE="gateway" ;;
        2) SELECTED_SERVICE="identity" ;;
        3) SELECTED_SERVICE="core" ;;
        4) SELECTED_SERVICE="payment" ;;
        5) SELECTED_SERVICE="notification" ;;
        6) SELECTED_SERVICE="all" ;;
        *) echo "Opción inválida"; exit 1 ;;
    esac
}

main() {
    > "$RESULTS_FILE"
    check_prerequisites || { echo -e "${RED}❌ Requisitos no cumplidos${NC}"; exit 1; }
    show_menu
    print_header "Iniciando pruebas"
    
    if [ "$SELECTED_SERVICE" = "all" ]; then
        RUNNING_ALL=true
    fi
    
    case $SELECTED_SERVICE in
        gateway)      test_gateway_service ;;
        identity)     test_identity_service ;;
        core)         test_core_service ;;
        payment)      test_payment_service ;;
        notification) test_notification_service ;;
        all)
            test_gateway_service
            test_identity_service
            test_core_service
            test_payment_service
            test_notification_service
            ;;
    esac
    echo -e "\n${GREEN}📄 Log completo guardado en: $RESULTS_FILE${NC}\n"
    
    echo -e "\n${CYAN}Presioná Enter para limpiar y cerrar...${NC}"
    read -r _
    
    cleanup
}

trap cleanup EXIT INT TERM

if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi
