package com.myagenda.booking.booking;

import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;
import java.util.logging.Logger;

@Service
public class MetricsNotificationService {

    private static final Logger logger = Logger.getLogger(MetricsNotificationService.class.getName());
    private static final String METRICS_SERVICE_URL = "http://localhost:8087/metrics";
    private static final int MAX_RETRIES = 3;

    private final BookingRepository bookingRepository;
    private final BookingEventRepository bookingEventRepository;
    private final RestTemplate restTemplate;
    private final ObjectMapper objectMapper;

    public MetricsNotificationService(BookingRepository bookingRepository,
                                     BookingEventRepository bookingEventRepository,
                                     RestTemplate restTemplate,
                                     ObjectMapper objectMapper) {
        this.bookingRepository = bookingRepository;
        this.bookingEventRepository = bookingEventRepository;
        this.restTemplate = restTemplate;
        this.objectMapper = objectMapper;
    }

    @Async
    public void notifyBookingConfirmed(Booking booking) {
        try {
            // Crear evento pendiente
            BookingEvent event = new BookingEvent();
            event.setId(UUID.randomUUID().toString());
            event.setBookingId(booking.getId());
            event.setEventType("SEÑA_RECIBIDA");
            event.setStatus("PENDING");
            event.setRetryCount(0);
            event.setCreatedAt(LocalDateTime.now());

            Map<String, Object> payload = new HashMap<>();
            payload.put("professionalId", booking.getAvailabilityId());
            payload.put("bookingId", booking.getId());
            payload.put("metricType", "SEÑA_RECIBIDA");
            payload.put("amount", 500);

            event.setPayload(objectMapper.writeValueAsString(payload));
            bookingEventRepository.save(event);

            // Intentar notificar
            sendMetricNotification(event, payload);
        } catch (Exception e) {
            logger.warning("Error notifying metrics: " + e.getMessage());
        }
    }

    private void sendMetricNotification(BookingEvent event, Map<String, Object> payload) {
        try {
            restTemplate.postForObject(METRICS_SERVICE_URL, payload, Map.class);

            // Marcar como enviado
            event.setStatus("SENT");
            event.setSentAt(LocalDateTime.now());
            bookingEventRepository.save(event);

            // Marcar booking como notificado
            Booking booking = bookingRepository.findById(event.getBookingId()).orElse(null);
            if (booking != null) {
                booking.setMetricsNotified(true);
                bookingRepository.save(booking);
            }
        } catch (Exception e) {
            logger.warning("Failed to send metric notification: " + e.getMessage());
            event.setRetryCount(event.getRetryCount() + 1);
            event.setStatus("FAILED");
            bookingEventRepository.save(event);
        }
    }

    public void retryFailedNotifications() {
        try {
            var failedEvents = bookingEventRepository.findByStatusAndRetryCountLessThan("FAILED", MAX_RETRIES);
            for (BookingEvent event : failedEvents) {
                try {
                    Map<String, Object> payload = objectMapper.readValue(event.getPayload(), Map.class);
                    sendMetricNotification(event, payload);
                } catch (Exception e) {
                    logger.warning("Error retrying notification: " + e.getMessage());
                }
            }
        } catch (Exception e) {
            logger.warning("Error in retryFailedNotifications: " + e.getMessage());
        }
    }
}
