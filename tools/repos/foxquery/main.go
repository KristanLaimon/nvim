// FoxQuery JSON-lines worker. Credentials and SQL arrive only over stdin.
package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"sync"
	"time"
)

type request struct {
	ID      any     `json:"id"`
	Op      string  `json:"op"`
	Profile profile `json:"profile"`
	Root    string  `json:"root"`
	SQL     string  `json:"sql"`
	Params  []any   `json:"params"`
}

func serve(input io.Reader, output io.Writer) {
	var lock sync.Mutex
	enc := json.NewEncoder(output)
	emit := func(v any) { lock.Lock(); defer lock.Unlock(); _ = enc.Encode(v) }
	var cancelLock sync.Mutex
	var current context.CancelFunc
	cancel := func() {
		cancelLock.Lock()
		defer cancelLock.Unlock()
		if current != nil {
			current()
		}
	}
	requests := make(chan request)
	started := make(chan struct{})
	done := make(chan struct{})
	d := &driver{}
	go func() {
		defer close(done)
		defer d.close()
		for r := range requests {
			ctx, stop := context.WithTimeout(context.Background(), 30*time.Second)
			cancelLock.Lock()
			current = stop
			cancelLock.Unlock()
			started <- struct{}{}
			var result any
			var err error
			switch {
			case r.Op == "connect":
				result, err = d.connect(ctx, r.Profile, r.Root)
			case r.Op == "disconnect":
				d.close()
				result = object{}
			case d.conn == nil:
				err = fmt.Errorf("Connect first")
			case r.Op == "metadata":
				result, err = d.metadata(ctx)
			case r.Op == "prepare":
				var ss []statement
				ss, err = prepare(r.SQL, d.syntax)
				n := 0
				for _, s := range ss {
					n += len(s.positions)
				}
				result = object{"parameters": n, "statements": len(ss)}
			case r.Op == "execute":
				result, err = d.execute(ctx, r.SQL, r.Params, emit, r.ID)
			default:
				err = fmt.Errorf("Unknown driver operation")
			}
			canceled := ctx.Err() != nil
			if canceled && err == nil {
				err = ctx.Err()
			}
			cancelLock.Lock()
			current = nil
			cancelLock.Unlock()
			stop()
			if err != nil {
				safe := "Database operation failed; check SQL, connection, permissions, and server compatibility"
				if r.Op == "prepare" || r.Op == "connect" {
					safe = err.Error()
				}
				if canceled {
					d.close()
					safe = "Canceled or timed out; reconnect before running SQL"
				}
				response := object{"id": r.ID, "error": safe, "disconnected": d.conn == nil}
				if r.Op == "execute" {
					response["error_detail"] = err.Error()
				}
				emit(response)
			} else {
				emit(object{"id": r.ID, "result": result})
			}
		}
	}()
	scanner := bufio.NewScanner(input)
	scanner.Buffer(make([]byte, 4096), 2*1024*1024)
	for scanner.Scan() {
		var r request
		dec := json.NewDecoder(bytes.NewReader(scanner.Bytes()))
		dec.UseNumber()
		if err := dec.Decode(&r); err != nil {
			emit(object{"id": r.ID, "error": "Invalid driver request"})
			continue
		}
		if r.Op == "cancel" {
			cancel()
		} else {
			requests <- r
			<-started
		}
	}
	if scanner.Err() != nil {
		emit(object{"error": "Driver request is too large or unreadable"})
	}
	cancel()
	close(requests)
	<-done
}
func main() { serve(os.Stdin, os.Stdout) }
