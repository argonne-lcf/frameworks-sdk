# Lustre `home` filesystem for the machine the tests run on.
home_filesystem() {
	case "$(hostname -f)" in
	*aurora*) echo "home:flare" ;;
	*sunspot*) echo "home:tegu" ;;
	*)
		echo "home_filesystem: unknown host $(hostname -f), pass -f to override" >&2
		return 1
		;;
	esac
}

# Default PBS queue: `next-eval` on the Aurora eval system, else `debug`. Only
# `CI_RUNNER_TAGS` identifies eval, since it shares hostnames with Aurora.
default_queue() {
	case "${CI_RUNNER_TAGS:-}" in
	*aurora-eval*) echo "next-eval" ;;
	*) echo "debug" ;;
	esac
}

# Queue for multi-hour suites: `next-eval` on the Aurora eval system (24 hrs),
# `capacity` on Aurora (7 days), and `workq` on Sunspot.
long_queue() {
	case "${CI_RUNNER_TAGS:-}" in
	*aurora-eval*)
		echo "next-eval"
		;;
	*)
		case "$(hostname -f)" in
		*sunspot*) echo "workq" ;;
		*) echo "capacity" ;;
		esac
		;;
	esac
}

# Spawns a PBS job with the given arguments and stdin as the script input
spawn_job() {
	QUEUE=""
	FILESYSTEMS=""
	PROJ_ALLOC="datascience" # override with `-A`
	N_NODES=1                # override with `-N`
	TIME=""
	OPTIND=1
	while getopts "q:A:N:t:f:" o; do
		case "$o" in
			q)
				QUEUE="$OPTARG"
				;;
			A)
				PROJ_ALLOC="$OPTARG"
				;;
			N)
				N_NODES="$OPTARG"
				;;
			t)
				TIME="$OPTARG"
				;;
			f)
				FILESYSTEMS="$OPTARG"
				;;
		esac
	done

	# Fall back to the defaults for the options that were not passed
	if [ -z "$QUEUE" ]; then
		QUEUE="$(default_queue)"
	fi
	if [ -z "$FILESYSTEMS" ]; then
		if ! FILESYSTEMS="$(home_filesystem)"; then
			return 1
		fi
	fi

	qsub -A "$PROJ_ALLOC" \
		-q "$QUEUE" \
		-l select="$N_NODES" \
		-l walltime="$TIME" \
		-l filesystems="$FILESYSTEMS" \
		-W block=true \
		-k oed \
		-o outfile \
		-e errfile \
		-V \
		- < /dev/stdin && true

	# Dump output on completion
	STATUS="$?"
	cat outfile 2>/dev/null || true
	cat errfile >&2 2>/dev/null || true
	rm -f outfile errfile
	return "$STATUS"
}
