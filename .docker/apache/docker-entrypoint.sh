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
			contentPath="${contentPath#/usr/src/bedrock/web}" # "app/plugins/akismet", etc.
			if [ -e "$PWD/$contentPath" ]; then
				echo >&2 "WARNING: '$PWD/$contentPath' exists! (not copying the Bedrock version)"
				sourceTarArgs+=( --exclude "./$contentPath" )
			fi
		done

        tar "${sourceTarArgs[@]}" . | tar "${targetTarArgs[@]}"
		echo >&2 "Complete! Bedrock has been successfully copied to $PWD"
    fi

    wpEnvs=( "${!WP_@}" )
	wpAdminEnvs=( "${!WP_ADMIN_@}" )

	if [ ! -s .env ] && [ "${#wpEnvs[@]}" -gt 0 ]; then
        for wpConfigDocker in \
            .env.template \
			/usr/src/bedrock/.env.template \
		; do
			if [ -s "$wpConfigDocker" ]; then
				echo >&2 "No '.env' found in $PWD, but 'WP_...' variables supplied; copying '$wpConfigDocker' (${wpEnvs[*]})"

				cat $wpConfigDocker | envsubst > .env | sh

				# envVariables="$(env | awk -F'=' '{printf("%s=\"%s\" ", $1, $2);}')";
				# envSubstitutes=$(echo -n "'"; env | cut -d'=' -f 1 | awk '{printf("${%s} ", $0);}'; echo -n "'";);

				# echo "$envVariables envsubst $envSubstitutes < $wpConfigDocker > .env" | sh

				# substitute environs
				# php -r "copy('.env.example', '.env');"
				# php -f "web/wp-config-docker.php"

				if [ "$uid" = '0' ]; then
					# attempt to ensure that .env is owned by the run user
					# could be on a filesystem that doesn't allow chown (like some NFS setups)
					chown "$user:$group" .env || true
				fi

				if [ "$WP_GENERATE_SALTS" = 'true' ]; then
					wp dotenv salts regenerate
				fi

				if [ ! -z "$WP_HOME" ] && [ ! -z "$WP_SITENAME" ] && [ ! -z "$WP_ADMIN_USERNAME" ] && [ ! -z "$WP_ADMIN_PASSWORD" ] && [ ! -z "$WP_ADMIN_EMAIL" ]; then
					wp core install \
						--url="$WP_HOME" \
						--title="$WP_SITENAME" \
						--admin_user="$WP_ADMIN_USERNAME" \
						--admin_password="$WP_ADMIN_PASSWORD" \
						--admin_email="$WP_ADMIN_EMAIL"
				fi
				
				break
			fi
		done
	fi

	# we don't need them anymore in apache's root folder
	rm -f web/wp-config-docker.php
	rm -f .env.template
fi

exec "$@"