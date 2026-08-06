#!/usr/bin/env bash
# Verifies the assertion helpers themselves.

it "assert_eq passes on equal values"
assert_eq "a" "a" "identical strings are equal"

it "assert_contains finds a substring"
assert_contains "hello world" "world" "substring is found"

it "assert_exit captures a non-zero exit code"
assert_exit 3 bash -c 'exit 3'
