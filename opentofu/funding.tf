# The donation links, in one place, written into every repo on the profile.
#
# A `.github/FUNDING.yml` is what puts the Sponsor button on a repo, and it is
# per-repo: the one in this repository covers this repository only. GitHub's
# account-wide default lives in a repo named `.github`, which does not exist
# here, so the links are written into each repo instead — which is also what
# makes them visible on repos that have their own.
#
# The repo list is ../.github/repos.yml, the same registry README.md is
# rendered from and the converge workflow reads. Nothing is enumerated twice.
#
# What this cannot do: the donation platforms themselves. Ko-fi, Buy Me a
# Coffee and thanks.dev publish no write API, Liberapay's is read-only, and
# none of the four has a Terraform provider. Open Collective is the exception
# — its GraphQL API has an `editAccount` mutation — but using it would mean
# writing a provider, not configuring one. The handles below are therefore
# the source of truth for where the money goes; the profile text on each
# platform stays hand-edited.

locals {
  # Every FUNDING.yml key that is actually set, and nothing else. Keys GitHub
  # supports but that do not apply are left out rather than set empty: an
  # empty value renders a Sponsor entry pointing nowhere.
  #
  #   patreon           no account
  #   polar             takes no plain donations
  #   tidelift          needs a published npm/PyPI package
  #   issuehunt         a bug bounty platform now, not OSS funding
  #   lfx_mentorship    program-level, not individual
  #   community_bridge  project-level, not individual
  #
  # open_collective is set because the page exists and the link resolves, but
  # `nathan-k` is a personal profile: only a Collective can take money. Make
  # it a Collective, or drop this key.
  funding = {
    buy_me_a_coffee = "n.at.han.k"
    github          = "n-at-han-k"
    ko_fi           = "n_at_han_k"
    liberapay       = "n-at-han-k"
    open_collective = "nathan-k"
    thanks_dev      = "u/gh/n-at-han-k"
  }

  # `for` over a map yields keys in lexical order, so this renders the same
  # bytes every run and does not show up as a diff on its own.
  funding_yml = join("", concat(
    [
      "# Managed by OpenTofu — see opentofu/funding.tf in n-at-han-k/n-at-han-k.\n",
      "# Edits here are overwritten on the next apply; change the handles there.\n",
      "\n",
    ],
    [for key, handle in local.funding : "${key}: ${handle}\n"]
  ))

  registry = yamldecode(file("${path.module}/../.github/repos.yml"))

  # Flattened to repo => section title, then filtered to the owner this
  # provider is configured for. A repo under another owner silently resolving
  # to the wrong account is worse than it being absent, so the filter is on
  # the full slug rather than assumed.
  owned = merge([
    for section in local.registry.sections : {
      for entry in section.repos :
      split("/", entry.repo)[1] => section.title
      if startswith(entry.repo, "n-at-han-k/")
    }
  ]...)
}

# n-at-han-k/n-at-han-k is not in the registry — it lists projects, not the
# profile repo — so its own committed .github/FUNDING.yml is untouched by
# this. Adding it here would mean two things writing one file, which shows up
# as a diff on every plan.
resource "github_repository_file" "funding" {
  for_each = local.owned

  repository = each.key
  file       = ".github/FUNDING.yml"
  content    = local.funding_yml

  # No `branch`: the provider uses each repo's default branch, and these are
  # not all `main`.
  commit_message      = "Add funding links from n-at-han-k/n-at-han-k"
  commit_author       = "github-actions[bot]"
  commit_email        = "41898282+github-actions[bot]@users.noreply.github.com"
  overwrite_on_create = true
}

output "funding_repos" {
  description = "Repos whose .github/FUNDING.yml this config manages."
  value       = sort(keys(local.owned))
}

output "funding_yml" {
  description = "The file written into each of them."
  value       = local.funding_yml
}
