package account

import "strings"

// NormalizeE164 turns the many ways a phone number arrives in SIP into +<country><number>.
//
//	"+44 7700 900123", "tel:+447700900123", "sip:+447700900123@x" -> +447700900123
//	"0044 7700 900123" -> +447700900123            (international prefix 00)
//	"011 1 555 0100 123" -> +15550100123           (North American international prefix 011)
//	"07700 900123" with countryCode "44" -> +447700900123   (national, leading 0 dropped)
//	"5550100123" with countryCode "1" -> +15550100123       (10-digit NANP national)
//
// When it can't tell (no country code for a national number, letters, too short), it returns
// the input with separators removed and ok=false; the caller decides whether to use it anyway.
func NormalizeE164(raw, countryCode string) (string, bool) {
	s := strings.TrimSpace(raw)
	for _, p := range []string{"tel:", "sip:", "sips:"} {
		if len(s) >= len(p) && strings.EqualFold(s[:len(p)], p) {
			s = s[len(p):]
		}
	}
	if i := strings.IndexAny(s, "@;"); i >= 0 {
		s = s[:i]
	}
	// Drop visual separators.
	var b strings.Builder
	for i, r := range s {
		switch {
		case r >= '0' && r <= '9':
			b.WriteRune(r)
		case r == '+' && i == 0:
			b.WriteRune(r)
		case r == ' ' || r == '-' || r == '.' || r == '(' || r == ')' || r == '/':
		default:
			return strings.TrimSpace(raw), false // letters, '*', '#': not a plain number
		}
	}
	n := b.String()
	digits := strings.TrimPrefix(n, "+")
	if digits == "" {
		return n, false
	}
	switch {
	case strings.HasPrefix(n, "+"):
	case strings.HasPrefix(digits, "00"):
		digits = digits[2:]
	case strings.HasPrefix(digits, "011") && (countryCode == "1" || countryCode == ""):
		digits = digits[3:]
	case countryCode == "1" && len(digits) == 11 && digits[0] == '1':
		// 1 + 10 digits: already has the NANP country code.
	case countryCode == "1" && len(digits) == 10:
		digits = "1" + digits
	case countryCode != "" && strings.HasPrefix(digits, "0"):
		digits = countryCode + strings.TrimLeft(digits, "0")
	case countryCode == "" && len(digits) >= 11 && digits[0] != '0':
		// Long enough to already include a country code (e.g. Twilio's 447700900123).
	default:
		return n, false
	}
	if len(digits) < 7 || len(digits) > 15 || digits[0] == '0' {
		return n, false
	}
	return "+" + digits, true
}
