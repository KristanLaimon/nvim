package main

import (
	"fmt"
	"regexp"
	"strings"
	"unicode"
)

type token struct {
	kind, text string
	start, end int
}
type statement struct {
	sql          string
	positions    []int
	confirmation bool
	autoSafe     bool
}

var word = regexp.MustCompile(`^[A-Za-z_][A-Za-z_0-9$]*|^[0-9]+(?:\.[0-9]+)?`)
var dollar = regexp.MustCompile(`^\$(?:[A-Za-z_][A-Za-z_0-9]*)?\$`)

func lex(s, engine string) ([]token, error) {
	out := []token{}
	for i := 0; i < len(s); {
		start := i
		c := s[i : i+1]
		if unicode.IsSpace(rune(s[i])) {
			i++
			continue
		}
		if strings.HasPrefix(s[i:], "--") || strings.HasPrefix(engine, "mysql") && c == "#" {
			for i < len(s) && s[i] != '\n' {
				i++
			}
			continue
		}
		if strings.HasPrefix(s[i:], "/*") {
			if strings.HasPrefix(s[i:], "/*!") || strings.HasPrefix(s[i:], "/*M!") {
				return nil, fmt.Errorf("Executable SQL comments are not supported")
			}
			depth := 1
			i += 2
			for i < len(s) && depth > 0 {
				if strings.HasPrefix(s[i:], "/*") {
					if engine != "postgres" {
						return nil, fmt.Errorf("Nested SQL comments are unsupported in this dialect")
					}
					depth++
					i += 2
				} else if strings.HasPrefix(s[i:], "*/") {
					depth--
					i += 2
				} else {
					i++
				}
			}
			if depth > 0 {
				return nil, fmt.Errorf("Unfinished SQL comment")
			}
			continue
		}
		if engine == "postgres" {
			if tag := dollar.FindString(s[i:]); tag != "" {
				end := strings.Index(s[i+len(tag):], tag)
				if end < 0 {
					return nil, fmt.Errorf("Unfinished dollar-quoted SQL")
				}
				i += len(tag)*2 + end
				out = append(out, token{"string", s[start:i], start, i})
				continue
			}
		}
		if strings.Contains("'\"`[", c) {
			close := c
			if c == "[" {
				close = "]"
			}
			i++
			done := false
			for i < len(s) {
				if s[i:i+1] == close {
					i++
					if i < len(s) && s[i:i+1] == close {
						i++
						continue
					}
					done = true
					break
				}
				if s[i] == '\\' && c == "'" && (engine == "mysql" || engine == "postgres" && start > 0 && strings.EqualFold(s[start-1:start], "e")) {
					i += 2
				} else {
					i++
				}
			}
			if !done {
				return nil, fmt.Errorf("Unfinished SQL quote")
			}
			kind := "identifier"
			if c == "'" {
				kind = "string"
			}
			out = append(out, token{kind, s[start:i], start, i})
			continue
		}
		if w := word.FindString(s[i:]); w != "" {
			i += len(w)
			out = append(out, token{"word", w, start, i})
		} else {
			i++
			out = append(out, token{"symbol", c, start, i})
		}
	}
	return out, nil
}

