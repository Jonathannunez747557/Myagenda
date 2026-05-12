package com.myagenda.authorization.health;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
public class AuthorizationHealthController {

    @GetMapping("/api/v1/authorization/health")
    public Map<String, String> health() {
        return Map.of(
                "service", "authorization-service",
                "status", "UP"
        );
    }
}