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

package lint

import (
	"fmt"

	"github.com/spf13/cobra"

	appsv1 "k8s.io/api/apps/v1"
	networking "k8s.io/api/networking/v1"
	kmeta "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/cli-runtime/pkg/genericclioptions"

	"k8s.io/ingress-nginx/cmd/plugin/lints"
	"k8s.io/ingress-nginx/cmd/plugin/request"
	"k8s.io/ingress-nginx/cmd/plugin/util"
)

// CreateCommand creates and returns this cobra subcommand
func CreateCommand(flags *genericclioptions.ConfigFlags) *cobra.Command {
	var opts *lintOptions
	cmd := &cobra.Command{
		Use:   "lint",
		Short: "Inspect kubernetes resources for possible issues",
		RunE: func(_ *cobra.Command, _ []string) error {
			fmt.Println("Checking ingresses...")
			err := ingresses(*opts)
			if err != nil {
				util.PrintError(err)
			}
			fmt.Println("Checking deployments...")
			err = deployments(*opts)
			if err != nil {
				util.PrintError(err)
			}

			return nil
		},
	}

	opts = addCommonOptions(flags, cmd)

	cmd.AddCommand(createSubcommand(flags, []string{"ingresses", "ingress", "ing"}, "Check ingresses for possible issues", ingresses))
	cmd.AddCommand(createSubcommand(flags, []string{"deployments", "deployment", "dep"}, "Check deployments for possible issues", deployments))

	return cmd
}

func createSubcommand(flags *genericclioptions.ConfigFlags, names []string, short string, f func(opts lintOptions) error) *cobra.Command {
	var opts *lintOptions
	cmd := &cobra.Command{
		Use:     names[0],
		Aliases: names[1:],
		Short:   short,
		RunE: func(_ *cobra.Command, _ []string) error {
			util.PrintError(f(*opts))
			return nil
		},
	}

	opts = addCommonOptions(flags, cmd)

	return cmd
}

func addCommonOptions(flags *genericclioptions.ConfigFlags, cmd *cobra.Command) *lintOptions {
	out := lintOptions{
		flags: flags,
	}
	cmd.Flags().BoolVar(&out.allNamespaces, "all-namespaces", false, "Check resources in all namespaces")
	cmd.Flags().BoolVar(&out.showAll, "show-all", false, "Show all resources, not just the ones with problems")
	cmd.Flags().BoolVarP(&out.verbose, "verbose", "v", false, "Show extra information about the lints")

	return &out
}

type lintOptions struct {
	flags         *genericclioptions.ConfigFlags
	allNamespaces bool
	showAll       bool
	verbose       bool
}

type lint interface {
	Check(obj kmeta.Object) bool
	Message() string
	Link() string
}

func checkObjectArray(allLints []lint, objects []kmeta.Object, opts lintOptions) {
	for _, obj := range objects {
		objName := obj.GetName()
		if opts.allNamespaces {
			objName = obj.GetNamespace() + "/" + obj.GetName()
		}

		failedLints := make([]lint, 0)
		for _, lint := range allLints {
			if lint.Check(obj) {
				failedLints = append(failedLints, lint)
			}
		}

		if len(failedLints) != 0 {
			fmt.Printf("✗ %v\n", objName)
			for _, lint := range failedLints {
				fmt.Printf("  - %v\n", lint.Message())
				if opts.verbose && lint.Link() != "" {
					fmt.Printf("      %v\n", lint.Link())
				}
			}
			fmt.Println("")
			continue
		}

		if opts.showAll {
			fmt.Printf("✓ %v\n", objName)
		}
	}
}

func ingresses(opts lintOptions) error {
	var ings []networking.Ingress
	var err error
	if opts.allNamespaces {
		ings, err = request.GetIngressDefinitions(opts.flags, "")
	} else {
		ings, err = request.GetIngressDefinitions(opts.flags, util.GetNamespace(opts.flags))
	}
	if err != nil {
		return err
	}

	iLints := lints.GetIngressLints()
	genericLints := make([]lint, len(iLints))
	for i := range iLints {
		genericLints[i] = iLints[i]
	}

	objects := make([]kmeta.Object, 0)
	for i := range ings {
		objects = append(objects, &ings[i])
	}

	checkObjectArray(genericLints, objects, opts)
	return nil
}

func deployments(opts lintOptions) error {
	var deps []appsv1.Deployment
	var err error
	if opts.allNamespaces {
		deps, err = request.GetDeployments(opts.flags, "")
	} else {
		deps, err = request.GetDeployments(opts.flags, util.GetNamespace(opts.flags))
	}
	if err != nil {
		return err
	}

	iLints := lints.GetDeploymentLints()
	genericLints := make([]lint, len(iLints))
	for i := range iLints {
		genericLints[i] = iLints[i]
	}

	objects := make([]kmeta.Object, 0)
	for i := range deps {
		objects = append(objects, &deps[i])
	}

	checkObjectArray(genericLints, objects, opts)
	return nil
}