func prepare(s, engine string) ([]statement, error) {
	if len(s) > 1024*1024 {
		return nil, fmt.Errorf("SQL must be text of at most 1 MiB")
	}
	tokens, err := lex(s, engine)
	if err != nil {
		return nil, err
	}
	pieces := []string{}
	first, depth, block := 0, 0, 0
	create, trigger := false, false
	for _, t := range tokens {
		if t.kind == "word" && depth == 0 {
			w := strings.ToUpper(t.text)
			if t.start == tokens[0].start || first > 0 && !create && w == "CREATE" {
				create = w == "CREATE"
			}
			if create && w == "TRIGGER" {
				trigger = true
			}
			if trigger && (w == "BEGIN" || block > 0 && w == "CASE") {
				block++
			}
			if trigger && block > 0 && w == "END" {
				block--
			}
		}
		if t.kind != "symbol" {
			continue
		}
		switch t.text {
		case "(":
			depth++
		case ")":
			depth--
			if depth < 0 {
				return nil, fmt.Errorf("Unbalanced SQL parentheses")
			}
		case ";":
			if depth != 0 {
				return nil, fmt.Errorf("Unsupported SQL statement body")
			}
			if block == 0 {
				pieces = append(pieces, s[first:t.start])
				first, create, trigger = t.end, false, false
			}
		}
	}
	if depth != 0 || block != 0 {
		return nil, fmt.Errorf("Unbalanced SQL parentheses or trigger body")
	}
	pieces = append(pieces, s[first:])
	out := []statement{}
	for _, piece := range pieces {
		ts, _ := lex(piece, engine)
		if len(ts) == 0 {
			continue
		}
		st := statement{sql: piece, autoSafe: ts[0].kind == "word" && strings.EqualFold(ts[0].text, "SELECT")}
		// A nested WHERE does not limit the outer UPDATE or DELETE.
		level, mutation, where := 0, false, false
		triggerBody := false
		for _, t := range ts {
			if t.kind == "symbol" {
				if t.text == "(" {
					level++
				}
				if t.text == ")" {
					level--
				}
			}
			if t.kind != "word" {
				continue
			}
			w := strings.ToUpper(t.text)
			if w == "TRIGGER" {
				triggerBody = true
			}
			if strings.Contains(" INSERT UPDATE DELETE MERGE CREATE ALTER DROP TRUNCATE ATTACH DETACH PRAGMA COPY CALL DO SET RESET INTO LOCK UNLOCK GRANT REVOKE VACUUM ANALYZE ANALYSE LOAD ", " "+w+" ") {
				st.autoSafe = false
			}
			if strings.Contains(" DROP TRUNCATE ", " "+w+" ") {
				st.confirmation = true
			}
			if w == "UPDATE" || w == "DELETE" {
				if level != 0 || mutation || triggerBody {
					st.confirmation = true
				}
				mutation = true
				where = false
			}
			if mutation && w == "WHERE" && level == 0 {
				where = true
			}
		}
		if mutation && !where {
			st.confirmation = true
		}
		for i, t := range ts {
			if t.kind != "symbol" || t.text != "?" {
				continue
			}
			if engine == "postgres" {
				if i+1 < len(ts) && (ts[i+1].text == "|" || ts[i+1].text == "&") {
					continue
				}
				if i > 0 {
					p := ts[i-1]
					if p.kind == "identifier" || p.kind == "string" || p.text == ")" || p.text == "]" || p.kind == "word" && !strings.Contains(" SELECT WHERE AND OR WHEN THEN ELSE LIMIT OFFSET BY AS DISTINCT BETWEEN LIKE ILIKE IS IN ", " "+strings.ToUpper(p.text)+" ") {
						continue
					}
				}
			}
			if i+1 < len(ts) && ts[i+1].start == t.end && ts[i+1].text[0] >= '0' && ts[i+1].text[0] <= '9' {
				return nil, fmt.Errorf("Use plain ? placeholders, not numbered placeholders")
			}
			st.positions = append(st.positions, t.start)
		}
		out = append(out, st)
	}
	if len(out) == 0 {
		return nil, fmt.Errorf("No SQL statements to execute")
	}
	if len(out) > 100 {
		return nil, fmt.Errorf("At most 100 statements per run")
	}
	return out, nil
}
func boundSQL(s statement, engine string) string {
	if engine != "postgres" {
		return s.sql
	}
	var b strings.Builder
	first := 0
	for i, pos := range s.positions {
		b.WriteString(s.sql[first:pos])
		fmt.Fprintf(&b, "$%d", i+1)
		first = pos + 1
	}
	b.WriteString(s.sql[first:])
	return b.String()
}
