package com.myagenda.core.booking;

import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;
import java.time.LocalDateTime;
import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/bookings")
public class BookingController {

    private final BookingRepository bookingRepository;

    public BookingController(BookingRepository bookingRepository) {
        this.bookingRepository = bookingRepository;
    }

    @PostMapping("/hold")
    public Booking holdBooking(@RequestBody HoldBookingRequest request, Authentication auth) {
        String userId = auth.getName();

        Booking booking = new Booking();
        booking.setId(UUID.randomUUID().toString());
        booking.setUserId(userId);
        booking.setAvailabilityId(request.availabilityId());
        booking.setBookedAt(LocalDateTime.now());
        booking.setStatus(BookingStatus.HOLD);

        return bookingRepository.save(booking);
    }

    @PostMapping("/{bookingId}/confirm")
    public Booking confirmBooking(@PathVariable String bookingId, Authentication auth) {
        String userId = auth.getName();

        Booking booking = bookingRepository.findByIdAndUserId(bookingId, userId)
                .orElseThrow(() -> new RuntimeException("Booking not found"));

        booking.setStatus(BookingStatus.CONFIRMED);
        return bookingRepository.save(booking);
    }

    @GetMapping
    public List<Booking> getUserBookings(Authentication auth) {
        String userId = auth.getName();
        return bookingRepository.findByUserId(userId);
    }

    @GetMapping("/{bookingId}")
    public Booking getBooking(@PathVariable String bookingId, Authentication auth) {
        String userId = auth.getName();
        return bookingRepository.findByIdAndUserId(bookingId, userId)
                .orElseThrow(() -> new RuntimeException("Booking not found"));
    }

    public record HoldBookingRequest(String availabilityId) {}
}
