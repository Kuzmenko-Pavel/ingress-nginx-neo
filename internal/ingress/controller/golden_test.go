// SPDX-License-Identifier: Apache-2.0

package controller

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	"github.com/pmezard/go-difflib/difflib"
	corev1 "k8s.io/api/core/v1"
	discoveryv1 "k8s.io/api/discovery/v1"
	networking "k8s.io/api/networking/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/util/yaml"

	"k8s.io/ingress-nginx/internal/ingress/annotations"
	"k8s.io/ingress-nginx/internal/ingress/annotations/auth"
	ngx_config "k8s.io/ingress-nginx/internal/ingress/controller/config"
	"k8s.io/ingress-nginx/internal/ingress/controller/store"
	ngx_template "k8s.io/ingress-nginx/internal/ingress/controller/template"
	"k8s.io/ingress-nginx/internal/ingress/defaults"
	"k8s.io/ingress-nginx/internal/ingress/resolver"
	"k8s.io/ingress-nginx/pkg/apis/ingress"
	"k8s.io/ingress-nginx/pkg/util/file"
)

// goldenResolver resolves what the annotations of a case reference: the
// ConfigMaps, Secrets, Services and EndpointSlices of its ingress.yaml and the
// configuration of the controller from its configmap.yaml, as the store does
// in a cluster.
type goldenResolver struct {
	cfg        ngx_config.Configuration
	configMaps map[string]*corev1.ConfigMap
	secrets    map[string]*corev1.Secret
	services   map[string]*corev1.Service
	// by the key of their Service
	endpointSlices map[string][]*discoveryv1.EndpointSlice
}

func (r *goldenResolver) GetDefaultBackend() defaults.Backend {
	return r.cfg.Backend
}

func (r *goldenResolver) GetSecurityConfiguration() defaults.SecurityConfiguration {
	return defaults.SecurityConfiguration{
		AnnotationsRiskLevel:         r.cfg.AnnotationsRiskLevel,
		AllowCrossNamespaceResources: r.cfg.AllowCrossNamespaceResources,
	}
}

func (r *goldenResolver) GetConfigMap(key string) (*corev1.ConfigMap, error) {
	if cm, ok := r.configMaps[key]; ok {
		return cm, nil
	}
	return nil, fmt.Errorf("no ConfigMap %s in ingress.yaml", key)
}

func (r *goldenResolver) GetSecret(key string) (*corev1.Secret, error) {
	if s, ok := r.secrets[key]; ok {
		return s, nil
	}
	return nil, fmt.Errorf("no Secret %s in ingress.yaml", key)
}

func (r *goldenResolver) GetService(key string) (*corev1.Service, error) {
	if svc, ok := r.services[key]; ok {
		return svc, nil
	}
	return nil, fmt.Errorf("no Service %s in ingress.yaml", key)
}

// GetAuthCertificate names the files of the Secret as the store writes them.
func (r *goldenResolver) GetAuthCertificate(key string) (*resolver.AuthSSLCert, error) {
	s, err := r.GetSecret(key)
	if err != nil {
		return nil, err
	}

	name := strings.ReplaceAll(key, "/", "-")
	cert := &resolver.AuthSSLCert{Secret: key}
	if _, ok := s.Data["tls.crt"]; ok {
		cert.PemFileName = fmt.Sprintf("%s/%s.pem", file.DefaultSSLDirectory, name)
	}
	if _, ok := s.Data["ca.crt"]; ok {
		// the CA goes into the PEM file of the certificate when there is one
		cert.CAFileName = cert.PemFileName
		if cert.CAFileName == "" {
			cert.CAFileName = fmt.Sprintf("%s/ca-%s.pem", file.DefaultSSLDirectory, name)
		}
	}
	if _, ok := s.Data["ca.crl"]; ok {
		cert.CRLFileName = fmt.Sprintf("%s/crl-%s.pem", file.DefaultSSLDirectory, name)
	}

	return cert, nil
}

// goldenStore gives the controller the configuration, the Services and the
// EndpointSlices of the case, as the store reads them from the cluster.
type goldenStore struct {
	store.Storer
	r *goldenResolver
}

func (s *goldenStore) GetBackendConfiguration() ngx_config.Configuration {
	return s.r.cfg
}

func (s *goldenStore) GetDefaultBackend() defaults.Backend {
	return s.r.cfg.Backend
}

func (s *goldenStore) GetService(key string) (*corev1.Service, error) {
	return s.r.GetService(key)
}

func (s *goldenStore) GetServiceEndpointsSlices(key string) ([]*discoveryv1.EndpointSlice, error) {
	return s.r.endpointSlices[key], nil
}

// goldenBackends is the configuration the controller passes outside of
// nginx.conf: the backends of the Lua balancer and the backends of the TCP
// proxy of SSL passthrough.
type goldenBackends struct {
	Backends            []*ingress.Backend               `json:"backends"`
	PassthroughBackends []*ingress.SSLPassthroughBackend `json:"passthroughBackends,omitempty"`
}

