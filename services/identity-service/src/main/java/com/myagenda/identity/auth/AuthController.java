package com.myagenda.identity.auth;

import com.myagenda.identity.security.JwtService;
import org.springframework.web.bind.annotation.*;

import java.time.Instant;
import java.util.Map;

@RestController
@RequestMapping("/auth")
public class AuthController {

    private final JwtService jwtService = new JwtService();

    @PostMapping("/login")
    public Map<String, Object> login(@RequestBody LoginRequest request) {
        if (!"admin".equals(request.username()) || !"admin123".equals(request.password())) {
            throw new RuntimeException("Invalid credentials");
        }

        String token = jwtService.generateToken(request.username());

        System.out.println("JWT REAL GENERADO");

        return Map.of(
                "access_token", token,
                "token_type", "Bearer",
                "expires_at", Instant.now().plusSeconds(3600).toString()
        );
    }

    public record LoginRequest(String username, String password) {
    }
}