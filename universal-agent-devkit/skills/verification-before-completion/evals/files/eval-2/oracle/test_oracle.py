import unittest
from rate_limiter import SlidingWindowLimiter


class RateLimiterOracleTest(unittest.TestCase):
    def test_blocks_at_limit_and_recovers_after_window(self):
        limiter = SlidingWindowLimiter(limit=2, window_seconds=5.0)
        self.assertTrue(limiter.allow_request("c1", 10.0))
        self.assertTrue(limiter.allow_request("c1", 12.0))
        self.assertFalse(limiter.allow_request("c1", 14.9))
        self.assertTrue(limiter.allow_request("c1", 15.1))

    def test_isolates_clients(self):
        limiter = SlidingWindowLimiter(limit=1, window_seconds=10.0)
        self.assertTrue(limiter.allow_request("a", 1.0))
        self.assertFalse(limiter.allow_request("a", 2.0))
        self.assertTrue(limiter.allow_request("b", 2.0))


if __name__ == "__main__":
    unittest.main()