// TestGolden renders the Ingresses of every testdata/golden/<case>/ingress.yaml
// through the code of the controller (annotations, servers and locations,
// backends, nginx.tmpl). It compares the server blocks with
// testdata/golden/<case>/server.conf, followed by the lines the Ingresses change
// outside of the server blocks (rate limit zones, auth upstreams, stream
// snippets), and the backends the controller passes to Lua and to the TCP
// proxy of SSL passthrough with testdata/golden/<case>/backends.json.
// UPDATE_GOLDEN=1 rewrites the files.
func TestGolden(t *testing.T) {
	tpl, err := ngx_template.NewTemplate(filepath.Join("..", "..", "..", "rootfs", "etc", "nginx", "template", "nginx.tmpl"))
	if err != nil {
		t.Fatalf("loading nginx.tmpl: %v", err)
	}

	cases, err := filepath.Glob(filepath.Join("testdata", "golden", "*"))
	if err != nil || len(cases) == 0 {
		t.Fatalf("no golden cases in testdata/golden: %v", err)
	}

	// The parser of basic and digest auth writes the users of the Secret into
	// auth.AuthDirectory; the golden files show the directory of a cluster.
	clusterAuthDir, authDir := auth.AuthDirectory, t.TempDir()
	defer func() { auth.AuthDirectory = clusterAuthDir }()
	auth.AuthDirectory = authDir

	for _, dir := range cases {
		t.Run(filepath.Base(dir), func(t *testing.T) {
			ings, r := readGoldenCase(t, dir)

			ingresses := make([]*ingress.Ingress, 0, len(ings))
			for _, ing := range ings {
				parsed, err := annotations.NewAnnotationExtractor(r).Extract(ing)
				if err != nil {
					t.Fatalf("parsing the annotations of %s: %v", ing.Name, err)
				}
				ingresses = append(ingresses, &ingress.Ingress{Ingress: *ing, ParsedAnnotations: parsed})
			}

			n := newDynamicNginxController(t, testConfigMap)
			n.store = &goldenStore{Storer: n.store, r: r}
			n.t = tpl
			// the defaults of the command line arguments
			n.cfg.ListenPorts = &ngx_config.ListenPorts{HTTP: 80, HTTPS: 443, Health: 10254, Default: 8181, SSLProxy: 442}
			render := func(ingresses []*ingress.Ingress) (string, *ingress.Configuration) {
				_, _, cfg := n.getConfiguration(ingresses)
				conf, err := n.generateTemplate(r.cfg, *cfg)
				if err != nil {
					t.Fatalf("rendering nginx.tmpl: %v", err)
				}
				return normalizeConf(strings.ReplaceAll(string(conf), authDir, clusterAuthDir)), cfg
			}

			conf, cfg := render(ingresses)
			servers, rest := splitServers(conf)
			if servers == "" {
				t.Fatal("no server block of the Ingresses in the rendered configuration")
			}
			base, _ := render(nil)
			_, base = splitServers(base)
			compareGolden(t, filepath.Join(dir, "server.conf"), servers+outsideChanges(t, base, rest))

			backends, err := json.MarshalIndent(goldenBackends{
				Backends:            luaBackends(cfg.Backends),
				PassthroughBackends: cfg.PassthroughBackends,
			}, "", "  ")
			if err != nil {
				t.Fatalf("encoding the backends: %v", err)
			}
			compareGolden(t, filepath.Join(dir, "backends.json"), string(backends)+"\n")
		})
	}
}

// readGoldenCase reads the Ingresses of the case with the objects their
// annotations reference (ingress.yaml) and the data of the ConfigMap of the
// controller (configmap.yaml, optional).
func readGoldenCase(t *testing.T, dir string) ([]*networking.Ingress, *goldenResolver) {
	t.Helper()

	r := &goldenResolver{
		configMaps:     map[string]*corev1.ConfigMap{},
		secrets:        map[string]*corev1.Secret{},
		services:       map[string]*corev1.Service{},
		endpointSlices: map[string][]*discoveryv1.EndpointSlice{},
	}
	var ings []*networking.Ingress

	for _, doc := range readGoldenYAML(t, filepath.Join(dir, "ingress.yaml")) {
		var meta metav1.TypeMeta
		if err := json.Unmarshal(doc, &meta); err != nil {
			t.Fatalf("ingress.yaml: %v", err)
		}

		decode := func(obj metav1.Object) string {
			if err := json.Unmarshal(doc, obj); err != nil {
				t.Fatalf("ingress.yaml: decoding a %s: %v", meta.Kind, err)
			}
			return obj.GetNamespace() + "/" + obj.GetName()
		}

		switch meta.Kind {
		case "Ingress":
			ing := &networking.Ingress{}
			decode(ing)
			ings = append(ings, ing)
		case "ConfigMap":
			cm := &corev1.ConfigMap{}
			r.configMaps[decode(cm)] = cm
		case "Secret":
			s := &corev1.Secret{}
			r.secrets[decode(s)] = s
		case "Service":
			svc := &corev1.Service{}
			r.services[decode(svc)] = svc
		case "EndpointSlice":
			eps := &discoveryv1.EndpointSlice{}
			decode(eps)
			key := eps.Namespace + "/" + eps.Labels[discoveryv1.LabelServiceName]
			r.endpointSlices[key] = append(r.endpointSlices[key], eps)
		default:
			t.Fatalf("ingress.yaml: unexpected kind %q", meta.Kind)
		}
	}
	if len(ings) == 0 {
		t.Fatal("ingress.yaml: no Ingress")
	}

	var data map[string]string
	docs := readGoldenYAML(t, filepath.Join(dir, "configmap.yaml"))
	if len(docs) > 0 {
		cm := &corev1.ConfigMap{}
		if len(docs) > 1 || json.Unmarshal(docs[0], cm) != nil || cm.Kind != "ConfigMap" {
			t.Fatal("configmap.yaml: holds one ConfigMap of the controller")
		}
		data = cm.Data
	}
	r.cfg = ngx_template.ReadConfig(data)

	return ings, r
}

