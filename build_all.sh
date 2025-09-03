#!/bin/bash
#
# build_all.sh
#


PREFIXES=("repo.prd.lucera.com" "docker.lucera.com/lcp")

# run with true to push
PUSH="${1:-false}"


for PREFIX in "${PREFIXES[@]}"
do
    for FLAVOR in $(./build_onload_image.rb --flavors)
    do
        for VERSION in $(./build_onload_image.rb --versions)
        do
            IMAGE="${PREFIX}/onload-${FLAVOR}:${VERSION}"
            ./build_onload_image.rb -o "${VERSION}" -f "${FLAVOR}" -t "${IMAGE}" --execute
            if [ "${PUSH}" == "true" ]
            then 
                docker push "${IMAGE}"
            fi
        done
    done
done
