#!/bin/sh
# Retained command for operators during the GoTrue refresh bridge.
exec python3 /srv/tidex/healthcheck.py --legacy-refresh "$@"
