package com.myagenda.core.availability;

import org.springframework.data.jpa.repository.JpaRepository;
import java.time.LocalDateTime;
import java.util.List;

public interface AvailabilityRepository extends JpaRepository<Availability, String> {
    List<Availability> findByStartTimeGreaterThanEqual(LocalDateTime startTime);
}
