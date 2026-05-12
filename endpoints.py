#!/usr/bin/env python3
"""
MyAgenda Microservices Endpoints Testing Tool
Multiplataforma (Windows, Linux, macOS)
"""

import os
import sys
import json
import subprocess
import time
import requests
import threading
import signal
from pathlib import Path
from typing import List, Dict, Optional
from datetime import datetime

# Colors for terminal output
class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    CYAN = '\033[0;36m'
    NC = '\033[0m'

# Configuration
BASE_URL = "http://localhost"
PORTS = {
    "gateway": 8080,
    "identity": 8081,
    "availability": 8082,
    "booking": 8085,
    "payment": 8083,
    "notification": 8084,
    "external-wallets": 8086,
    "professional-metrics": 8087,
    "professional-dashboard": 8088,
}

DBS = {
    "identity": "identity-db",
    "availability": "availability-db",
    "booking": "booking-db",
    "payment": "payment-db",
    "notification": "notification-db",
    "external-wallets": "wallets-db",
    "professional-metrics": "mongodb",
}

SERVICE_DIRS = {
    "gateway": "services/gateway-service",
    "identity": "services/identity-service",
    "availability": "services/availability-service",
    "booking": "services/booking-service",
    "payment": "services/payment-service",
    "notification": "services/notification-service",
    "external-wallets": "services/external-wallets-service",
    "professional-metrics": "services/professional-metrics-service",
    "professional-dashboard": "services/professional-dashboard-service",
}

SERVICE_DEPENDENCIES = {
    "gateway": ["identity"],
    "identity": [],
    "availability": ["identity"],
    "booking": ["identity", "availability"],
    "payment": ["identity", "booking"],
    "notification": ["identity"],
    "external-wallets": ["identity"],
    "professional-metrics": ["identity", "booking"],
    "professional-dashboard": ["professional-metrics"],
}

RESULTS_FILE = "endpoints_results.log"
PROJECT_ROOT = Path(__file__).parent

# Global state
auth_token = None
failed_tests = []
running_processes = []
lock = threading.Lock()
MVN_CMD = None
availability_id = None


def find_mvn() -> Optional[str]:
    """Find Maven executable in PATH or common locations"""
    # Try standard PATH first
    try:
        subprocess.run(["mvn", "--version"], capture_output=True, check=True)
        return "mvn"
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass
    
    # Try common Windows locations
    if sys.platform == "win32":
        common_paths = [
            Path.home() / "AppData" / "Local" / "Programs" / "Maven" / "bin" / "mvn.cmd",
            Path("C:/Program Files/Maven/bin/mvn.cmd"),
            Path("C:/Program Files (x86)/Maven/bin/mvn.cmd"),
            Path.home() / ".m2" / "bin" / "mvn.cmd",
        ]
        
        for path in common_paths:
            if path.exists():
                return str(path)
        
        # Try PowerShell Get-Command
        try:
            result = subprocess.run(
                ["powershell", "-Command", "Get-Command mvn | Select-Object -ExpandProperty Source"],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0 and result.stdout.strip():
                mvn_path = result.stdout.strip()
                if Path(mvn_path).exists():
                    return mvn_path
        except Exception:
            pass
    
    return None


def print_header(text: str):
    """Print a formatted header"""
    print(f"\n{Colors.BLUE}========================================{Colors.NC}")
    print(f"{Colors.BLUE}  {text}{Colors.NC}")
    print(f"{Colors.BLUE}========================================{Colors.NC}\n")


def print_success(text: str):
    """Print success message"""
    print(f"{Colors.GREEN}✅ {text}{Colors.NC}")


def print_error(text: str):
    """Print error message"""
    print(f"{Colors.RED}❌ {text}{Colors.NC}")


def print_warning(text: str):
    """Print warning message"""
    print(f"{Colors.YELLOW}⚠️  {text}{Colors.NC}")


def print_info(text: str):
    """Print info message"""
    print(f"{Colors.CYAN}{text}{Colors.NC}")


def check_prerequisites() -> bool:
    """Check if Maven and Docker are available"""
    global MVN_CMD
    
    print_info("🔍 Verificando requisitos...")
    
    MVN_CMD = find_mvn()
    if not MVN_CMD:
        print_error("Maven no está en el PATH ni en ubicaciones comunes")
        return False
    
    print_success("Maven disponible")
    
    try:
        subprocess.run(["docker", "--version"], capture_output=True, check=True)
        print_success("Docker disponible")
    except (subprocess.CalledProcessError, FileNotFoundError):
        print_error("Docker no está en el PATH")
        return False
    
    return True


def run_command(cmd: List[str], cwd: Optional[Path] = None, capture: bool = False) -> Optional[str]:
    """Run a shell command"""
    try:
        if capture:
            result = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=30)
            return result.stdout + result.stderr
        else:
            subprocess.run(cmd, cwd=cwd, check=False)
            return None
    except Exception as e:
        print_error(f"Error ejecutando comando: {e}")
        return None


