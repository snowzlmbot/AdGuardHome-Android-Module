package main

import (
	"fmt"
	"os"
	"path/filepath"
)

// Same-directory rename makes the PID marker atomic; the parent directory must
// already exist and be trusted/private. No shell, and no symlink-following write.
func publishReady(path string) error {
	if path == "" {
		return nil
	}
	file, err := os.CreateTemp(filepath.Dir(path), ".dns-tproxy-ready-*")
	if err != nil {
		return err
	}
	temp := file.Name()
	defer os.Remove(temp)
	if _, err := fmt.Fprintf(file, "%d\n", os.Getpid()); err != nil {
		file.Close()
		return err
	}
	if err := file.Sync(); err != nil {
		file.Close()
		return err
	}
	if err := file.Close(); err != nil {
		return err
	}
	return os.Rename(temp, path)
}
func removeReady(path string) {
	if path != "" {
		os.Remove(path)
	}
}
