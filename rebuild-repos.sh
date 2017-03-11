#!/bin/bash

REPOS=('arch-openrc' 'arch-nosystemd')

for repo in "${REPOS[@]}"; do
	cd ${repo}-repo-sourceforge
	cd x86_64
	rm ${repo}.*
	for file in $(find ./ -maxdepth 1 -type f -name '*.pkg.tar.xz'); do
		repo-add --sign ${repo}.db.tar.gz $file
	done
	cd ../..
done
