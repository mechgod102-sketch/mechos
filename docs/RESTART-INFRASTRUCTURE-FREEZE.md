# Frozen Restart Infrastructure

Restart is system infrastructure and is no longer owned by normal MechOS hotfixes.

The stable restart path is:

`/usr/local/bin/mechos-reboot`
→ `/usr/local/libexec/mechos-powerctl-v1 reboot`

The frozen power authority uses the session-safe order:

1. KDE Plasma shutdown service
2. systemd-logind over D-Bus
3. root `systemctl reboot`
4. PolicyKit `systemctl reboot`

The previously reintroduced `loginctl reboot` path is intentionally not used.

Normal hotfixes must not contain either the frozen reboot wrapper or power authority. Existing affected systems can run `scripts/mechos-restart-maintenance-v1.py` once to restore both files without changing the MechOS release version.
