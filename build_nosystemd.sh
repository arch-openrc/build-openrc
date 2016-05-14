#!/bin/bash
# build_nosystemd.sh

# Source repo packages and functions
[ -e nosystemd_repo_packages ] && . nosystemd_repo_packages
. functions_nosystemd || exit 1

# Set the user
if [ "$(sed -n '/nous/ p' <<< "$USER")" ]; then
	sfname=archnous
elif [ "$(sed -n '/cromer/ p' <<< "$USER")" ]; then
	sfname=agisci
else
	sfname=aaditya1234
fi

# Set the variables
if [ -d /lib64 ]; then
	TARGETS=('x86_64')
else
	TARGETS=('i686')
fi
BASEDIR=$PWD
BUILDDIR=$BASEDIR/packages-nosystemd
LOGDIR=/tmp/nosystemd-autobuild-$(date +%F_%T)
LOGFILE=$LOGDIR/log
REPO=arch-nosystemd
REPODIR=$BASEDIR/$REPO
REPO_REMOTE=$REPO-sf
if [[ $sfname = archnous ]]; then
	REPODIR_REMOTE=$BASEDIR/$REPO_REMOTE
elif [[ $sfname = agisci ]]; then
	REPODIR_REMOTE=$PWD/$REPO_REMOTE
else
	REPODIR_REMOTE=$HOME/$REPO_REMOTE
fi
if [[ $sfname = agisci ]]; then
	AURDOWNLOAD="cower -d --ignorerepo=arch-nosystemd"
else
	AURDOWNLOAD="yaourt -G"
fi
MAKEPACKAGES="true"
MAKEPKGOPTS=(--noconfirm --skipinteg --skippgpcheck -scf)
LINE="=================================================================== "
SFREPO="frs.sourceforge.net:/home/frs/project/archopenrc/arch-nosystemd/"
GHREPO="https://github.com/cromerc/packages-nosystemd"
PATCHDIR="$PWD/nosystemd_patches"

# Parse commandline args
if [[ $@ = *upload* ]]; then
	MAKEPACKAGES="false"
	UPLOADFILES="yes"
fi

unalias cp mv rm 2>/dev/null
	mkdir -p "$LOGDIR"

log() {
	echo "$*"
	echo "$(date +%F_%T)" " $* " >> "$LOGFILE"
}

