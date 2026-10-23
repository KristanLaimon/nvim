"""FoxQuerier JSON-lines driver. Secrets/SQL travel on stdin, never argv or disk."""

import base64
import datetime
import decimal
import importlib
import json
from pathlib import Path
import queue
import re
import sqlite3
import sys
import threading
import time
import uuid


def lex(sql, engine):
    """Return (kind, text, start, end); reject unfinished input before execution."""
    result, i = [], 0
    while i < len(sql):
        start, char = i, sql[i]
        if char.isspace():
            i += 1
            continue
        if sql.startswith("--", i) or engine.startswith("mysql") and char == "#":
            end = sql.find("\n", i)
            i = len(sql) if end < 0 else end + 1
            continue
        if sql.startswith("/*", i):
            # MySQL executable comments must not bypass the statement guard.
            if sql.startswith(("/*!", "/*M!"), i):
                raise ValueError("Executable SQL comments are not supported")
            depth, i = 1, i + 2
            while i < len(sql) and depth:
                if sql.startswith("/*", i):
                    depth, i = depth + 1, i + 2
                elif sql.startswith("*/", i):
                    depth, i = depth - 1, i + 2
                else:
                    i += 1
            if depth:
                raise ValueError("Unfinished SQL comment")
            continue
        tag = re.match(r"\$(?:[A-Za-z_][A-Za-z_0-9]*)?\$", sql[i:]) if engine == "postgres" else None
        if tag:
            end = sql.find(tag[0], i + len(tag[0]))
            if end < 0:
                raise ValueError("Unfinished dollar-quoted SQL")
            i = end + len(tag[0])
            result.append(("string", sql[start:i], start, i))
            continue
        if char in "'\"`[":
            closing, i = ("]" if char == "[" else char), i + 1
            while i < len(sql):
                if sql[i] == closing:
                    if sql[i:i + 2] == closing * 2:
                        i += 2
                    else:
                        i += 1
                        break
                elif sql[i] == "\\" and char == "'" and (engine == "mysql" or engine == "postgres" and start > 0 and sql[start - 1].lower() == "e"):
                    i += 2
                else:
                    i += 1
            else:
                raise ValueError("Unfinished SQL quote")
            result.append(("string" if char == "'" else "identifier", sql[start:i], start, i))
            continue
        word = re.match(r"[A-Za-z_][A-Za-z_0-9$]*|[0-9]+(?:\.[0-9]+)?", sql[i:])
        if word:
            i += len(word[0])
            result.append(("word", word[0], start, i))
        else:
            i += 1
            result.append(("symbol", char, start, i))
    return result


def prepare(sql, engine):
    if not isinstance(sql, str) or len(sql.encode("utf-8")) > 1024 * 1024:
        raise ValueError("SQL must be text of at most 1 MiB")
    tokens, statements, first, depth = lex(sql, engine), [], 0, 0
    forbidden = {"INSERT", "UPDATE", "DELETE", "MERGE", "CREATE", "ALTER", "DROP", "TRUNCATE", "ATTACH", "DETACH", "PRAGMA", "COPY", "CALL", "DO", "SET", "RESET", "INTO", "LOCK", "UNLOCK", "GRANT", "REVOKE", "VACUUM", "ANALYZE", "ANALYSE", "LOAD"}
    for token in tokens:
        kind, value, start, end = token
        if kind == "word" and value.upper() in forbidden:
            raise ValueError("Read-only querying only; unsupported operation: " + value.upper())
        if value == "(":
            depth += 1
        elif value == ")":
            depth -= 1
            if depth < 0:
                raise ValueError("Unbalanced SQL parentheses")
        elif value == ";":
            if depth:
                raise ValueError("Unsupported SQL statement body")
            statements.append(sql[first:start])
            first = end
    if depth:
        raise ValueError("Unbalanced SQL parentheses")
    statements.append(sql[first:])
    prepared = []
    for statement in statements:
        parts = lex(statement, engine)
        if not parts:
            continue
        if parts[0][0] != "word" or parts[0][1].upper() not in {"SELECT", "WITH", "EXPLAIN"}:
            raise ValueError("Only SELECT, read-only WITH, and EXPLAIN are supported")
        positions = []
        for index, part in enumerate(parts):
            if part[1] != "?" or part[0] != "symbol":
                continue
            prev = parts[index - 1] if index else None
            following = parts[index + 1] if index + 1 < len(parts) else None
            if engine == "postgres":
                if following and following[1] in {"|", "&"}:
                    continue
                # JSON existence operator has a value on its left. A placeholder
                # follows an operator, comma, parenthesis, or expression keyword.
                if prev and (prev[0] in {"identifier", "string"} or prev[1] in {")", "]"} or prev[0] == "word" and prev[1].upper() not in {"SELECT", "WHERE", "AND", "OR", "WHEN", "THEN", "ELSE", "LIMIT", "OFFSET", "BY", "AS", "DISTINCT", "BETWEEN", "LIKE", "ILIKE", "IS", "IN"}):
                    continue
            if following and following[2] == part[3] and following[1].isdigit():
                raise ValueError("Use plain ? placeholders, not numbered placeholders")
            positions.append((part[2], part[3]))
        prepared.append((statement, positions))
    if not prepared:
        raise ValueError("No SQL statements to execute")
    if len(prepared) > 100:
        raise ValueError("At most 100 statements per run")
    return prepared


