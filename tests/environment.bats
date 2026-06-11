#!/usr/bin/env bats

setup() {
  load helpers/stub
  # The hook requires an agent id and keeps installs agent-local; point the
  # tool root at the test tmpdir so nothing leaks into the real $HOME.
  export BUILDKITE_AGENT_ID="bats-agent-1"
  export MERGIFY_CI_TOOL_ROOT="${BATS_TEST_TMPDIR}/toolroot"
  # Stub uv (records its args) and mergify (so the post-install check passes).
  # The hook looks for uv at ${UV_INSTALL_DIR}/uv, so put the stub dir there.
  stub_command uv 0
  stub_command mergify 0 "mergify-cli 0.0.0-stub"
  export UV_INSTALL_DIR="${BATS_TEST_TMPDIR}/stubs"
}

@test "environment: installs the pinned default when version is unset" {
  run bash hooks/environment

  [ "$status" -eq 0 ]
  # Read the default straight from the hook so this stays green when Renovate
  # bumps DEFAULT_MERGIFY_CLI_VERSION.
  default="$(grep -oE 'DEFAULT_MERGIFY_CLI_VERSION="[^"]+"' hooks/environment | cut -d'"' -f2)"
  grep -q -- "tool install --force --upgrade --python 3.13 mergify-cli==${default}$" "${BATS_TEST_TMPDIR}/uv.log"
}

@test "environment: installs latest when version is 'latest'" {
  export BUILDKITE_PLUGIN_MERGIFY_CI_MERGIFY_CLI_VERSION="latest"

  run bash hooks/environment

  [ "$status" -eq 0 ]
  grep -q -- "tool install --force --upgrade --python 3.13 mergify-cli$" "${BATS_TEST_TMPDIR}/uv.log"
}

@test "environment: pins the exact version when one is given" {
  export BUILDKITE_PLUGIN_MERGIFY_CI_MERGIFY_CLI_VERSION="2026.5.5.4"

  run bash hooks/environment

  [ "$status" -eq 0 ]
  grep -q -- "tool install --force --upgrade --python 3.13 mergify-cli==2026.5.5.4$" "${BATS_TEST_TMPDIR}/uv.log"
}

@test "environment: omits --python when python_version is 'system'" {
  export BUILDKITE_PLUGIN_MERGIFY_CI_PYTHON_VERSION="system"
  export BUILDKITE_PLUGIN_MERGIFY_CI_MERGIFY_CLI_VERSION="2026.5.5.4"

  run bash hooks/environment

  [ "$status" -eq 0 ]
  grep -q -- "tool install --force --upgrade mergify-cli==2026.5.5.4$" "${BATS_TEST_TMPDIR}/uv.log"
}

@test "environment: fails when BUILDKITE_AGENT_ID is missing" {
  unset BUILDKITE_AGENT_ID

  run bash hooks/environment

  [ "$status" -eq 1 ]
  [[ "$output" == *"BUILDKITE_AGENT_ID is required"* ]]
}

@test "environment: falls back to a cached mergify when the install fails" {
  # Re-stub uv to fail, simulating PyPI being unreachable. The mergify stub
  # from setup() plays the role of the binary cached by a previous build.
  stub_command uv 1

  run bash hooks/environment

  [ "$status" -eq 0 ]
  [[ "$output" == *"Using cached version"* ]]
  [[ "$output" == *"mergify-cli 0.0.0-stub"* ]]
}

@test "environment: fails when the install fails and no cached mergify exists" {
  stub_command uv 1
  rm "${BATS_TEST_TMPDIR}/stubs/mergify"

  run bash hooks/environment

  [ "$status" -eq 1 ]
  [[ "$output" == *"no cached version is available"* ]]
}
