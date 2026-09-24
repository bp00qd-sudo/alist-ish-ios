//go:build ios

package op

// Keep this list explicit and reviewable. Drivers not listed here are built
// normally; add a name when a future upstream driver needs FUSE, WinAPI, or an
// external process that is unavailable on iOS.
var iosUnsupportedDrivers = map[string]bool{}

func driverSupportedOnIOS(name string) bool {
	return !iosUnsupportedDrivers[name]
}