def restart_db(db_name: str):
    """Restart a Docker database container"""
    print_info(f"🔄 Reiniciando {db_name}...")
    
    docker_compose_file = PROJECT_ROOT / "infra" / "docker" / "docker-compose-local.yml"
    
    run_command(["docker-compose", "-f", str(docker_compose_file), "stop", db_name])
    run_command(["docker-compose", "-f", str(docker_compose_file), "rm", "-f", db_name])
    run_command(["docker-compose", "-f", str(docker_compose_file), "up", "-d", db_name])
    
    print_success(f"{db_name} reiniciada")
    print_info("⏳ Esperando 5s para que la BD levante...")
    time.sleep(5)


def wait_for_service(port: int, name: str, max_attempts: int = 20) -> bool:
    """Wait for a service to be ready"""
    print_info(f"⏳ Esperando que {name} responda en :{port}...")
    
    for attempt in range(max_attempts):
        try:
            response = requests.get(f"http://localhost:{port}/actuator/health", timeout=5)
            if response.status_code == 200:
                print_success(f"{name} está listo")
                return True
        except requests.RequestException:
            pass
        
        time.sleep(3)
    
    print_error(f"{name} no respondió en el tiempo esperado")
    return False


def start_microservice(service_name: str, port: int, service_dir: Path) -> Optional[int]:
    """Start a microservice in background"""
    print_info(f"🚀 Levantando {service_name} en background...")
    
    if not service_dir.exists():
        print_error(f"Directorio no existe: {service_dir}")
        return None
    
    # Kill any existing process on this port
    kill_port_process(port)
    
    # Start Maven process
    cmd = [
        MVN_CMD,
        "spring-boot:run",
        "-Dspring-boot.run.arguments=--spring.profiles.active=local"
    ]
    
    try:
        process = subprocess.Popen(
            cmd,
            cwd=service_dir,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            preexec_fn=os.setsid if hasattr(os, 'setsid') else None
        )
        
        with lock:
            running_processes.append(process.pid)
        
        print_info(f"  PID: {process.pid}")
        return process.pid
    except Exception as e:
        print_error(f"Error iniciando {service_name}: {e}")
        return None


def kill_port_process(port: int):
    """Kill process using a specific port"""
    try:
        if sys.platform == "win32":
            # Windows
            result = subprocess.run(
                ["netstat", "-ano"],
                capture_output=True,
                text=True
            )
            for line in result.stdout.split('\n'):
                if f":{port}" in line and "LISTENING" in line:
                    pid = line.split()[-1]
                    subprocess.run(["taskkill", "/PID", pid, "/F"], capture_output=True)
                    print_warning(f"Puerto {port} ocupado (PID {pid}), matando...")
                    time.sleep(1)
        else:
            # Linux/macOS
            result = subprocess.run(
                ["lsof", "-i", f":{port}"],
                capture_output=True,
                text=True
            )
            for line in result.stdout.split('\n')[1:]:
                if line.strip():
                    pid = line.split()[1]
                    os.kill(int(pid), signal.SIGKILL)
                    print_warning(f"Puerto {port} ocupado (PID {pid}), matando...")
                    time.sleep(1)
    except Exception:
        pass


