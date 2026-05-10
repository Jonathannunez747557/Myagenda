package com.myagenda.booking.booking;

import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDateTime;
import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/bookings")
public class BookingController {

    private final BookingRepository bookingRepository;
    private final MetricsNotificationService metricsNotificationService;

    public BookingController(BookingRepository bookingRepository,
                           MetricsNotificationService metricsNotificationService) {
        this.bookingRepository = bookingRepository;
        this.metricsNotificationService = metricsNotificationService;
    }

    @PostMapping
    public ResponseEntity<?> createBooking(@RequestBody CreateBookingRequest request, Authentication auth) {
        String clientId = auth.getName();

        boolean hasConflict = bookingRepository.existsConflictingBooking(
                request.availabilityId(),
                request.slotStart(),
                request.slotEnd()
        );

        if (hasConflict) {
            return ResponseEntity.status(409).body(Map.of("error", "Slot ya reservado para ese horario"));
        }

        Booking booking = new Booking();
        booking.setId(UUID.randomUUID().toString());
        booking.setAvailabilityId(request.availabilityId());
        booking.setClientId(clientId);
        booking.setSlotStart(request.slotStart());
        booking.setSlotEnd(request.slotEnd());
        booking.setStatus(BookingStatus.CONFIRMED);
        booking.setCreatedAt(LocalDateTime.now());

        Booking savedBooking = bookingRepository.save(booking);

        metricsNotificationService.notifyBookingConfirmed(savedBooking);

        return ResponseEntity.ok(savedBooking);
    }

    public record CreateBookingRequest(
            String availabilityId,
            LocalDateTime slotStart,
            LocalDateTime slotEnd
    ) {}
}
