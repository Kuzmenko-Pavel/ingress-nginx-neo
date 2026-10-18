#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Shards split the e2e suite by spec file, so that CI runs it in parallel jobs.
# The last shard takes every file the others do not, so a new spec file always
# runs. make docker-build-e2e checks that every spec runs in exactly one shard
# (test/e2e/check-shards.sh). Move a boundary here to rebalance the shards.
#
# shard_args <shard>: sets SHARD_ARGS to the ginkgo arguments of the shard,
# all runs the whole suite.
shard_args() {
  case "$1" in
    all)
      SHARD_ARGS=()
      ;;
    1)
      SHARD_ARGS=(--focus-file='test/e2e/annotations/[a-c]')
      ;;
    2)
      SHARD_ARGS=(--focus-file='test/e2e/annotations/[d-z]' --focus-file='test/e2e/admission/')
      ;;
    3)
      SHARD_ARGS=(--focus-file='test/e2e/settings/[a-l]')
      ;;
    4)
      SHARD_ARGS=(--skip-file='test/e2e/annotations/' --skip-file='test/e2e/settings/[a-l]' --skip-file='test/e2e/admission/')
      ;;
    *)
      echo "unknown e2e shard $1" >&2
      return 1
      ;;
  esac
}