def wait_for_services(services: Dict[str, int]):
    """Wait for multiple services in parallel"""
    threads = []
    
    for service_name, port in services.items():
        thread = threading.Thread(target=wait_for_service, args=(port, service_name))
        thread.start()
        threads.append(thread)
    
    for thread in threads:
        thread.join()
    
    print_info("⏳ Esperando 3s para que los servicios se estabilicen...")
    time.sleep(3)


def create_test_user():
    """Create test admin user"""
    print_info("👤 Creando usuario de prueba...")
    
    # Clean up existing user
    try:
        subprocess.run([
            "docker", "exec", "identity-db",
            "psql", "-U", "myagenda", "-d", "identity_db", "-c",
            "DELETE FROM user_roles WHERE user_id IN (SELECT id FROM users WHERE username = 'testadmin'); DELETE FROM users WHERE username = 'testadmin';"
        ], capture_output=True)
    except Exception:
        pass
    
    # Create user via API
    try:
        response = requests.post(
            f"{BASE_URL}:{PORTS['identity']}/users",
            json={"username": "testadmin", "password": "Admin1234!", "roles": ["ADMIN"]},
            timeout=10
        )
        
        if response.status_code == 200:
            print_success("Usuario creado")
        else:
            print_warning("Usuario ya existe o error al crear")
    except Exception as e:
        print_error(f"Error creando usuario: {e}")


def get_auth_token() -> Optional[str]:
    """Get JWT token from login"""
    global auth_token
    
    print_info("🔑 Obteniendo JWT...")
    
    try:
        response = requests.post(
            f"{BASE_URL}:{PORTS['identity']}/auth/login",
            json={"username": "testadmin", "password": "Admin1234!"},
            timeout=10
        )
        
        if response.status_code == 200:
            data = response.json()
            auth_token = data.get("access_token")
            if auth_token:
                print_success(f"Token obtenido: {auth_token[:20]}...")
                return auth_token
        
        print_error("No se pudo obtener token")
        print(f"  Respuesta: {response.text}")
        return None
    except Exception as e:
        print_error(f"Error obteniendo token: {e}")
        return None


def execute_curl(description: str, method: str, url: str, headers: Optional[Dict] = None, json_data: Optional[Dict] = None):
    """Execute HTTP request and log results"""
    global failed_tests
    
    print(f"\n{Colors.YELLOW}→ {description}{Colors.NC}")
    
    try:
        if method == "GET":
            response = requests.get(url, headers=headers, timeout=10)
        elif method == "POST":
            response = requests.post(url, json=json_data, headers=headers, timeout=10)
        else:
            print_error(f"Método HTTP no soportado: {method}")
            return
        
        status_code = response.status_code
        
        if 200 <= status_code < 300:
            print(f"{Colors.GREEN}  HTTP {status_code} ✅{Colors.NC}")
            try:
                resp_json = response.json()
                print(f"  {json.dumps(resp_json)[:100]}...")
            except:
                print(f"  {response.text[:100]}...")
        else:
            print(f"{Colors.RED}  HTTP {status_code} ❌{Colors.NC}")
            failed_tests.append(f"{description} → HTTP {status_code}")
            if response.text:
                print(f"{Colors.RED}  Error: {response.text[:100]}{Colors.NC}")
            else:
                print(f"{Colors.RED}  ⚠️  Sin body en la respuesta{Colors.NC}")
        
        # Log to file
        with open(RESULTS_FILE, "a") as f:
            f.write(f"\n{description}\n")
            f.write(f"METHOD: {method}\n")
            f.write(f"URL: {url}\n")
            f.write(f"HTTP Status: {status_code}\n")
            f.write(f"Response: {response.text}\n")
            f.write("---\n")
    
    except Exception as e:
        print_error(f"Error ejecutando request: {e}")
        failed_tests.append(f"{description} → Error: {e}")


