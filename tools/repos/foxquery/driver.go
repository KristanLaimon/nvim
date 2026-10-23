package main

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/go-sql-driver/mysql"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/stdlib"
	"modernc.org/sqlite"
	sqlite3 "modernc.org/sqlite/lib"
)

type profile struct {
	Engine      string   `json:"engine"`
	Path        string   `json:"path"`
	Host        string   `json:"host"`
	Port        int      `json:"port"`
	Database    string   `json:"database"`
	User        string   `json:"user"`
	Password    string   `json:"password"`
	Schemas     []string `json:"schemas"`
	Schema      string   `json:"schema"`
	SSLMode     string   `json:"sslmode"`
	SSLRootCert string   `json:"sslrootcert"`
	SSLCA       string   `json:"ssl_ca"`
}
type driver struct {
	db      *sql.DB
	conn    *sql.Conn
	profile profile
	syntax  string
}

func (d *driver) close() {
	if d.conn != nil {
		d.conn.Close()
		d.conn = nil
	}
	if d.db != nil {
		d.db.Close()
		d.db = nil
	}
}
func (d *driver) connect(ctx context.Context, p profile, root string) (any, error) {
	d.close()
	d.profile = p
	d.syntax = p.Engine
	var db *sql.DB
	var err error
	switch p.Engine {
	case "sqlite":
		path := p.Path
		if !filepath.IsAbs(path) {
			path = filepath.Join(root, path)
		}
		path, err = filepath.Abs(path)
		if err != nil {
			return nil, err
		}
		info, e := os.Stat(path)
		if e != nil || !info.Mode().IsRegular() {
			return nil, fmt.Errorf("SQLite path must be an existing file")
		}
		path = filepath.ToSlash(path)
		if !strings.HasPrefix(path, "/") {
			path = "/" + path
		}
		u := url.URL{Scheme: "file", Path: path}
		db, err = sql.Open("sqlite", u.String()+"?mode=ro&_pragma=query_only(1)")
	case "mysql":
		cfg := mysql.NewConfig()
		cfg.User = p.User
		cfg.Passwd = p.Password
		cfg.DBName = p.Database
		cfg.Net = "tcp"
		host := p.Host
		if host == "" {
			host = "127.0.0.1"
		}
		port := p.Port
		if port == 0 {
			port = 3306
		}
		cfg.Addr = net.JoinHostPort(host, strconv.Itoa(port))
		cfg.Timeout = 10 * time.Second
		cfg.ReadTimeout = 30 * time.Second
		cfg.WriteTimeout = 10 * time.Second
		cfg.Params = map[string]string{"charset": "utf8mb4"}
		if p.SSLCA != "" {
			pem, e := os.ReadFile(p.SSLCA)
			if e != nil {
				return nil, fmt.Errorf("Cannot read MySQL CA certificate")
			}
			roots := x509.NewCertPool()
			if !roots.AppendCertsFromPEM(pem) {
				return nil, fmt.Errorf("Invalid MySQL CA certificate")
			}
			if e = mysql.RegisterTLSConfig("foxquery", &tls.Config{RootCAs: roots, ServerName: host, MinVersion: tls.VersionTLS12}); e != nil {
				return nil, e
			}
			cfg.TLSConfig = "foxquery"
		}
		db, err = sql.Open("mysql", cfg.FormatDSN())
	case "postgres":
		u := url.URL{Scheme: "postgres", User: url.UserPassword(p.User, p.Password), Path: p.Database}
		host := p.Host
		if host == "" {
			host = "127.0.0.1"
		}
		port := p.Port
		if port == 0 {
			port = 5432
		}
		u.Host = net.JoinHostPort(host, strconv.Itoa(port))
		q := url.Values{"connect_timeout": {"10"}}
		if p.SSLMode != "" {
			q.Set("sslmode", p.SSLMode)
		}
		if p.SSLRootCert != "" {
			q.Set("sslrootcert", p.SSLRootCert)
		}
		u.RawQuery = q.Encode()
		cfg, e := pgx.ParseConfig(u.String())
		if e != nil {
			return nil, fmt.Errorf("Invalid PostgreSQL connection settings")
		}
		db = stdlib.OpenDB(*cfg)
	default:
		return nil, fmt.Errorf("Choose sqlite, mysql, or postgres")
	}
	if err != nil {
		return nil, err
	}
	d.db = db
	db.SetMaxOpenConns(1)
	d.conn, err = db.Conn(ctx)
	if err != nil {
		d.close()
		return nil, fmt.Errorf("Database connection failed; check host, credentials, TLS, and permissions")
	}
	success := false
	defer func() {
		if !success {
			d.close()
		}
	}()
	version := ""
	switch p.Engine {
	case "sqlite":
		_, err = sqlite.Limit(d.conn, sqlite3.SQLITE_LIMIT_ATTACHED, 0)
		if err == nil {
			err = d.conn.QueryRowContext(ctx, "SELECT sqlite_version()").Scan(&version)
		}
	case "mysql":
		_, err = d.conn.ExecContext(ctx, "SET SESSION TRANSACTION READ ONLY")
		if err == nil {
			var mode string
			err = d.conn.QueryRowContext(ctx, "SELECT VERSION(), @@SESSION.sql_mode").Scan(&version, &mode)
			if strings.Contains(","+mode+",", ",NO_BACKSLASH_ESCAPES,") {
				d.syntax = "mysql-no-backslash"
			}
		}
	case "postgres":
		_, err = d.conn.ExecContext(ctx, "SET default_transaction_read_only = on")
		if err == nil {
			schemas := p.Schemas
			if len(schemas) == 0 {
				schema := p.Schema
				if schema == "" {
					schema = "public"
				}
				schemas = []string{schema}
			}
			quoted := []string{}
			for _, s := range schemas {
				quoted = append(quoted, quote(s))
			}
			_, err = d.conn.ExecContext(ctx, "SET search_path TO "+strings.Join(quoted, ","))
		}
		if err == nil {
			err = d.conn.QueryRowContext(ctx, "SHOW server_version").Scan(&version)
		}
	}
	if err != nil {
		return nil, fmt.Errorf("Could not enforce a read-only session; verify server compatibility and restricted credentials")
	}
	success = true
	return map[string]any{"engine": p.Engine, "syntax": d.syntax, "version": version, "read_only": "engine-enforced read-only; use restricted credentials"}, nil
}
func quote(s string) string { return `"` + strings.ReplaceAll(s, `"`, `""`) + `"` }
func valueJSON(v any, typ string) (any, bool) {
	if v == nil {
		return nil, false
	}
	switch x := v.(type) {
	case []byte:
		binary := typ == "" || strings.Contains(typ, "BLOB") || strings.Contains(typ, "BINARY") || typ == "BYTEA"
		if binary {
			n := len(x)
			if len(x) > 4096 {
				x = x[:4096]
			}
			return map[string]any{"type": "binary", "base64": base64.StdEncoding.EncodeToString(x), "bytes": n}, false
		}
		return string(x), isText(typ)
	case string:
		return x, isText(typ)
	case bool:
		return x, false
	case time.Time:
		return x.Format(time.RFC3339Nano), false
	default:
		return fmt.Sprint(x), false
	}
}
func isText(t string) bool {
	return t == "" || strings.Contains(t, "CHAR") || strings.Contains(t, "TEXT") || t == "NAME" || t == "UNKNOWN" || t == "VARCHAR"
}

