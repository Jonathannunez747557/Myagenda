package com.myagenda.login.health;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
public class LoginHealthController {

    @GetMapping("/api/v1/login/health")
    public Map<String, String> health() {
        return Map.of(
                "service", "login-service",
                "status", "UP"
        );
    }
}