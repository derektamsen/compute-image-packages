#!/bin/sh
# Copyright 2018 Google Inc. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Contains dracut-specific logic for detecting disk, then calls appropriate
# library functions.

# Notes for developing dracut modules: this module must never exit with anything
# other than a 0 exit code. That means no use of set -e or traps on err, and
# every command must be defensively written so that errors are caught and
# logged, rather than causing end of execution. Note that error handling in the
# main() function always calls return 0

kmsg() {
  echo "expand_rootfs: $@" > /dev/kmsg
}

main() {
  local disk="" partnum="" fs_type="" rootdev=""

  # Remove 'block:' prefix and find the root device.
  if ! rootdev=$(readlink -f "${root#block:}") || [ -z "${rootdev}" ]; then
    kmsg "Unable to find root device."
    return
  fi

  if ! out=$(split_partition "$rootdev"); then
    kmsg "Failed to detect disk and partition info: ${out}"
    return
  fi

  disk=${out%:*}
  partnum=${out#*:}

  if ! parted_needresize "$disk" "$partnum"; then
    kmsg "Disk ${rootdev} doesn't need resizing"
    return
  fi

  if ! parted --help | grep -q 'resizepart'; then
    kmsg "No 'resizepart' command in this parted"
    return
  fi

  kmsg "Resizing disk ${rootdev}"

  # First, move the secondary GPT to the end.
  if ! out=$(sgdisk_fix_gpt "$disk"); then
    kmsg "Failed to fix GPT: ${out}"
  fi

  if ! out=$(parted_resizepart "$disk" "$partnum"); then
    kmsg "Failed to resize partition: ${out}"
    return
  fi

  if ! out=$(resize_filesystem "$rootdev"); then
    kmsg "Failed to resize filesystem: ${out}"
    return
  fi
}

. /lib/expandfs-lib.sh
main
