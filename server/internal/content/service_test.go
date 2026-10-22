package content

import "testing"

func TestValidPackName(t *testing.T) {
	valid := []string{"jobs", "beijing.env", "landmarks-0001", "v1_2"}
	for _, name := range valid {
		if !ValidPackName(name) {
			t.Errorf("应接受内容包名 %q", name)
		}
	}
	invalid := []string{"", ".hidden", "_tmp", "-tmp", "Upper", "a/b", "a b", "../x"}
	for _, name := range invalid {
		if ValidPackName(name) {
			t.Errorf("应拒绝内容包名 %q", name)
		}
	}
}
