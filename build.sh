#!/bin/bash -e

# BEGIN COPYRIGHT BLOCK
# (C) 2018 Red Hat, Inc.
# All rights reserved.
# END COPYRIGHT BLOCK

NAME=tomcatjss

SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_NAME="$(basename "$SCRIPT_PATH")"

SRC_DIR="$(dirname "$SCRIPT_PATH")"
WORK_DIR="$HOME/build/$NAME"

SOURCE_TAG=

WITH_TIMESTAMP=
WITH_COMMIT_ID=
DIST=

VERBOSE=
DEBUG=

usage() {
    echo "Usage: $SCRIPT_NAME [OPTIONS] <target>"
    echo
    echo "Options:"
    echo "    --work-dir=<path>      Working directory (default: $WORK_DIR)."
    echo "    --source-tag=<tag>     Generate RPM sources from a source tag."
    echo "    --with-timestamp       Append timestamp to release number."
    echo "    --with-commit-id       Append commit ID to release number."
    echo "    --dist=<name>          Distribution name (e.g. fc28)."
    echo " -v,--verbose              Run in verbose mode."
    echo "    --debug                Run in debug mode."
    echo "    --help                 Show help message."
    echo
    echo "Target:"
    echo "    src    Generate RPM sources."
    echo "    spec   Generate RPM spec."
    echo "    srpm   Build SRPM package."
    echo "    rpm    Build RPM packages (default)."
}

generate_rpm_sources() {

    TARBALL="$NAME-$VERSION${_PHASE}.tar.gz"

    if [ "$SOURCE_TAG" != "" ] ; then

        if [ "$VERBOSE" = true ] ; then
            echo "Generating $TARBALL from $SOURCE_TAG tag"
        fi

        git -C "$SRC_DIR" \
            archive \
            --format=tar.gz \
            --prefix $NAME-$VERSION${_PHASE}/ \
            -o "$WORK_DIR/SOURCES/$TARBALL" \
            $SOURCE_TAG

        if [ "$SOURCE_TAG" != "HEAD" ] ; then

            TAG_ID="$(git -C "$SRC_DIR" rev-parse $SOURCE_TAG)"
            HEAD_ID="$(git -C "$SRC_DIR" rev-parse HEAD)"

            if [ "$TAG_ID" != "$HEAD_ID" ] ; then
                generate_patch
            fi
        fi

        return
    fi

    if [ "$VERBOSE" = true ] ; then
        echo "Generating $TARBALL"
    fi

    tar czf "$WORK_DIR/SOURCES/$TARBALL" \
        --transform "s,^./,$NAME-$VERSION${_PHASE}/," \
        --exclude .git \
        --exclude bin \
        -C "$SRC_DIR" \
        .
}

generate_patch() {

    PATCH="$NAME-$VERSION-$RELEASE.patch"

    if [ "$VERBOSE" = true ] ; then
        echo "Generating $PATCH for all changes since $SOURCE_TAG tag"
    fi

    git -C "$SRC_DIR" \
        format-patch \
        --stdout \
        $SOURCE_TAG \
        > "$WORK_DIR/SOURCES/$PATCH"
}

generate_rpm_spec() {

    RPM_SPEC="$NAME.spec"

    if [ "$VERBOSE" = true ] ; then
        echo "Generating $RPM_SPEC"
    fi

    # hard-code timestamp
    commands="s/%{?_timestamp}/${_TIMESTAMP}/g"

    # hard-code commit ID
    commands="${commands}; s/%{?_commit_id}/${_COMMIT_ID}/g"

    # hard-code phase
    commands="${commands}; s/%{?_phase}/${_PHASE}/g"

    # hard-code patch
    if [ "$PATCH" != "" ] ; then
        commands="${commands}; s/# Patch: tomcatjss-VERSION-RELEASE.patch/Patch: $PATCH/g"
    fi

    sed "$commands" "$SPEC_TEMPLATE" > "$WORK_DIR/SPECS/$RPM_SPEC"

    # rpmlint "$WORK_DIR/SPECS/$RPM_SPEC"
}

while getopts v-: arg ; do
    case $arg in
    v)
        VERBOSE=true
        ;;
    -)
        LONG_OPTARG="${OPTARG#*=}"

        case $OPTARG in
        work-dir=?*)
            WORK_DIR="$(readlink -f "$LONG_OPTARG")"
            ;;
        source-tag=?*)
            SOURCE_TAG="$LONG_OPTARG"
            ;;
        with-timestamp)
            WITH_TIMESTAMP=true
            ;;
        with-commit-id)
            WITH_COMMIT_ID=true
            ;;
        dist=?*)
            DIST="$LONG_OPTARG"
            ;;
        verbose)
            VERBOSE=true
            ;;
        debug)
            VERBOSE=true
            DEBUG=true
            ;;
        help)
            usage
            exit
            ;;
        '')
            break # "--" terminates argument processing
            ;;
        work-dir* | source-tag* | dist*)
            echo "ERROR: Missing argument for --$OPTARG option" >&2
            exit 1
            ;;
        *)
            echo "ERROR: Illegal option --$OPTARG" >&2
            exit 1
            ;;
        esac
        ;;
    \?)
        exit 1 # getopts already reported the illegal option
        ;;
    esac
done

# remove parsed options and args from $@ list
shift $((OPTIND-1))

if [ "$#" -lt 1 ] ; then
    BUILD_TARGET=rpm
else
    BUILD_TARGET=$1
fi

