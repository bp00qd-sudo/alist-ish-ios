package op

import (
	"testing"

	"github.com/alist-org/alist/v3/cmd/flags"
	"github.com/alist-org/alist/v3/internal/model"
)

func TestFixedAdminCredentials(t *testing.T) {
	previous := flags.FixedAdmin
	flags.FixedAdmin = true
	defer func() { flags.FixedAdmin = previous }()

	admin := &model.User{
		Username:  "changed",
		Role:      model.Roles{model.ADMIN},
		BasePath:  "/other",
		OtpSecret: "otp",
		Disabled:  true,
	}
	admin.SetPassword("changed")
	if !applyAdminDefaults(admin) {
		t.Fatal("expected the iOS admin policy to repair the account")
	}
	if admin.Username != "admin" || admin.ValidateRawPassword("admin") != nil {
		t.Fatal("admin/admin must remain valid")
	}
	if admin.OtpSecret != "" || admin.Disabled || admin.BasePath != "/" {
		t.Fatal("admin must remain enabled without a second login factor")
	}
	if applyAdminDefaults(admin) {
		t.Fatal("an unchanged admin account must not be rewritten")
	}
}
