#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

BASE_URL="http://localhost"
GATEWAY_PORT=8080
IDENTITY_PORT=8081
CORE_PORT=8082
PAYMENT_PORT=8083
NOTIFICATION_PORT=8084

MOCK_JWT="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ0ZXN0dXNlciIsInJvbGVzIjpbInVzZXIiXSwiaWF0IjoxNjE2MjM5MDIyLCJleHAiOjk5OTk5OTk5OTl9.mock_signature"
RESULTS_FILE="endpoints_results.log"
SELECTED_SERVICE=""

print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

execute_curl() {
    local description="$1"
    shift
    echo -e "\n${YELLOW}→ $description${NC}"
    echo -e "${BLUE}CURL:${NC}"
    echo "curl $@"
    echo ""
    local response=$(curl -s "$@")
    local http_code=$(curl -s -o /dev/null -w '%{http_code}' "$@")
    echo -e "${BLUE}RESPUESTA:${NC}"
    echo "$response" | head -20
    echo ""
    echo -e "${BLUE}HTTP Status:${NC} $http_code"
    echo "---"
    {
        echo "$description"
        echo "CURL: curl $@"
        echo "HTTP Status: $http_code"
        echo "Response: $response"
        echo "---"
    } >> "$RESULTS_FILE"
}

test_identity_service() {
    print_header "IDENTITY SERVICE"
    execute_curl "POST /identity/users" -X POST "${BASE_URL}:${GATEWAY_PORT}/identity/users" -H "Content-Type: application/json" -d '{"username": "testuser", "password": "password123", "roles": ["user"]}'
    execute_curl "POST /identity/auth/login" -X POST "${BASE_URL}:${GATEWAY_PORT}/identity/auth/login" -H "Content-Type: application/json" -d '{"username": "testuser", "password": "password123"}'
    execute_curl "GET /identity/admin/test" -X GET "${BASE_URL}:${GATEWAY_PORT}/identity/admin/test" -H "Authorization: Bearer $MOCK_JWT"
    execute_curl "GET /identity/actuator/health" -X GET "${BASE_URL}:${GATEWAY_PORT}/identity/actuator/health"
}

test_core_service() {
    print_header "CORE SERVICE"
    execute_curl "POST /core/bookings/hold" -X POST "${BASE_URL}:${GATEWAY_PORT}/core/bookings/hold" -H "Content-Type: application/json" -H "Authorization: Bearer $MOCK_JWT" -d '{"availabilityId": "avail-001"}'
    execute_curl "GET /core/availability" -X GET "${BASE_URL}:${GATEWAY_PORT}/core/availability"
}

test_payment_service() {
    print_header "PAYMENT SERVICE"
    execute_curl "POST /payments/process" -X POST "${BASE_URL}:${GATEWAY_PORT}/payments/process" -H "Content-Type: application/json" -H "Authorization: Bearer $MOCK_JWT" -d '{"bookingId": "booking-001", "amount": 100.00}'
}

test_notification_service() {
    print_header "NOTIFICATION SERVICE"
    execute_curl "POST /notifications/send" -X POST "${BASE_URL}:${GATEWAY_PORT}/notifications/send" -H "Content-Type: application/json" -H "Authorization: Bearer $MOCK_JWT" -d '{"message": "Tu booking ha sido confirmado", "type": "booking_confirmed"}'
}

test_gateway_service() {
    print_header "GATEWAY SERVICE"
    execute_curl "GET /actuator/health" -X GET "${BASE_URL}:${GATEWAY_PORT}/actuator/health"
}

show_menu() {
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║       MyAgenda Microservices Endpoints Test Script             ║"
    echo "║                                                                ║"
    echo "║  ¿Qué microservicio quieres testear?                          ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    echo "Opciones:"
    echo "  1) Gateway Service"
    echo "  2) Identity Service"
    echo "  3) Core Service"
    echo "  4) Payment Service"
    echo "  5) Notification Service"
    echo "  6) Todos"
    echo ""
    read -p "Selecciona: " choice
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
    show_menu
    echo ""
    print_header "Iniciando pruebas"
    case $SELECTED_SERVICE in
        gateway) test_gateway_service ;;
        identity) test_identity_service ;;
        core) test_core_service ;;
        payment) test_payment_service ;;
        notification) test_notification_service ;;
        all) test_gateway_service; test_identity_service; test_core_service; test_payment_service; test_notification_service ;;
    esac
    print_header "TESTS COMPLETADOS"
    echo -e "${GREEN}Resultados en: $RESULTS_FILE${NC}"
}

if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi
