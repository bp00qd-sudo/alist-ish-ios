// Copyright (c) The M1CPU Authors
// SPDX-License-Identifier: MPL-2.0

//go:build ios

package m1cpu

// iOS does not expose the macOS IOKit interfaces used by the upstream
// implementation. Keep the API available for packages such as gopsutil,
// while returning conservative values instead of linking desktop frameworks.
func IsAppleSilicon() bool { return true }
func PCoreHz() uint64 { return 0 }
func ECoreHz() uint64 { return 0 }
func PCoreGHz() float64 { return 0 }
func ECoreGHz() float64 { return 0 }
func PCoreCount() int { return 0 }
func ECoreCount() int { return 0 }
func PCoreCache() (int, int, int) { return 0, 0, 0 }
func ECoreCache() (int, int, int) { return 0, 0, 0 }
func ModelName() string { return "Apple Silicon (iOS)" }