if [[ $MAKEPACKAGES = "true" ]]; then
	# Building process starts
	mkdir -p $REPODIR/{i686,x86_64}

	log "$LINE"
	log "Building for CPU(s): ${TARGETS[*]}"

	if [ -d "$BUILDDIR" ]; then
		cd "$BUILDDIR"
		git fetch origin
		git reset --hard origin/master
		git clean -fd
		git pull $GHREPO.git
	else
		cd "$BASEDIR"
		git clone $GHREPO.git
	fi

	cd "$BUILDDIR"
	if [[ ! $? -eq 0 ]]; then
		log "Can't find sources. Aborting"
		exit 1
	fi

	#Remove orphans to prevent contamination of other packages
	sudo pacman --noconfirm -Rns $(pacman -Qtdq)

	rm -f $REPODIR/*/*pkg.tar.xz
	rm -f $REPODIR/*/*pkg.tar.xz.sig

	echo "Fetching remote repo from sourceforge for $sfname"
	echo "Saving to $REPODIR_REMOTE"
	rsync -auvPH --delete-after --exclude "*.iso" "${sfname}"@"${SFREPO}" "$REPODIR_REMOTE" || exit 1

	echo "Downloading AUR packages"
	for package in "${extras[@]}" "${extras_any[@]}"; do
		$AURDOWNLOAD "$package"
	done

	log "Start building"

	for package in "${arches[@]}" "${extras[@]}"; do
		echo "$LINE"
		echo "Entering $package"
		if check_ignore "$package"; then
		    echo "$package ignored."
		    continue
		fi
		cd "$BUILDDIR/$package"
		echo "Sourcing PKGBUILD"
		. PKGBUILD
		for cpu in "${TARGETS[@]}"; do
		    check_package "$REPODIR_REMOTE" "$pkgname" "$pkgver" "$pkgrel" "$cpu" && continue # package already present
			if [ -f "${PATCHDIR}/${package}.patch" ]; then
				cp "${PATCHDIR}/${package}.patch" .
				patch < ${package}.patch
			fi
		    echo "Building $package for $cpu"
		    if [[ $cpu = i686 ]]; then
		        [[ $package = lib32-* ]] && continue
		        makepkg --sign "${MAKEPKGOPTS[@]}" --config=/etc/makepkg.conf."$cpu" 1>"$LOGFILE-$package-$cpu"-build 2>"$LOGFILE-$package-$cpu"-errors || log "Error building $package; see $LOGFILE-$package-$cpu-errors for details"
		    else
		        makepkg --sign "${MAKEPKGOPTS[@]}" --config=/etc/makepkg.conf."$cpu" 1>"$LOGFILE-$package-$cpu"-build 2>"$LOGFILE-$package-$cpu"-errors || log "Error building $package; see $LOGFILE-$package-$cpu-errors for details"
		    fi
			if [ -f "$package"-[0-9]*-"$cpu".pkg.tar.xz.sig ]; then
				mv -vf "$package"-[0-9]*-"$cpu".pkg.tar.xz "$REPODIR/$cpu/"
				mv -vf "$package"-[0-9]*-"$cpu".pkg.tar.xz.sig "$REPODIR/$cpu/"
			else
				log "Error signing $package; see $LOGFILE-$package-$cpu-errors for details"
			fi
		done
		#Remove orphans to prevent contamination of other packages
		sudo pacman --noconfirm -Rns $(pacman -Qtdq)
		rm -fr package
	done

	for package in "${any[@]}" "${extras_any[@]}"; do
		echo "$LINE"
		echo "Entering $package"
		cd "$BUILDDIR/$package"
		if check_ignore "$package"; then
		    echo "$package ignored."
		    continue
		fi
		echo "Sourcing PKGBUILD"
		. PKGBUILD
		# Special check for service packages
		if [[ $package = openrc-* ]]; then
		    check_package "$REPODIR_REMOTE" "$pkgname" "$pkgver" "$pkgrel" "$TARGETS" "service" && continue # package already present
		else
		    check_package "$REPODIR_REMOTE" "$pkgname" "$pkgver" "$pkgrel" "$TARGETS" && continue # package already present
		fi
		echo "Building $package for any"
		cpu=any
		makepkg --sign "${MAKEPKGOPTS[@]}" 1>"$LOGFILE-$package-$cpu-build" 2>"$LOGFILE-$package-$cpu-errors" || log "Error building $package; see $LOGFILE-$package-$cpu-errors for details"
		cp -vf ./*-"$cpu".pkg.tar.xz "$REPODIR/i686/"
		cp -vf ./*-"$cpu".pkg.tar.xz.sig "$REPODIR/i686/"
		mv -vf ./*-"$cpu".pkg.tar.xz "$REPODIR/x86_64/"
		mv -vf ./*-"$cpu".pkg.tar.xz.sig "$REPODIR/x86_64/"

		#Remove orphans to prevent contamination of other packages
		sudo pacman --noconfirm -Rns $(pacman -Qtdq)
	done

	log "$LINE"

	read -p "Do you want to upload packages? (yes/no): " UPLOADFILES
	log "Finished building - updating repo database..."
fi

if [[ $UPLOADFILES = "yes" ]]; then
	# Copy the built packages
	for repo in "${TARGETS[@]}"; do
		flag=0
		# add packages to pacman db
		cd "$REPODIR/$repo"
		for file in $(find ./ -maxdepth 1 -type f -not -name '*.pkg.tar.xz.sig');
		do
			nice -n 20 repo-add --sign "$REPODIR_REMOTE/$repo/$REPO.db.tar.gz" $file
		done
		cp -vf "$REPODIR/$repo"/*.pkg.tar.xz "$REPODIR_REMOTE/$repo/" || flag=1  # repo state unchanged, nothing to do
		cp -vf "$REPODIR/$repo"/*.pkg.tar.xz.sig "$REPODIR_REMOTE/$repo/" || flag=1  # repo state unchanged, nothing to do
		if [[ $flag -eq 1 ]]; then
		    echo "Nothing to do"
		    continue
		fi
		cd "$REPODIR_REMOTE/$repo"
		# remove old versions
		echo "Trimming $REPODIR_REMOTE/$repo of old packages..."
		paccache -rv -k1 -c .
		log "Uploading to $SFREPO/$repo"
		rsync -auvLPH --delete-after --exclude "*.iso" "$REPODIR_REMOTE/$repo" "${sfname}"@"${SFREPO}"/
	done
fi
