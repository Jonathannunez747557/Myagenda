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
AVAILABILITY_PORT=8082
BOOKING_PORT=8085
PAYMENT_PORT=8083
NOTIFICATION_PORT=8084
WALLETS_PORT=8086
METRICS_PORT=8087
DASHBOARD_PORT=8088
RESULTS_FILE="endpoints_results.log"
DOCKER_COMPOSE_FILE="$(dirname "$0")/infra/docker/docker-compose-local.yml"
PROJECT_ROOT="$(dirname "$0")"

AUTH_TOKEN=""
FAILED_TESTS=()
SELECTED_SERVICE=""
PIDS_TO_KILL=()
RUNNING_ALL=false
IDENTITY_STARTED=false
PARALLEL_STARTUP=false
PORTS_TO_KILL=($GATEWAY_PORT $IDENTITY_PORT $AVAILABILITY_PORT $BOOKING_PORT $PAYMENT_PORT $NOTIFICATION_PORT $WALLETS_PORT $METRICS_PORT $DASHBOARD_PORT)
SERVICES_TO_TEST=()
SERVICES_STARTED=()
DBS_TO_RESTART=()
AVAILABILITY_ID=""

declare -A SERVICE_DEPENDENCIES=(
    [gateway]="identity"
    [identity]=""
    [availability]="identity"
    [booking]="identity availability"
    [payment]="identity booking"
    [notification]="identity"
    [external-wallets]="identity"
    [professional-metrics]="identity booking"
    [professional-dashboard]="professional-metrics"
)

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

resolve_dependencies() {
    local service="$1"
    local -a resolved=()
    local -a to_process=("$service")
    local -a processed=()
    
    while [ ${#to_process[@]} -gt 0 ]; do
        local current="${to_process[0]}"
        to_process=("${to_process[@]:1}")
        
        if [[ " ${processed[@]} " =~ " ${current} " ]]; then
            continue
        fi
        processed+=("$current")
        
        local deps="${SERVICE_DEPENDENCIES[$current]}"
        if [ -n "$deps" ]; then
            for dep in $deps; do
                if ! [[ " ${processed[@]} " =~ " ${dep} " ]]; then
                    to_process+=("$dep")
                fi
            done
        fi
        
        resolved+=("$current")
    done
    
    echo "${resolved[@]}"
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
        echo -e "${YELLOW}  Matando proceso $pid...${NC}"
        taskkill //PID "$pid" //F 2>/dev/null || kill -9 "$pid" 2>/dev/null || true
    done

    echo -e "${CYAN}  Liberando puertos...${NC}"
    for port in "${PORTS_TO_KILL[@]}"; do
        local pids_in_port
        pids_in_port=$(netstat -ano 2>/dev/null | grep ":${port}.*LISTENING" | awk '{print $5}' | sort -u)
        
        if [ -n "$pids_in_port" ]; then
            echo -e "${YELLOW}    Puerto $port: matando procesos...${NC}"
            for p in $pids_in_port; do
                taskkill //PID "$p" //F 2>/dev/null || true
            done
            sleep 1
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

startup_all_services() {
    local services_str=""
    local wait_str=""
    
    for service in "${SERVICES_TO_TEST[@]}"; do
        case $service in
            gateway)
                if [ "$IDENTITY_STARTED" = false ]; then
                    setup_identity_once
                fi
                start_microservice "gateway-service" $GATEWAY_PORT "$PROJECT_ROOT/services/gateway-service"
                services_str="${services_str}gateway-service|$GATEWAY_PORT "
                ;;
            identity)
                setup_identity_once
                ;;
            availability)
                if [ "$IDENTITY_STARTED" = false ]; then
                    setup_identity_once
                fi
                restart_db "availability-db"
                start_microservice "availability-service" $AVAILABILITY_PORT "$PROJECT_ROOT/services/availability-service"
                services_str="${services_str}availability-service|$AVAILABILITY_PORT "
                ;;
            booking)
                if [ "$IDENTITY_STARTED" = false ]; then
                    setup_identity_once
                fi
                restart_db "booking-db"
                start_microservice "booking-service" $BOOKING_PORT "$PROJECT_ROOT/services/booking-service"
                services_str="${services_str}booking-service|$BOOKING_PORT "
                ;;
            payment)
                if [ "$IDENTITY_STARTED" = false ]; then
                    setup_identity_once
                fi
                restart_db "payment-db"
                start_microservice "payment-service" $PAYMENT_PORT "$PROJECT_ROOT/services/payment-service"
                services_str="${services_str}payment-service|$PAYMENT_PORT "
                ;;
            notification)
                if [ "$IDENTITY_STARTED" = false ]; then
                    setup_identity_once
                fi
                restart_db "notification-db"
                start_microservice "notification-service" $NOTIFICATION_PORT "$PROJECT_ROOT/services/notification-service"
                services_str="${services_str}notification-service|$NOTIFICATION_PORT "
                ;;
            external-wallets)
                if [ "$IDENTITY_STARTED" = false ]; then
                    setup_identity_once
                fi
                restart_db "wallets-db"
                start_microservice "external-wallets-service" $WALLETS_PORT "$PROJECT_ROOT/services/external-wallets-service"
                services_str="${services_str}external-wallets-service|$WALLETS_PORT "
                ;;
            professional-metrics)
                if [ "$IDENTITY_STARTED" = false ]; then
                    setup_identity_once
                fi
                restart_db "mongodb"
                start_microservice "professional-metrics-service" $METRICS_PORT "$PROJECT_ROOT/services/professional-metrics-service"
                services_str="${services_str}professional-metrics-service|$METRICS_PORT "
                ;;
            professional-dashboard)
                start_microservice "professional-dashboard-service" $DASHBOARD_PORT "$PROJECT_ROOT/services/professional-dashboard-service"
                services_str="${services_str}professional-dashboard-service|$DASHBOARD_PORT "
                ;;
        esac
    done
    
    if [ -n "$services_str" ]; then
        wait_for_microservices $services_str
    fi
}