def resolve_dependencies(service: str) -> List[str]:
    """Resolve service dependencies recursively"""
    resolved = []
    to_process = [service]
    processed = set()
    
    while to_process:
        current = to_process.pop(0)
        
        if current in processed:
            continue
        
        processed.add(current)
        
        deps = SERVICE_DEPENDENCIES.get(current, [])
        for dep in deps:
            if dep not in processed:
                to_process.append(dep)
        
        resolved.append(current)
    
    return resolved


def print_summary(service_name: str):
    """Print test summary"""
    global failed_tests
    
    print(f"\n{Colors.BLUE}----------------------------------------{Colors.NC}")
    print(f"{Colors.BLUE}  RESUMEN: {service_name}{Colors.NC}")
    print(f"{Colors.BLUE}----------------------------------------{Colors.NC}")
    
    if not failed_tests:
        print_success("Todos los endpoints respondieron OK")
    else:
        print_error(f"Endpoints fallidos:")
        for test in failed_tests:
            print(f"{Colors.RED}    • {test}{Colors.NC}")
        
        with open(RESULTS_FILE, "a") as f:
            f.write(f"\n=== FALLOS EN {service_name} ===\n")
            for test in failed_tests:
                f.write(f"  FAILED: {test}\n")
    
    failed_tests = []


def test_identity_service():
    """Test Identity Service"""
    print_header("🔐 IDENTITY SERVICE")
    
    restart_db("identity-db")
    start_microservice("identity-service", PORTS["identity"], PROJECT_ROOT / SERVICE_DIRS["identity"])
    wait_for_service(PORTS["identity"], "identity-service")
    create_test_user()
    get_auth_token()
    
    headers = {"Authorization": f"Bearer {auth_token}"} if auth_token else {}
    
    execute_curl(
        "POST /users - Crear usuario ADMIN",
        "POST",
        f"{BASE_URL}:{PORTS['identity']}/users",
        headers={"Content-Type": "application/json"},
        json_data={"username": "testuser2", "password": "Test1234!", "roles": ["ADMIN"]}
    )
    
    execute_curl(
        "GET /admin/test - Admin test",
        "GET",
        f"{BASE_URL}:{PORTS['identity']}/admin/test",
        headers=headers
    )
    
    execute_curl(
        "GET /actuator/health",
        "GET",
        f"{BASE_URL}:{PORTS['identity']}/actuator/health"
    )
    
    print_summary("IDENTITY SERVICE")


def test_availability_service():
    """Test Availability Service"""
    global availability_id
    
    print_header("📅 AVAILABILITY SERVICE")
    
    restart_db("availability-db")
    start_microservice("availability-service", PORTS["availability"], PROJECT_ROOT / SERVICE_DIRS["availability"])
    wait_for_service(PORTS["availability"], "availability-service")
    
    headers = {"Authorization": f"Bearer {auth_token}"} if auth_token else {}
    
    try:
        response = requests.post(
            f"{BASE_URL}:{PORTS['availability']}/availability",
            json={"date": "2026-06-01", "startTime": "09:00:00", "endTime": "18:00:00", "slotDurationMinutes": 30},
            headers={**headers, "Content-Type": "application/json"},
            timeout=10
        )
        
        if response.status_code == 200:
            data = response.json()
            availability_id = data.get("id")
            print_success(f"Disponibilidad creada con ID: {availability_id}")
        else:
            print_error(f"Error creando disponibilidad: HTTP {response.status_code}")
    except Exception as e:
        print_error(f"Error: {e}")
    
    execute_curl(
        "GET /actuator/health",
        "GET",
        f"{BASE_URL}:{PORTS['availability']}/actuator/health"
    )
    
    print_summary("AVAILABILITY SERVICE")


