#!/usr/bin/env bash
# Author: Connor Weeks

SCRIPT_DIR="$(cd "$(dirname "${0}")"; pwd)"
RED="\033[1;31m"
YELLOW="\033[1;33m"
GREEN="\033[0;32m"
NO_COLOR="\033[0m"

# Prints an error message and exits with an error code of 1
fail () {
    echo -e "${RED}Command failed - script terminated${NO_COLOR}"
    exit 1
}

# Prints usage information concerning this script
print_usage () {
    echo "|
| Usage: ${0} generate|install [args]
|
| --> ${0} generate installed|external <tensorflow-source-dir> [<cmake-dir> <install-dir>]:
|
|     Generates the cmake files for the given installation of tensorflow
|     and writes them to <cmake-dir>. If 'generate installed' is executed,
|     <install-dir> corresponds to the directory Protobuf was installed to; 
|     defaults to /usr/local.
|
| --> ${0} install <tensorflow-source-dir> [<install-dir> <download-dir>]
|
|     Downloads Protobuf to <download-dir> (defaults to the current directory),
|     and installs it to <install-dir> (defaults to /usr/local).
|"
}


# validate and assign input
if [ ${#} -lt 2 ]; then
    print_usage
    exit 1
fi
# Determine mode
if [ "${1}" == "install" ] || [ "${1}" == "generate" ]; then
    MODE="${1}"
else
    print_usage
    exit 1
fi

# get arguments
if [ "${MODE}" == "install" ]; then
    TF_DIR="${2}"
    INSTALL_DIR="/usr/local"
    DOWNLOAD_DIR="${PWD}"
    if [ ${#} -gt 2 ]; then
       INSTALL_DIR="$(cd ${3}; pwd)"
    fi
    if [ ${#} -gt 3 ]; then
	DOWNLOAD_DIR="$(cd ${4}; pwd)"
    fi
elif [ "${MODE}" == "generate" ]; then
    GENERATE_MODE="${2}"
    if [ "${GENERATE_MODE}" != "installed" ] && [ "${GENERATE_MODE}" != "external" ]; then
	print_usage
	exit 1
    fi
    TF_DIR="${3}"
    CMAKE_DIR="${PWD}"
    if [ ${#} -gt 3 ]; then
	CMAKE_DIR="$(cd ${4}; pwd)"
    fi
    INSTALL_DIR="/usr/local"
    if [ "${GENERATE_MODE}" == "installed" ] && [ ${#} -gt 4 ]; then
	INSTALL_DIR="$(cd ${5}; pwd)"
    fi
fi

# locate protobuf information in tensorflow directory
ANY="[^\)]*"
ANY_NO_QUOTES="[^\)\\\"]*"
HTTP_HEADER="native.http_archive\(\s"
NAME_START="name\s*=\s*\\\""
QUOTE_START="\s*=\s*\\\""
QUOTE_END="\\\"\s*,\s*"
FOOTER="\)"
PROTOBUF_NAME="${NAME_START}protobuf${QUOTE_END}"

PROTOBUF_REGEX="${HTTP_HEADER}${ANY}${PROTOBUF_NAME}${ANY}${FOOTER}"

URL="s/\s*url${QUOTE_START}\(${ANY_NO_QUOTES}\)${QUOTE_END}/\1/p"
FOLDER="s/\s*strip_prefix${QUOTE_START}\(${ANY_NO_QUOTES}\)${QUOTE_END}/\1/p"

echo "Finding protobuf information in ${TF_DIR}..."
PROTOBUF_TEXT=$(grep -Pzo ${PROTOBUF_REGEX} ${TF_DIR}/tensorflow/workspace.bzl) || fail
PROTOBUF_URL=$(echo "${PROTOBUF_TEXT}" | sed -n ${URL}) || fail
PROTOBUF_ARCHIVE=$(echo "${PROTOBUF_URL}" | rev | cut -d'/' -f 1 | rev) || fail
PROTOBUF_FOLDER=$(echo "${PROTOBUF_TEXT}" | sed -n ${FOLDER}) || fail

if [ -z "${PROTOBUF_URL}" ] || [ -z "${PROTOBUF_ARCHIVE}" ] || [ -z "${PROTOBUF_FOLDER}" ]; then
    echo "Failure: Could not find all required strings in ${TF_DIR}"
    exit 1
fi

# print information
echo
echo -e "${GREEN}Found Protobuf information in ${TF_DIR}:${NO_COLOR}"
echo "Protobuf URL:  ${PROTOBUF_URL}"
echo "Protobuf archive:  ${PROTOBUF_ARCHIVE}"
echo "Protobuf folder:  ${PROTOBUF_FOLDER}"
echo

# perform requested action
if [ "${MODE}" == "install" ]; then
    # see if protobuf already exists in DONWLOAD_DIR
    DOWNLOAD="true"
    if [ -d "${DOWNLOAD_DIR}/${PROTOBUF_FOLDER}" ]; then
	echo -e "${YELLOW}Warning: Found protobuf directory, will delete and download latest version.${NO_COLOR}"
	rm -r ${DOWNLOAD_DIR}/${PROTOBUF_FOLDER} || fail
    fi
    if [ "${DOWNLOAD}" == "true" ]; then
	# download protobuf from http archive
	cd ${DOWNLOAD_DIR} || fail
	wget -q -N ${PROTOBUF_URL} || fail
	tar -xf ${PROTOBUF_ARCHIVE} || fail
	cd ${PROTOBUF_FOLDER} || fail
    fi
    # configure
    ./autogen.sh || fail
    ./configure --prefix=${INSTALL_DIR} || fail
    echo "Starting protobuf install."
    # build and install
    make || fail
    make check || fail
    make install || fail
    ldconfig || fail
    cd ${DOWNLOAD_DIR} || fail
    rm ${PROTOBUF_ARCHIVE} || fail
    echo "Protobuf has been installed to ${INSTALL_DIR}"
elif [ "${MODE}" == "generate" ]; then
    
    if [ "${GENERATE_MODE}" == "installed" ]; then
	# try to locate protobuf in INSTALL_DIR
	if [ -d "${INSTALL_DIR}/include/google/protobuf" ]; then
            echo -e "${GREEN}Found Protobuf in ${INSTALL_DIR}${NO_COLOR}"
	else
 	    echo -e "${YELLOW}Warning: Could not find Protobuf in ${INSTALL_DIR}${NO_COLOR}"	
	fi
    fi
    
    PROTOBUF_OUT="${CMAKE_DIR}/Protobuf_VERSION.cmake"	
    echo "set(Protobuf_URL ${PROTOBUF_URL})" > ${PROTOBUF_OUT} || fail
    if [ "${GENERATE_MODE}" == "external" ]; then
	echo "Wrote Protobuf_VERSION.cmake to ${CMAKE_DIR}"
	cp ${SCRIPT_DIR}/Protobuf.cmake ${CMAKE_DIR} || fail
	echo "Copied Protobuf.cmake to ${CMAKE_DIR}"
    elif [ "${GENERATE_MODE}" == "installed" ]; then
	echo "set(Protobuf_INSTALL_DIR ${INSTALL_DIR})" >> ${PROTOBUF_OUT} || fail
	echo "Wrote Protobuf_VERSION.cmake to ${CMAKE_DIR}"
	cp ${SCRIPT_DIR}/FindProtobuf.cmake ${CMAKE_DIR} || fail
	echo "Copied FindProtobuf.cmake to ${CMAKE_DIR}"
    fi
fi
echo -e "${GREEN}Done${NO_COLOR}"
exit 0
