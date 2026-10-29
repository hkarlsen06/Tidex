import json
import unittest
from unittest.mock import patch

import healthcheck


class HealthcheckFailures(unittest.TestCase):
    def test_database_failure_is_not_hidden_by_a_running_api(self):
        responses = [(200, b"version", {}), (500, b"database unavailable", {})]
        with patch.object(healthcheck, "request", side_effect=responses), self.assertRaises(AssertionError):
            healthcheck.convex()

    def test_generic_not_found_does_not_prove_calendar_routing(self):
        with patch.object(healthcheck, "request", return_value=(404, b"", {})), self.assertRaises(AssertionError):
            healthcheck.calendars()

    def test_unverified_email_or_disabled_apple_is_not_healthy(self):
        settings = {
            "attributes": {"email_address": {"enabled": True, "required": False, "verify_at_sign_up": True}},
            "social": {name: {"enabled": True, "authenticatable": True} for name in ("oauth_apple", "oauth_google")},
        }
        def response():
            return 200, json.dumps({"user_settings": settings}).encode(), {}
        with patch.object(healthcheck, "request", side_effect=lambda *args: response()):
            healthcheck.clerk()
            settings["attributes"]["email_address"]["verify_at_sign_up"] = False
            with self.assertRaises(AssertionError):
                healthcheck.clerk()
            settings["attributes"]["email_address"]["verify_at_sign_up"] = True
            settings["social"]["oauth_apple"]["enabled"] = False
            with self.assertRaises(AssertionError):
                healthcheck.clerk()


if __name__ == "__main__":
    unittest.main()
