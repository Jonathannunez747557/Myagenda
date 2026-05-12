package com.myagenda.availability.availability;

import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.util.ArrayList;
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
    public AvailabilityResponse createAvailability(@RequestBody CreateAvailabilityRequest request,
                                                   Authentication auth) {
        String professionalId = auth.getName();

        Availability availability = new Availability();
        availability.setId(UUID.randomUUID().toString());
        availability.setProfessionalId(professionalId);
        availability.setDate(request.date());
        availability.setStartTime(request.startTime());
        availability.setEndTime(request.endTime());
        availability.setSlotDurationMinutes(request.slotDurationMinutes());
        availability.setCreatedAt(LocalDateTime.now());

        Availability saved = availabilityRepository.save(availability);

        List<SlotDto> slots = computeSlots(saved.getStartTime(), saved.getEndTime(), saved.getSlotDurationMinutes());

        return new AvailabilityResponse(
                saved.getId(),
                saved.getProfessionalId(),
                saved.getDate(),
                saved.getStartTime(),
                saved.getEndTime(),
                saved.getSlotDurationMinutes(),
                saved.getCreatedAt(),
                slots
        );
    }

    @GetMapping
    public List<AvailabilityResponse> getAvailabilities(Authentication auth) {
        String professionalId = auth.getName();
        List<Availability> availabilities = availabilityRepository.findByProfessionalId(professionalId);
        
        return availabilities.stream()
                .map(availability -> new AvailabilityResponse(
                        availability.getId(),
                        availability.getProfessionalId(),
                        availability.getDate(),
                        availability.getStartTime(),
                        availability.getEndTime(),
                        availability.getSlotDurationMinutes(),
                        availability.getCreatedAt(),
                        computeSlots(availability.getStartTime(), availability.getEndTime(), availability.getSlotDurationMinutes())
                ))
                .toList();
    }

    private List<SlotDto> computeSlots(LocalTime start, LocalTime end, int durationMinutes) {
        List<SlotDto> slots = new ArrayList<>();
        LocalTime current = start;
        while (!current.plusMinutes(durationMinutes).isAfter(end)) {
            slots.add(new SlotDto(current, current.plusMinutes(durationMinutes)));
            current = current.plusMinutes(durationMinutes);
        }
        return slots;
    }

    public record CreateAvailabilityRequest(
            LocalDate date,
            LocalTime startTime,
            LocalTime endTime,
            int slotDurationMinutes
    ) {}

    public record SlotDto(LocalTime start, LocalTime end) {}

    public record AvailabilityResponse(
            String id,
            String professionalId,
            LocalDate date,
            LocalTime startTime,
            LocalTime endTime,
            int slotDurationMinutes,
            LocalDateTime createdAt,
            List<SlotDto> slots
    ) {}
}
