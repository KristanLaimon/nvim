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
	sql       string
	positions []int
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
	forbidden := " INSERT UPDATE DELETE MERGE CREATE ALTER DROP TRUNCATE ATTACH DETACH PRAGMA COPY CALL DO SET RESET INTO LOCK UNLOCK GRANT REVOKE VACUUM ANALYZE ANALYSE LOAD "
	pieces := []string{}
	first, depth := 0, 0
	for _, t := range tokens {
		if t.kind == "word" && strings.Contains(forbidden, " "+strings.ToUpper(t.text)+" ") {
			return nil, fmt.Errorf("Read-only querying only; unsupported operation: %s", strings.ToUpper(t.text))
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
			pieces = append(pieces, s[first:t.start])
			first = t.end
		}
	}
	if depth != 0 {
		return nil, fmt.Errorf("Unbalanced SQL parentheses")
	}
	pieces = append(pieces, s[first:])
	out := []statement{}
	for _, piece := range pieces {
		ts, _ := lex(piece, engine)
		if len(ts) == 0 {
			continue
		}
		if ts[0].kind != "word" || !strings.Contains(" SELECT WITH EXPLAIN ", " "+strings.ToUpper(ts[0].text)+" ") {
			return nil, fmt.Errorf("Only SELECT, read-only WITH, and EXPLAIN are supported")
		}
		st := statement{sql: piece}
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
