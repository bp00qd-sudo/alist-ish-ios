//go:build ios

// Package fuse is intentionally a no-op on iOS. iOS does not permit mounting
// a user-space filesystem from an application process, but keeping a small
// package stub lets the complete upstream module be inspected with `go list`.
package fuse
