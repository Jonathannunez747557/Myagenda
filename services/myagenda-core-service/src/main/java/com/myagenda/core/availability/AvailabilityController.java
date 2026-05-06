package com.myagenda.core.availability;

import org.springframework.web.bind.annotation.*;
import java.time.LocalDateTime;
import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/availability")
public class AvailabilityController {

    private final AvailabilityRepository availabilityRepository;

    public AvailabilityController(AvailabilityRepository availabilityRepository) {
        this.availabilityRepository = availabilityRepository;
    }

    @PostMapping
    public Availability createAvailability(@RequestBody CreateAvailabilityRequest request) {
        Availability availability = new Availability();
        availability.setId(UUID.randomUUID().toString());
        availability.setStartTime(request.startTime());
        availability.setEndTime(request.endTime());
        availability.setCapacity(request.capacity());
        availability.setBooked(0);

        return availabilityRepository.save(availability);
    }

    @GetMapping
    public List<Availability> getAvailabilities(@RequestParam(required = false) LocalDateTime from) {
        if (from != null) {
            return availabilityRepository.findByStartTimeGreaterThanEqual(from);
        }
        return availabilityRepository.findAll();
    }

    @GetMapping("/{availabilityId}")
    public Availability getAvailability(@PathVariable String availabilityId) {
        return availabilityRepository.findById(availabilityId)
                .orElseThrow(() -> new RuntimeException("Availability not found"));
    }

    public record CreateAvailabilityRequest(
            LocalDateTime startTime,
            LocalDateTime endTime,
            int capacity
    ) {}
}