if [ "$DEBUG" = true ] ; then
    echo "WORK_DIR: $WORK_DIR"
    echo "BUILD_TARGET: $BUILD_TARGET"
fi

if [ "$BUILD_TARGET" != "src" ] &&
        [ "$BUILD_TARGET" != "spec" ] &&
        [ "$BUILD_TARGET" != "srpm" ] &&
        [ "$BUILD_TARGET" != "rpm" ] ; then
    echo "ERROR: Invalid build target: $BUILD_TARGET" >&2
    exit 1
fi

SPEC_TEMPLATE="$SRC_DIR/$NAME.spec"
VERSION="$(rpmspec -P "$SPEC_TEMPLATE" | grep "^Version:" | awk '{print $2;}')"

if [ "$DEBUG" = true ] ; then
    echo "VERSION: $VERSION"
fi

RELEASE="$(rpmspec -P "$SPEC_TEMPLATE" --undefine dist | grep "^Release:" | awk '{print $2;}')"

if [ "$DEBUG" = true ] ; then
    echo "RELEASE: $RELEASE"
fi

spec=$(<"$SPEC_TEMPLATE")
regex=$'%global *_phase *([^\n]+)'
if [[ $spec =~ $regex ]] ; then
    _PHASE="${BASH_REMATCH[1]}"
fi

if [ "$DEBUG" = true ] ; then
    echo "PHASE: ${_PHASE}"
fi

if [ "$WITH_TIMESTAMP" = true ] ; then
    TIMESTAMP="$(date -u +"%Y%m%d%H%M%S%Z")"
    _TIMESTAMP=".$TIMESTAMP"
fi

if [ "$DEBUG" = true ] ; then
    echo "TIMESTAMP: $TIMESTAMP"
fi

if [ "$WITH_COMMIT_ID" = true ]; then
    COMMIT_ID="$(git -C "$SRC_DIR" rev-parse --short=8 HEAD)"
    _COMMIT_ID=".$COMMIT_ID"
fi

if [ "$DEBUG" = true ] ; then
    echo "COMMIT_ID: $COMMIT_ID"
fi

echo "Building $NAME-$VERSION-$RELEASE${_TIMESTAMP}${_COMMIT_ID}"

################################################################################
# Initialize working directory
################################################################################

if [ "$VERBOSE" = true ] ; then
    echo "Initializing $WORK_DIR"
fi

mkdir -p $WORK_DIR
cd $WORK_DIR

rm -rf BUILD
rm -rf RPMS
rm -rf SOURCES
rm -rf SPECS
rm -rf SRPMS

mkdir BUILD
mkdir RPMS
mkdir SOURCES
mkdir SPECS
mkdir SRPMS

################################################################################
# Generate RPM sources
################################################################################

generate_rpm_sources

echo "RPM sources:"
find "$WORK_DIR/SOURCES" -type f -printf " %p\n"

if [ "$BUILD_TARGET" = "src" ] ; then
    exit
fi

################################################################################
# Generate RPM spec
################################################################################

generate_rpm_spec

echo "RPM spec:"
find "$WORK_DIR/SPECS" -type f -printf " %p\n"

if [ "$BUILD_TARGET" = "spec" ] ; then
    exit
fi

################################################################################
# Build source package
################################################################################

OPTIONS=()

OPTIONS+=(--quiet)
OPTIONS+=(--define "_topdir ${WORK_DIR}")

if [ "$WITH_TIMESTAMP" = true ] ; then
    OPTIONS+=(--define "_timestamp ${_TIMESTAMP}")
fi

if [ "$WITH_COMMIT_ID" = true ] ; then
    OPTIONS+=(--define "_commit_id ${_COMMIT_ID}")
fi

if [ "$DIST" != "" ] ; then
    OPTIONS+=(--define "dist .$DIST")
fi

if [ "$DEBUG" = true ] ; then
    echo "rpmbuild -bs ${OPTIONS[@]} $WORK_DIR/SPECS/$RPM_SPEC"
fi

# build SRPM with user-provided options
rpmbuild -bs "${OPTIONS[@]}" "$WORK_DIR/SPECS/$RPM_SPEC"

rc=$?

if [ $rc != 0 ]; then
    echo "ERROR: Unable to build SRPM package"
    exit 1
fi

SRPM="$(find "$WORK_DIR/SRPMS" -type f)"

echo "SRPM package:"
echo " $SRPM"

if [ "$BUILD_TARGET" = "srpm" ] ; then
    exit
fi

################################################################################
# Build binary packages
################################################################################

OPTIONS=()

if [ "$VERBOSE" = true ] ; then
    OPTIONS+=(--define "_verbose 1")
fi

OPTIONS+=(--define "_topdir ${WORK_DIR}")

if [ "$DEBUG" = true ] ; then
    echo "rpmbuild --rebuild ${OPTIONS[@]} $SRPM"
fi

# rebuild RPM with hard-coded options in SRPM
rpmbuild --rebuild "${OPTIONS[@]}" "$SRPM"

rc=$?

if [ $rc != 0 ]; then
    echo "ERROR: Unable to build RPM packages"
    exit 1
fi

# install SRPM to restore sources and spec file removed during rebuild
rpm -i --define "_topdir $WORK_DIR" "$SRPM"

# flatten folder
find "$WORK_DIR/RPMS" -mindepth 2 -type f -exec mv -i '{}' "$WORK_DIR/RPMS" ';'

# remove empty subfolders
find "$WORK_DIR/RPMS" -mindepth 1 -type d -delete

echo "RPM packages:"
find "$WORK_DIR/RPMS" -type f -printf " %p\n"
