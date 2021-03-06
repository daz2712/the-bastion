#! /usr/bin/env bash
# vim: set filetype=sh ts=4 sw=4 sts=4 et:
set -e

RELEASE_API_URL='https://api.github.com/repos/ovh/ovh-ttyrec/releases'

basedir=$(readlink -f "$(dirname "$0")"/../..)
# shellcheck source=lib/shell/functions.inc
. "$basedir"/lib/shell/functions.inc

usage() {
    cat <<EOF
Options:
    -s   Download and install precompiled ttyrec static binaries in /usr/local/bin
    -d   Download the prebuilt Debian package, and install it (for Debian, Ubuntu and derivatives)
    -r   Download the prebuild RPM package, and install it (for RHEL, CentOS and derivatives)
    -a   Automatically detect the OS to install the proper package type, fallback to static binaries if no package applies
    -h   Show this help
EOF
}

set_download_url() {
    pattern="$1"

    action_doing "Checking for prerequisites..."
    if command -v curl >/dev/null; then
        action_done curl
        _apicall() {
            curl -sL -H 'Accept: application/vnd.github.v3+json' "$1"
        }
        _download() {
            curl -sL -O "$1"
        }
    elif command -v wget >/dev/null; then
        action_done wget
        _apicall() {
            wget -q -O - --header="Accept: application/vnd.github.v3+json" "$1"
        }
        _download() {
            wget -q "$1"
        }
    else
        action_error "Couldn't find wget nor curl"
        exit 1
    fi

    action_doing "Getting latest release..."
    if command -v jq >/dev/null; then
        # If we have jq, we can do it properly
        url=$(_apicall $RELEASE_API_URL | jq -r '.[0].assets|.[]|.browser_download_url' | grep -F "$pattern")
    elif perl -MJSON -e 1 2>/dev/null; then
        # If we don't, there's a good chance we have Perl with the JSON module, use it
        url=$(_apicall $RELEASE_API_URL | perl -MJSON -e 'undef $/; $d=decode_json(<>); foreach(@{ $d->[0]{assets} || [] }) { $_=$_->{browser_download_url}; /\Q'"$pattern"'\E/ && print && exit }')
    else
        # Otherwise, go the ugly way, don't bother the user in installing jq just for this need
        url=$(_apicall $RELEASE_API_URL | grep -Eo 'https://[a-z0-9./_-]+' | grep -F "$pattern" | head -n1)
    fi

    action_detail "$url"
}

prepare_temp_folder() {
    tmpfolder=$(mktemp -d)
    # shellcheck disable=SC2064
    trap "test -d '$tmpfolder' && rm -rf -- '$tmpfolder'" EXIT
    cd "$tmpfolder"
}

action_static() {
    set_download_url "linux-static-binary.tar.gz"
    prepare_temp_folder

    _download "$url"
    # we have just one archive file in the current temp directory
    # shellcheck disable=SC2035
    tar xzf *.tar.gz
    # at this point we have just one directory, named ovh-ttyrec-w.x.y.z, just use the shell completion to get in it!
    cd ovh-ttyrec-*/
    action_done

    action_doing "Installing files"
    for file in ttytime ttyrec ttyplay; do
        action_detail "/usr/local/bin/$file"
        install -m 0755 "$file" /usr/local/bin/
    done
    cd docs
    for file in *.1; do
        action_detail "/usr/local/man/man1/$file"
        install -m 0644 "$file" /usr/local/man/man1/
    done
    action_done

    cd /
}

action_debian() {
    set_download_url ".deb"
    prepare_temp_folder

    _download "$url"
    action_done

    action_doing "Installing package"
    if dpkg -i -- *.deb; then
        action_done
    else
        action_error
    fi

    cd /
}

action_rpm() {
    set_download_url ".rpm"
    prepare_temp_folder

    _download "$url"
    action_done

    action_doing "Installing package"
    if rpm -Uvh -- *.rpm; then
        action_done
    else
        action_error
    fi

    cd /
}

action_auto() {
    action_doing "Detecting OS..."
    action_detail "Found $OS_FAMILY"
    if [ "$OS_FAMILY" = Linux ]; then
        action_detail "Found distro $LINUX_DISTRO version $DISTRO_VERSION (major $DISTRO_VERSION_MAJOR), distro like $DISTRO_LIKE"
    fi
    action_done

    case "$DISTRO_LIKE" in
        *debian*) action_debian;;
        *rhel*)   action_rpm;;
        *suse*)   action_rpm;;
        *)
            if [ "$OS_FAMILY" = Linux ]; then
                action_static
            else
                echo "This script doesn't support this OS yet ($DISTRO_LIKE)" >&2
                exit 1
            fi;;
    esac
}

while getopts :sdrah arg; do
    case "$arg" in
        s) action_static; exit 0;;
        d) action_debian; exit 0;;
        r) action_rpm;    exit 0;;
        a) action_auto;   exit 0;;
        h) usage;         exit 0;;
        ?) echo "Invalid option: -$OPTARG"; usage; exit 1;;
    esac
done
usage