def test_booking_service():
    """Test Booking Service"""
    print_header("📋 BOOKING SERVICE")
    
    restart_db("booking-db")
    start_microservice("availability-service", PORTS["availability"], PROJECT_ROOT / SERVICE_DIRS["availability"])
    start_microservice("booking-service", PORTS["booking"], PROJECT_ROOT / SERVICE_DIRS["booking"])
    wait_for_service(PORTS["booking"], "booking-service")
    
    headers = {"Authorization": f"Bearer {auth_token}"} if auth_token else {}
    
    execute_curl(
        "GET /availability - Obtener disponibilidades",
        "GET",
        f"{BASE_URL}:{PORTS['availability']}/availability",
        headers=headers
    )
    
    if availability_id:
        execute_curl(
            "POST /bookings - Reservar turno",
            "POST",
            f"{BASE_URL}:{PORTS['booking']}/bookings",
            headers={**headers, "Content-Type": "application/json"},
            json_data={"availabilityId": availability_id, "slotStart": "2026-06-01T09:30:00", "slotEnd": "2026-06-01T10:00:00"}
        )
    else:
        print_warning("No hay availabilityId disponible para crear booking")
    
    execute_curl(
        "GET /actuator/health",
        "GET",
        f"{BASE_URL}:{PORTS['booking']}/actuator/health"
    )
    
    print_summary("BOOKING SERVICE")


def test_external_wallets_service():
    """Test External Wallets Service"""
    print_header("💳 EXTERNAL WALLETS SERVICE")
    
    restart_db("wallets-db")
    start_microservice("external-wallets-service", PORTS["external-wallets"], PROJECT_ROOT / SERVICE_DIRS["external-wallets"])
    wait_for_service(PORTS["external-wallets"], "external-wallets-service")
    
    headers = {"Authorization": f"Bearer {auth_token}"} if auth_token else {}
    
    execute_curl(
        "POST /wallets - Crear wallet",
        "POST",
        f"{BASE_URL}:{PORTS['external-wallets']}/wallets",
        headers={**headers, "Content-Type": "application/json"},
        json_data={"userFullName": "Juan Perez", "userEmail": "juan@example.com", "userDocument": "12345678", "provider": "MERCADOPAGO", "apiKey": "test-key", "secretKey": "test-secret"}
    )
    
    execute_curl(
        "GET /actuator/health",
        "GET",
        f"{BASE_URL}:{PORTS['external-wallets']}/actuator/health"
    )
    
    print_summary("EXTERNAL WALLETS SERVICE")


def test_professional_metrics_service():
    """Test Professional Metrics Service"""
    print_header("📊 PROFESSIONAL METRICS SERVICE")
    
    restart_db("metrics-db")
    start_microservice("professional-metrics-service", PORTS["professional-metrics"], PROJECT_ROOT / SERVICE_DIRS["professional-metrics"])
    wait_for_service(PORTS["professional-metrics"], "professional-metrics-service")
    
    headers = {"Authorization": f"Bearer {auth_token}"} if auth_token else {}
    
    execute_curl(
        "GET /metrics/{professionalId} - Obtener métricas",
        "GET",
        f"{BASE_URL}:{PORTS['professional-metrics']}/metrics/prof-123",
        headers=headers
    )
    
    execute_curl(
        "GET /actuator/health",
        "GET",
        f"{BASE_URL}:{PORTS['professional-metrics']}/actuator/health"
    )
    
    print_summary("PROFESSIONAL METRICS SERVICE")


