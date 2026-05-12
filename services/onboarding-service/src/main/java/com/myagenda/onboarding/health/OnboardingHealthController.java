package com.myagenda.onboarding.health;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
public class OnboardingHealthController {

    @GetMapping("/api/v1/onboarding/health")
    public Map<String, String> health() {
        return Map.of(
                "service", "onboarding-service",
                "status", "UP"
        );
    }
}