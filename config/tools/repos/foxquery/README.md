# FoxQuery worker

The Lua editor uses this Go worker over UTF-8 JSON lines on stdin/stdout. SQL,
parameters, passwords, and full execution errors stay in memory. The bundled
executables include their runtime and drivers; no external database CLI,
SQLite library, or driver installation is required.

`go.mod`/`go.sum` pin source dependency versions. The build scripts generate
`vendor/` locally when missing, including dependency licenses, then reuse it.
Vendor source is Git-ignored to keep clones small. SQLite is embedded using
modernc.org/sqlite. MySQL/MariaDB use go-sql-driver/mysql and PostgreSQL uses pgx. MariaDB profiles
select `engine: "mysql"` and use the MySQL SQL dialect.
Go's runtime is compiled into each
executable with CGO disabled, including Linux builds without a libc dependency.

From this directory, with Go 1.24 or newer installed:

```powershell
.\build.ps1
```

```sh
bash build.sh
```

This runs tests and builds Windows and Linux executables for amd64
under `../../foxquery/`, then writes `SHA256SUMS`. The first build needs network
access unless the pinned dependencies are already cached. Later builds reuse
`vendor/` offline. After changing `go.mod`/`go.sum`, regenerate it with
`go mod vendor`; Go rejects stale vendor metadata. Only rebuilding requires Go.
The first Go invocation may initialize its toolchain cache; compiler and module
caches used by the shared builder are under `.cache/`.
Intermediate caches, `vendor/`, `dist/`, and generated `config/tools/foxquery/licenses/`
notices are ignored; source, module lockfiles, executables, and checksums belong
in Git. The builder copies those notices locally from dependencies and the Go toolchain.
On Linux the Lua launcher restores executable permissions if checkout did not
preserve them. macOS and 32-bit builds are
not included.

After the first build, run backend tests without rebuilding everything:

```sh
go test -mod=vendor ./...
```

`config/tests/query/fixture.db` is a committed SQLite test fixture. To regenerate it
after changing `fixture()` in `driver_test.go`, set `FOXQUERY_FIXTURE` to that
file's absolute path and run `go test -mod=vendor -run TestExportLuaFixture`.
Production code has no database creation or write operation.

The worker preserves the read-only guard, driver-bound `?` parameters, schema
metadata, 30-second deadline, cancellation, 1,000-row/8-MiB result caps, and
20,000-row metadata cap. SQLite also opens existing files read-only, enables
query-only mode, and disables attachments. MySQL/PostgreSQL use read-only
sessions. A capped MySQL stream is canceled and disconnected to avoid draining
unbounded results. Use restricted server credentials as before.

Profiles, saved queries, metadata caches, and local passwords keep their existing
formats. No user databases or project-private files are migrated or deleted.

Server connections still require network access and valid credentials; custom
CA files must exist on the destination PC. The portability guarantee here is
for FoxQuery, not every optional FoxVim language server or plugin.
