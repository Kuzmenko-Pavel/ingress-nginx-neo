// SPDX-License-Identifier: Apache-2.0

package request

import (
	"strings"
	"testing"

	apiv1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/cli-runtime/pkg/genericclioptions"
	"k8s.io/client-go/kubernetes/fake"
	corev1 "k8s.io/client-go/kubernetes/typed/core/v1"
)

const testNamespace = "ingress-nginx-neo"

func withObjects(t *testing.T, objects ...runtime.Object) *genericclioptions.ConfigFlags {
	t.Helper()
	client := fake.NewSimpleClientset(objects...)
	previous := newCoreClient
	newCoreClient = func(*genericclioptions.ConfigFlags) (corev1.CoreV1Interface, error) {
		return client.CoreV1(), nil
	}
	t.Cleanup(func() { newCoreClient = previous })

	flags := genericclioptions.NewConfigFlags(false)
	namespace := testNamespace
	flags.Namespace = &namespace
	return flags
}

func controllerPod(name, chartName, ownerKind, ownerName string, ready bool) *apiv1.Pod {
	isController := true
	status := apiv1.ConditionFalse
	if ready {
		status = apiv1.ConditionTrue
	}
	return &apiv1.Pod{
		ObjectMeta: metav1.ObjectMeta{
			Name:      name,
			Namespace: testNamespace,
			Labels: map[string]string{
				"app.kubernetes.io/name":      chartName,
				"app.kubernetes.io/component": "controller",
			},
			OwnerReferences: []metav1.OwnerReference{{
				Kind:       ownerKind,
				Name:       ownerName,
				Controller: &isController,
			}},
		},
		Status: apiv1.PodStatus{
			Conditions: []apiv1.PodCondition{{Type: apiv1.PodReady, Status: status}},
		},
	}
}

func TestChoosePodDeployment(t *testing.T) {
	flags := withObjects(t,
		controllerPod("neo-controller-abc-1", "ingress-nginx-neo", "ReplicaSet", "neo-controller-abc", false),
		controllerPod("neo-controller-abc-2", "ingress-nginx-neo", "ReplicaSet", "neo-controller-abc", true),
	)

	pod, err := ChoosePod(flags, "", "", "")
	if err != nil {
		t.Fatal(err)
	}
	if pod.Name != "neo-controller-abc-2" {
		t.Errorf("expected the Ready pod, got %v", pod.Name)
	}
}

func TestChoosePodDaemonSet(t *testing.T) {
	flags := withObjects(t,
		controllerPod("neo-controller-x1", "ingress-nginx-neo", "DaemonSet", "neo-controller", true),
		&apiv1.Pod{ObjectMeta: metav1.ObjectMeta{Name: "other", Namespace: testNamespace}},
	)

	pod, err := ChoosePod(flags, "", "", "")
	if err != nil {
		t.Fatal(err)
	}
	if pod.Name != "neo-controller-x1" {
		t.Errorf("expected the DaemonSet pod, got %v", pod.Name)
	}
}

func TestChoosePodNameOverride(t *testing.T) {
	flags := withObjects(t,
		controllerPod("ingress-nginx-controller-y1", "ingress-nginx", "DaemonSet", "ingress-nginx-controller", false),
	)

	pod, err := ChoosePod(flags, "", "", "")
	if err != nil {
		t.Fatal(err)
	}
	if pod.Name != "ingress-nginx-controller-y1" {
		t.Errorf("expected the pod of the nameOverride release, got %v", pod.Name)
	}
}

func TestChoosePodNoController(t *testing.T) {
	flags := withObjects(t,
		&apiv1.Pod{ObjectMeta: metav1.ObjectMeta{Name: "other", Namespace: testNamespace}},
	)

	_, err := ChoosePod(flags, "", "", "")
	if err == nil || !strings.Contains(err.Error(), "no controller pods found") {
		t.Errorf("expected a no controller pods error, got %v", err)
	}
}

func TestChoosePodExplicitDeployment(t *testing.T) {
	flags := withObjects(t,
		controllerPod("a-controller-abc-1", "ingress-nginx-neo", "ReplicaSet", "a-controller-abc", true),
		controllerPod("b-controller-def-1", "ingress-nginx-neo", "ReplicaSet", "b-controller-def", true),
	)

	pod, err := ChoosePod(flags, "", "b-controller", "")
	if err != nil {
		t.Fatal(err)
	}
	if pod.Name != "b-controller-def-1" {
		t.Errorf("expected the pod of deployment b-controller, got %v", pod.Name)
	}
}

func TestChoosePodExplicitName(t *testing.T) {
	flags := withObjects(t,
		controllerPod("a-controller-abc-1", "ingress-nginx-neo", "ReplicaSet", "a-controller-abc", true),
		controllerPod("a-controller-abc-2", "ingress-nginx-neo", "ReplicaSet", "a-controller-abc", true),
	)

	pod, err := ChoosePod(flags, "a-controller-abc-2", "", "")
	if err != nil {
		t.Fatal(err)
	}
	if pod.Name != "a-controller-abc-2" {
		t.Errorf("expected the named pod, got %v", pod.Name)
	}
}

func controllerService(name, chartName string) *apiv1.Service {
	return &apiv1.Service{ObjectMeta: metav1.ObjectMeta{
		Name:      name,
		Namespace: testNamespace,
		Labels: map[string]string{
			"app.kubernetes.io/name":      chartName,
			"app.kubernetes.io/component": "controller",
		},
	}}
}

func TestGetControllerService(t *testing.T) {
	flags := withObjects(t,
		controllerService("neo-ingress-nginx-neo-controller", "ingress-nginx-neo"),
		controllerService("neo-ingress-nginx-neo-controller-admission", "ingress-nginx-neo"),
		controllerService("neo-ingress-nginx-neo-controller-metrics", "ingress-nginx-neo"),
	)

	service, err := GetControllerService(flags)
	if err != nil {
		t.Fatal(err)
	}
	if service.Name != "neo-ingress-nginx-neo-controller" {
		t.Errorf("expected the controller service, got %v", service.Name)
	}
}

func TestGetControllerServiceAmbiguous(t *testing.T) {
	flags := withObjects(t,
		controllerService("a-ingress-nginx-neo-controller", "ingress-nginx-neo"),
		controllerService("b-ingress-nginx-controller", "ingress-nginx"),
	)

	_, err := GetControllerService(flags)
	if err == nil || !strings.Contains(err.Error(), "several controller services") {
		t.Errorf("expected an ambiguity error, got %v", err)
	}
}
