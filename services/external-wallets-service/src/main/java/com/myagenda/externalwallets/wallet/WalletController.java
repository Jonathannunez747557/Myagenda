package com.myagenda.externalwallets.wallet;

import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDateTime;
import java.util.UUID;

@RestController
@RequestMapping("/wallets")
public class WalletController {

    private final WalletRepository walletRepository;

    public WalletController(WalletRepository walletRepository) {
        this.walletRepository = walletRepository;
    }

    @PostMapping
    public Wallet createWallet(@RequestBody CreateWalletRequest request, Authentication auth) {
        String professionalId = auth.getName();

        Wallet wallet = new Wallet();
        wallet.setId(UUID.randomUUID().toString());
        wallet.setProfessionalId(professionalId);
        wallet.setUserFullName(request.userFullName());
        wallet.setUserEmail(request.userEmail());
        wallet.setUserDocument(request.userDocument());
        wallet.setProvider(request.provider());
        wallet.setApiKey(request.apiKey());
        wallet.setSecretKey(request.secretKey());
        wallet.setCreatedAt(LocalDateTime.now());

        return walletRepository.save(wallet);
    }

    public record CreateWalletRequest(
            String userFullName,
            String userEmail,
            String userDocument,
            String provider,
            String apiKey,
            String secretKey
    ) {}
}
