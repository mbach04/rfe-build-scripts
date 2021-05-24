#!/bin/bash

podman rmi rhel-edge:v1.0 --force
podman rmi rhel-edge:latest --force

podman build -t rhel-edge:v1.0 --build-arg  commit=b5c05a66-4b38-4f51-81d0-531c56ef33bf-commit.tar -f Containerfile .
podman tag rhel-edge:v1.0 quay.io/mbach/rfe:latest
podman push quay.io/mbach/rfe:latest

oc project httpd
oc import-image rfe
