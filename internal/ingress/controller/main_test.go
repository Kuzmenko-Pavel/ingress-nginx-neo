// SPDX-License-Identifier: Apache-2.0

package controller

import (
	"net"
	"os"
	"testing"

	"k8s.io/ingress-nginx/internal/nginx"
)

// TestMain serves the status and stream endpoints of the tests on free ports:
// the default ports are checked by the tests of pkg/flags, which run in
// parallel with this package.
func TestMain(m *testing.M) {
	nginx.StatusPort = freePort()
	nginx.StreamPort = freePort()
	os.Exit(m.Run())
}

func freePort() int {
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		panic(err)
	}
	defer l.Close()
	addr, ok := l.Addr().(*net.TCPAddr)
	if !ok {
		panic("unexpected listener address " + l.Addr().String())
	}
	return addr.Port
}
