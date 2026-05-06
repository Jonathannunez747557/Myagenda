package com.myagenda.notification.notification;

import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;
import java.time.LocalDateTime;
import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/notifications")
public class NotificationController {

    private final NotificationRepository notificationRepository;

    public NotificationController(NotificationRepository notificationRepository) {
        this.notificationRepository = notificationRepository;
    }

    @PostMapping("/send")
    public Notification sendNotification(@RequestBody SendNotificationRequest request, Authentication auth) {
        String userId = auth.getName();

        Notification notification = new Notification();
        notification.setId(UUID.randomUUID().toString());
        notification.setUserId(userId);
        notification.setMessage(request.message());
        notification.setType(request.type());
        notification.setSentAt(LocalDateTime.now());
        notification.setStatus(NotificationStatus.SENT);

        return notificationRepository.save(notification);
    }

    @GetMapping
    public List<Notification> getUserNotifications(Authentication auth) {
        String userId = auth.getName();
        return notificationRepository.findByUserId(userId);
    }

    @GetMapping("/{notificationId}")
    public Notification getNotification(@PathVariable String notificationId) {
        return notificationRepository.findById(notificationId)
                .orElseThrow(() -> new RuntimeException("Notification not found"));
    }

    public record SendNotificationRequest(
            String message,
            String type
    ) {}
}
