#!/usr/bin/env bats

# The `up` tests exercise the caller's fallback branches with an elixir stub.
# This test verifies the actual Elixir term rewrite against the Mix 1.19
# manifest shape that the helper deliberately supports.

load test_helper

@test "patch_mix_manifest_cwd: rewrites only the cwd in a Mix 1.19 manifest" {
  manifest="$TEST_ROOT/compile.elixir"
  new_cwd="$TEST_ROOT/new-worktree"
  # The fake test repo deliberately has no toolchain declaration. Give asdf
  # the same Elixir version supported by the production helper explicitly.
  printf 'erlang 28.1.1\nelixir 1.19.2-otp-28\n' > "$BASE/.tool-versions"

  run elixir -e '
    term = {29, [:module], [:source], [:export], [:parent], :cache, "/old/worktree", :deps, 1, 2, :protocols}
    File.write!(hd(System.argv()), :erlang.term_to_binary(term))
  ' "$manifest"
  [ "$status" -eq 0 ]

  run elixir "$BATS_TEST_DIRNAME/../lib/patch_mix_manifest_cwd.exs" "$manifest" "$new_cwd"
  [ "$status" -eq 0 ]

  run elixir -e '
    {29, modules, sources, exports, parents, cache_key, cwd, deps_config, project_mtime, config_mtime, protocols} =
      System.argv() |> hd() |> File.read!() |> :erlang.binary_to_term()
    IO.write(inspect({modules, sources, exports, parents, cache_key, cwd, deps_config, project_mtime, config_mtime, protocols}))
  ' "$manifest"
  [ "$status" -eq 0 ]
  [ "$output" = "{[:module], [:source], [:export], [:parent], :cache, \"$new_cwd\", :deps, 1, 2, :protocols}" ]
}

@test "patch_mix_manifest_cwd: rejects an unexpected manifest shape without overwriting it" {
  manifest="$TEST_ROOT/compile.elixir"
  printf 'erlang 28.1.1\nelixir 1.19.2-otp-28\n' > "$BASE/.tool-versions"
  printf 'not an Erlang term' > "$manifest"
  original_checksum="$(shasum -a 256 "$manifest" | awk '{print $1}')"

  run elixir "$BATS_TEST_DIRNAME/../lib/patch_mix_manifest_cwd.exs" "$manifest" "$TEST_ROOT/new-worktree"

  [ "$status" -ne 0 ]
  [ "$(shasum -a 256 "$manifest" | awk '{print $1}')" = "$original_checksum" ]
}