test_identity_service() {
    print_header "🔐 IDENTITY SERVICE"
    
    if [ "$PARALLEL_STARTUP" = false ]; then
        restart_db "identity-db"
        start_microservice "identity-service" $IDENTITY_PORT "$PROJECT_ROOT/services/identity-service"
        wait_for_microservices "identity-service|$IDENTITY_PORT"
        create_test_user
        get_auth_token
    fi

    execute_curl "POST /users - Crear usuario ADMIN" \
        -X POST "${BASE_URL}:${IDENTITY_PORT}/users" \
        -H "Content-Type: application/json" \
        -d '{"username":"testuser2","password":"Test1234!","roles":["ADMIN"]}'

    execute_curl "GET /admin/test - Admin test" \
        -X GET "${BASE_URL}:${IDENTITY_PORT}/admin/test" \
        -H "Authorization: Bearer $AUTH_TOKEN"

    execute_curl "GET /actuator/health" \
        -X GET "${BASE_URL}:${IDENTITY_PORT}/actuator/health"

    print_summary "IDENTITY SERVICE"
}

test_availability_service() {
    print_header "📅 AVAILABILITY SERVICE"
    
    if [ "$PARALLEL_STARTUP" = false ]; then
        restart_db "identity-db"
        restart_db "availability-db"
        start_microservice "identity-service" $IDENTITY_PORT "$PROJECT_ROOT/services/identity-service"
        start_microservice "availability-service" $AVAILABILITY_PORT "$PROJECT_ROOT/services/availability-service"
        wait_for_microservices "identity-service|$IDENTITY_PORT" "availability-service|$AVAILABILITY_PORT"
        create_test_user
        get_auth_token
    fi

    local avail_response
    avail_response=$(curl -s -X POST "${BASE_URL}:${AVAILABILITY_PORT}/availability" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $AUTH_TOKEN" \
        -d '{"date":"2026-06-01","startTime":"09:00:00","endTime":"18:00:00","slotDurationMinutes":30}')
    
    AVAILABILITY_ID=$(echo "$avail_response" | grep -o '"id":"[^"]*' | sed 's/"id":"//' | head -1)
    
    if [ -n "$AVAILABILITY_ID" ]; then
        echo -e "${GREEN}✅ Disponibilidad creada con ID: $AVAILABILITY_ID${NC}"
    else
        echo -e "${RED}❌ Error creando disponibilidad${NC}"
    fi

    execute_curl "GET /actuator/health" \
        -X GET "${BASE_URL}:${AVAILABILITY_PORT}/actuator/health"

    print_summary "AVAILABILITY SERVICE"
}

test_booking_service() {
    print_header "📋 BOOKING SERVICE"
    
    if [ "$PARALLEL_STARTUP" = false ]; then
        restart_db "identity-db"
        restart_db "booking-db"
        start_microservice "identity-service" $IDENTITY_PORT "$PROJECT_ROOT/services/identity-service"
        start_microservice "availability-service" $AVAILABILITY_PORT "$PROJECT_ROOT/services/availability-service"
        start_microservice "booking-service" $BOOKING_PORT "$PROJECT_ROOT/services/booking-service"
        wait_for_microservices "identity-service|$IDENTITY_PORT" "availability-service|$AVAILABILITY_PORT" "booking-service|$BOOKING_PORT"
        create_test_user
        get_auth_token
    fi

    execute_curl "GET /availability - Obtener disponibilidades" \
        -X GET "${BASE_URL}:${AVAILABILITY_PORT}/availability" \
        -H "Authorization: Bearer $AUTH_TOKEN"

    if [ -n "$AVAILABILITY_ID" ]; then
        execute_curl "POST /bookings - Reservar turno" \
            -X POST "${BASE_URL}:${BOOKING_PORT}/bookings" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $AUTH_TOKEN" \
            -d "{\"availabilityId\":\"$AVAILABILITY_ID\",\"slotStart\":\"2026-06-01T09:30:00\",\"slotEnd\":\"2026-06-01T10:00:00\"}"
    else
        echo -e "${YELLOW}⚠️  No hay availabilityId para crear booking${NC}"
    fi

    execute_curl "GET /actuator/health" \
        -X GET "${BASE_URL}:${BOOKING_PORT}/actuator/health"

    print_summary "BOOKING SERVICE"
}

test_external_wallets_service() {
    print_header "💳 EXTERNAL WALLETS SERVICE"
    
    if [ "$PARALLEL_STARTUP" = false ]; then
        restart_db "identity-db"
        restart_db "wallets-db"
        start_microservice "identity-service" $IDENTITY_PORT "$PROJECT_ROOT/services/identity-service"
        start_microservice "external-wallets-service" $WALLETS_PORT "$PROJECT_ROOT/services/external-wallets-service"
        wait_for_microservices "identity-service|$IDENTITY_PORT" "external-wallets-service|$WALLETS_PORT"
        create_test_user
        get_auth_token
    fi

    execute_curl "POST /wallets - Crear wallet" \
        -X POST "${BASE_URL}:${WALLETS_PORT}/wallets" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $AUTH_TOKEN" \
        -d '{"userFullName":"Juan Perez","userEmail":"juan@example.com","userDocument":"12345678","provider":"MERCADOPAGO","apiKey":"test-key","secretKey":"test-secret"}'

    execute_curl "GET /actuator/health" \
        -X GET "${BASE_URL}:${WALLETS_PORT}/actuator/health"

    print_summary "EXTERNAL WALLETS SERVICE"
}

test_professional_metrics_service() {
    print_header "📊 PROFESSIONAL METRICS SERVICE"
    
    if [ "$PARALLEL_STARTUP" = false ]; then
        restart_db "identity-db"
        restart_db "metrics-db"
        start_microservice "identity-service" $IDENTITY_PORT "$PROJECT_ROOT/services/identity-service"
        start_microservice "professional-metrics-service" $METRICS_PORT "$PROJECT_ROOT/services/professional-metrics-service"
        wait_for_microservices "identity-service|$IDENTITY_PORT" "professional-metrics-service|$METRICS_PORT"
        create_test_user
        get_auth_token
    fi

    execute_curl "GET /metrics/{professionalId} - Obtener métricas" \
        -X GET "${BASE_URL}:${METRICS_PORT}/metrics/prof-123" \
        -H "Authorization: Bearer $AUTH_TOKEN"

    execute_curl "GET /actuator/health" \
        -X GET "${BASE_URL}:${METRICS_PORT}/actuator/health"

    print_summary "PROFESSIONAL METRICS SERVICE"
}

test_professional_dashboard_service() {
    print_header "📋 PROFESSIONAL DASHBOARD SERVICE"
    
    if [ "$PARALLEL_STARTUP" = false ]; then
        start_microservice "professional-dashboard-service" $DASHBOARD_PORT "$PROJECT_ROOT/services/professional-dashboard-service"
        wait_for_microservices "professional-dashboard-service|$DASHBOARD_PORT"
    fi

    execute_curl "POST /availability - Publicar disponibilidad" \
        -X POST "${BASE_URL}:${DASHBOARD_PORT}/availability" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $AUTH_TOKEN" \
        -d '{"date":"2026-06-01","startTime":"09:00:00","endTime":"18:00:00","slotDurationMinutes":30}'

    execute_curl "GET /actuator/health" \
        -X GET "${BASE_URL}:${DASHBOARD_PORT}/actuator/health"

    print_summary "PROFESSIONAL DASHBOARD SERVICE"
}

test_payment_service() {
    print_header "💳 PAYMENT SERVICE"
    
    if [ "$PARALLEL_STARTUP" = false ]; then
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
    PAYMENT_ID=$(echo "$payment_resp" | grep -o '"id":"[^"]*' | sed 's/"id":"//' | head -1)

    execute_curl "POST /payments/process - Procesar pago" \
        -X POST "${BASE_URL}:${PAYMENT_PORT}/payments/process" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $AUTH_TOKEN" \
        -d '{"bookingId":"booking-test-001","amount":100.00}'

    if [ -n "$PAYMENT_ID" ]; then
        execute_curl "GET /payments/$PAYMENT_ID - Obtener pago por ID" \
            -X GET "${BASE_URL}:${PAYMENT_PORT}/payments/$PAYMENT_ID" \
            -H "Authorization: Bearer $AUTH_TOKEN"
    fi

    execute_curl "GET /actuator/health" \
        -X GET "${BASE_URL}:${PAYMENT_PORT}/actuator/health"

    print_summary "PAYMENT SERVICE"
}

test_notification_service() {
    print_header "🔔 NOTIFICATION SERVICE"
    
    if [ "$PARALLEL_STARTUP" = false ]; then
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
    NOTIFICATION_ID=$(echo "$notif_resp" | grep -o '"id":"[^"]*' | sed 's/"id":"//' | head -1)

    execute_curl "POST /notifications/send - Enviar notificación" \
        -X POST "${BASE_URL}:${NOTIFICATION_PORT}/notifications/send" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $AUTH_TOKEN" \
        -d '{"message":"Tu reserva fue confirmada","type":"EMAIL"}'

    execute_curl "GET /notifications - Listar notificaciones" \
        -X GET "${BASE_URL}:${NOTIFICATION_PORT}/notifications" \
        -H "Authorization: Bearer $AUTH_TOKEN"

    if [ -n "$NOTIFICATION_ID" ]; then
        execute_curl "GET /notifications/$NOTIFICATION_ID - Obtener notificación por ID" \
            -X GET "${BASE_URL}:${NOTIFICATION_PORT}/notifications/$NOTIFICATION_ID" \
            -H "Authorization: Bearer $AUTH_TOKEN"
    fi

    execute_curl "GET /actuator/health" \
        -X GET "${BASE_URL}:${NOTIFICATION_PORT}/actuator/health"

    print_summary "NOTIFICATION SERVICE"
}

test_gateway_service() {
    print_header "🌐 GATEWAY SERVICE"
    
    if [ "$PARALLEL_STARTUP" = false ]; then
        restart_db "identity-db"
        start_microservice "identity-service" $IDENTITY_PORT "$PROJECT_ROOT/services/identity-service"
        start_microservice "gateway-service" $GATEWAY_PORT "$PROJECT_ROOT/services/gateway-service"
        wait_for_microservices "identity-service|$IDENTITY_PORT" "gateway-service|$GATEWAY_PORT"
        create_test_user
        get_auth_token
    fi

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
    echo "║  (Se levantarán automáticamente sus dependencias)             ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo "  1) Gateway Service (requiere: Identity)"
    echo "  2) Identity Service (sin dependencias)"
    echo "  3) Availability Service (requiere: Identity)"
    echo "  4) Booking Service (requiere: Identity, Availability)"
    echo "  5) Payment Service (requiere: Identity, Booking)"
    echo "  6) Notification Service (requiere: Identity)"
    echo "  7) External Wallets Service (requiere: Identity)"
    echo "  8) Professional Metrics Service (requiere: Identity, Booking)"
    echo "  9) Professional Dashboard Service (requiere: Professional Metrics)"
    echo ""
    read -rp "Selecciona (1-9): " choice
    
    case $choice in
        1) SERVICES_TO_TEST=(gateway) ;;
        2) SERVICES_TO_TEST=(identity) ;;
        3) SERVICES_TO_TEST=(availability) ;;
        4) SERVICES_TO_TEST=(booking) ;;
        5) SERVICES_TO_TEST=(payment) ;;
        6) SERVICES_TO_TEST=(notification) ;;
        7) SERVICES_TO_TEST+=(external-wallets) ;;
        8) SERVICES_TO_TEST=(professional-metrics) ;;
        9) SERVICES_TO_TEST=(professional-dashboard) ;;
        *) echo -e "${RED}Opción inválida: $choice${NC}"; exit 1 ;;
    esac
    
    local resolved_services
    resolved_services=$(resolve_dependencies "${SERVICES_TO_TEST[0]}")
    SERVICES_TO_TEST=($resolved_services)
}

