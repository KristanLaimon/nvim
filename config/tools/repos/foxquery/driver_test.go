package main

import (
	"bufio"
	"context"
	"database/sql"
	"encoding/json"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func fixture(t *testing.T) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "fixture.db")
	db, err := sql.Open("sqlite", path)
	if err != nil {
		t.Fatal(err)
	}
	_, err = db.Exec(`CREATE TABLE customers(id INTEGER PRIMARY KEY,name TEXT); CREATE TABLE orders(id INTEGER PRIMARY KEY,customer_id INTEGER REFERENCES customers,total TEXT); INSERT INTO customers VALUES(1,'Ada'); INSERT INTO orders VALUES(10,1,'12345678901234567890.12'); CREATE TABLE things(id INTEGER PRIMARY KEY,name TEXT); INSERT INTO things VALUES(1,'fox');`)
	if err != nil {
		t.Fatal(err)
	}
	if err = db.Close(); err != nil {
		t.Fatal(err)
	}
	return path
}
func connected(t *testing.T) *driver {
	t.Helper()
	d := &driver{}
	_, err := d.connect(context.Background(), profile{Engine: "sqlite", Path: fixture(t)}, "")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(d.close)
	return d
}
func execute(t *testing.T, d *driver, s string, p ...any) object {
	t.Helper()
	r, e := d.execute(context.Background(), s, p, func(any) {}, 1)
	if e != nil {
		t.Fatal(e)
	}
	return r.(map[string]any)
}
func TestSQLite(t *testing.T) {
	d := connected(t)
	m, e := d.metadata(context.Background())
	if e != nil {
		t.Fatal(e)
	}
	rels := m.(map[string]any)["relations"].([]object)
	if len(rels) != 1 || rels[0]["columns"].([]object)[0]["target"] != "id" {
		t.Fatal(m)
	}
	r := execute(t, d, "SELECT ?, ?, ?, ?, ?, 9007199254740993, 1.25, x'00ff'", "'; DROP TABLE customers; --", nil, "", "á🦊獣", json.Number("9007199254740993"))["sets"].([]resultSet)[0]
	if r.Rows[0][4] != "9007199254740993" || r.Rows[0][5] != "9007199254740993" || r.Rows[0][1] != nil || !r.Strings[0][0] || r.Strings[0][5] || r.Rows[0][7].(map[string]any)["base64"] != "AP8=" {
		t.Fatal(r)
	}
	if execute(t, d, "SELECT total FROM orders")["sets"].([]resultSet)[0].Rows[0][0] != "12345678901234567890.12" {
		t.Fatal("precision lost")
	}
	if _, e = d.conn.ExecContext(context.Background(), "DELETE FROM orders"); e == nil {
		t.Fatal("database allowed writes")
	}
	if _, e = d.conn.ExecContext(context.Background(), "ATTACH ':memory:' AS secret"); e == nil {
		t.Fatal("database allowed attachments")
	}
	if _, e = d.execute(context.Background(), "SELECT ?", nil, func(any) {}, 1); e == nil {
		t.Fatal("missing parameter allowed")
	}
}
func TestMissingFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "missing.db")
	d := &driver{}
	defer d.close()
	if _, e := d.connect(context.Background(), profile{Engine: "sqlite", Path: path}, ""); e == nil {
		t.Fatal("missing file accepted")
	}
	if _, e := os.Stat(path); !os.IsNotExist(e) {
		t.Fatal("missing database was created")
	}
}
func TestBoundsAndCancel(t *testing.T) {
	d := connected(t)
	r := execute(t, d, "WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<5000) SELECT x FROM n")["sets"].([]resultSet)[0]
	if len(r.Rows) != 1000 || !r.Truncated {
		t.Fatal(r)
	}
	r = execute(t, d, "SELECT printf('%.*c',9000000,'x')")["sets"].([]resultSet)[0]
	if len(r.Rows) != 0 || !r.Truncated {
		t.Fatal("byte cap failed")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Millisecond)
	defer cancel()
	_, err := d.execute(ctx, "WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<100000000) SELECT sum(x) FROM n", nil, func(any) {}, 1)
	if err == nil {
		t.Fatal("query was not canceled")
	}
}
func TestSQL(t *testing.T) {
	if _, err := prepare("SELECT 1 /* /* */ INTO OUTFILE 'x' -- */", "mysql"); err == nil {
		t.Fatal("nested comments bypassed the write guard")
	}
	if _, err := prepare("SELECT 1 /* outer /* inner */ outer */", "postgres"); err != nil {
		t.Fatal(err)
	}
	for _, s := range []string{"DELETE FROM customers", "WITH x AS (SELECT 1) DELETE FROM orders", "SELECT 1 INTO OUTFILE 'x'", "/*! SELECT 1 */", "ATTACH 'x' AS x", "PRAGMA query_only=OFF", "SELECT 'unfinished", "SELECT (1", "SELECT ?1"} {
		if _, e := prepare(s, "mysql"); e == nil {
			t.Fatal("accepted", s)
		}
	}
	ss, e := prepare("SELECT ';?' AS literal; -- ?\nSELECT ?", "sqlite")
	if e != nil || len(ss) != 2 || len(ss[1].positions) != 1 {
		t.Fatal(ss, e)
	}
	ss, e = prepare("SELECT doc ? 'name', doc ?| array['x'], ? FROM things WHERE id = ?", "postgres")
	if e != nil || len(ss[0].positions) != 2 || !strings.Contains(boundSQL(ss[0], "postgres"), "$2") {
		t.Fatal(ss, e)
	}
	ss, e = prepare("SELECT $$?;$$, ?", "postgres")
	if e != nil || len(ss[0].positions) != 1 {
		t.Fatal(ss, e)
	}
	ss, e = prepare("SELECT '50%', ?, 100 % 7", "mysql")
	if e != nil || boundSQL(ss[0], "mysql") != ss[0].sql {
		t.Fatal(ss, e)
	}
	if _, e = prepare("SELECT 1 AS \"(\"", "sqlite"); e != nil {
		t.Fatal(e)
	}
}
func TestProtocol(t *testing.T) {
	path := fixture(t)
	input, writer := io.Pipe()
	reader, output := io.Pipe()
	done := make(chan struct{})
	go func() { serve(input, output); output.Close(); close(done) }()
	t.Cleanup(func() { writer.Close(); reader.Close(); <-done })
	scan := bufio.NewScanner(reader)
	scan.Buffer(make([]byte, 4096), 1024*1024)
	request := func(r object) object {
		t.Helper()
		b, _ := json.Marshal(r)
		if _, e := writer.Write(append(b, '\n')); e != nil {
			t.Fatal(e)
		}
		if !scan.Scan() {
			t.Fatal("worker stopped", scan.Err())
		}
		var response object
		if e := json.Unmarshal(scan.Bytes(), &response); e != nil {
			t.Fatal(e)
		}
		return response
	}
	if r := request(object{"id": 1, "op": "connect", "profile": object{"engine": "sqlite", "path": path}}); r["error"] != nil {
		t.Fatal(r)
	}
	missing := "missing_" + strings.Repeat("x", 5000)
	r := request(object{"id": 2, "op": "execute", "sql": "SELECT * FROM " + quote(missing)})
	if !strings.Contains(text(r["error_detail"]), missing) {
		t.Fatal("diagnostics truncated", r)
	}
	r = request(object{"id": 3, "op": "execute", "sql": "SELECT ? AS \"名前\"", "params": []any{"á🦊獣"}})
	if r["error"] != nil || !strings.Contains(text(r["result"]), "á🦊獣") {
		t.Fatal(r)
	}
	// Cancellation must be read while the worker is still executing, even immediately after submission.
	_, err := io.WriteString(writer, "{\"id\":4,\"op\":\"execute\",\"sql\":\"WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<100000000) SELECT sum(x) FROM n\"}\n{\"op\":\"cancel\"}\n")
	if err != nil {
		t.Fatal(err)
	}
	if !scan.Scan() {
		t.Fatal("worker stopped during cancellation", scan.Err())
	}
	if err = json.Unmarshal(scan.Bytes(), &r); err != nil {
		t.Fatal(err)
	}
	if r["disconnected"] != true || !strings.Contains(text(r["error"]), "Canceled") {
		t.Fatal(r)
	}
	if r = request(object{"id": 5, "op": "connect", "profile": object{"engine": "sqlite", "path": path}}); r["error"] != nil {
		t.Fatal(r)
	}
}
func TestExportLuaFixture(t *testing.T) {
	if path := os.Getenv("FOXQUERY_FIXTURE"); path != "" {
		fixturePath := fixture(t)
		db, e := sql.Open("sqlite", fixturePath)
		if e != nil {
			t.Fatal(e)
		}
		if _, e = db.Exec("DROP TABLE orders; DROP TABLE customers; VACUUM"); e != nil {
			t.Fatal(e)
		}
		if e = db.Close(); e != nil {
			t.Fatal(e)
		}
		b, e := os.ReadFile(fixturePath)
		if e != nil {
			t.Fatal(e)
		}
		if e = os.WriteFile(path, b, 0644); e != nil {
			t.Fatal(e)
		}
	}
}
