//go:build ignore

// Shared builder for build.ps1 and build.sh.
package main

import (
	"crypto/sha256"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
)

func main() {
	_, file, _, ok := runtime.Caller(0)
	if !ok {
		panic("Cannot find build directory")
	}
	root := filepath.Dir(file)
	if err := os.Chdir(root); err != nil {
		panic(err)
	}
	env := append(os.Environ(), "CGO_ENABLED=0", "GOTELEMETRY=off", "GOCACHE="+filepath.Join(root, ".cache", "build"), "GOPATH="+filepath.Join(root, ".cache", "go"))
	run := func(args []string, extra ...string) {
		cmd := exec.Command("go", args...)
		cmd.Env = append(env, extra...)
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		if err := cmd.Run(); err != nil {
			panic(err)
		}
	}
	if _, err := os.Stat(filepath.Join(root, "vendor", "modules.txt")); os.IsNotExist(err) {
		fmt.Println("Generating vendor dependencies from go.mod/go.sum...")
		run([]string{"mod", "vendor"})
	} else if err != nil {
		panic(err)
	} else {
		fmt.Println("Reusing vendor dependencies")
	}
	env = append(env, "GOPROXY=off", "GOSUMDB=off")
	run([]string{"test", "-mod=vendor", "./..."})
	output := filepath.Clean(filepath.Join(root, "..", "..", "foxquery"))
	if err := os.MkdirAll(output, 0755); err != nil {
		panic(err)
	}
	vendor := filepath.Join(root, "vendor")
	if err := filepath.WalkDir(vendor, func(path string, entry os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if entry.IsDir() || entry.Name() != "LICENSE" {
			return nil
		}
		relative, err := filepath.Rel(vendor, path)
		if err != nil {
			return err
		}
		destination := filepath.Join(output, "licenses", relative)
		if err = os.MkdirAll(filepath.Dir(destination), 0755); err != nil {
			return err
		}
		data, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		return os.WriteFile(destination, data, 0644)
	}); err != nil {
		panic(err)
	}
	license, err := os.ReadFile(filepath.Join(runtime.GOROOT(), "LICENSE"))
	if err != nil {
		panic(err)
	}
	if err = os.WriteFile(filepath.Join(output, "licenses", "Go-LICENSE"), license, 0644); err != nil {
		panic(err)
	}
	checksums := ""
	for _, platform := range []struct{ os, arch string }{{"windows", "amd64"}, {"linux", "amd64"}} {
		name := "foxquery-" + platform.os + "-" + platform.arch
		if platform.os == "windows" {
			name += ".exe"
		}
		path := filepath.Join(output, name)
		run([]string{"build", "-mod=vendor", "-trimpath", "-buildvcs=false", "-ldflags=-s -w -buildid=", "-o", path, "."}, "GOOS="+platform.os, "GOARCH="+platform.arch)
		b, err := os.ReadFile(path)
		if err != nil {
			panic(err)
		}
		checksums += fmt.Sprintf("%x  %s\n", sha256.Sum256(b), name)
		fmt.Println("Built", name)
	}
	if err := os.WriteFile(filepath.Join(output, "SHA256SUMS"), []byte(checksums), 0644); err != nil {
		panic(err)
	}
}
