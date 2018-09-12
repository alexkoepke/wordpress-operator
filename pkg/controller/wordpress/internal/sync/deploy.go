/*
Copyright 2018 Pressinfra SRL.

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

package sync

import (
	appsv1 "k8s.io/api/apps/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"

	"github.com/presslabs/controller-util/syncer"

	wordpressv1alpha1 "github.com/presslabs/wordpress-operator/pkg/apis/wordpress/v1alpha1"
)

// NewDeploymentSyncer returns a new sync.Interface for reconciling web Deployment
func NewDeploymentSyncer(wp *wordpressv1alpha1.Wordpress, rt *wordpressv1alpha1.WordpressRuntime) syncer.Interface {
	obj := &appsv1.Deployment{
		ObjectMeta: metav1.ObjectMeta{
			Name:      wp.GetDeploymentName(),
			Namespace: wp.Namespace,
		},
	}

	return syncer.New("Deployment", wp, obj, func(existing runtime.Object) error {
		out := existing.(*appsv1.Deployment)

		out.Labels = wp.WebPodLabels()

		out.Spec.Selector = metav1.SetAsLabelSelector(wp.WebPodLabels())
		out.Spec.Template = *wp.WebPodTemplateSpec(rt)
		if wp.Spec.Replicas != nil {
			out.Spec.Replicas = wp.Spec.Replicas
		}

		return nil
	})
}