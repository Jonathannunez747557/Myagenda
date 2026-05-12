package com.myagenda.identityvalidation.health;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
public class IdentityValidationHealthController {

    @GetMapping("/api/v1/identity/health")
    public Map<String, String> health() {
        return Map.of(
                "service", "identity-validation-service",
                "status", "UP"
        );
    }
}