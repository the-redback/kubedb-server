#!/usr/bin/env bash

pushd $GOPATH/src/github.com/kubedb/kubedb-server/hack/gendocs
go run main.go
popd
