package com.myagenda.metrics.metric;

import org.springframework.web.bind.annotation.*;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/metrics")
public class MetricController {

    private final MetricRepository metricRepository;

    public MetricController(MetricRepository metricRepository) {
        this.metricRepository = metricRepository;
    }

    @PostMapping
    public Metric createMetric(@RequestBody CreateMetricRequest request) {
        Metric metric = new Metric();
        metric.setId(UUID.randomUUID().toString());
        metric.setProfessionalId(request.professionalId());
        metric.setBookingId(request.bookingId());
        metric.setMetricType(request.metricType());
        metric.setAmount(request.amount());
        metric.setCreatedAt(LocalDateTime.now());

        return metricRepository.save(metric);
    }

    @GetMapping("/{professionalId}")
    public Map<String, Object> getMetrics(@PathVariable String professionalId) {
        Map<String, Object> metrics = new HashMap<>();

        long totalSeñas = metricRepository.countByProfessionalIdAndMetricType(professionalId, "SEÑA_RECIBIDA");
        long totalAsistencias = metricRepository.countByProfessionalIdAndMetricType(professionalId, "ASISTENCIA");
        long totalCancelaciones = metricRepository.countByProfessionalIdAndMetricType(professionalId, "CANCELACION");

        Double totalSeñasAmount = metricRepository.sumAmountByProfessionalIdAndMetricType(professionalId, "SEÑA_RECIBIDA");
        Double totalAsistenciasAmount = metricRepository.sumAmountByProfessionalIdAndMetricType(professionalId, "ASISTENCIA");

        metrics.put("professionalId", professionalId);
        metrics.put("totalSeñas", totalSeñas);
        metrics.put("totalAsistencias", totalAsistencias);
        metrics.put("totalCancelaciones", totalCancelaciones);
        metrics.put("totalSeñasAmount", totalSeñasAmount);
        metrics.put("totalAsistenciasAmount", totalAsistenciasAmount);

        return metrics;
    }

    public record CreateMetricRequest(
            String professionalId,
            String bookingId,
            String metricType,
            BigDecimal amount
    ) {}
}
