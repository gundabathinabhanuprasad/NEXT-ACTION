# Production SSL/TLS Certificate Configuration

This directory contains instructions and placeholders for mounting production TLS certificates into the Nginx reverse proxy.

## Expected Certificate Files
When deploying to production, mount your domain's TLS certificates at:
- `fullchain.pem` — The complete server certificate chain including intermediate CA certificates.
- `privkey.pem` — The private key matching the leaf certificate (mode `0600`).

## Automated Certificate Provisioning with Let's Encrypt / Certbot

### 1. Initial Certificate Issuance
Using Certbot in standalone or webroot mode against the `.well-known/acme-challenge/` endpoint:
```bash
certbot certonly --webroot -w /var/www/certbot \
    -d app.nextaction.com -d api.nextaction.com \
    --email admin@nextaction.com --agree-tos --no-eff-email
```

### 2. Automated Certificate Renewal
Certbot certificates expire every 90 days. Set up an automated cronjob or systemd timer:
```bash
# Add to crontab or cron.d
0 3 * * * certbot renew --quiet --deploy-hook "docker compose -f docker-compose.prod.yml exec reverse-proxy nginx -s reload"
```

## Local Development / Smoke Test Self-Signed Certificates
For local staging or CI smoke testing, generate temporary self-signed certificates:
```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout nginx/ssl/privkey.pem \
    -out nginx/ssl/fullchain.pem \
    -subj "/CN=localhost/O=NextAction/C=US"
```
Do NOT commit production private keys to Git repository or include them in Docker images.
