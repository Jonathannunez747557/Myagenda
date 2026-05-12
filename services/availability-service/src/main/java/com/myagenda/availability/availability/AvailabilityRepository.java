package com.myagenda.availability.availability;

import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;

public interface AvailabilityRepository extends JpaRepository<Availability, String> {
    List<Availability> findByProfessionalId(String professionalId);
}
