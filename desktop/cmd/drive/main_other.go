//go:build !darwin && !windows

// Command drive posts real input for tests of pointing; it runs on macOS
// and Windows only.
package main

import (
	"fmt"
	"os"
)

func main() {
	fmt.Fprintln(os.Stderr, "drive: macOS only")
	os.Exit(1)
}
