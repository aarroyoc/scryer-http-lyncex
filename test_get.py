from unittest import TestCase

import requests

class HttpGet(TestCase):
    def setUp(self):
        self.base = "http://localhost:7890"

    def test_get_text(self):
        r = requests.get(f"{self.base}/")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.text, "Welcome to Scryer Prolog!")

    def test_get_notfound(self):
        pass
    
    def test_useragent_text(self):
        headers = {'User-Agent': 'test-suite/0.0.1'}
        r = requests.get(f"{self.base}/user-agent", headers=headers)
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.text, "test-suite/0.0.1")