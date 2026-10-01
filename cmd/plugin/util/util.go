/*
Copyright 2019 The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package util

import (
	"fmt"
	"strings"

	"github.com/spf13/cobra"
	apiv1 "k8s.io/api/core/v1"
	"k8s.io/cli-runtime/pkg/genericclioptions"
)

// DefaultIngressContainerName is the name of the controller container.
const DefaultIngressContainerName = "controller"

// ControllerSelector matches the controller pods and services of the
// ingress-nginx-neo chart, including releases installed with
// nameOverride=ingress-nginx.
const ControllerSelector = "app.kubernetes.io/component=controller,app.kubernetes.io/name in (ingress-nginx-neo,ingress-nginx)"

// IssuePrefix is the URL that an issue number of this project is appended to.
const IssuePrefix = "https://github.com/Kuzmenko-Pavel/ingress-nginx-neo/issues/"

// UpstreamIssuePrefix is the URL that an issue number of the
// kubernetes/ingress-nginx project is appended to.
const UpstreamIssuePrefix = "https://github.com/kubernetes/ingress-nginx/issues/"

// PrintError receives an error value and prints it if it exists
func PrintError(e error) {
	if e != nil {
		fmt.Println(e)
	}
}

// PodInDeployment returns whether a pod is part of a deployment with the given name
// a pod is considered to be in {deployment} if it is owned by a replicaset with a name of format {deployment}-otherchars
func PodInDeployment(pod *apiv1.Pod, deployment string) bool {
	for _, owner := range pod.OwnerReferences {
		if owner.Controller == nil || !*owner.Controller || owner.Kind != "ReplicaSet" {
			continue
		}

		if strings.Count(owner.Name, "-") != strings.Count(deployment, "-")+1 {
			continue
		}

		if strings.HasPrefix(owner.Name, deployment+"-") {
			return true
		}
	}
	return false
}

// AddPodFlag adds a --pod flag to a cobra command
func AddPodFlag(cmd *cobra.Command) *string {
	v := ""
	cmd.Flags().StringVar(&v, "pod", "", "Query a particular controller pod")
	return &v
}

// AddDeploymentFlag adds a --deployment flag to a cobra command
func AddDeploymentFlag(cmd *cobra.Command) *string {
	v := ""
	cmd.Flags().StringVar(&v, "deployment", "", "Query a pod of this controller Deployment instead of any controller pod found by label")
	return &v
}

// AddSelectorFlag adds a --selector flag to a cobra command
func AddSelectorFlag(cmd *cobra.Command) *string {
	v := ""
	cmd.Flags().StringVarP(&v, "selector", "l", "", "Selector (label query) of the controller pod; defaults to "+ControllerSelector)
	return &v
}

// AddContainerFlag adds a --container flag to a cobra command
func AddContainerFlag(cmd *cobra.Command) *string {
	v := ""
	cmd.Flags().StringVar(&v, "container", DefaultIngressContainerName, "The name of the controller container")
	return &v
}

// GetNamespace takes a set of kubectl flag values and returns the namespace we should be operating in
func GetNamespace(flags *genericclioptions.ConfigFlags) string {
	namespace, _, err := flags.ToRawKubeConfigLoader().Namespace()
	if err != nil || namespace == "" {
		namespace = apiv1.NamespaceDefault
	}
	return namespace
}
