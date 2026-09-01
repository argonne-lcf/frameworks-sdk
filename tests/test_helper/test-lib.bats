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

# Spawns a PBS job with the given arguments and stdin as the script input
spawn_job() {
	QUEUE=""
	FILESYSTEMS=""
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
		-N "$N_NODES" \
		-q "$QUEUE" \
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
	cat outfile
	cat errfile >&2
	rm -f outfile errfile
	return "$STATUS"
}
