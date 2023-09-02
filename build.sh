#!@bash@/bin/bash
# evaluate all package sets
eval_results="${2:-eval.json}"
@nixevaljobs@/bin/nix-eval-jobs --flake "$1" --gc-roots-dir gcroots --check-cache-status |
	tee "$eval_results" |
	@jq@/bin/jq '{attr: .attr, isCached: .isCached, drvPath: .drvPath, now: now | todateiso8601}'
# find uncached derivations
IFS=$'\n' read -r -d '' -a derivations <<<"$(@jq@/bin/jq -r "select(.isCached | not) | .drvPath" <"$eval_results")"
# build the uncached derivations
for derivation in "${derivations[@]}"; do
	echo "building derivation:"
	echo "$derivation"
	nix-store --realise "$derivation"
done
