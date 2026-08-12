#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/lib/common.sh"

PIPELINE="$1"
PIPELINE_FILE="$MODDIR/pipelines/$PIPELINE"

[ -z "$PIPELINE" ] && die "No pipeline specified"
[ ! -f "$PIPELINE_FILE" ] && die "Pipeline not found: $PIPELINE"

while IFS= read -r line; do
    [ -z "$line" ] && continue
    [ "${line#\#}" != "$line" ] && continue

    feature="$line"
    optional=false
    [ "${feature%\?}" != "$feature" ] && optional=true && feature="${feature%\?}"

    FEATURE_PATH="$MODDIR/features/$feature"
    if [ "$optional" = "true" ] && [ ! -f "$FEATURE_PATH" ]; then
        log "ORCH" "Warning: Optional feature '$feature' not found -- skipping"
        continue
    fi

    log "ORCH" "Running: $feature"
    if ! sh "$FEATURE_PATH"; then
        die "Pipeline aborted: $feature failed"
    fi
done < "$PIPELINE_FILE"
