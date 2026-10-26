import json
import sqlite3
import tempfile
import unittest
from contextlib import closing
from pathlib import Path
from catalog import dispatch

class CatalogTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.database = Path(self.temp.name) / "catalog.sqlite"
        self.project = {"id": "project", "name": "Demo", "path": "demo.sfs.json", "hash": "123", "bible_version": 1, "references": [], "dependencies": []}

    def index(self):
        return dispatch(self.database, {"schema": 1, "command": "index", "project": self.project})

    def test_idempotent_upsert(self):
        self.index()
        self.project["name"] = "Updated"
        self.index()
        result = dispatch(self.database, {"schema": 1, "command": "list"})
        self.assertEqual(len(result["projects"]), 1)
        self.assertEqual(result["projects"][0]["name"], "Updated")

    def test_bound_sql_parameters(self):
        self.project["name"] = "'); DROP TABLE projects;--"
        self.index()
        self.assertEqual(dispatch(self.database, {"schema": 1, "command": "list"})["projects"][0]["name"], self.project["name"])

    def test_reference_allowlist(self):
        self.project["references"] = [{"id": "r", "sha256": "abc", "state": "partial", "name": "Study", "original_png": "secret bytes", "api_key": "not a real key"}]
        self.index()
        with closing(sqlite3.connect(self.database)) as con:
            data = json.loads(con.execute("SELECT metadata FROM refs").fetchone()[0])
        self.assertEqual(data, {"name": "Study"})

    def test_transaction_rollback(self):
        self.index()
        self.project["name"] = "Uncommitted"
        self.project["references"] = [{"id": "r", "sha256": "abc", "state": "invalid"}]
        with self.assertRaises(ValueError):
            self.index()
        self.assertEqual(dispatch(self.database, {"schema": 1, "command": "list"})["projects"][0]["name"], "Demo")

    def test_dependency_state_persists(self):
        self.project["dependencies"] = [{"source": "r", "target": "sprite", "stale": True}]
        self.index()
        with closing(sqlite3.connect(self.database)) as con:
            self.assertEqual(con.execute("SELECT stale FROM dependencies").fetchone()[0], 1)

    def test_protocol_rejected(self):
        with self.assertRaises(ValueError):
            dispatch(self.database, {"schema": 99, "command": "list"})

if __name__ == "__main__":
    unittest.main()
