package main

import (
	"encoding/json"
	"fmt"
	"log"
	"os"
	"regexp"
	"strings"
	"slices"
)

func ToNixNil() string {
	return "null"
}

func ToNixBool(b bool) string {
	if b {
		return "true"
	}
	return "false"
}

func ToNixNumber(n json.Number) string {
	re := regexp.MustCompile(`^[^.]*e.*$`)
	if re.MatchString(n.String()) {
		return strings.Join(strings.Split(n.String(), "e"), ".e")
	}
	return n.String()
}

func ToNixString(s string) string {
	var sb strings.Builder

	sb.WriteString("\"")
	for i := 0; i < len(s); i++ {
		switch r := s[i]; r {
		case '\n':
			sb.WriteString("\\n")
		case '\r':
			sb.WriteString("\\r")
		case '\t':
			sb.WriteString("\\t")
		case '\\':
			sb.WriteString("\\\\")
		case '"':
			sb.WriteString("\\\"")
		case '$':
			if i+1 < len(s) && s[i+1] == '{' {
				sb.WriteString("\\${")
				i++
			} else {
				sb.WriteString("$")
			}
		default:
			sb.WriteString(fmt.Sprintf("%c", r))
		}
	}
	sb.WriteString("\"")

	return sb.String()
}

func ToNixArray(a []interface{}) (string, error) {
	var sb strings.Builder

	sb.WriteString("[")
	for i, v := range a {
		nix, err := ToNix(v)
		if err != nil {
			return sb.String(), err
		}
		if i != 0 {
			sb.WriteString(" ")
		}
		sb.WriteString(nix)
	}
	sb.WriteString("]")

	return sb.String(), nil
}

func ToNixIdentifier(s string) string {
	re := regexp.MustCompile(`^[a-zA-Z_][a-zA-Z0-9_'-]*$`)
	kws := []string{
		"assert",
		"else",
		"if",
		"in",
		"inherit",
		"let",
		"or",
		"rec",
		"then",
		"with",
	}
	if re.MatchString(s) && !slices.Contains(kws, s) {
		return s
	}
	return ToNixString(s)
}

func ToNixAttribute(k string, v interface{}) (string, error) {
	if m, ok := v.(map[string]interface{}); ok && len(m) == 1 {
		for mk, mv := range m {
			nix, err := ToNixAttribute(mk, mv)
			if err != nil {
				return "", err
			}
			return fmt.Sprintf("%s.%s", ToNixIdentifier(k), nix), nil
		}
	}
	nix, err := ToNix(v)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%s=%s;", ToNixIdentifier(k), nix), nil
}

func ToNixStringMap(m map[string]interface{}) (string, error) {
	var sb strings.Builder

	sb.WriteString("{")
	for k, v := range m {
		nix, err := ToNixAttribute(k, v)
		if err != nil {
			return sb.String(), err
		}
		sb.WriteString(nix)
	}
	sb.WriteString("}")

	return sb.String(), nil
}

func ToNix(data interface{}) (string, error) {
	switch v := data.(type) {
	case nil:
		return ToNixNil(), nil
	case bool:
		return ToNixBool(v), nil
	case json.Number:
		return ToNixNumber(v), nil
	case string:
		return ToNixString(v), nil
	case []interface{}:
		return ToNixArray(v)
	case map[string]interface{}:
		return ToNixStringMap(v)
	default:
		return "", fmt.Errorf("invalid type: %T", v)
	}
}

func main() {
	log.SetFlags(0)

	decoder := json.NewDecoder(os.Stdin)
	decoder.UseNumber()

	var data interface{}
	err := decoder.Decode(&data)
	if err != nil {
		log.Fatalf("Error while decoding JSON: %v", err.Error())
	}

	nix, err := ToNix(data)
	if err != nil {
		log.Fatalf("Error while encoding Nix: %v", err.Error())
	}

	fmt.Println(nix)
}
