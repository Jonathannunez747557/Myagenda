package com.myagenda.payment.payment;

import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.UUID;

@RestController
@RequestMapping("/payments")
public class PaymentController {

    private final PaymentRepository paymentRepository;

    public PaymentController(PaymentRepository paymentRepository) {
        this.paymentRepository = paymentRepository;
    }

    @PostMapping("/process")
    public Payment processPayment(@RequestBody ProcessPaymentRequest request, Authentication auth) {
        String userId = auth.getName();

        Payment payment = new Payment();
        payment.setId(UUID.randomUUID().toString());
        payment.setBookingId(request.bookingId());
        payment.setUserId(userId);
        payment.setAmount(request.amount());
        payment.setProcessedAt(LocalDateTime.now());
        payment.setStatus(PaymentStatus.COMPLETED);

        return paymentRepository.save(payment);
    }

    @GetMapping("/{paymentId}")
    public Payment getPayment(@PathVariable String paymentId) {
        return paymentRepository.findById(paymentId)
                .orElseThrow(() -> new RuntimeException("Payment not found"));
    }

    public record ProcessPaymentRequest(
            String bookingId,
            BigDecimal amount
    ) {}
}