// readGoldenYAML returns the documents of a YAML file as JSON, none when the
// file does not exist.
func readGoldenYAML(t *testing.T, path string) []json.RawMessage {
	t.Helper()

	f, err := os.Open(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		t.Fatalf("opening %s: %v", path, err)
	}
	defer f.Close()

	var docs []json.RawMessage
	d := yaml.NewYAMLOrJSONDecoder(f, 4096)
	for {
		var doc json.RawMessage
		err := d.Decode(&doc)
		if errors.Is(err, io.EOF) {
			return docs
		}
		if err != nil {
			t.Fatalf("decoding %s: %v", path, err)
		}
		docs = append(docs, doc)
	}
}

var (
	serverBlock = regexp.MustCompile(`(?ms)^[ \t]*## start server \S+\n.*?## end server \S+\n`)
	blankLines  = regexp.MustCompile(`\n(\s*\n)+`)
)

// normalizeConf drops the trailing spaces and the empty lines of a rendered
// configuration.
func normalizeConf(conf string) string {
	lines := strings.Split(conf, "\n")
	for k := range lines {
		lines[k] = strings.TrimRight(lines[k], " \t")
	}
	return blankLines.ReplaceAllString(strings.Join(lines, "\n"), "\n")
}

// splitServers cuts the server blocks out of the configuration, except the
// default server "_", by the markers the template writes around them (the e2e
// framework finds servers the same way), and returns them and the rest.
func splitServers(conf string) (servers, rest string) {
	var b strings.Builder
	rest = serverBlock.ReplaceAllStringFunc(conf, func(block string) string {
		if strings.HasPrefix(strings.TrimLeft(block, " \t"), "## start server _\n") {
			return block
		}
		b.WriteString(strings.TrimLeft(block, " \t"))
		return ""
	})
	return b.String(), rest
}

// outsideChanges returns the lines of the configuration outside of the server
// blocks that the Ingress adds (+) or removes (-), without their positions so
// that a change of the template elsewhere does not touch the golden files.
func outsideChanges(t *testing.T, base, rest string) string {
	t.Helper()

	diff, err := difflib.GetUnifiedDiffString(difflib.UnifiedDiff{
		A:       difflib.SplitLines(base),
		B:       difflib.SplitLines(rest),
		Context: 0,
	})
	if err != nil {
		t.Fatalf("diffing the configuration outside of the server blocks: %v", err)
	}

	var changes []string
	for _, line := range strings.SplitAfter(diff, "\n") {
		if strings.HasPrefix(line, "+++") || strings.HasPrefix(line, "---") {
			continue
		}
		if strings.HasPrefix(line, "+") || strings.HasPrefix(line, "-") {
			changes = append(changes, line)
		}
	}
	if len(changes) == 0 {
		return ""
	}

	return "## outside of the server blocks (+ added, - removed by the Ingress)\n" + strings.Join(changes, "")
}

func compareGolden(t *testing.T, path, got string) {
	t.Helper()

	if os.Getenv("UPDATE_GOLDEN") != "" {
		if err := os.WriteFile(path, []byte(got), 0o600); err != nil {
			t.Fatalf("writing %s: %v", path, err)
		}
		return
	}

	want, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading %s: %v (UPDATE_GOLDEN=1 creates it)", path, err)
	}
	if got == string(want) {
		return
	}

	diff, err := difflib.GetUnifiedDiffString(difflib.UnifiedDiff{
		A:        difflib.SplitLines(string(want)),
		B:        difflib.SplitLines(got),
		FromFile: path,
		ToFile:   "rendered",
		Context:  3,
	})
	if err != nil {
		t.Fatalf("diffing %s: %v", path, err)
	}
	t.Errorf("golden mismatch:\n%s\nupdate with: make test-unit TEST_ARGS='-run TestGolden' UPDATE_GOLDEN=1", diff)
}