def bound_sql(statement, positions, engine):
    if engine == "sqlite" or not positions:
        return statement
    result, first = [], 0
    for start, end in positions:
        result.extend((statement[first:start].replace("%", "%%"), "%s"))
        first = end
    result.append(statement[first:].replace("%", "%%"))
    return "".join(result)


def value_json(value):
    if value is None or isinstance(value, (str, bool)):
        return value
    if isinstance(value, bytes):
        return {"type": "binary", "base64": base64.b64encode(value[:4096]).decode(), "bytes": len(value)}
    if isinstance(value, (datetime.date, datetime.time, datetime.datetime)):
        return value.isoformat()
    if isinstance(value, (int, float, decimal.Decimal)):
        return str(value)  # Preserve precision through Lua/JSON.
    if isinstance(value, (dict, list)):
        return value
    return str(value)


class Driver:
    def __init__(self):
        self.connection = None
        self.profile = None
        self.canceled = threading.Event()

    def connect(self, profile, root):
        self.close()
        if profile.get("engine") not in {"sqlite", "mysql", "postgres"}:
            raise ValueError("Choose sqlite, mysql, or postgres")
        self.profile, engine = dict(profile), profile["engine"]
        self.syntax = engine
        self.canceled.clear()
        if engine == "sqlite":
            path = Path(profile["path"])
            if not path.is_absolute():
                path = Path(root) / path
            path = path.resolve(strict=True)
            if not path.is_file():
                raise ValueError("SQLite path must be an existing file")
            con = sqlite3.connect(path.as_uri() + "?mode=ro", uri=True, check_same_thread=False)
            con.execute("PRAGMA query_only = ON")
            allowed_pragmas = {"table_info", "table_xinfo", "foreign_key_list", "index_list", "index_info"}

            def authorizer(action, arg1, _arg2, _db, _source):
                if action in {sqlite3.SQLITE_ATTACH, sqlite3.SQLITE_DETACH}:
                    return sqlite3.SQLITE_DENY
                if action == sqlite3.SQLITE_PRAGMA and arg1.lower() not in allowed_pragmas:
                    return sqlite3.SQLITE_DENY
                return sqlite3.SQLITE_OK

            con.set_authorizer(authorizer)
            version = sqlite3.sqlite_version
        elif engine == "mysql":
            pymysql = importlib.import_module("pymysql")
            options = {key: profile[key] for key in ("host", "port", "database", "user", "password") if key in profile}
            options.update(charset="utf8mb4", connect_timeout=10, read_timeout=30, write_timeout=10, autocommit=True, local_infile=False)
            if profile.get("ssl_ca"):
                options.update(ssl_ca=profile["ssl_ca"], ssl_verify_cert=True, ssl_verify_identity=True)
            con = pymysql.connect(**options)
            try:
                with con.cursor() as cursor:
                    cursor.execute("SET SESSION TRANSACTION READ ONLY")
                    cursor.execute("SELECT VERSION(), @@SESSION.sql_mode")
                    version, sql_mode = cursor.fetchone()
                    if "NO_BACKSLASH_ESCAPES" in sql_mode.split(","):
                        self.syntax = "mysql-no-backslash"
                self.mysql_options = options
            except Exception:
                con.close()
                raise ValueError("Could not enforce a read-only MySQL session; verify server compatibility and restricted credentials") from None
        else:
            psycopg = importlib.import_module("psycopg")
            options = {key: profile[key] for key in ("host", "port", "user", "password", "sslmode", "sslrootcert") if key in profile}
            options.update(dbname=profile.get("database"), connect_timeout=10, autocommit=True)
            con = psycopg.connect(**options)
            schemas = profile.get("schemas") or [profile.get("schema", "public")]
            con.execute(psycopg.sql.SQL("SET search_path TO {}").format(psycopg.sql.SQL(",").join(psycopg.sql.Identifier(schema) for schema in schemas)))
            con.autocommit = False
            con.read_only = True
            version = str(con.info.server_version)
        self.connection = con
        return {"version": version, "read_only": "engine-enforced read-only; use restricted credentials", "engine": engine, "syntax": self.syntax}

    def cancel(self):
        self.canceled.set()
        con = self.connection
        if con is None:
            return
        try:
            if self.profile["engine"] == "sqlite":
                con.interrupt()
            elif self.profile["engine"] == "postgres":
                con.cancel()
            else:
                pymysql = importlib.import_module("pymysql")
                with pymysql.connect(**self.mysql_options) as control:
                    with control.cursor() as cursor:
                        cursor.execute("KILL QUERY %s", (con.thread_id(),))
        except Exception:
            pass  # The final response requires disconnect even if cancellation cannot be verified.

    def close(self):
        con, self.connection = self.connection, None
        if con is not None:
            try:
                con.close()
            except Exception:
                pass

    def rows(self, sql, args=()):
        if self.canceled.is_set():
            raise ValueError("Canceled; reconnect before using the session")
        cursor = self.connection.cursor()
        try:
            cursor.execute(sql, args)
            rows = cursor.fetchmany(20001)
            if len(rows) > 20000:
                raise ValueError("Metadata exceeds 20,000 objects; narrow the selected database/schema")
            return rows
        finally:
            cursor.close()

    def metadata(self):
        engine, database = self.profile["engine"], self.profile.get("database")
        tables, relations = {}, {}
        if engine == "sqlite":
            for name, kind in self.rows("SELECT name, type FROM sqlite_master WHERE type IN ('table','view') AND name NOT LIKE 'sqlite_%' ORDER BY name"):
                escaped = '"' + name.replace('"', '""') + '"'
                columns = [{"name": r[1], "type": r[2], "nullable": not bool(r[3]), "default": r[4], "pk": bool(r[5]), "pk_order": r[5]} for r in self.rows("PRAGMA table_info(" + escaped + ")")]
                indexes = [{"name": r[1], "unique": bool(r[2])} for r in self.rows("PRAGMA index_list(" + escaped + ")")]
                tables[name] = {"key": name, "name": name, "kind": kind, "columns": columns, "indexes": indexes}
                for row in self.rows("PRAGMA foreign_key_list(" + escaped + ")"):
                    key = name + ":" + str(row[0])
                    relation = relations.setdefault(key, {"name": key, "source": name, "target": row[2], "columns": []})
                    relation["columns"].append({"source": row[3], "target": row[4]})
            for relation in relations.values():
                target = tables.get(relation["target"], {})
                pk = [c["name"] for c in sorted(target.get("columns", []), key=lambda c: c["pk_order"]) if c["pk"]]
                for index, column in enumerate(relation["columns"]):
                    if column["target"] is None and index < len(pk):
                        column["target"] = pk[index]
        elif engine == "mysql":
            for schema, name, kind in self.rows("SELECT TABLE_SCHEMA,TABLE_NAME,TABLE_TYPE FROM information_schema.TABLES WHERE TABLE_SCHEMA=%s ORDER BY TABLE_NAME", (database,)):
                key = schema + "." + name
                tables[key] = {"key": key, "schema": schema, "name": name, "kind": kind, "columns": []}
            for schema, name, column, kind, nullable, default, key in self.rows("SELECT TABLE_SCHEMA,TABLE_NAME,COLUMN_NAME,COLUMN_TYPE,IS_NULLABLE,COLUMN_DEFAULT,COLUMN_KEY FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=%s ORDER BY TABLE_NAME,ORDINAL_POSITION", (database,)):
                table = tables.get(schema + "." + name)
                if table:
                    table["columns"].append({"name": column, "type": kind, "nullable": nullable == "YES", "default": default, "pk": key == "PRI"})
            for schema, table, constraint, column, target_schema, target, target_column in self.rows("SELECT TABLE_SCHEMA,TABLE_NAME,CONSTRAINT_NAME,COLUMN_NAME,REFERENCED_TABLE_SCHEMA,REFERENCED_TABLE_NAME,REFERENCED_COLUMN_NAME FROM information_schema.KEY_COLUMN_USAGE WHERE TABLE_SCHEMA=%s AND REFERENCED_TABLE_NAME IS NOT NULL ORDER BY TABLE_NAME,CONSTRAINT_NAME,ORDINAL_POSITION", (database,)):
                key = schema + "." + table + ":" + constraint
                relation = relations.setdefault(key, {"name": constraint, "source": schema + "." + table, "target": target_schema + "." + target, "columns": []})
                relation["columns"].append({"source": column, "target": target_column})
            for table, name, non_unique, column in self.rows("SELECT TABLE_NAME,INDEX_NAME,NON_UNIQUE,COLUMN_NAME FROM information_schema.STATISTICS WHERE TABLE_SCHEMA=%s ORDER BY TABLE_NAME,INDEX_NAME,SEQ_IN_INDEX", (database,)):
                item = tables.get(database + "." + table)
                if item:
                    item.setdefault("indexes", []).append({"name": name, "unique": not bool(non_unique), "column": column})
        else:
            schemas = self.profile.get("schemas") or [self.profile.get("schema", "public")]
            for schema in schemas:
                for name, kind in self.rows("SELECT table_name,table_type FROM information_schema.tables WHERE table_schema=%s ORDER BY table_name", (schema,)):
                    key = schema + "." + name
                    tables[key] = {"key": key, "schema": schema, "name": name, "kind": kind, "columns": []}
                for name, column, kind, nullable, default in self.rows("SELECT table_name,column_name,data_type,is_nullable,column_default FROM information_schema.columns WHERE table_schema=%s ORDER BY table_name,ordinal_position", (schema,)):
                    table = tables.get(schema + "." + name)
                    if table:
                        table["columns"].append({"name": column, "type": kind, "nullable": nullable == "YES", "default": default})
                for table, column in self.rows("SELECT tc.table_name,kcu.column_name FROM information_schema.table_constraints tc JOIN information_schema.key_column_usage kcu USING(constraint_catalog,constraint_schema,constraint_name,table_catalog,table_schema,table_name) WHERE tc.table_schema=%s AND tc.constraint_type='PRIMARY KEY'", (schema,)):
                    for item_column in tables.get(schema + "." + table, {}).get("columns", []):
                        if item_column["name"] == column:
                            item_column["pk"] = True
                for table, index_name, definition in self.rows("SELECT tablename,indexname,indexdef FROM pg_catalog.pg_indexes WHERE schemaname=%s", (schema,)):
                    item = tables.get(schema + "." + table)
                    if item:
                        item.setdefault("indexes", []).append({"name": index_name, "definition": definition})
                query = """SELECT tc.table_name,tc.constraint_name,kcu.column_name,ccu.table_schema,ccu.table_name,ccu.column_name
                    FROM information_schema.table_constraints tc
                    JOIN information_schema.key_column_usage kcu ON tc.constraint_catalog=kcu.constraint_catalog AND tc.constraint_schema=kcu.constraint_schema AND tc.constraint_name=kcu.constraint_name AND tc.table_name=kcu.table_name
                    JOIN information_schema.referential_constraints rc ON tc.constraint_catalog=rc.constraint_catalog AND tc.constraint_schema=rc.constraint_schema AND tc.constraint_name=rc.constraint_name
                    JOIN information_schema.key_column_usage ccu ON rc.unique_constraint_catalog=ccu.constraint_catalog AND rc.unique_constraint_schema=ccu.constraint_schema AND rc.unique_constraint_name=ccu.constraint_name AND ccu.ordinal_position=kcu.position_in_unique_constraint
                    WHERE tc.table_schema=%s AND tc.constraint_type='FOREIGN KEY' ORDER BY tc.table_name,tc.constraint_name,kcu.ordinal_position"""
                for table, constraint, column, target_schema, target, target_column in self.rows(query, (schema,)):
                    key = schema + "." + table + ":" + constraint
                    relation = relations.setdefault(key, {"name": constraint, "source": schema + "." + table, "target": target_schema + "." + target, "columns": []})
                    relation["columns"].append({"source": column, "target": target_column})
        return {"engine": engine, "syntax": self.syntax, "tables": list(tables.values()), "relations": list(relations.values()), "updated_at": int(time.time()), "coverage": "visible objects only; permissions may hide relationships"}

    def execute(self, sql, params, emit, request_id):
        engine = self.profile["engine"]
        statements = prepare(sql, self.syntax)
        if len(params) != sum(len(p) for _, p in statements):
            raise ValueError("Parameter count does not match SQL")
        self.canceled.clear()
        sets, offset, total_bytes, total_rows = [], 0, 0, 0
        for statement, positions in statements:
            if self.canceled.is_set():
                raise ValueError("Canceled; reconnect before running SQL")
            query = bound_sql(statement, positions, engine)
            args, offset = params[offset:offset + len(positions)], offset + len(positions)
            if engine == "mysql":
                cursor = self.connection.cursor(importlib.import_module("pymysql.cursors").SSCursor)
            elif engine == "postgres" and not statement.lstrip().upper().startswith("EXPLAIN"):
                cursor = self.connection.cursor(name="fox_" + uuid.uuid4().hex)
            else:
                cursor = self.connection.cursor()
            truncated = False
            try:
                cursor.execute(query, tuple(args) if positions else None) if engine != "sqlite" else cursor.execute(query, args)
                columns = [item[0] for item in cursor.description or []]
                rows, strings = [], []
                while cursor.description and not self.canceled.is_set():
                    row = cursor.fetchone()
                    if row is None:
                        break
                    encoded = [value_json(value) for value in row]
                    size = len(json.dumps(encoded, ensure_ascii=False).encode("utf-8"))
                    if total_rows >= 1000 or total_bytes + size > 8 * 1024 * 1024:
                        truncated = True
                        break
                    strings.append([isinstance(value, str) for value in row])
                    rows.append(encoded)
                    total_rows, total_bytes = total_rows + 1, total_bytes + size
                    if len(rows) % 100 == 0:
                        emit({"id": request_id, "event": "fetching", "rows": total_rows})
                sets.append({"columns": columns, "rows": rows, "strings": strings, "truncated": truncated})
            finally:
                if engine == "mysql" and (truncated or self.canceled.is_set()):
                    self.close()  # An unbuffered cursor must not drain an unbounded remainder.
                else:
                    cursor.close()
            if truncated:
                break
        if engine == "postgres" and self.connection:
            self.connection.rollback()
        if self.canceled.is_set():
            self.close()
            raise ValueError("Canceled; reconnect before running SQL")
        return {"sets": sets, "disconnected": self.connection is None}


