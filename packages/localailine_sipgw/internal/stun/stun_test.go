package stun

import (
	"context"
	"encoding/binary"
	"net"
	"net/netip"
	"testing"
	"time"
)

// A tiny STUN server that answers with the XOR-MAPPED-ADDRESS it sees.
func TestPublicAddrAgainstFakeServer(t *testing.T) {
	pc, err := net.ListenPacket("udp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer pc.Close()
	go func() {
		buf := make([]byte, 1500)
		for {
			n, from, err := pc.ReadFrom(buf)
			if err != nil {
				return
			}
			if n < 20 {
				continue
			}
			ua := from.(*net.UDPAddr)
			resp := make([]byte, 20+12)
			binary.BigEndian.PutUint16(resp[0:], 0x0101)
			binary.BigEndian.PutUint16(resp[2:], 12)
			copy(resp[4:20], buf[4:20]) // cookie + transaction id
			binary.BigEndian.PutUint16(resp[20:], 0x0020)
			binary.BigEndian.PutUint16(resp[22:], 8)
			resp[25] = 0x01
			binary.BigEndian.PutUint16(resp[26:], uint16(ua.Port)^uint16(magicCookie>>16))
			ip4 := ua.IP.To4()
			for i := range 4 {
				resp[28+i] = ip4[i] ^ resp[4+i]
			}
			pc.WriteTo(resp, from)
		}
	}()
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	ap, err := PublicAddr(ctx, pc.LocalAddr().String())
	if err != nil {
		t.Fatal(err)
	}
	if ap.Addr() != netip.MustParseAddr("127.0.0.1") || ap.Port() == 0 {
		t.Fatalf("got %v", ap)
	}
}

func TestParseRejectsForeign(t *testing.T) {
	if _, err := Parse(make([]byte, 20), make([]byte, 12)); err == nil {
		t.Fatal("zero message accepted")
	}
}
