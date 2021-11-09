import subprocess
import time
from unittest import TestCase

import requests

class HttpPost(TestCase):
    @classmethod
    def setUpClass(cls):
        cls.base = "http://localhost:7890"
        cls.server = subprocess.Popen(["/home/aarroyoc/dev/scryer-prolog/target/release/scryer-prolog","-g", "run","server.pl"])
        time.sleep(10)

    @classmethod
    def tearDownClass(cls):
        cls.server.terminate()

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

    def test_form(self):
        r = requests.post(f"{self.base}/form", data={"key1": "value1", "key2": "value2"})
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.text, "value2")

