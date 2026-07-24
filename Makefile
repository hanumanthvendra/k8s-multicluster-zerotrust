.PHONY: all prereqs clusters cilium mesh deploy test up down hubble
SHELL := /bin/bash

all: up test        ## full build + verification

prereqs:            ## install cilium CLI, check tooling
	./scripts/00-prereqs.sh
clusters:           ## create the two kind clusters
	./scripts/01-create-clusters.sh
cilium:             ## install Cilium (kube-proxy repl, wireguard, egress, hubble)
	./scripts/02-install-cilium.sh
mesh:               ## connect the clusters into one mesh
	./scripts/03-enable-clustermesh.sh
deploy:             ## deploy apps + identity policy
	./scripts/04-deploy-apps.sh

up: prereqs clusters cilium mesh deploy   ## everything up

test:               ## run the 3 proofs (cross-cluster / identity / egress)
	./scripts/05-test.sh

hubble:             ## open the Hubble traffic-map UI (eks-sim)
	cilium hubble ui --context kind-eks-sim

down:               ## tear it all down
	./scripts/99-teardown.sh
