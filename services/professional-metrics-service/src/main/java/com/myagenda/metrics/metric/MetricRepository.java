package com.myagenda.metrics.metric;

import org.springframework.data.mongodb.repository.MongoRepository;
import org.springframework.data.mongodb.repository.Aggregation;

import java.math.BigDecimal;
import java.util.List;

public interface MetricRepository extends MongoRepository<Metric, String> {

    long countByProfessionalIdAndMetricType(String professionalId, String metricType);

    @Aggregation(pipeline = {
        "{ $match: { professionalId: ?0, metricType: ?1 } }",
        "{ $group: { _id: null, total: { $sum: $amount } } }"
    })
    Double sumAmountByProfessionalIdAndMetricType(String professionalId, String metricType);

    List<Metric> findByProfessionalId(String professionalId);
}