def test_professional_dashboard_service():
    """Test Professional Dashboard Service"""
    print_header("📋 PROFESSIONAL DASHBOARD SERVICE")
    
    start_microservice("professional-dashboard-service", PORTS["professional-dashboard"], PROJECT_ROOT / SERVICE_DIRS["professional-dashboard"])
    wait_for_service(PORTS["professional-dashboard"], "professional-dashboard-service")
    
    headers = {"Authorization": f"Bearer {auth_token}"} if auth_token else {}
    
    execute_curl(
        "POST /availability - Publicar disponibilidad",
        "POST",
        f"{BASE_URL}:{PORTS['professional-dashboard']}/availability",
        headers={**headers, "Content-Type": "application/json"},
        json_data={"date": "2026-06-01", "startTime": "09:00:00", "endTime": "18:00:00", "slotDurationMinutes": 30}
    )
    
    execute_curl(
        "GET /actuator/health",
        "GET",
        f"{BASE_URL}:{PORTS['professional-dashboard']}/actuator/health"
    )
    
    print_summary("PROFESSIONAL DASHBOARD SERVICE")


def test_payment_service():
    """Test Payment Service"""
    print_header("💳 PAYMENT SERVICE")
    
    restart_db("payment-db")
    start_microservice("payment-service", PORTS["payment"], PROJECT_ROOT / SERVICE_DIRS["payment"])
    wait_for_service(PORTS["payment"], "payment-service")
    
    headers = {"Authorization": f"Bearer {auth_token}"} if auth_token else {}
    
    execute_curl(
        "POST /payments/process - Procesar pago",
        "POST",
        f"{BASE_URL}:{PORTS['payment']}/payments/process",
        headers={**headers, "Content-Type": "application/json"},
        json_data={"bookingId": "booking-test-001", "amount": 100.00}
    )
    
    execute_curl(
        "GET /actuator/health",
        "GET",
        f"{BASE_URL}:{PORTS['payment']}/actuator/health"
    )
    
    print_summary("PAYMENT SERVICE")


def test_notification_service():
    """Test Notification Service"""
    print_header("🔔 NOTIFICATION SERVICE")
    
    restart_db("notification-db")
    start_microservice("notification-service", PORTS["notification"], PROJECT_ROOT / SERVICE_DIRS["notification"])
    wait_for_service(PORTS["notification"], "notification-service")
    
    headers = {"Authorization": f"Bearer {auth_token}"} if auth_token else {}
    
    execute_curl(
        "POST /notifications/send - Enviar notificación",
        "POST",
        f"{BASE_URL}:{PORTS['notification']}/notifications/send",
        headers={**headers, "Content-Type": "application/json"},
        json_data={"message": "Tu reserva fue confirmada", "type": "EMAIL"}
    )
    
    execute_curl(
        "GET /notifications - Listar notificaciones",
        "GET",
        f"{BASE_URL}:{PORTS['notification']}/notifications",
        headers=headers
    )
    
    execute_curl(
        "GET /actuator/health",
        "GET",
        f"{BASE_URL}:{PORTS['notification']}/actuator/health"
    )
    
    print_summary("NOTIFICATION SERVICE")


def test_gateway_service():
    """Test Gateway Service"""
    print_header("🌐 GATEWAY SERVICE")
    
    start_microservice("gateway-service", PORTS["gateway"], PROJECT_ROOT / SERVICE_DIRS["gateway"])
    wait_for_service(PORTS["gateway"], "gateway-service")
    
    execute_curl(
        "GET /actuator/health",
        "GET",
        f"{BASE_URL}:{PORTS['gateway']}/actuator/health"
    )
    
    print_summary("GATEWAY SERVICE")


def cleanup():
    """Kill all running processes and cleanup"""
    print_info("\n🧹 Limpiando procesos y contenedores...")
    
    # Kill all processes
    for pid in running_processes:
        try:
            if sys.platform == "win32":
                subprocess.run(["taskkill", "/PID", str(pid), "/F"], capture_output=True)
            else:
                os.killpg(os.getpgid(pid), signal.SIGKILL)
        except Exception:
            pass
    
    # Kill processes on ports
    for port in PORTS.values():
        kill_port_process(port)
    
    # Stop Docker containers
    print_info("  Bajando contenedores y volúmenes...")
    docker_compose_file = PROJECT_ROOT / "infra" / "docker" / "docker-compose-local.yml"
    subprocess.run(
        ["docker-compose", "-f", str(docker_compose_file), "down", "-v"],
        capture_output=True
    )
    
    print_success("Limpieza completada")


