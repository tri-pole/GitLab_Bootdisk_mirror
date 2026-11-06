#!/bin/bash

# petitboot_gen_relnotes.bash
# 26-11-02: v0.1, Qwen
#
# Generate RELEASE_NOTES_<tag>.md in a Petitboot initramfs result directory.
#
# Usage:
#   ./petitboot_gen_relnotes.bash <result_dir>
# where <result_dir> is the result directory produced by a
# petitboot_mkinitrd_*.bash run, e.g. result_aarch64_261102T1257 (a trailing
# slash is optional).
#
# The notes contain source/commit/build info, the component versions taken
# verbatim from the README file the build script embeds into the initramfs
# (usr/share/petitboot/README_petitboot_initrd.txt), and a file table with
# sizes and SHA256 checksums. The file is written to
# <result_dir>/RELEASE_NOTES_<tag>.md where <tag> is the version tag baked
# into the initramfs file names (e.g. v1.15-aarch64-3p-261102), so the arch
# appears exactly once in the file name.
#
# When run from a GitLab pipeline the built-in CI variables (CI_PROJECT_PATH,
# CI_COMMIT_SHORT_SHA, CI_JOB_ID, CI_PROJECT_URL, CI_COMMIT_REF_NAME) are
# used; sensible fallbacks are used when run locally.

set -u

i_msg="[\033[94m Info \033[0m]"
w_msg="[\033[93m Warning \033[0m]"
e_msg="[\033[91m Error \033[0m]"
ok_msg="[\033[92m OK \033[0m]"

if [[ $# -ne 1 ]]; then
    echo -e ${e_msg}" Usage: $0 <result_dir>"
    exit 1
fi

result_dir=${1%/}
if [[ ! -d "$result_dir" ]]; then
    echo -e ${e_msg}" The result dir $result_dir was not found, exiting."
    exit 1
fi

echo -e ${i_msg}" Looking for initramfs files in $result_dir ..."
initrd=$(ls "${result_dir}"/initrd-pb-* 2>/dev/null | head -1)
if [[ -z "$initrd" ]]; then
    echo -e ${e_msg}" No initrd-pb-* file found in $result_dir, exiting."
    exit 1
fi
initrd_base=$(basename "$initrd")
uinitrd=$(ls "${result_dir}"/uInitrd-pb-* 2>/dev/null | head -1)
uinitrd_base=""
if [[ -n "$uinitrd" ]]; then
    uinitrd_base=$(basename "$uinitrd")
fi

# The tag is the version tag baked into the file names, e.g.
# v1.15-aarch64-3p-261102 (format: v<pb_ver>-<arch>-<build_tag>).
tag=${initrd_base#initrd-pb-}
IFS='-' read -r _pbver arch _btag <<< "${tag#v}"

commit_sha=${CI_COMMIT_SHORT_SHA:-}
if [[ -z "$commit_sha" ]]; then
    commit_sha=$(git rev-parse --short HEAD 2>/dev/null)
fi
commit_sha=${commit_sha:-unknown}
source_ref=${CI_PROJECT_PATH:-local}
build_when=$(date -u '+%Y-%m-%d %H:%M UTC')
if [[ -n "${CI_JOB_ID:-}" ]]; then
    built_where="GitLab job ${CI_JOB_ID}"
else
    built_where="local host $(hostname 2>/dev/null || echo unknown)"
fi
changelog_url=${CI_PROJECT_URL:-}
if [[ -n "$changelog_url" ]]; then
    changelog_link="[CHANGELOG.md](${changelog_url}/-/blob/${CI_COMMIT_REF_NAME:-HEAD}/CHANGELOG.md) in the repository"
else
    changelog_link="CHANGELOG.md in the repository"
fi

echo -e ${i_msg}" Extracting the embedded build README from the initramfs ..."
embedded=$(zcat "$initrd" | \
    cpio -i --to-stdout usr/share/petitboot/README_petitboot_initrd.txt 2>/dev/null)
if [[ -z "$embedded" ]]; then
    echo -e ${w_msg}" Could not extract the embedded README from the initramfs;"
    echo -e ${w_msg}" the component version section will be empty."
fi

echo -e ${i_msg}" Computing sizes and SHA256 checksums ..."
size_initrd=$(numfmt --to=iec $(stat -c%s "$initrd"))
sha256_initrd=$(sha256sum "$initrd" | cut -d' ' -f1)
size_uinitrd=""
sha256_uinitrd=""
if [[ -n "$uinitrd_base" ]]; then
    size_uinitrd=$(numfmt --to=iec $(stat -c%s "$uinitrd"))
    sha256_uinitrd=$(sha256sum "$uinitrd" | cut -d' ' -f1)
fi

notes_file="${result_dir}/RELEASE_NOTES_${tag}.md"
{
    echo "# Petitboot initramfs for ${arch} — ${tag#v}"
    echo
    echo "- **Source:** ${source_ref}, commit \`${commit_sha}\` (script: \`petitboot_mkinitrd_${arch}.bash\`)"
    echo "- **Built:** ${build_when}, ${built_where}"
    echo
    echo "## Component versions and build environment"
    echo
    echo '```text'
    echo "$embedded"
    echo '```'
    echo
    echo "## Files"
    echo
    echo "| File | Size | SHA256 |"
    echo "|------|------|--------|"
    echo "| \`${initrd_base}\` | ${size_initrd} | \`${sha256_initrd}\` |"
    if [[ -n "$uinitrd_base" ]]; then
        echo "| \`${uinitrd_base}\` | ${size_uinitrd} | \`${sha256_uinitrd}\` |"
    fi
    echo
    echo "## Changes since previous release"
    echo
    echo "See ${changelog_link}."
    echo
    echo "## Tested on"
    echo
    echo "Ugoos AM6 plus (aarch64), VisionFive 2, v1.3b (riscv64)"
} > "$notes_file"

echo -e ${ok_msg}" Release notes written to ${notes_file}"
