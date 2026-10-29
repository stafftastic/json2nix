package main

import (
	"flag"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

var update = flag.Bool("update", false, "rewrite the golden files in testdata")

func TestGolden(t *testing.T) {
	inputs, err := filepath.Glob(filepath.Join("testdata", "*.json"))
	if err != nil {
		t.Fatal(err)
	}
	if len(inputs) == 0 {
		t.Fatal("no golden inputs in testdata")
	}

	for _, input := range inputs {
		name := strings.TrimSuffix(filepath.Base(input), ".json")
		t.Run(name, func(t *testing.T) {
			file, err := os.Open(input)
			if err != nil {
				t.Fatal(err)
			}
			defer file.Close()

			got, err := Convert(file)
			if err != nil {
				t.Fatal(err)
			}
			got += "\n"

			golden := strings.TrimSuffix(input, ".json") + ".nix"
			if *update {
				if err := os.WriteFile(golden, []byte(got), 0o644); err != nil {
					t.Fatal(err)
				}
			}

			want, err := os.ReadFile(golden)
			if err != nil {
				t.Fatal(err)
			}
			if got != string(want) {
				t.Errorf("%s:\ngot:  %s\nwant: %s", golden, got, want)
			}
		})
	}
}
