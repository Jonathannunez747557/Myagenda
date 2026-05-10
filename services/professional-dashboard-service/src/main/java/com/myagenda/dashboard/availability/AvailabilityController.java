package com.myagenda.dashboard.availability;

import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.client.RestTemplate;

import java.time.LocalDate;
import java.time.LocalTime;
import java.util.HashMap;
import java.util.Map;

@RestController
@RequestMapping("/availability")
public class AvailabilityController {

    private final RestTemplate restTemplate;

    public AvailabilityController(RestTemplate restTemplate) {
        this.restTemplate = restTemplate;
    }

    @PostMapping
    public Map<String, Object> createAvailability(@RequestBody CreateAvailabilityRequest request, Authentication auth) {
        String professionalId = auth.getName();

        Map<String, Object> payload = new HashMap<>();
        payload.put("date", request.date());
        payload.put("startTime", request.startTime());
        payload.put("endTime", request.endTime());
        payload.put("slotDurationMinutes", request.slotDurationMinutes());

        try {
            Map<String, Object> response = restTemplate.postForObject(
                    "http://localhost:8082/availability",
                    payload,
                    Map.class
            );

            Map<String, Object> result = new HashMap<>();
            result.put("professionalId", professionalId);
            result.put("availabilityData", response);
            result.put("status", "success");

            try {
                Map<String, Object> metrics = restTemplate.getForObject(
                        "http://localhost:8087/metrics/" + professionalId,
                        Map.class
                );
                result.put("metrics", metrics);
            } catch (Exception metricsError) {
                result.put("metrics", new HashMap<>());
            }

            return result;
        } catch (Exception e) {
            Map<String, Object> error = new HashMap<>();
            error.put("status", "error");
            error.put("message", e.getMessage());
            return error;
        }
    }

    public record CreateAvailabilityRequest(
            LocalDate date,
            LocalTime startTime,
            LocalTime endTime,
            int slotDurationMinutes
    ) {}
}
