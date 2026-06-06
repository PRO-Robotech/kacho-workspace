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


def mint(secret: str, sub: str, exp_seconds: int | None = None, extra_claims: dict | None = None) -> str:
    """HS256 JWT с claim'ами sub, iat, iss (+ exp ТОЛЬКО если exp_seconds задан).

    exp_seconds=None → БЕССРОЧНЫЙ токен (без `exp`) — требование zero-manual тестов
    (KAC-263): newman/e2e не должны падать из-за протухших JWT. api-gateway dev-authn
    (`jwt.Parse`, без WithExpirationRequired) корректно принимает токен без `exp`.
    Отрицательный exp_seconds → уже-протухший токен (для expired-варианта model 6).
    """
    header = {"alg": "HS256", "typ": "JWT"}
    now = int(time.time())
    claims: dict = {
        "sub": sub,
        "iat": now,
        "iss": "kacho-authz-deny-suite",
    }
    if exp_seconds is not None:
        claims["exp"] = now + exp_seconds
    if extra_claims:
        claims.update(extra_claims)
    head_b64 = b64u(json.dumps(header, separators=(",", ":")).encode())
    body_b64 = b64u(json.dumps(claims, separators=(",", ":")).encode())
    signing_input = f"{head_b64}.{body_b64}".encode()
    sig = hmac.new(secret.encode(), signing_input, hashlib.sha256).digest()
    sig_b64 = b64u(sig)
    return f"{head_b64}.{body_b64}.{sig_b64}"


def bulk(secret: str) -> dict:
    """6 основных user-токенов — БЕССРОЧНЫЕ (exp_seconds=None, KAC-263)."""
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
    return {name: mint(secret, sub) for name, sub in subjects.items()}


def mint_sa(secret: str, sva_id: str, exp_seconds: int | None = None) -> str:
    """KAC-127 модель 5 — Service Account токен.

    На стенде dev-mode моделирует Kachō-JWT, который Hydra-token_hook
    выдаёт после client_credentials grant: `sub=<svaId>` +
    `kacho_principal_type=service_account`. Реальный Hydra-flow живёт в
    setup.sh (SAKeyService.Issue + /oauth2/token); здесь — dev-эквивалент,
    т.к. api-gateway authn в dev-mode принимает HS256 dev-secret JWT.
    """
    return mint(secret, sva_id, exp_seconds, extra_claims={
        "kacho_principal_type": "service_account",
        "kacho_sa_id": sva_id,
    })


def mint_api_token(secret: str, sva_id: str, exp_seconds: int, scope: str) -> str:
    """KAC-127 модель 6 — статический API-token.

    Привязан к principal (SA) + scope. exp_seconds может быть отрицательным
    (для expired-варианта). `scope` — space-separated (например
    "vpc.* project:<projectId>").
    """
    return mint(secret, sva_id, exp_seconds, extra_claims={
        "kacho_principal_type": "service_account",
        "kacho_sa_id": sva_id,
        "kacho_token_kind": "api_token",
        "scope": scope,
    })


def main() -> int:
    parser = argparse.ArgumentParser(description="HS256 JWT minter for authz-deny suite")
    parser.add_argument("--secret", required=True, help="HMAC secret (KACHO_API_GATEWAY_AUTHN_DEV_SECRET)")
    parser.add_argument("--sub", help="sub claim (single-mint mode)")
    parser.add_argument("--exp-hours", type=int, default=0, help="exp = iat + exp-hours*3600; 0 (default) = БЕССРОЧНЫЙ токен без exp (KAC-263)")
    parser.add_argument("--bulk", action="store_true", help="Mint all 6 subjects, print JSON")
    # KAC-127 models 5-6.
    parser.add_argument("--sa", metavar="SVA_ID",
                        help="mint Service Account token (kacho_principal_type=service_account)")
    parser.add_argument("--api-token", metavar="SVA_ID",
                        help="mint static API token bound to principal SVA_ID")
    parser.add_argument("--scope", default="vpc.*",
                        help="API-token scope (space-separated; used with --api-token)")
    parser.add_argument("--exp-seconds", type=int,
                        help="explicit exp offset in seconds (may be negative → expired); "
                             "overrides --exp-hours for --sa / --api-token")
    args = parser.parse_args()

    if args.bulk:
        result = bulk(args.secret)
        json.dump(result, sys.stdout, indent=2)
        sys.stdout.write("\n")
        return 0

    # exp_seconds: явный --exp-seconds (включая отрицательный для expired-теста);
    # иначе --exp-hours>0 → секунды; иначе None → бессрочный (KAC-263).
    if args.exp_seconds is not None:
        exp_seconds = args.exp_seconds
    elif args.exp_hours > 0:
        exp_seconds = args.exp_hours * 3600
    else:
        exp_seconds = None

    if args.sa:
        sys.stdout.write(mint_sa(args.secret, args.sa, exp_seconds))
        return 0
    if args.api_token:
        sys.stdout.write(mint_api_token(args.secret, args.api_token, exp_seconds, args.scope))
        return 0
    if not args.sub:
        parser.error("--sub required when --bulk / --sa / --api-token not set")
    token = mint(args.secret, args.sub, exp_seconds)
    sys.stdout.write(token)
    return 0


if __name__ == "__main__":
    sys.exit(main())
