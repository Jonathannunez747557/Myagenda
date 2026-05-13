package com.myagenda.fraudguardian.health;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
public class FraudGuardianHealthController {

    @GetMapping("/api/v1/fraud/health")
    public Map<String, String> health() {
        return Map.of(
                "service", "fraud-guardian-service",
                "status", "UP"
        );
    }
}