#!/usr/bin/env bash
set -Eeuo pipefail

# MODIFIED VERSION OF WP LIBRARY
if [[ "$1" == apache2* ]] || [ "$1" = 'php-fpm' ]; then
    uid="$(id -u)"
	gid="$(id -g)"
    if [ "$uid" = '0' ]; then
		case "$1" in
			apache2*)
				user="${APACHE_RUN_USER:-www-data}"
				group="${APACHE_RUN_GROUP:-www-data}"

				# strip off any '#' symbol ('#1000' is valid syntax for Apache)
				pound='#'
				user="${user#$pound}"
				group="${group#$pound}"
				;;
			*) # php-fpm
				user='www-data'
				group='www-data'
				;;
		esac
	else
		user="$uid"
		group="$gid"
	fi

    if [ ! -e web/index.php ] && [ ! -e web/wp/wp-includes/version.php ]; then
        # if the directory exists and Bedrock doesn't appear to be installed AND the permissions of it are root:root, let's chown it (likely a Docker-created directory)
		if [ "$uid" = '0' ] && [ "$(stat -c '%u:%g' .)" = '0:0' ]; then
			chown "$user:$group" .
		fi

        echo >&2 "Bedrock not found in $PWD - copying now..."
		if [ -n "$(find -mindepth 1 -maxdepth 1 -not -name app)" ]; then
			echo >&2 "WARNING: $PWD is not empty! (copying anyhow)"
		fi

        sourceTarArgs=(
			--create
			--file -
			--directory /usr/src/bedrock
			--owner "$user" --group "$group"
		)
		targetTarArgs=(
			--extract
			--file -
		)

        if [ "$uid" != '0' ]; then
			# avoid "tar: .: Cannot utime: Operation not permitted" and "tar: .: Cannot change mode to rwxr-xr-x: Operation not permitted"
			targetTarArgs+=( --no-overwrite-dir )
		fi

        # loop over "pluggable" content in the source, and if it already exists in the destination, skip it
		for contentPath in \
			/usr/src/bedrock/web/.htaccess \
			/usr/src/bedrock/web/app/*/*/ \
		; do
			contentPath="${contentPath%/}"
			[ -e "$contentPath" ] || continue
			contentPath="${contentPath#/usr/src/bedrock/}" # "app/plugins/akismet", etc.
			if [ -e "$PWD/$contentPath" ]; then
				echo >&2 "WARNING: '$PWD/$contentPath' exists! (not copying the Bedrock version)"
				sourceTarArgs+=( --exclude "./$contentPath" )
			fi
		done

        tar "${sourceTarArgs[@]}" . | tar "${targetTarArgs[@]}"
		echo >&2 "Complete! Bedrock has been successfully copied to $PWD"
    fi

    wpEnvs=( "${!WP_@}" )
	if [ -s web/wp-config-docker.php ] && [ "${#wpEnvs[@]}" -gt 0 ]; then
        for wpConfigDocker in \
            .env.example \
			/usr/src/bedrock/.env.example \
		; do
			if [ -s "$wpConfigDocker" ]; then
				echo >&2 "No '.env.local' found in $PWD, but 'WP_...' variables supplied; copying '$wpConfigDocker' (${wpEnvs[*]})"
				# using "awk" to replace all instances of "generateme" with a properly unique string (for AUTH_KEY and friends to have safe defaults if they aren't specified with environment variables)
				awk '
					/generateme/ {
						cmd = "head -c1m /dev/urandom | sha1sum | cut -d\\  -f1"
						cmd | getline str
						close(cmd)
						gsub("generateme", str)
					}
					{ print }
				' "$wpConfigDocker" > .env

				if [ "$uid" = '0' ]; then
					# attempt to ensure that .env is owned by the run user
					# could be on a filesystem that doesn't allow chown (like some NFS setups)
					chown "$user:$group" .env || true
				fi
				break
			fi
		done

		# Update .env with Docker Environment
		php web/wp-config-docker.php
	fi
fi

exec "$@"