package com.myagenda.booking.booking;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDateTime;

public interface BookingRepository extends JpaRepository<Booking, String> {

    @Query("SELECT COUNT(b) > 0 FROM Booking b " +
           "WHERE b.availabilityId = :availabilityId " +
           "AND b.status = 'CONFIRMED' " +
           "AND b.slotStart < :slotEnd " +
           "AND b.slotEnd > :slotStart")
    boolean existsConflictingBooking(
            @Param("availabilityId") String availabilityId,
            @Param("slotStart") LocalDateTime slotStart,
            @Param("slotEnd") LocalDateTime slotEnd
    );
}
