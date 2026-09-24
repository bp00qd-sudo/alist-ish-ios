package driver

type Config struct {
	Name              string `json:"name"`
	LocalSort         bool   `json:"local_sort"`
	OnlyLocal         bool   `json:"only_local"`
	OnlyProxy         bool   `json:"only_proxy"`
	NoCache           bool   `json:"no_cache"`
	NoUpload          bool   `json:"no_upload"`
	NeedMs            bool   `json:"need_ms"` // if need get message from user, such as validate code
	DefaultRoot       string `json:"default_root"`
	CheckStatus       bool   `json:"-"`
	Alert             string `json:"alert"` //info,success,warning,danger
	// IOSSupported is false when a driver depends on a desktop-only facility.
	// It lets the native host keep upstream metadata without advertising an
	// operation that cannot work on the device.
	IOSSupported      bool   `json:"ios_supported"`
	NoOverwriteUpload bool   `json:"-"`     // whether to support overwrite upload
	ProxyRangeOption  bool   `json:"-"`
}

func (c Config) MustProxy() bool {
	return c.OnlyProxy || c.OnlyLocal
}