def main():
    # JSONL is UTF-8 on both ends, regardless of the Windows console code page.
    sys.stdin.reconfigure(encoding="utf-8")
    sys.stdout.reconfigure(encoding="utf-8")
    driver, requests, output_lock = Driver(), queue.Queue(), threading.Lock()

    def emit(message):
        with output_lock:
            sys.stdout.write(json.dumps(message, ensure_ascii=False, default=value_json) + "\n")
            sys.stdout.flush()

    def worker():
        for request in iter(requests.get, None):
            timer = None
            try:
                operation = request.get("op")
                if operation in {"metadata", "execute"}:
                    timer = threading.Timer(30, driver.cancel)
                    timer.daemon = True
                    timer.start()
                if operation == "connect":
                    result = driver.connect(request["profile"], request["root"])
                elif operation == "disconnect":
                    driver.close()
                    result = {}
                elif driver.connection is None:
                    raise ValueError("Connect first")
                elif operation == "metadata":
                    result = driver.metadata()
                elif operation == "prepare":
                    prepared = prepare(request["sql"], driver.syntax)
                    result = {"parameters": sum(len(p) for _, p in prepared), "statements": len(prepared)}
                elif operation == "execute":
                    result = driver.execute(request["sql"], request.get("params", []), emit, request["id"])
                else:
                    raise ValueError("Unknown driver operation")
                emit({"id": request["id"], "result": result})
            except Exception as error:
                # Diagnostics can contain values; the Query UI keeps them in RAM.
                safe = str(error) if isinstance(error, (ValueError, FileNotFoundError, ModuleNotFoundError)) else "Database operation failed (" + type(error).__name__ + "); check SQL, connection, permissions, and server compatibility"
                if driver.canceled.is_set():
                    safe = "Canceled or timed out; reconnect before running SQL"
                if driver.connection and driver.profile["engine"] == "postgres":
                    try:
                        driver.connection.rollback()
                    except Exception:
                        driver.close()
                if driver.canceled.is_set():
                    driver.close()
                emit({"id": request.get("id"), "error": safe, "error_detail": str(error) if request.get("op") == "execute" else None, "disconnected": driver.connection is None})
            finally:
                if timer:
                    timer.cancel()

    threading.Thread(target=worker, daemon=True).start()
    try:
        for line in sys.stdin:
            if len(line) > 2 * 1024 * 1024:
                emit({"error": "Driver request is too large"})
                continue
            request = json.loads(line)
            if request.get("op") == "cancel":
                threading.Thread(target=driver.cancel, daemon=True).start()
            else:
                requests.put(request)
    finally:
        driver.cancel()
        driver.close()


if __name__ == "__main__":
    main()
