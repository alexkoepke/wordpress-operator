# Image URL to use all building/pushing image targets
APP_VERSION ?= $(shell git describe --abbrev=5 --dirty --tags --always)
IMG ?= quay.io/presslabs/wordpress-operator:$(APP_VERSION)
KUBEBUILDER_VERSION ?= 1.0.0

ifneq ("$(wildcard $(shell which yq))","")
yq := yq
else
yq := yq.v2
endif

ifneq ("$(wildcard $(shell which gometalinter))","")
gometalinter := gometalinter
else
gometalinter := gometalinter.v2
endif

all: test manager

# Run tests
test: generate fmt vet manifests
	go test -v -race ./pkg/... ./cmd/... -coverprofile cover.out

# Build manager binary
manager: generate fmt vet
	go build -o bin/manager github.com/presslabs/wordpress-operator/cmd/manager

# Run against the configured Kubernetes cluster in ~/.kube/config
run: generate fmt vet
	go run ./cmd/manager/main.go

# Install CRDs into a cluster
install: manifests
	kubectl apply -f config/crds

# Deploy controller in the configured Kubernetes cluster in ~/.kube/config
deploy: manifests
	kubectl apply -f config/crds
	kustomize build config/default | kubectl apply -f -

# Generate manifests e.g. CRD, RBAC etc.
manifests:
	go run vendor/sigs.k8s.io/controller-tools/cmd/controller-gen/main.go all

.PHONY: chart
chart:
	rm -rf chart/wordpress-operator
	cp -r chart/wordpress-operator-src chart/wordpress-operator
	$(yq) w -i chart/wordpress-operator/Chart.yaml version "$(APP_VERSION)"
	$(yq) w -i chart/wordpress-operator/Chart.yaml appVersion "$(APP_VERSION)"
	$(yq) w -i chart/wordpress-operator/values.yaml image "$(IMG)"
	awk 'FNR==1 && NR!=1 {print "---"}{print}' config/crds/*.yaml > chart/wordpress-operator/templates/crds.yaml
	$(yq) m -d'*' -i chart/wordpress-operator/templates/crds.yaml hack/chart-metadata.yaml
	$(yq) w -d'*' -i chart/wordpress-operator/templates/crds.yaml 'metadata.annotations[helm.sh/hook]' crd-install
	$(yq) d -d'*' -i chart/wordpress-operator/templates/crds.yaml metadata.creationTimestamp
	$(yq) d -d'*' -i chart/wordpress-operator/templates/crds.yaml status metadata.creationTimestamp
	cp config/rbac/rbac_role.yaml chart/wordpress-operator/templates/rbac.yaml
	$(yq) m -d'*' -i chart/wordpress-operator/templates/rbac.yaml hack/chart-metadata.yaml
	$(yq) d -d'*' -i chart/wordpress-operator/templates/rbac.yaml metadata.creationTimestamp
	$(yq) w -d'*' -i chart/wordpress-operator/templates/rbac.yaml metadata.name '{{ template "wordpress-operator.fullname" . }}'
	echo '{{- if .Values.rbac.create }}' > chart/wordpress-operator/templates/clusterrole.yaml
	cat chart/wordpress-operator/templates/rbac.yaml >> chart/wordpress-operator/templates/clusterrole.yaml
	echo '{{- end }}' >> chart/wordpress-operator/templates/clusterrole.yaml
	rm chart/wordpress-operator/templates/rbac.yaml

# Run go fmt against code
fmt:
	go fmt ./pkg/... ./cmd/...

# Run go vet against code
vet:
	go vet ./pkg/... ./cmd/...

# Generate code
generate:
	go generate ./pkg/... ./cmd/...

# Build the docker image
images: test
	docker build . -t ${IMG}
	@echo "updating kustomize image patch file for manager resource"
	sed -i 's@image: .*@image: '"${IMG}"'@' ./config/default/manager_image_patch.yaml

# Push the docker image
publish:
	docker push ${IMG}

lint:
	$(gometalinter) --disable-all \
    --deadline 5m \
    --enable=misspell \
    --enable=structcheck \
    --enable=golint \
    --enable=deadcode \
    --enable=goimports \
    --enable=errcheck \
    --enable=varcheck \
    --enable=goconst \
    --enable=gas \
    --enable=unparam \
    --enable=ineffassign \
    --enable=nakedret \
    --enable=interfacer \
    --enable=misspell \
    --enable=gocyclo \
    --line-length=170 \
    --enable=lll \
    --dupl-threshold=400 \
    --enable=dupl \
    --exclude=zz_generated.deepcopy.go \
    ./pkg/... ./cmd/...

    # TODO: Enable these as we fix them to make them pass
    # --enable=maligned \
    # --enable=safesql \

dependencies:
	go get -u gopkg.in/mikefarah/yq.v2
	go get -u gopkg.in/alecthomas/gometalinter.v2
	gometalinter.v2 --install

	# install Kubebuilder
	curl -L -O https://github.com/kubernetes-sigs/kubebuilder/releases/download/v${KUBEBUILDER_VERSION}/kubebuilder_${KUBEBUILDER_VERSION}_linux_amd64.tar.gz
	tar -zxvf kubebuilder_${KUBEBUILDER_VERSION}_linux_amd64.tar.gz
	mv kubebuilder_${KUBEBUILDER_VERSION}_linux_amd64 -T /usr/local/kubebuilder
