// Command pcc4e-node is a reference prototype of the PCC4E discovery protocol
// described in pcc4e/proto/DISCOVERY.md. It joins a multicast group, announces
// itself periodically, and prints every peer it hears from.
package main

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net"
	"os"
	"sync"
	"time"
)

const (
	multicastAddr = "239.255.77.77"
	multicastPort = 7777
	announceEvery = 2 * time.Second
	peerTimeout   = 6 * time.Second
)

type Announce struct {
	V      int      `json:"v"`
	Type   string   `json:"type"`
	NodeID string   `json:"node_id"`
	Name   string   `json:"name"`
	Caps   []string `json:"caps"`
	PubKey string   `json:"pubkey"`
	Port   int      `json:"port"`
	TS     int64    `json:"ts"`
}

type peerState struct {
	mu    sync.Mutex
	peers map[string]Announce
	last  map[string]time.Time
}

func newPeerState() *peerState {
	return &peerState{peers: map[string]Announce{}, last: map[string]time.Time{}}
}

func (p *peerState) observe(a Announce) bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	_, known := p.peers[a.NodeID]
	p.peers[a.NodeID] = a
	p.last[a.NodeID] = time.Now()
	return !known
}

func (p *peerState) reap() {
	p.mu.Lock()
	defer p.mu.Unlock()
	for id, last := range p.last {
		if time.Since(last) > peerTimeout {
			delete(p.last, id)
			delete(p.peers, id)
			log.Printf("peer gone: %s (%s)", p.peers[id].Name, id)
		}
	}
}

func randHex(n int) string {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	return hex.EncodeToString(b)
}

func main() {
	name := flag.String("name", "", "human-readable node name")
	dataPort := flag.Int("port", 9443, "advertised data-plane port")
	caps := flag.String("caps", "compute,relay", "comma-separated capabilities")
	runFor := flag.Duration("run-for", 0, "exit after this duration (0 = run forever)")
	flag.Parse()

	if *name == "" {
		h, _ := os.Hostname()
		*name = h
	}

	nodeID := randHex(8)
	pubKey := randHex(16)

	gaddr := &net.UDPAddr{IP: net.ParseIP(multicastAddr), Port: multicastPort}

	recvConn, err := net.ListenMulticastUDP("udp4", nil, gaddr)
	if err != nil {
		log.Fatalf("listen multicast: %v", err)
	}
	recvConn.SetReadBuffer(1 << 16)

	sendConn, err := net.ListenUDP("udp4", &net.UDPAddr{})
	if err != nil {
		log.Fatalf("listen udp (send): %v", err)
	}

	log.Printf("pcc4e-node %s (%s) up — data-plane port %d, group %s:%d", *name, nodeID, *dataPort, multicastAddr, multicastPort)

	state := newPeerState()

	capsList := splitCSV(*caps)

	send := func() {
		a := Announce{
			V: 1, Type: "announce",
			NodeID: nodeID, Name: *name, Caps: capsList,
			PubKey: pubKey, Port: *dataPort, TS: time.Now().Unix(),
		}
		b, _ := json.Marshal(a)
		b = append(b, '\n')
		if _, err := sendConn.WriteToUDP(b, gaddr); err != nil {
			log.Printf("send error: %v", err)
		}
	}

	var stop <-chan time.Time
	if *runFor > 0 {
		stop = time.After(*runFor)
	}

	// receiver
	go func() {
		buf := make([]byte, 2048)
		for {
			n, src, err := recvConn.ReadFromUDP(buf)
			if err != nil {
				return
			}
			var a Announce
			if err := json.Unmarshal(buf[:n], &a); err != nil {
				continue
			}
			if a.NodeID == nodeID {
				continue // ignore our own announces
			}
			if state.observe(a) {
				log.Printf("discovered peer %-12s id=%s caps=%v port=%d addr=%s", a.Name, a.NodeID, a.Caps, a.Port, src.IP)
			}
		}
	}()

	send()
	ticker := time.NewTicker(announceEvery)
	reapTicker := time.NewTicker(1 * time.Second)
	defer ticker.Stop()
	defer reapTicker.Stop()

	for {
		select {
		case <-ticker.C:
			send()
		case <-reapTicker.C:
			state.reap()
		case <-stop:
			state.mu.Lock()
			fmt.Printf("\n=== %s (%s) final peer table ===\n", *name, nodeID)
			for id, a := range state.peers {
				fmt.Printf("  %-12s id=%s caps=%v port=%d\n", a.Name, id, a.Caps, a.Port)
			}
			state.mu.Unlock()
			return
		}
	}
}

func splitCSV(s string) []string {
	var out []string
	cur := ""
	for _, r := range s {
		if r == ',' {
			if cur != "" {
				out = append(out, cur)
			}
			cur = ""
			continue
		}
		cur += string(r)
	}
	if cur != "" {
		out = append(out, cur)
	}
	return out
}
