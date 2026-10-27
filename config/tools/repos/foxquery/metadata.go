package main

import (
	"context"
	"fmt"
	"sort"
	"time"
)

type object = map[string]any

func (d *driver) rows(ctx context.Context, q string, args ...any) ([][]any, error) {
	st := statement{sql: q}
	for i, c := range q {
		if c == '?' {
			st.positions = append(st.positions, i)
		}
	}
	rows, err := d.conn.QueryContext(ctx, boundSQL(st, d.profile.Engine), args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	cols, err := rows.Columns()
	if err != nil {
		return nil, err
	}
	out := [][]any{}
	for rows.Next() {
		if len(out) >= 20000 {
			return nil, fmt.Errorf("Metadata exceeds 20,000 objects; narrow the selected database/schema")
		}
		r := make([]any, len(cols))
		dest := make([]any, len(cols))
		for i := range r {
			dest[i] = &r[i]
		}
		if err = rows.Scan(dest...); err != nil {
			return nil, err
		}
		for i, v := range r {
			if b, ok := v.([]byte); ok {
				r[i] = string(b)
			}
		}
		out = append(out, r)
	}
	return out, rows.Err()
}
func text(v any) string {
	if v == nil {
		return ""
	}
	return fmt.Sprint(v)
}
func yes(v any) bool { return text(v) != "0" && text(v) != "" && text(v) != "false" }
func (d *driver) metadata(ctx context.Context) (any, error) {
	tables := map[string]object{}
	relations := map[string]object{}
	query := func(q string, args ...any) ([][]any, error) { return d.rows(ctx, q, args...) }
	addRelation := func(key, name, source, target string, from, to any) {
		r := relations[key]
		if r == nil {
			r = object{"name": name, "source": source, "target": target, "columns": []object{}}
			relations[key] = r
		}
		r["columns"] = append(r["columns"].([]object), object{"source": from, "target": to})
	}
	if d.profile.Engine == "sqlite" {
		rs, e := query("SELECT name,type FROM sqlite_master WHERE type IN ('table','view') AND name NOT LIKE 'sqlite_%' ORDER BY name")
		if e != nil {
			return nil, e
		}
		for _, r := range rs {
			name := text(r[0])
			cols, e := query("PRAGMA table_info(" + quote(name) + ")")
			if e != nil {
				return nil, e
			}
			columns := []object{}
			for _, c := range cols {
				columns = append(columns, object{"name": c[1], "type": c[2], "nullable": !yes(c[3]), "default": c[4], "pk": yes(c[5]), "pk_order": c[5]})
			}
			indexes := []object{}
			idx, e := query("PRAGMA index_list(" + quote(name) + ")")
			if e != nil {
				return nil, e
			}
			for _, i := range idx {
				indexes = append(indexes, object{"name": i[1], "unique": yes(i[2])})
			}
			tables[name] = object{"key": name, "name": name, "kind": r[1], "columns": columns, "indexes": indexes}
			fks, e := query("PRAGMA foreign_key_list(" + quote(name) + ")")
			if e != nil {
				return nil, e
			}
			for _, f := range fks {
				key := name + ":" + text(f[0])
				addRelation(key, key, name, text(f[2]), f[3], f[4])
			}
		}
		for _, r := range relations {
			if target := tables[text(r["target"])]; target != nil {
				pk := []object{}
				for _, c := range target["columns"].([]object) {
					if c["pk"] == true {
						pk = append(pk, c)
					}
				}
				sort.Slice(pk, func(i, j int) bool { return pk[i]["pk_order"].(int64) < pk[j]["pk_order"].(int64) })
				for i, c := range r["columns"].([]object) {
					if c["target"] == nil && i < len(pk) {
						c["target"] = pk[i]["name"]
					}
				}
			}
		}
	} else {
		schemas := d.profile.Schemas
		if d.profile.Engine == "mysql" {
			schemas = []string{d.profile.Database}
		} else if len(schemas) == 0 {
			s := d.profile.Schema
			if s == "" {
				s = "public"
			}
			schemas = []string{s}
		}
		for _, schema := range schemas {
			rs, e := query("SELECT table_name,table_type FROM information_schema.tables WHERE table_schema=? ORDER BY table_name", schema)
			if e != nil {
				return nil, e
			}
			for _, r := range rs {
				key := schema + "." + text(r[0])
				tables[key] = object{"key": key, "schema": schema, "name": r[0], "kind": r[1], "columns": []object{}, "indexes": []object{}}
			}
			kind := "data_type"
			if d.profile.Engine == "mysql" {
				kind = "column_type"
			}
			rs, e = query("SELECT table_name,column_name,"+kind+",is_nullable,column_default FROM information_schema.columns WHERE table_schema=? ORDER BY table_name,ordinal_position", schema)
			if e != nil {
				return nil, e
			}
			for _, r := range rs {
				if t := tables[schema+"."+text(r[0])]; t != nil {
					t["columns"] = append(t["columns"].([]object), object{"name": r[1], "type": r[2], "nullable": text(r[3]) == "YES", "default": r[4]})
				}
			}
			rs, e = query("SELECT tc.table_name,kcu.column_name FROM information_schema.table_constraints tc JOIN information_schema.key_column_usage kcu USING(constraint_catalog,constraint_schema,constraint_name,table_catalog,table_schema,table_name) WHERE tc.table_schema=? AND tc.constraint_type='PRIMARY KEY'", schema)
			if e != nil {
				return nil, e
			}
			for _, r := range rs {
				if t := tables[schema+"."+text(r[0])]; t != nil {
					for _, c := range t["columns"].([]object) {
						if text(c["name"]) == text(r[1]) {
							c["pk"] = true
						}
					}
				}
			}
			if d.profile.Engine == "mysql" {
				rs, e = query("SELECT TABLE_NAME,CONSTRAINT_NAME,COLUMN_NAME,REFERENCED_TABLE_SCHEMA,REFERENCED_TABLE_NAME,REFERENCED_COLUMN_NAME FROM information_schema.KEY_COLUMN_USAGE WHERE TABLE_SCHEMA=? AND REFERENCED_TABLE_NAME IS NOT NULL ORDER BY TABLE_NAME,CONSTRAINT_NAME,ORDINAL_POSITION", schema)
			} else {
				// Joining information_schema key views can exceed the metadata timeout on PostgreSQL.
				rs, e = query(`SELECT src.relname, con.conname, sa.attname, tn.nspname, tgt.relname, ta.attname
FROM pg_catalog.pg_constraint con
JOIN pg_catalog.pg_class src ON src.oid=con.conrelid
JOIN pg_catalog.pg_namespace sn ON sn.oid=src.relnamespace
JOIN pg_catalog.pg_class tgt ON tgt.oid=con.confrelid
JOIN pg_catalog.pg_namespace tn ON tn.oid=tgt.relnamespace
CROSS JOIN LATERAL unnest(con.conkey,con.confkey) WITH ORDINALITY AS keys(source_att,target_att,position)
JOIN pg_catalog.pg_attribute sa ON sa.attrelid=src.oid AND sa.attnum=keys.source_att
JOIN pg_catalog.pg_attribute ta ON ta.attrelid=tgt.oid AND ta.attnum=keys.target_att
WHERE sn.nspname=? AND con.contype='f'
AND (has_table_privilege(src.oid,'SELECT') OR has_any_column_privilege(src.oid,'SELECT'))
AND (has_table_privilege(tgt.oid,'SELECT') OR has_any_column_privilege(tgt.oid,'SELECT'))
ORDER BY src.relname,con.conname,keys.position`, schema)
			}
			if e != nil {
				return nil, e
			}
			for _, r := range rs {
				key := schema + "." + text(r[0]) + ":" + text(r[1])
				addRelation(key, text(r[1]), schema+"."+text(r[0]), text(r[3])+"."+text(r[4]), r[2], r[5])
			}
			if d.profile.Engine == "mysql" {
				rs, e = query("SELECT TABLE_NAME,INDEX_NAME,NON_UNIQUE,COLUMN_NAME FROM information_schema.STATISTICS WHERE TABLE_SCHEMA=? ORDER BY TABLE_NAME,INDEX_NAME,SEQ_IN_INDEX", schema)
			} else {
				rs, e = query("SELECT tablename,indexname,indexdef FROM pg_catalog.pg_indexes WHERE schemaname=?", schema)
			}
			if e != nil {
				return nil, e
			}
			for _, r := range rs {
				if t := tables[schema+"."+text(r[0])]; t != nil {
					i := object{"name": r[1]}
					if d.profile.Engine == "mysql" {
						i["unique"] = !yes(r[2])
						i["column"] = r[3]
					} else {
						i["definition"] = r[2]
					}
					t["indexes"] = append(t["indexes"].([]object), i)
				}
			}
		}
	}
	ts, rs := []object{}, []object{}
	for _, t := range tables {
		ts = append(ts, t)
	}
	for _, r := range relations {
		rs = append(rs, r)
	}
	sort.Slice(ts, func(i, j int) bool { return text(ts[i]["key"]) < text(ts[j]["key"]) })
	sort.Slice(rs, func(i, j int) bool {
		return text(rs[i]["name"])+text(rs[i]["source"]) < text(rs[j]["name"])+text(rs[j]["source"])
	})
	return object{"tables": ts, "relations": rs, "engine": d.profile.Engine, "syntax": d.syntax, "updated_at": time.Now().Unix(), "coverage": "visible objects only; permissions may hide relationships"}, nil
}
