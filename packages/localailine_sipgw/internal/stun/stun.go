// Package stun asks a STUN server (RFC 5389) "what address do you see me as?", so a gateway
// behind a home router can put its public IP in Contact and Via.
package stun

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/binary"
	"errors"
	"net"
	"net/netip"
	"time"
)

const magicCookie = 0x2112A442

// PublicAddr sends one Binding request to server (host:port) over UDP and returns the mapped
// address, retrying a couple of times.
func PublicAddr(ctx context.Context, server string) (netip.AddrPort, error) {
	var d net.Dialer
	conn, err := d.DialContext(ctx, "udp", server)
	if err != nil {
		return netip.AddrPort{}, err
	}
	defer conn.Close()

	req := make([]byte, 20)
	binary.BigEndian.PutUint16(req[0:], 0x0001) // Binding request
	binary.BigEndian.PutUint32(req[4:], magicCookie)
	txID := req[8:20]
	if _, err := rand.Read(txID); err != nil {
		return netip.AddrPort{}, err
	}
	buf := make([]byte, 1500)
	for attempt := range 3 {
		if _, err := conn.Write(req); err != nil {
			return netip.AddrPort{}, err
		}
		deadline := time.Now().Add(time.Duration(500<<attempt) * time.Millisecond)
		if d, ok := ctx.Deadline(); ok && d.Before(deadline) {
			deadline = d
		}
		conn.SetReadDeadline(deadline)
		n, err := conn.Read(buf)
		if err != nil {
			if ctx.Err() != nil {
				return netip.AddrPort{}, ctx.Err()
			}
			continue
		}
		if ap, err := Parse(buf[:n], txID); err == nil {
			return ap, nil
		}
	}
	return netip.AddrPort{}, errors.New("stun: no answer")
}

// Parse reads a Binding success response with transaction id txID and returns its
// XOR-MAPPED-ADDRESS (or MAPPED-ADDRESS from old servers).
func Parse(msg, txID []byte) (netip.AddrPort, error) {
	if len(msg) < 20 || binary.BigEndian.Uint16(msg[0:]) != 0x0101 || binary.BigEndian.Uint32(msg[4:]) != magicCookie || !bytes.Equal(msg[8:20], txID) {
		return netip.AddrPort{}, errors.New("stun: not our binding response")
	}
	length := int(binary.BigEndian.Uint16(msg[2:]))
	if 20+length > len(msg) {
		return netip.AddrPort{}, errors.New("stun: truncated")
	}
	attrs := msg[20 : 20+length]
	var fallback netip.AddrPort
	for len(attrs) >= 4 {
		typ := binary.BigEndian.Uint16(attrs[0:])
		alen := int(binary.BigEndian.Uint16(attrs[2:]))
		if 4+alen > len(attrs) {
			break
		}
		val := attrs[4 : 4+alen]
		switch typ {
		case 0x0020: // XOR-MAPPED-ADDRESS
			if ap, ok := decodeAddr(val, true, msg[4:20]); ok {
				return ap, nil
			}
		case 0x0001: // MAPPED-ADDRESS
			if ap, ok := decodeAddr(val, false, nil); ok {
				fallback = ap
			}
		}
		attrs = attrs[4+((alen+3)&^3):]
	}
	if fallback.IsValid() {
		return fallback, nil
	}
	return netip.AddrPort{}, errors.New("stun: no mapped address")
}

// decodeAddr reads family/port/address; with xor, port and address are XORed with the magic
// cookie (and, for IPv6, the transaction id): key is cookie||txID.
func decodeAddr(v []byte, xor bool, key []byte) (netip.AddrPort, bool) {
	if len(v) < 8 {
		return netip.AddrPort{}, false
	}
	port := binary.BigEndian.Uint16(v[2:])
	var ip []byte
	switch v[1] {
	case 0x01:
		ip = append([]byte{}, v[4:8]...)
	case 0x02:
		if len(v) < 20 {
			return netip.AddrPort{}, false
		}
		ip = append([]byte{}, v[4:20]...)
	default:
		return netip.AddrPort{}, false
	}
	if xor {
		port ^= uint16(magicCookie >> 16)
		for i := range ip {
			ip[i] ^= key[i]
		}
	}
	addr, ok := netip.AddrFromSlice(ip)
	if !ok {
		return netip.AddrPort{}, false
	}
	return netip.AddrPortFrom(addr.Unmap(), port), true
}