main() {
    > "$RESULTS_FILE"
    check_prerequisites || { echo -e "${RED}❌ Requisitos no cumplidos${NC}"; exit 1; }
    show_menu
    
    echo -e "\n${CYAN}📦 Servicios a levantar:${NC}"
    for service in "${SERVICES_TO_TEST[@]}"; do
        echo -e "  ${GREEN}✓${NC} $service"
    done
    echo ""
    
    print_header "Iniciando pruebas"
    
    if [ ${#SERVICES_TO_TEST[@]} -gt 1 ]; then
        PARALLEL_STARTUP=true
        startup_all_services
    fi
    
    for service in "${SERVICES_TO_TEST[@]}"; do
        case $service in
            gateway)                  test_gateway_service ;;
            identity)                 test_identity_service ;;
            availability)             test_availability_service ;;
            booking)                  test_booking_service ;;
            payment)                  test_payment_service ;;
            notification)             test_notification_service ;;
            external-wallets)         test_external_wallets_service ;;
            professional-metrics)     test_professional_metrics_service ;;
            professional-dashboard)   test_professional_dashboard_service ;;
        esac
    done
    
    echo -e "\n${GREEN}📄 Log completo guardado en: $RESULTS_FILE${NC}\n"
    
    echo -e "\n${CYAN}Presioná Enter para limpiar y cerrar...${NC}"
    read -r _
    
    cleanup
}

trap cleanup EXIT INT TERM

if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi
