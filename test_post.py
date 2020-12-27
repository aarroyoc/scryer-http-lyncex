from unittest import TestCase

import requests

class HttpPost(TestCase):
    def setUp(self):
        self.base = "http://localhost:7890"

    def test_echo_text(self):
        r = requests.post(f"{self.base}/echo-text", data="Echo".encode("utf-8"))
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.text, "Echo")

    def test_echo_json(self):
        r = requests.post(f"{self.base}/echo", json={
            "sum": [1,2,3]
        })
        self.assertEqual(r.status_code, 200)
        self.assertDictEqual(r.json(), {"sum": [1,2,3]})

