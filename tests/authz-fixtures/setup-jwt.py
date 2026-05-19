#!/usr/bin/env python3
"""HS256 JWT minter для authz-deny newman suite (KAC-122).

Использование:
    python3 setup-jwt.py --secret kacho-dev-jwt-secret-2026 \
                        --sub auth-test-account-admin-a \
                        --exp-hours 24
    -> печатает signed JWT в stdout (один токен, без переноса)

Mass-mint режим:
    python3 setup-jwt.py --secret <s> --bulk
    -> печатает JSON {"jwtBootstrap": "...", "jwtNoBindings": "...", ...}

Не использует внешних зависимостей кроме stdlib (hmac, hashlib, base64, json).
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import hmac
import json
import sys
import time


def b64u(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def mint(secret: str, sub: str, exp_seconds: int, extra_claims: dict | None = None) -> str:
    """HS256 JWT с минимальным набором claim'ов: sub, iat, exp."""
    header = {"alg": "HS256", "typ": "JWT"}
    now = int(time.time())
    claims: dict = {
        "sub": sub,
        "iat": now,
        "exp": now + exp_seconds,
        "iss": "kacho-authz-deny-suite",
    }
    if extra_claims:
        claims.update(extra_claims)
    head_b64 = b64u(json.dumps(header, separators=(",", ":")).encode())
    body_b64 = b64u(json.dumps(claims, separators=(",", ":")).encode())
    signing_input = f"{head_b64}.{body_b64}".encode()
    sig = hmac.new(secret.encode(), signing_input, hashlib.sha256).digest()
    sig_b64 = b64u(sig)
    return f"{head_b64}.{body_b64}.{sig_b64}"


def bulk(secret: str, exp_hours: int) -> dict:
    exp = exp_hours * 3600
    subjects = {
        # external_id ↔ JWT env-var name. external_id = `sub` claim, который
        # api-gateway пробросит на InternalIAMService.LookupByExternalID для
        # резолва User-row по этому external_id.
        # Bootstrap admin использует email matcher KACHO_IAM_BOOTSTRAP_ADMIN_EMAIL.
        # Email-в-sub допустим на стенде (LookupByExternalID matchит и по полю
        # email если external_id не найден — KAC-119 bootstrap matcher).
        "jwtBootstrap": "admin@prorobotech.ru",
        "jwtNoBindings": "auth-test-no-bindings@example.com",
        "jwtProjectAdminA1": "auth-test-proj-admin-a1@example.com",
        "jwtAccountAdminA": "auth-test-account-admin-a@example.com",
        "jwtAccountAdminB": "auth-test-account-admin-b@example.com",
        "jwtInvitee": "auth-test-invitee@example.com",
    }
    return {name: mint(secret, sub, exp) for name, sub in subjects.items()}


def main() -> int:
    parser = argparse.ArgumentParser(description="HS256 JWT minter for authz-deny suite")
    parser.add_argument("--secret", required=True, help="HMAC secret (KACHO_API_GATEWAY_AUTHN_DEV_SECRET)")
    parser.add_argument("--sub", help="sub claim (single-mint mode)")
    parser.add_argument("--exp-hours", type=int, default=24, help="exp = iat + exp-hours*3600")
    parser.add_argument("--bulk", action="store_true", help="Mint all 6 subjects, print JSON")
    args = parser.parse_args()

    if args.bulk:
        result = bulk(args.secret, args.exp_hours)
        json.dump(result, sys.stdout, indent=2)
        sys.stdout.write("\n")
        return 0
    if not args.sub:
        parser.error("--sub required when --bulk not set")
    token = mint(args.secret, args.sub, args.exp_hours * 3600)
    sys.stdout.write(token)
    return 0


if __name__ == "__main__":
    sys.exit(main())
