terraform {
  required_providers {
    github = {
      source = "integrations/github"
    }
  }
}

# One owner. The gems under general-intelligence-systems are in the registry
# but out of scope here, the same way they are out of scope for the converge
# run: bringing them in means a second `provider "github"` with an alias and a
# token that can write to that org, which is its own decision.
provider "github" {
  owner = "n-at-han-k"
}