def show_menu() -> List[str]:
    """Show service selection menu"""
    print(f"{Colors.BLUE}")
    print("╔════════════════════════════════════════════════════════════════╗")
    print("║       MyAgenda Microservices Endpoints Test Tool               ║")
    print("║                                                                ║")
    print("║  ¿Qué microservicio quieres testear?                          ║")
    print("║  (Se levantarán automáticamente sus dependencias)             ║")
    print("╚════════════════════════════════════════════════════════════════╝")
    print(f"{Colors.NC}")
    print("  1) Gateway Service (requiere: Identity)")
    print("  2) Identity Service (sin dependencias)")
    print("  3) Availability Service (requiere: Identity)")
    print("  4) Booking Service (requiere: Identity, Availability)")
    print("  5) Payment Service (requiere: Identity, Booking)")
    print("  6) Notification Service (requiere: Identity)")
    print("  7) External Wallets Service (requiere: Identity)")
    print("  8) Professional Metrics Service (requiere: Identity, Booking)")
    print("  9) Professional Dashboard Service (requiere: Professional Metrics)")
    print()
    
    choice = input("Selecciona (1-9): ").strip()
    
    service_map = {
        "1": "gateway",
        "2": "identity",
        "3": "availability",
        "4": "booking",
        "5": "payment",
        "6": "notification",
        "7": "external-wallets",
        "8": "professional-metrics",
        "9": "professional-dashboard",
    }
    
    selected_service = service_map.get(choice)
    if not selected_service:
        return []
    
    return resolve_dependencies(selected_service)


def main():
    """Main function"""
    global auth_token
    
    # Clear results file
    open(RESULTS_FILE, "w").close()
    
    # Check prerequisites
    if not check_prerequisites():
        print_error("Requisitos no cumplidos")
        sys.exit(1)
    
    # Show menu and get services
    services = show_menu()
    if not services:
        print_error("Opción inválida")
        sys.exit(1)
    
    print(f"\n{Colors.CYAN}📦 Servicios a levantar:{Colors.NC}")
    for service in services:
        print(f"  {Colors.GREEN}✓{Colors.NC} {service}")
    print()
    
    print_header("Iniciando pruebas")
    
    # Setup signal handler for cleanup
    signal.signal(signal.SIGINT, lambda s, f: cleanup_and_exit())
    signal.signal(signal.SIGTERM, lambda s, f: cleanup_and_exit())
    
    try:
        # If multiple services, start identity first
        if len(services) > 1 and "identity" in services:
            restart_db("identity-db")
            start_microservice("identity-service", PORTS["identity"], PROJECT_ROOT / SERVICE_DIRS["identity"])
            wait_for_service(PORTS["identity"], "identity-service")
            create_test_user()
            get_auth_token()
        
        # Run tests
        test_functions = {
            "gateway": test_gateway_service,
            "identity": test_identity_service,
            "availability": test_availability_service,
            "booking": test_booking_service,
            "payment": test_payment_service,
            "notification": test_notification_service,
            "external-wallets": test_external_wallets_service,
            "professional-metrics": test_professional_metrics_service,
            "professional-dashboard": test_professional_dashboard_service,
        }
        
        for service in services:
            if service in test_functions:
                test_functions[service]()
        
        print(f"\n{Colors.GREEN}📄 Log completo guardado en: {RESULTS_FILE}{Colors.NC}\n")
        
        input(f"\n{Colors.CYAN}Presioná Enter para limpiar y cerrar...{Colors.NC}")
        
    finally:
        cleanup()


def cleanup_and_exit():
    """Cleanup and exit"""
    cleanup()
    sys.exit(0)


if __name__ == "__main__":
    main()
