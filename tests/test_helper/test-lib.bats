# Spawns a PBS job with the given arguments and stdin as the script input
spawn_job() {
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
