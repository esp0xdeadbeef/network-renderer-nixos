#!/usr/bin/env bash

resolve_adjacent_repo() {
  local override_name="$1"
  local repo_name="$2"
  local override_value="${!override_name:-}"
  local git_common_dir
  local workspace_root

  if [[ -n "${override_value}" ]]; then
    printf '%s\n' "${override_value}"
    return 0
  fi

  if [[ -d "${repo_root}/../${repo_name}" ]]; then
    realpath "${repo_root}/../${repo_name}"
    return 0
  fi

  git_common_dir="$(git -C "${repo_root}" rev-parse --path-format=absolute --git-common-dir)"
  workspace_root="$(realpath "${git_common_dir}/../..")"
  printf '%s\n' "${workspace_root}/${repo_name}"
}
