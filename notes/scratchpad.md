# scratchpad.md - Claude Code / Cowork sessions IGNORE THIS

Follow-ups:

- BOOTSTRAP.md Phase 2 can be touched up to use `--output json | jq` instead (awk is a convention, but `jq` is a better tool when working with awscli output.
- May not actually be necessary to "hide" prior SPEC.md from git-history, though ignoring it going forward is worthwhile.
- All the additional sanity / availability checks Claude is currently running should be folded into the bootstrap process as part of the automated tool runs.
  - e.g., validating the SSM agent prior to ansible runs (briefly scripted check would be good here)
- Update ACCESS.md with a note about the kubeconfig setup script (and why it's necessary, given we're not using EKS)
- on local and upstream on AWS, still have to declare my own portforwards, for ease of use / demo make use of the barzel.sh domain and that work to quickly strap in DNS.
    - also need to isolate this functionality, as it may be _too much_ for the demo.
- important bits to do on Sunday/Monday; lower the barrier to entry for diagnostic systems, make the bootstrap process less local-OS/platform reliant (shift to toolbox in "endless-unpack" mode, per Planetron)
    - having this work on a broader spread of local OS systems when in local-dev mode is also a refinement, but again-- make sure it's within scope and not overkill.
- we'll need to run a pass to confirm we're not duplicating work or spreading it across multiple scripts and configs. Need to "compact" the whole system, effectively
- the "prod cert" vs "staging / not-trusted" is poor user-facing smell only, but need to check if defaulting to prod is a good idea or not
- don't forget to consolidate the secrets, creds, clients, etc. and document up-front what needs to be set up and can't be automated (e.g., QUAY, DOCKERHUB, GITHUB, etc.)
    - all these additional fittings are definitely "above and beyond" and it should be possible to demo this without all the pre-staging, which is a bad look for an "assignment"; would be acceptable or even desired as a "deliverable product", so it's a trade-off.

