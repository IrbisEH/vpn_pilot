#!/usr/bin/bash

# library.sh

SetupDir() {
  local perms="$1"
  shift 1

  if [ -z "$perms" ]; then
    echo "Usage: SetupDir <permissions> [paths...]"
    return 1
  fi

  local paths_list=("$@")

  for path in "${paths_list[@]}"; do
    if [ ! -d "$path" ]; then
      mkdir -p "$path"
      if [ $? -eq 1 ]; then
        echo "Error! Can not create path $path"
        return 1
      fi
    fi

    chmod "$perms" "$path"
    if [ $? -eq 1 ]; then
      echo "Error! Can not assign permission on $path"
      return 1
    fi
  done

  return 0
}

SetupFile() {
  local perms="$1"
  shift 1

  if [ -z "$perms" ]; then
    echo "Usage: SetupDir <permissions> [paths...]"
    return 1
  fi

  local paths_list=("$@")

  for path in "${paths_list[@]}"; do
    if [ ! -d "$path" ]; then
      touch "$path"
      if [ $? -eq 1 ]; then
        echo "Error! Can not create file $path"
        return 1
      fi
    fi

    chmod "$perms" "$path"
    if [ $? -eq 1 ]; then
      echo "Error! Can not assign permission on $path"
      return 1
    fi
  done

  return 0
}