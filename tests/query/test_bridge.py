import importlib.util
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import threading
import unittest

BRIDGE = Path(__file__).resolve().parents[2] / "scripts" / "query_bridge.py"
spec = importlib.util.spec_from_file_location("query_bridge", BRIDGE)
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class BridgeTests(unittest.TestCase):
    def setUp(self):
        scratch = BRIDGE.parents[1] / ".foxnvim" / "query" / "cache" / "tests"
        scratch.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=scratch)
        self.root = Path(self.temp.name)
        self.path = self.root / "fixture.db"
        with sqlite3.connect(self.path) as con:
            con.executescript("""
                CREATE TABLE customers(id INTEGER PRIMARY KEY, name TEXT);
                CREATE TABLE orders(id INTEGER PRIMARY KEY, customer_id INTEGER REFERENCES customers(id), total TEXT);
                INSERT INTO customers VALUES(1, 'Ada');
                INSERT INTO orders VALUES(10,1,'12345678901234567890.12');
            """)
        con.close()
        self.driver = bridge.Driver()
        self.driver.connect({"engine": "sqlite", "path": "fixture.db"}, self.root)

    def tearDown(self):
        self.driver.close()
        self.temp.cleanup()

    def execute(self, sql, params=()):
        return self.driver.execute(sql, list(params), lambda _event: None, 1)

    def test_metadata_contains_fk_without_reading_table_rows(self):
        data = self.driver.metadata()
        self.assertEqual({t["name"] for t in data["tables"]}, {"customers", "orders"})
        self.assertEqual(data["relations"][0]["columns"], [{"source": "customer_id", "target": "id"}])

    def test_real_binding_null_unicode_and_injection(self):
        malicious = "'; DROP TABLE customers; --"
        rows = self.execute("SELECT ?, ?, ?, ?, ?", [malicious, None, "", "á🦊", 9007199254740993])["sets"][0]["rows"]
        self.assertEqual(rows, [[malicious, None, "", "á🦊", "9007199254740993"]])
        self.assertEqual(self.execute("SELECT total FROM orders")["sets"][0]["rows"][0][0], "12345678901234567890.12")

    def test_batch_ignores_semicolons_and_question_marks_in_literals(self):
        result = self.execute("SELECT ';?' AS literal; -- ?\nSELECT ?", ["bound"])
        self.assertEqual(len(result["sets"]), 2)
        self.assertEqual(result["sets"][1]["rows"], [["bound"]])

    def test_rejects_writes_and_executable_comments_before_execution(self):
        for sql in ["DELETE FROM customers", "WITH x AS (SELECT 1) DELETE FROM orders", "SELECT 1 INTO OUTFILE 'x'", "/*! SELECT 1 */", "ATTACH 'x' AS x", "PRAGMA query_only=OFF"]:
            with self.subTest(sql=sql), self.assertRaises(ValueError):
                bridge.prepare(sql, "mysql")

    def test_readonly_is_enforced_by_database_even_without_classifier(self):
        with self.assertRaises(sqlite3.DatabaseError):
            self.driver.connection.execute("DELETE FROM orders")
        with self.assertRaises(sqlite3.DatabaseError):
            self.driver.connection.execute("ATTACH ':memory:' AS secret")

    def test_missing_sqlite_does_not_create_a_file(self):
        self.driver.close()
        with self.assertRaises(FileNotFoundError):
            self.driver.connect({"engine": "sqlite", "path": "absent.db"}, self.root)
        self.assertFalse((self.root / "absent.db").exists())

    def test_fetches_bounded_rows_and_cancels_long_query(self):
        result = self.execute("WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<5000) SELECT x FROM n")
        self.assertEqual(len(result["sets"][0]["rows"]), 1000)
        self.assertTrue(result["sets"][0]["truncated"])
        timer = threading.Timer(0.05, self.driver.cancel)
        timer.start()
        try:
            with self.assertRaises((sqlite3.OperationalError, ValueError)):
                self.execute("WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<100000000) SELECT sum(x) FROM n")
        finally:
            timer.cancel()

    def test_postgres_question_mark_operators_and_mysql_percent_binding(self):
        statements = bridge.prepare("SELECT doc ? 'name', doc ?| array['x'], ? FROM things WHERE id = ?", "postgres")
        self.assertEqual(len(statements[0][1]), 2)
        sql, positions = bridge.prepare("SELECT '50%', ?, 100 % 7", "mysql")[0]
        self.assertEqual(bridge.bound_sql(sql, positions, "mysql"), "SELECT '50%%', %s, 100 %% 7")
        self.assertEqual(len(bridge.prepare("SELECT $$?;$$, ?", "postgres")[0][1]), 1)

    def test_protocol_survives_errors_and_unicode_with_legacy_encoding(self):
        with sqlite3.connect(self.path) as con:
            con.execute("UPDATE customers SET name = ?", ["獣"])
        con.close()
        env = {**os.environ, "PYTHONIOENCODING": "cp1252", "PYTHONUTF8": "0"}
        proc = subprocess.Popen([sys.executable, "-u", "-B", str(BRIDGE)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, encoding="utf-8", cwd=self.root, env=env)
        try:
            def request(payload):
                proc.stdin.write(json.dumps(payload, ensure_ascii=False) + "\n")
                proc.stdin.flush()
                return json.loads(proc.stdout.readline())
            result = request({"id": 1, "op": "connect", "root": str(self.root), "profile": {"engine": "sqlite", "path": "fixture.db"}})
            self.assertIn("result", result)
            result = request({"id": 2, "op": "execute", "sql": "SELECT missing FROM orders", "params": []})
            self.assertIn("error", result)
            result = request({"id": 3, "op": "execute", "sql": "SELECT ?", "params": ["secret-value"]})
            self.assertEqual(result["result"]["sets"][0]["rows"], [["secret-value"]])
            result = request({"id": 4, "op": "execute", "sql": "SELECT name FROM customers", "params": []})
            self.assertEqual(result["result"]["sets"][0]["rows"], [["獣"]])
            result = request({"id": 5, "op": "execute", "sql": "SELECT '獣' AS \"名前\", ? AS bound", "params": ["á🦊獣"]})
            self.assertEqual(result["result"]["sets"][0]["columns"], ["名前", "bound"])
            self.assertEqual(result["result"]["sets"][0]["rows"], [["獣", "á🦊獣"]])
            self.assertEqual({p.name for p in self.root.iterdir()}, {"fixture.db"})
        finally:
            proc.stdin.close()
            proc.wait(timeout=5)
            proc.stdout.close()
            proc.stderr.close()


if __name__ == "__main__":
    unittest.main()
