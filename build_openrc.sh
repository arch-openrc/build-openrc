#!/bin/bash
# build_openrc.sh

# start the gpg-agent and create the temp source files
# /tmp/sources should be declared in the /etc/makepkg.conf file for the sources directory
if [ -f ./pgpsign.sig ]; then
	rm ./pgpsign.sig
fi
touch ./pgpsign
gpg -b ./pgpsign
if [ ! -d /tmp/sources ]; then
	mkdir /tmp/sources
fi

# Source repo packages and functions
[ -e openrc_repo_packages ] && . openrc_repo_packages
. functions_openrc || exit 1

# Set the user
if [ "$(sed -n '/nous/ p' <<< "$USER")" ]; then
	sfname=archnous
elif [ "$(sed -n '/cromer/ p' <<< "$USER")" ]; then
	sfname=agisci
else
	sfname=aaditya1234
fi

# Set the variables
TARGETS=('x86_64' 'i686')
BASEDIR=$PWD
BUILDDIR=$BASEDIR/arch-openrc
LOGDIR=/tmp/openrc-autobuild-$(date +%F_%T)
LOGFILE=$LOGDIR/log
REPO=arch-openrc-repo
REPODIR=$BASEDIR/$REPO
REPO_REMOTE=$REPO-sourceforge
REPO_FILE=arch-openrc
if [[ $sfname = archnous ]]; then
	REPODIR_REMOTE=$BASEDIR/$REPO_REMOTE
elif [[ $sfname = agisci ]]; then
	REPODIR_REMOTE=$PWD/$REPO_REMOTE
else
	REPODIR_REMOTE=$HOME/$REPO_REMOTE
fi
if [[ $sfname = agisci ]]; then
	AURDOWNLOAD="cower -f -d --ignorerepo=arch-openrc"
else
	AURDOWNLOAD="yaourt -G"
fi
USEAUR="false"
MAKEPACKAGES="true"
MAKEPKGOPTS=(-c)
LINE="=================================================================== "
SFREPO="frs.sourceforge.net:/home/frs/project/archopenrc/arch-openrc/"
GHREPO="https://github.com/cromerc/arch-openrc"
PATCHDIR="$PWD/openrc_patches"