type resultSet struct {
	Columns   []string `json:"columns"`
	Rows      [][]any  `json:"rows"`
	Strings   [][]bool `json:"strings"`
	Truncated bool     `json:"truncated"`
}

func (d *driver) execute(ctx context.Context, s string, params []any, emit func(any), id any) (any, error) {
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	statements, err := prepare(s, d.syntax)
	if err != nil {
		return nil, err
	}
	count := 0
	for _, st := range statements {
		count += len(st.positions)
	}
	if len(params) != count {
		return nil, fmt.Errorf("Parameter count does not match SQL")
	}
	for i, p := range params {
		if n, ok := p.(json.Number); ok {
			if v, e := n.Int64(); e == nil {
				params[i] = v
			} else if v, e := n.Float64(); e == nil {
				params[i] = v
			} else {
				return nil, fmt.Errorf("Invalid numeric parameter")
			}
		}
	}
	sets := []resultSet{}
	offset, totalRows, totalBytes := 0, 0, 0
	for _, st := range statements {
		rows, e := d.conn.QueryContext(ctx, boundSQL(st, d.profile.Engine), params[offset:offset+len(st.positions)]...)
		offset += len(st.positions)
		if e != nil {
			return nil, e
		}
		set := resultSet{Rows: [][]any{}, Strings: [][]bool{}}
		set.Columns, e = rows.Columns()
		if e != nil {
			rows.Close()
			return nil, e
		}
		types, e := rows.ColumnTypes()
		if e != nil {
			rows.Close()
			return nil, e
		}
		for rows.Next() {
			raw := make([]any, len(set.Columns))
			dest := make([]any, len(raw))
			for i := range raw {
				dest[i] = &raw[i]
			}
			if e = rows.Scan(dest...); e != nil {
				break
			}
			encoded := make([]any, len(raw))
			flags := make([]bool, len(raw))
			for i, v := range raw {
				encoded[i], flags[i] = valueJSON(v, strings.ToUpper(types[i].DatabaseTypeName()))
				if _, ok := v.(string); ok && d.profile.Engine == "sqlite" {
					flags[i] = true
				}
			}
			b, _ := json.Marshal(encoded)
			if totalRows >= 1000 || totalBytes+len(b) > 8*1024*1024 {
				set.Truncated = true
				break
			}
			set.Rows = append(set.Rows, encoded)
			set.Strings = append(set.Strings, flags)
			totalRows++
			totalBytes += len(b)
			if totalRows%100 == 0 {
				emit(map[string]any{"id": id, "event": "fetching", "rows": totalRows})
			}
		}
		if e == nil {
			e = rows.Err()
		}
		// Closing MySQL streaming rows drains them; discard the connection on a cap instead.
		if set.Truncated && d.profile.Engine == "mysql" {
			cancel()
		}
		rows.Close()
		if set.Truncated && d.profile.Engine == "mysql" {
			d.close()
		}
		if e != nil {
			return nil, e
		}
		sets = append(sets, set)
		if set.Truncated {
			break
		}
	}
	return map[string]any{"sets": sets, "disconnected": d.conn == nil}, nil
}
