import unittest
from rate_limiter import SlidingWindowLimiter


class RateLimiterTest(unittest.TestCase):
    def test_allows_requests_within_limit(self):
        limiter = SlidingWindowLimiter(limit=3, window_seconds=10.0)
        self.assertTrue(limiter.allow_request("u1", 1.0))
        self.assertTrue(limiter.allow_request("u1", 2.0))
        self.assertTrue(limiter.allow_request("u1", 3.0))


if __name__ == "__main__":
    unittest.main()
