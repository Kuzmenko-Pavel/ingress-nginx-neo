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

package lints

import (
	"fmt"
	"strings"

	v1 "k8s.io/api/apps/v1"
	kmeta "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/ingress-nginx/cmd/plugin/util"
)

// DeploymentLint is a validation for a deployment
type DeploymentLint struct {
	message string
	issue   int
	f       func(cmp v1.Deployment) bool
}

// Check returns true if the lint detects an issue
func (lint DeploymentLint) Check(obj kmeta.Object) bool {
	cmp, ok := obj.(*v1.Deployment)
	if !ok {
		util.PrintError(fmt.Errorf("unexpected type: %T", obj))
	}
	return lint.f(*cmp)
}

// Message is a description of the lint
func (lint DeploymentLint) Message() string {
	return lint.message
}

// Link is a URL to the kubernetes/ingress-nginx issue explaining the lint
func (lint DeploymentLint) Link() string {
	if lint.issue > 0 {
		return fmt.Sprintf("%v%v", util.UpstreamIssuePrefix, lint.issue)
	}

	return ""
}

// GetDeploymentLints returns all of the lints for ingresses
func GetDeploymentLints() []DeploymentLint {
	return []DeploymentLint{
		unsupportedFlag("sort-backends", 3655),
		unsupportedFlag("force-namespace-isolation", 3887),
	}
}

func unsupportedFlag(flag string, issueNumber int) DeploymentLint {
	return DeploymentLint{
		message: fmt.Sprintf("Uses the --%v flag, which the controller does not accept", flag),
		issue:   issueNumber,
		f: func(dep v1.Deployment) bool {
			if !isIngressNginxDeployment(&dep) {
				return false
			}

			args := getNginxArgs(&dep)
			for _, arg := range args {
				if strings.HasPrefix(arg, fmt.Sprintf("--%v", flag)) {
					return true
				}
			}

			return false
		},
	}
}

func getNginxArgs(dep *v1.Deployment) []string {
	for i := range dep.Spec.Template.Spec.Containers {
		container := &dep.Spec.Template.Spec.Containers[i]
		if len(container.Args) > 0 && container.Args[0] == "/nginx-ingress-controller" {
			return container.Args
		}
	}
	return make([]string, 0)
}

func isIngressNginxDeployment(dep *v1.Deployment) bool {
	containers := dep.Spec.Template.Spec.Containers
	for i := range containers {
		if len(containers[i].Args) > 0 && containers[i].Args[0] == "/nginx-ingress-controller" {
			return true
		}
	}
	return false
}
