# MechOS 0.3.1 update signing

MechOS 0.3.1 introduces a signed Stable-channel manifest for post-0.3.1 updates.

## Trust model

The repository contains only the **public** update-signing key at `updates/mechos-update-signing-public.pem`. The corresponding private key must be stored only as the GitHub Actions secret `MECHOS_UPDATE_SIGNING_PRIVATE_KEY` or in an equivalently protected offline release-signing environment.

Never commit the private key to Git, an ISO, an update bundle, issue, pull request, log, or chat transcript.

The publisher signs the exact bytes of `updates/stable.json` with RSA/SHA-256 and publishes `updates/stable.json.sig`. Installed 0.3.1 systems verify the signature with OpenSSL before trusting the version, bundle URL, checksum, or reboot flag.

## Provisioning requirement

Before the 0.3.1 Stable publisher can run:

1. Generate a dedicated release-signing RSA key pair in a secure environment.
2. Commit only the public key as `updates/mechos-update-signing-public.pem`.
3. Store the complete private PEM as the repository Actions secret `MECHOS_UPDATE_SIGNING_PRIVATE_KEY`.
4. Verify the public/private pair locally before enabling publication.
5. Run the 0.3.1 validation workflow and then the publisher.

The 0.3.1 publisher intentionally fails closed when either the public key or private signing secret is missing.
