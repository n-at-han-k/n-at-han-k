## Run Locally

```sh
GITHUB_TOKEN=$(gh auth token) nix develop --command ./opentofu/bin/01_plan
GITHUB_TOKEN=$(gh auth token) nix develop --command ./opentofu/bin/02_apply
```

`01_plan` writes nothing. `02_apply` commits `.github/FUNDING.yml` to every
repo the plan lists — read the plan before running it.

The handles live in `opentofu/funding.tf`; the repo list is
`.github/repos.yml`, shared with the README renderer and the converge
workflow.
