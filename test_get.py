from unittest import TestCase
from hashlib import sha256

import requests

class HttpGet(TestCase):
    def setUp(self):
        self.base = "http://localhost:7890"

    def test_get_text(self):
        r = requests.get(f"{self.base}/")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.text, "Welcome to Scryer Prolog!")

    def test_get_notfound(self):
        r = requests.get(f"{self.base}/non-existing")
        self.assertEqual(r.status_code, 404)
    
    def test_useragent_text(self):
        headers = {'User-Agent': 'test-suite/0.0.1'}
        r = requests.get(f"{self.base}/user-agent", headers=headers)
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.text, "test-suite/0.0.1")

    def test_parameters(self):
        r = requests.get(f"{self.base}/user/aarroyoc")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.text, "aarroyoc")

    def test_parameters_2(self):
        r = requests.get(f"{self.base}/user/mthom")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.text, "mthom")

    def test_redirect(self):
        r = requests.get(f"{self.base}/redirectme")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.text, "Welcome to Scryer Prolog!")

    def test_search(self):
        r = requests.get(f"{self.base}/search?q=backtracking")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.text, "Search term: backtracking")

    def test_multiple_queries(self):
        r = requests.get(f"{self.base}/search?x=100&q=unification&y=450")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.text, "Search term: unification")

    def test_getfile(self):
        r = requests.get(f"{self.base}/file")
        self.assertEqual(r.status_code, 200)
        file = open("comuneros.jpg", "rb")
        h1 = sha256()
        h2 = sha256()
        h1.update(file.read())
        h2.update(r.content)
        self.assertEqual(h1.digest(), h2.digest())

    def test_urlencode(self):
        r = requests.get(f"{self.base}/search?q=adrián")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.text, "Search term: adrián")
