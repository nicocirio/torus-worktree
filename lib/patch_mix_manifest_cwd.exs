# Mix 1.19 stores the absolute cwd separately in its compile manifest. A
# copied _build therefore looks stale in a new worktree even when all source
# and compiler inputs still match. Rewrite only that field; `mix compile`
# immediately afterwards remains responsible for deciding what truly needs
# recompilation.
#
# Usage: elixir patch_mix_manifest_cwd.exs <manifest_path> <new_cwd>

case System.argv() do
  [manifest_path, new_cwd] when is_binary(new_cwd) ->
    with true <- String.starts_with?(new_cwd, "/"),
         {:ok, raw} <- File.read(manifest_path),
         term <- :erlang.binary_to_term(raw),
         {29, modules, sources, exports, parents, cache_key, old_cwd, deps_config, project_mtime,
          config_mtime, protocols} <- term,
         true <- is_binary(old_cwd) and String.starts_with?(old_cwd, "/") do
      updated =
        {29, modules, sources, exports, parents, cache_key, new_cwd, deps_config, project_mtime,
         config_mtime, protocols}

      temp_path = manifest_path <> ".tmp-#{:erlang.unique_integer([:positive])}"
      File.write!(temp_path, :erlang.term_to_binary(updated, [:compressed]))
      File.rename!(temp_path, manifest_path)
    else
      _ -> System.halt(1)
    end

  _ ->
    System.halt(1)
end
