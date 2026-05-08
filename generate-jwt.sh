#!/bin/bash

# Generar JWT válido usando openssl y base64
# Secret: clave-super-secreta-12345678901234567890

SECRET="clave-super-secreta-12345678901234567890"
HEADER='{"alg":"HS256","typ":"JWT"}'
PAYLOAD='{"sub":"testadmin","roles":["ADMIN"],"iat":1715147600,"exp":9999999999}'

# Codificar header y payload en base64
HEADER_B64=$(echo -n "$HEADER" | base64 | tr -d '=' | tr '+/' '-_')
PAYLOAD_B64=$(echo -n "$PAYLOAD" | base64 | tr -d '=' | tr '+/' '-_')

# Crear signature
SIGNATURE_INPUT="$HEADER_B64.$PAYLOAD_B64"
SIGNATURE=$(echo -n "$SIGNATURE_INPUT" | openssl dgst -sha256 -hmac "$SECRET" -binary | base64 | tr -d '=' | tr '+/' '-_')

# Token final
JWT="$SIGNATURE_INPUT.$SIGNATURE"

echo "$JWT"
