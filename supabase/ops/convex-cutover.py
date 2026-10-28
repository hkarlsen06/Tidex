#!/usr/bin/env python3
"""Write a Caddy candidate for the approved cutover, without installing it."""

import argparse
from pathlib import Path
import re


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--source", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--calendar", choices=("supabase", "convex"), required=True)
args = parser.parse_args()
source = args.source.read_text()
pattern = r"(?ms)^identity\.tidex\.no, api\.tidex\.no \{\n.*?^\}"
if len(re.findall(pattern, source)) != 1:
    parser.error("Expected exactly one Tidex Supabase host block")
if args.source.resolve() == args.output.resolve():
    parser.error("Write a candidate file, not over the source")

feed = """reverse_proxy 100.109.207.90:8000 {
                    header_up X-Forwarded-For {client_ip}
                }"""
if args.calendar == "convex":
    feed = """uri strip_prefix /functions/v1
                reverse_proxy 127.0.0.1:3221"""
site = """identity.tidex.no, api.tidex.no {
    import /etc/caddy/norskenavn-mail.caddy
    bind 2001:880:a:334::37d
    tls {
        dns cloudflare {env.CF_API_TOKEN}
    }
    encode zstd gzip
    log_skip /functions/v1/calendar-feed/*
    route {
        @calendar {
            method GET HEAD
            path /functions/v1/calendar-feed/*
        }
        handle @calendar {
            FEED
        }
        @refresh {
            method POST
            path /auth/v1/token
            expression `{http.request.uri.query} == "grant_type=refresh_token"`
        }
        handle @refresh {
            reverse_proxy 100.109.207.90:8000 {
                header_up X-Forwarded-For {client_ip}
            }
        }
        handle {
            abort
        }
    }
}""".replace("FEED", feed)
args.output.write_text(re.sub(pattern, lambda _: site, source))
print(f"Wrote {args.output}; calendar backend is {args.calendar}. Nothing installed.")
