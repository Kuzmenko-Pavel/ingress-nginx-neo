// SPDX-License-Identifier: Apache-2.0

package framework

import (
	"fmt"
	"os"
	"sort"
	"strings"
)

// Images of the services the e2e suite deploys next to the controller. The
// project's own test images are content addressed and passed by the Makefile
// (make test-e2e); third-party images are pinned by digest.
var (
	// EchoImage is the image of the echo service.
	EchoImage = os.Getenv("E2E_ECHO_IMAGE")
	// HTTPBunImage is the image of the httpbun service.
	HTTPBunImage = os.Getenv("E2E_HTTPBUN_IMAGE")
	// FastCGIImage is the image of the FastCGI hello server.
	FastCGIImage = os.Getenv("E2E_FASTCGI_IMAGE")
	// CFSSLImage is the image of the cfssl OCSP responder.
	CFSSLImage = os.Getenv("E2E_CFSSL_IMAGE")
)

const (
	// EchoServerImage is the Kubernetes e2e echoserver used by the canary tests.
	EchoServerImage = "registry.k8s.io/e2e-test-images/echoserver:2.3@sha256:60bd75eb661054404b49f745694714b0c3298c698d8f08d21180189581e6a0f2"
	// GRPCBinImage is the gRPC test server.
	GRPCBinImage = "moul/grpcbin:latest@sha256:bd8f2ffdd02d0849fad2d1c754eff4402c867e7a3e0552b8992f4590f5687d20"
	// GRPCBinDelayImage is the gRPC test server with delayed responses.
	GRPCBinDelayImage = "ghcr.io/anddd7/grpcbin:v1.0.6@sha256:9b8885d2999fd9bb01a90df4984e29575b1b8cc0de30219bd2a839b05bfc1de4"
)

// CheckImages fails when an image the suite needs is not configured.
func CheckImages() error {
	var missing []string
	for name, value := range map[string]string{
		"E2E_ECHO_IMAGE":    EchoImage,
		"E2E_HTTPBUN_IMAGE": HTTPBunImage,
		"E2E_FASTCGI_IMAGE": FastCGIImage,
		"E2E_CFSSL_IMAGE":   CFSSLImage,
		"NGINX_BASE_IMAGE":  os.Getenv("NGINX_BASE_IMAGE"),
	} {
		if value == "" {
			missing = append(missing, name)
		}
	}
	if len(missing) > 0 {
		sort.Strings(missing)
		return fmt.Errorf("e2e images are not configured, set %s (make test-e2e passes them)", strings.Join(missing, ", "))
	}
	return nil
}
