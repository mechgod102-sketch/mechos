#!/usr/bin/env bash
set -Eeuo pipefail
# MECHOS_FIRSTBOOT_UPDATE_APPLY_V23

STATE=/var/lib/mechos
HELPER=/usr/local/bin/mechos-update-helper

fail(){ printf 'MechOS firstboot updater: %s\n' "$*" >&2; exit 77; }

[ "$(id -u)" -eq 0 ] || fail 'administrator privileges required'
[ -f "$STATE/installed" ] || fail 'this helper is only available on an installed MechOS system'
[ ! -f "$STATE/oobe-complete" ] || fail 'firstboot setup is already complete'
[ -x "$HELPER" ] || fail 'MechOS update helper is missing'

# pkexec exports the uid of the requesting desktop user. Refuse to become a
# general root update entry point: this bridge exists only for the temporary
# firstboot transport account, which intentionally has no password and is not
# a member of wheel.
origin_uid="${PKEXEC_UID:-}"
[ -n "$origin_uid" ] || fail 'missing pkexec requester identity'
origin_user="$(getent passwd "$origin_uid" | cut -d: -f1 || true)"
[ "$origin_user" = 'mechos-setup' ] || fail 'only the MechOS firstboot setup session may use this helper'

# The normal helper owns stable.json retrieval, SHA-256 verification, bundle
# path validation, staging and transactional installation. No caller-supplied
# URL, bundle path or version is accepted here.
exec "$HELPER" apply
