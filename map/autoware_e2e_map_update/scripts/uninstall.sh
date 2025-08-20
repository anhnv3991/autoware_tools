#!/bin/bash


pip3 uninstall map4-cli
docker images --format "{{.Repository}}:{{.Tag}} {{.ID}}" \
  | grep "map4_engine" \
  | awk '{print $2}' \
  | xargs -r docker rmi -f