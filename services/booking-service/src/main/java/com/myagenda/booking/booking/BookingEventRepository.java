package com.myagenda.booking.booking;

import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;

public interface BookingEventRepository extends JpaRepository<BookingEvent, String> {
    List<BookingEvent> findByStatusAndRetryCountLessThan(String status, Integer maxRetries);
    List<BookingEvent> findByBookingId(String bookingId);
}