# Parse commandline args
[[ $@ = *i686* ]] && TARGETS=('i686')
[[ $@ = *x86_64* ]] && TARGETS=('x86_64')
[[ $@ = *aur* ]] && USEAUR="true"
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
	CHROOTOP="no"
	read -p "Do you want to update the chroots? (yes/no): " CHROOTOP
	if [ "$CHROOTOP" = "yes" ]; then
		arch-nspawn /chroots/32/root pacman -Syu
		arch-nspawn /chroots/64/root pacman -Syu
	fi
	read -p "Do you want to remove old cached packages from the chroots? (yes/no): " CHROOTOP
	if [ "$CHROOTOP" = "yes" ]; then
		arch-nspawn /chroots/32/root pacman -Sc
		arch-nspawn /chroots/64/root pacman -Sc
	fi

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
	
	if [ -d "$BUILDDIR/openrc-keyring" ]; then
		cd "$BUILDDIR/openrc-keyring"
		git fetch origin
		git reset --hard origin/master
		git clean -fd
		git pull http://github.com/cromerc/openrc-keyring.git
	else
		cd "$BUILDDIR"
		git clone http://github.com/cromerc/openrc-keyring.git
	fi
	cd "$BUILDDIR"

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
			MAKEPKGOPTS=(-c)
		    check_package "$REPODIR_REMOTE" "$pkgname" "$pkgver" "$pkgrel" "$cpu" && continue # package already present
			if [ -f "${PATCHDIR}/${package}.patch" ]; then
				cp "${PATCHDIR}/${package}.patch" .
				patch < ${package}.patch
			fi
		    echo "Building $package for $cpu"
		    if [[ $cpu = i686 ]]; then
		        [[ $package = lib32-* ]] && continue
		        if [ $USEAUR = "true" ]; then
					for dependency in "${depends[@]}" "${makedepends[@]}";
					do
						DEPS=$(pacman -Ssq '^'$dependency'$')
						if [[ "$DEPS" == "" ]]; then
							cower -df $dependency
							cd $dependency
							makechrootpkg $MAKEPKGOPTS -r /chroots/32/ 1>>"$LOGFILE-$package-$cpu"-build 2>>"$LOGFILE-$package-$cpu"-errors || log "Error building $dependency; see $LOGFILE-$package-$cpu-errors for details"
							makechrootpkg -r /chroots/32 -I ./*.pkg.tar.xz 1>>"$LOGFILE-$package-$cpu"-build 2>>"$LOGFILE-$package-$cpu"-errors || log "Error building $dependency; see $LOGFILE-$package-$cpu-errors for details"
							cd ..
							MAKEPKGOPTS=()
						fi
					done
				fi
				makechrootpkg $MAKEPKGOPTS -r /chroots/32/ 1>>"$LOGFILE-$package-$cpu"-build 2>>"$LOGFILE-$package-$cpu"-errors || log "Error building $package; see $LOGFILE-$package-$cpu-errors for details"
				cp -vf ./*-"$cpu".pkg.tar.xz "$REPODIR/$cpu/"
				rm -vf ./*-"$cpu".pkg.tar.xz
		    else
				if [ $USEAUR = "true" ]; then
					for dependency in "${depends[@]}" "${makedepends[@]}";
					do
						DEPS=$(pacman -Ssq '^'$dependency'$')
						if [[ "$DEPS" == "" ]]; then
							cower -df $dependency
							cd $dependency
							makechrootpkg $MAKEPKGOPTS -r /chroots/64/ 1>>"$LOGFILE-$package-$cpu"-build 2>>"$LOGFILE-$package-$cpu"-errors || log "Error building $dependency; see $LOGFILE-$package-$cpu-errors for details"
							makechrootpkg -r /chroots/64 -I ./*.pkg.tar.xz 1>>"$LOGFILE-$package-$cpu"-build 2>>"$LOGFILE-$package-$cpu"-errors || log "Error building $dependency; see $LOGFILE-$package-$cpu-errors for details"
							cd ..
							MAKEPKGOPTS=()
						fi
					done
				fi
				makechrootpkg $MAKEPKGOPTS -r /chroots/64/ 1>>"$LOGFILE-$package-$cpu"-build 2>>"$LOGFILE-$package-$cpu"-errors || log "Error building $package; see $LOGFILE-$package-$cpu-errors for details"
				cp -vf ./*-"$cpu".pkg.tar.xz "$REPODIR/$cpu/"
				rm -vf ./*-"$cpu".pkg.tar.xz
		    fi
		done
		rm -fr package
	done

	for package in "${any[@]}" "${extras_any[@]}"; do
		MAKEPKGOPTS=(-c)
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
		if [[ $package = openrc-* &&  $package != openrc-repo ]]; then
		    check_package "$REPODIR_REMOTE" "$pkgname" "$pkgver" "$pkgrel" "$TARGETS" "service" && continue # package already present
		elif [[ $package = cronjobs || $package = auditd-openrc || $package = modemmanager-pk-rules ]]; then
		    check_package "$REPODIR_REMOTE" "$pkgname" "$pkgver" "$pkgrel" "$TARGETS" "service" && continue # package already present
		else
		    check_package "$REPODIR_REMOTE" "$pkgname" "$pkgver" "$pkgrel" "$TARGETS" && continue # package already present
		fi
		echo "Building $package for any"
		cpu=any
		if [ $USEAUR = "true" ]; then
			for dependency in "${depends[@]}" "${makedepends[@]}";
			do
				DEPS=$(pacman -Ssq '^'$dependency'$')
				if [[ "$DEPS" == "" ]]; then
					cower -d $dependency
					cd $dependency
					makechrootpkg $MAKEPKGOPTS -r /chroots/64/ 1>>"$LOGFILE-$package-$cpu"-build 2>>"$LOGFILE-$package-$cpu"-errors || log "Error building $dependency; see $LOGFILE-$package-$cpu-errors for details"
					makechrootpkg -r /chroots/64 -I ./*.pkg.tar.xz 1>>"$LOGFILE-$package-$cpu"-build 2>>"$LOGFILE-$package-$cpu"-errors || log "Error building $dependency; see $LOGFILE-$package-$cpu-errors for details"
					cd ..
					MAKEPKGOPTS=()
				fi
			done
		fi
		makechrootpkg $MAKEPKGOPTS -r /chroots/64/ 1>>"$LOGFILE-$package-$cpu"-build 2>>"$LOGFILE-$package-$cpu"-errors || log "Error building $package; see $LOGFILE-$package-$cpu-errors for details"
		for cpu2 in "${TARGETS[@]}"; do
			cp -vf ./*-"$cpu".pkg.tar.xz "$REPODIR/$cpu2/"
		done
		rm -vf ./*-"$cpu".pkg.tar.xz
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
		for file in $(find ./ -maxdepth 1 -type f -name '*.pkg.tar.xz');
		do
			gpg -b $file
		done
		for file in $(find ./ -maxdepth 1 -type f -not -name '*.pkg.tar.xz.sig');
		do
			nice -n 20 repo-add --sign "$REPODIR_REMOTE/$repo/$REPO_FILE.db.tar.gz" $file
		done
		mv -vf "$REPODIR/$repo"/*.pkg.tar.xz "$REPODIR_REMOTE/$repo/" || flag=1  # repo state unchanged, nothing to do
		mv -vf "$REPODIR/$repo"/*.pkg.tar.xz.sig "$REPODIR_REMOTE/$repo/" || flag=1  # repo state unchanged, nothing to do
		if [[ $flag -eq 1 ]]; then
		    echo "Nothing to do"
		    #continue
		fi
		cd "$REPODIR_REMOTE/$repo"
		# remove old versions
		echo "Trimming $REPODIR_REMOTE/$repo of old packages..."
		paccache -rv -k1 -c .
		log "Uploading to $SFREPO/$repo"
		rsync -auvLPH --delete-after --exclude "*.iso" "$REPODIR_REMOTE/$repo" "${sfname}"@"${SFREPO}"/
	done
fi
