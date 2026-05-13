package com.myagenda.users.health;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
public class UsersHealthController {

    @GetMapping("/api/v1/users/health")
    public Map<String, String> health() {
        return Map.of(
                "service", "users-service",
                "status", "UP"
        );
    }
}